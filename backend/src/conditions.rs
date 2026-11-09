//! Read-only provider adapters. Never store live responses as training labels or
//! predictions. Provider failures are isolated and returned as signal states.
use std::{sync::Arc, time::Duration};

use axum::{Json, extract::Extension};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::Semaphore;

use crate::{
    error::{AppError, AppResult},
    validation::{Validate, ValidatedQuery},
};

const SIGNAL_TIMEOUT: Duration = Duration::from_secs(8);
const MAX_AIR_AGE_HOURS: i64 = 3;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConditionsQuery {
    pub latitude: f64,
    pub longitude: f64,
    /// Explicit BMKG village code; coordinate-to-village lookup is not inferred.
    pub adm4: Option<String>,
}

impl Validate for ConditionsQuery {
    fn validate(&self) -> Result<(), AppError> {
        // Initial Jabodetabek service envelope, not an administrative boundary.
        if !self.latitude.is_finite()
            || !(-6.9..=-5.8).contains(&self.latitude)
            || !self.longitude.is_finite()
            || !(106.3..=107.3).contains(&self.longitude)
        {
            return Err(AppError::bad_request(
                "Coordinates must be within the initial Greater Jakarta service area (-6.9..-5.8 latitude, 106.3..107.3 longitude)",
            ));
        }
        if let Some(code) = &self.adm4 {
            let parts: Vec<_> = code.split('.').collect();
            if parts.len() != 4
                || parts.iter().zip([2, 2, 2, 4]).any(|(part, len)| {
                    part.len() != len || !part.bytes().all(|c| c.is_ascii_digit())
                })
            {
                return Err(AppError::bad_request(
                    "adm4 must use the BMKG village format NN.NN.NN.NNNN",
                ));
            }
        }
        Ok(())
    }
}

#[derive(Clone)]
pub struct ConditionsService {
    client: reqwest::Client,
    open_meteo: String,
    bmkg: String,
    openaq: String,
    tomtom: String,
    openaq_key: Option<String>,
    tomtom_key: Option<String>,
    permits: Arc<Semaphore>,
}

impl ConditionsService {
    pub fn from_env() -> Self {
        fn key(name: &str) -> Option<String> {
            std::env::var(name)
                .ok()
                .map(|v| v.trim().to_owned())
                .filter(|v| !v.is_empty())
        }
        Self {
            client: reqwest::Client::builder()
                .connect_timeout(Duration::from_secs(2))
                .timeout(Duration::from_secs(4))
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .expect("HTTP client configuration"),
            open_meteo: "https://api.open-meteo.com/v1/forecast".into(),
            bmkg: "https://api.bmkg.go.id/publik/prakiraan-cuaca".into(),
            openaq: "https://api.openaq.org/v3".into(),
            tomtom: "https://api.tomtom.com/traffic/services/4/flowSegmentData/absolute/16/json"
                .into(),
            openaq_key: key("OPENAQ_API_KEY"),
            tomtom_key: key("TOMTOM_API_KEY"),
            permits: Arc::new(Semaphore::new(8)),
        }
    }

    async fn get(&self, request: reqwest::RequestBuilder) -> Result<Value, &'static str> {
        // Do not log reqwest errors or URLs: TomTom credentials are in query strings.
        let response = request.send().await.map_err(|_| "provider_unreachable")?;
        match response.status().as_u16() {
            200 => {}
            401 | 403 => return Err("provider_access_denied"),
            429 => return Err("provider_rate_limited"),
            _ => return Err("provider_error"),
        }
        // Bound payload memory even if an upstream sends an oversized response.
        let mut response = response;
        let mut body = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(|_| "provider_unreachable")? {
            if body.len() + chunk.len() > 2_000_000 {
                return Err("invalid_provider_response");
            }
            body.extend_from_slice(&chunk);
        }
        serde_json::from_slice(&body).map_err(|_| "invalid_provider_response")
    }

    async fn weather(&self, q: &ConditionsQuery) -> Signal {
        let primary = self.get(self.client.get(&self.open_meteo).query(&[
            ("latitude", q.latitude.to_string()), ("longitude", q.longitude.to_string()),
            ("current", "temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m".into()),
            ("timeformat", "unixtime".into()), ("timezone", "GMT".into()),
            ("temperature_unit", "celsius".into()), ("wind_speed_unit", "kmh".into()),
            ("precipitation_unit", "mm".into()),
        ])).await.and_then(|value| parse_weather(&value));
        if let Ok(signal) = primary {
            return signal;
        }
        let Some(code) = &q.adm4 else {
            return Signal::missing(
                "open_meteo",
                "Weather unavailable. BMKG fallback requires the matching village adm4 code.",
            );
        };
        match self
            .get(self.client.get(&self.bmkg).query(&[("adm4", code)]))
            .await
            .and_then(|value| parse_bmkg(&value, q))
        {
            Ok(signal) => signal,
            Err(reason) => Signal::missing("bmkg", reason),
        }
    }

    async fn air_quality(&self, q: &ConditionsQuery) -> Signal {
        let Some(key) = &self.openaq_key else {
            return Signal::missing("openaq", "not_configured");
        };
        let locations = match self
            .get(
                self.client
                    .get(format!("{}/locations", self.openaq))
                    .header("X-API-Key", key)
                    .query(&[
                        ("coordinates", format!("{},{}", q.latitude, q.longitude)),
                        ("radius", "25000".into()),
                        ("limit", "100".into()),
                        ("parameters_id", "2".into()),
                    ]),
            )
            .await
        {
            Ok(value) => value,
            Err(reason) => return Signal::missing("openaq", reason),
        };
        let Some(results) = locations["results"].as_array() else {
            return Signal::missing("openaq", "invalid_provider_response");
        };
        let mut candidates: Vec<_> = results
            .iter()
            .filter_map(|station| {
                if station["isMobile"].as_bool() != Some(false) {
                    return None;
                }
                let lat = station["coordinates"]["latitude"].as_f64()?;
                let lon = station["coordinates"]["longitude"].as_f64()?;
                if !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lon) {
                    return None;
                }
                let distance = distance_km(q.latitude, q.longitude, lat, lon);
                (distance.is_finite() && distance <= 25.0).then_some((distance, station))
            })
            .collect();
        candidates.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut stale = None;
        // Bounded fan-out: examine the nearest three candidates, not all stations.
        for (distance, station) in candidates.into_iter().take(3) {
            let Some(id) = station["id"].as_u64() else {
                continue;
            };
            let Ok(latest) = self
                .get(
                    self.client
                        .get(format!("{}/locations/{id}/latest", self.openaq))
                        .header("X-API-Key", key)
                        .query(&[("limit", "100")]),
                )
                .await
            else {
                continue;
            };
            if let Some(signal) = parse_air_quality(station, &latest, distance) {
                if signal.status == "available" {
                    return signal;
                }
                if stale.is_none() {
                    stale = Some(signal);
                }
            }
        }
        stale.unwrap_or_else(|| {
            Signal::missing(
                "openaq",
                "No usable PM2.5 reading from the nearest three stations within 25 km.",
            )
        })
    }

    async fn traffic(&self, q: &ConditionsQuery) -> Signal {
        let Some(key) = &self.tomtom_key else {
            return Signal::missing("tomtom", "not_configured");
        };
        match self
            .get(self.client.get(&self.tomtom).query(&[
                ("key", key.to_owned()),
                ("point", format!("{},{}", q.latitude, q.longitude)),
                ("unit", "kmph".into()),
            ]))
            .await
            .and_then(|v| parse_traffic(&v))
        {
            Ok(signal) => signal,
            Err(reason) => Signal::missing("tomtom", reason),
        }
    }

    pub(crate) async fn lookup(&self, q: &ConditionsQuery) -> ConditionsResponse {
        async fn bounded(
            source: &'static str,
            f: impl std::future::Future<Output = Signal>,
        ) -> Signal {
            tokio::time::timeout(SIGNAL_TIMEOUT, f)
                .await
                .unwrap_or_else(|_| Signal::missing(source, "provider_timeout"))
        }
        let (weather, air_quality, traffic) = tokio::join!(
            bounded("open_meteo", self.weather(q)),
            bounded("openaq", self.air_quality(q)),
            bounded("tomtom", self.traffic(q)),
        );
        ConditionsResponse {
            latitude: q.latitude,
            longitude: q.longitude,
            retrieved_at: Utc::now(),
            weather,
            air_quality,
            traffic,
        }
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct Signal {
    pub status: &'static str,
    pub source: &'static str,
    pub kind: Option<&'static str>,
    pub valid_at: Option<DateTime<Utc>>,
    pub message: String,
    pub data: Option<Value>,
}

impl Signal {
    fn missing(source: &'static str, reason: &str) -> Self {
        Self {
            status: "unavailable",
            source,
            kind: None,
            valid_at: None,
            message: reason.into(),
            data: None,
        }
    }
}

#[derive(Clone, Serialize)]
pub struct ConditionsResponse {
    pub latitude: f64,
    pub longitude: f64,
    pub retrieved_at: DateTime<Utc>,
    pub weather: Signal,
    pub air_quality: Signal,
    pub traffic: Signal,
}

pub async fn current(
    Extension(service): Extension<Arc<ConditionsService>>,
    ValidatedQuery(query): ValidatedQuery<ConditionsQuery>,
) -> AppResult<Json<ConditionsResponse>> {
    // Fail fast instead of queueing unbounded fan-out against upstream quotas.
    let _permit = service
        .permits
        .try_acquire()
        .map_err(|_| AppError::Unavailable)?;
    Ok(Json(service.lookup(&query).await))
}

fn number(value: &Value, key: &str, min: f64, max: f64) -> Result<f64, &'static str> {
    value[key]
        .as_f64()
        .filter(|v| v.is_finite() && (*v >= min && *v <= max))
        .ok_or("invalid_provider_response")
}

fn parse_weather(value: &Value) -> Result<Signal, &'static str> {
    let current = &value["current"];
    let time = DateTime::from_timestamp(
        current["time"]
            .as_i64()
            .ok_or("invalid_provider_response")?,
        0,
    )
    .ok_or("invalid_provider_response")?;
    if (Utc::now() - time).num_minutes() > 120 || time > Utc::now() + chrono::Duration::minutes(15)
    {
        return Err("stale_provider_data");
    }
    let temperature = number(current, "temperature_2m", -60.0, 65.0)?;
    let humidity = number(current, "relative_humidity_2m", 0.0, 100.0)?;
    let precipitation = number(current, "precipitation", 0.0, 1000.0)?;
    let wind = number(current, "wind_speed_10m", 0.0, 500.0)?;
    let interval = current["interval"]
        .as_u64()
        .filter(|v| *v > 0 && *v <= 3600)
        .ok_or("invalid_provider_response")?;
    Ok(Signal { status: "available", source: "open_meteo", kind: Some("model_estimate"), valid_at: Some(time),
        message: "Weather data by Open-Meteo.com (https://open-meteo.com/). Model estimate, not a station observation.".into(),
        data: Some(serde_json::json!({ "temperature_c": temperature, "humidity_percent": humidity,
            "precipitation_mm": precipitation, "interval_seconds": interval, "wind_speed_kmh": wind,
            "weather_code": current["weather_code"], "model_latitude": value["latitude"], "model_longitude": value["longitude"] })) })
}

fn parse_bmkg(value: &Value, q: &ConditionsQuery) -> Result<Signal, &'static str> {
    let location = &value["lokasi"];
    if location["adm4"].as_str() != q.adm4.as_deref() {
        return Err("invalid_provider_response");
    }
    let lat = number(location, "lat", -90.0, 90.0)?;
    let lon = number(location, "lon", -180.0, 180.0)?;
    if distance_km(q.latitude, q.longitude, lat, lon) > 15.0 {
        return Err("BMKG village is too far from the requested coordinates");
    }
    let mut entries = Vec::new();
    for area in value["data"]
        .as_array()
        .ok_or("invalid_provider_response")?
    {
        for group in area["cuaca"]
            .as_array()
            .ok_or("invalid_provider_response")?
        {
            for entry in group.as_array().ok_or("invalid_provider_response")? {
                let Some(raw_time) = entry["utc_datetime"].as_str() else {
                    continue;
                };
                let Ok(time) = chrono::NaiveDateTime::parse_from_str(raw_time, "%Y-%m-%d %H:%M:%S")
                else {
                    continue;
                };
                let time = time.and_utc();
                if time >= Utc::now() && time <= Utc::now() + chrono::Duration::hours(6) {
                    entries.push((time, entry));
                }
            }
        }
    }
    entries.sort_by_key(|(time, _)| *time);
    let (time, entry) = entries
        .first()
        .ok_or("No upcoming BMKG forecast within six hours")?;
    let issued = entry["analysis_date"]
        .as_str()
        .and_then(|s| {
            DateTime::parse_from_rfc3339(s)
                .map(|v| v.with_timezone(&Utc))
                .ok()
                .or_else(|| {
                    chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%S")
                        .ok()
                        .map(|v| v.and_utc())
                })
        })
        .ok_or("invalid_provider_response")?;
    if issued < Utc::now() - chrono::Duration::hours(24)
        || issued > Utc::now() + chrono::Duration::minutes(15)
    {
        return Err("stale_provider_data");
    }
    let temperature = number(entry, "t", -60.0, 65.0)?;
    let humidity = number(entry, "hu", 0.0, 100.0)?;
    Ok(Signal { status: "available", source: "bmkg", kind: Some("provider_forecast"), valid_at: Some(*time),
        message: "Sumber: BMKG (https://www.bmkg.go.id/). Upcoming three-hourly forecast, not current observed weather. Open-Meteo was unavailable.".into(),
        data: Some(serde_json::json!({ "temperature_c": temperature, "humidity_percent": humidity,
            "description": entry["weather_desc"], "issued_at": issued, "village": location["desa"],
            "model_latitude": lat, "model_longitude": lon })) })
}

fn parse_air_quality(station: &Value, latest: &Value, distance: f64) -> Option<Signal> {
    let sensors = station["sensors"].as_array()?;
    let mut readings = Vec::new();
    for reading in latest["results"].as_array()? {
        let Some(sensor) = sensors.iter().find(|s| s["id"] == reading["sensorsId"]) else {
            continue;
        };
        if sensor["parameter"]["name"] != "pm25" {
            continue;
        }
        let unit = sensor["parameter"]["units"].as_str()?;
        if !matches!(unit, "µg/m³" | "μg/m³" | "ug/m3") {
            continue;
        }
        let value = reading["value"].as_f64()?;
        if !value.is_finite() || value < 0.0 {
            continue;
        }
        let time = DateTime::parse_from_rfc3339(reading["datetime"]["utc"].as_str()?)
            .ok()?
            .with_timezone(&Utc);
        if time > Utc::now() + chrono::Duration::minutes(15) {
            continue;
        }
        readings.push((time, value));
    }
    let (time, value) = readings.into_iter().max_by_key(|(t, _)| *t)?;
    let stale = time < Utc::now() - chrono::Duration::hours(MAX_AIR_AGE_HOURS);
    Some(Signal { status: if stale { "stale" } else { "available" }, source: "openaq", kind: Some("station_observation"), valid_at: Some(time),
        message: "OpenAQ (https://openaq.org/), attributed to the station's provider/owner below. Nearby station PM2.5 is not a computed AQI or a measurement at your exact point.".into(),
        data: Some(serde_json::json!({ "pm25_ug_m3": value, "station_id": station["id"],
            "station_name": station["name"], "distance_km": distance, "coordinates": station["coordinates"],
            "provider": station["provider"], "owner": station["owner"], "licenses": station["licenses"] })) })
}

fn parse_traffic(value: &Value) -> Result<Signal, &'static str> {
    let flow = &value["flowSegmentData"];
    let speed = number(flow, "currentSpeed", 0.0, 300.0)?;
    let free_flow = number(flow, "freeFlowSpeed", 0.0, 300.0)?;
    let travel_time = number(flow, "currentTravelTime", 0.0, 86400.0)?;
    let free_time = number(flow, "freeFlowTravelTime", 0.0, 86400.0)?;
    let confidence = number(flow, "confidence", 0.0, 1.0)?;
    let closure = flow["roadClosure"]
        .as_bool()
        .ok_or("invalid_provider_response")?;
    let geometry = flow["coordinates"]["coordinate"]
        .as_array()
        .filter(|v| v.len() >= 2)
        .ok_or("invalid_provider_response")?;
    for point in geometry {
        number(point, "latitude", -90.0, 90.0)?;
        number(point, "longitude", -180.0, 180.0)?;
    }
    Ok(Signal { status: "available", source: "tomtom", kind: Some("provider_live_estimate"), valid_at: None,
        message: "Traffic data © TomTom. Nearest returned road fragment, not a matched route or whole-area condition. Provider observation timestamp is unavailable; see retrieved_at.".into(),
        data: Some(serde_json::json!({ "speed_kmh": speed, "free_flow_speed_kmh": free_flow,
            "travel_time_seconds": travel_time, "free_flow_time_seconds": free_time,
            "confidence": confidence, "road_closed": closure, "coordinates": geometry })) })
}

fn distance_km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let a = ((lat2 - lat1).to_radians() / 2.0).sin().powi(2)
        + lat1.to_radians().cos()
            * lat2.to_radians().cos()
            * ((lon2 - lon1).to_radians() / 2.0).sin().powi(2);
    6371.0 * 2.0 * a.clamp(0.0, 1.0).sqrt().asin()
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        Router,
        body::{Body, to_bytes},
        http::{Request, StatusCode},
        routing::get,
    };
    use serde_json::json;
    use tower::ServiceExt;

    fn weather() -> Value {
        json!({ "latitude": -6.2, "longitude": 106.8, "current": {
            "time": Utc::now().timestamp(), "interval": 900,
            "temperature_2m": 30, "relative_humidity_2m": 80, "precipitation": 0.2,
            "wind_speed_10m": 4, "weather_code": 3 } })
    }

    fn bmkg() -> Value {
        json!({ "lokasi": { "adm4": "31.71.03.1001", "lat": -6.2, "lon": 106.8, "desa": "Test village" },
            "data": [{ "cuaca": [[{
                "utc_datetime": (Utc::now() + chrono::Duration::hours(1)).format("%Y-%m-%d %H:%M:%S").to_string(),
                "analysis_date": Utc::now().to_rfc3339(), "t": 29, "hu": 80, "weather_desc": "Berawan" }]] }] })
    }

    fn station() -> Value {
        json!({ "id": 123, "name": "Test monitor", "isMobile": false,
            "coordinates": { "latitude": -6.2, "longitude": 106.8 },
            "provider": { "name": "Test provider" }, "licenses": [{ "name": "Test license" }],
            "sensors": [{ "id": 456, "parameter": { "name": "pm25", "units": "µg/m³" } }] })
    }

    fn latest(time: DateTime<Utc>) -> Value {
        json!({ "results": [{ "sensorsId": 456, "value": 18.5, "datetime": { "utc": time.to_rfc3339() } }] })
    }

    fn traffic() -> Value {
        json!({ "flowSegmentData": { "currentSpeed": 20, "freeFlowSpeed": 50,
            "currentTravelTime": 120, "freeFlowTravelTime": 48, "confidence": 0.9, "roadClosure": false,
            "coordinates": { "coordinate": [{ "latitude": -6.2, "longitude": 106.8 }, { "latitude": -6.21, "longitude": 106.8 }] } } })
    }

    struct Mock {
        service: ConditionsService,
        server: tokio::task::JoinHandle<()>,
    }
    impl Drop for Mock {
        fn drop(&mut self) {
            self.server.abort();
        }
    }

    async fn mock(weather_fails: bool) -> Mock {
        let router = Router::new()
            .route("/denied", get(|| async { StatusCode::FORBIDDEN }))
            .route("/limited", get(|| async { StatusCode::TOO_MANY_REQUESTS }))
            .route(
                "/malformed",
                get(|| async { "<html>upstream proxy</html>" }),
            )
            .route(
                "/slow",
                get(|| async {
                    tokio::time::sleep(Duration::from_millis(200)).await;
                    Json(weather())
                }),
            )
            .route(
                "/weather",
                get(
                    move |axum::extract::Query(q): axum::extract::Query<
                        std::collections::HashMap<String, String>,
                    >| async move {
                        assert_eq!(q["timeformat"], "unixtime");
                        if weather_fails {
                            (StatusCode::SERVICE_UNAVAILABLE, Json(json!({})))
                        } else {
                            (StatusCode::OK, Json(weather()))
                        }
                    },
                ),
            )
            .route(
                "/bmkg",
                get(
                    |axum::extract::Query(q): axum::extract::Query<
                        std::collections::HashMap<String, String>,
                    >| async move {
                        assert_eq!(q["adm4"], "31.71.03.1001");
                        Json(bmkg())
                    },
                ),
            )
            .route(
                "/aq/locations",
                get(|headers: axum::http::HeaderMap| async move {
                    assert_eq!(headers["X-API-Key"], "fake-openaq-key");
                    Json(json!({ "results": [station()] }))
                }),
            )
            .route(
                "/aq/locations/123/latest",
                get(|| async { Json(latest(Utc::now())) }),
            )
            .route(
                "/traffic",
                get(
                    |axum::extract::Query(q): axum::extract::Query<
                        std::collections::HashMap<String, String>,
                    >| async move {
                        assert_eq!(q["key"], "fake-tomtom-key");
                        assert_eq!(q["point"], "-6.2,106.8");
                        Json(traffic())
                    },
                ),
            );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async { axum::serve(listener, router).await.unwrap() });
        let mut service = ConditionsService::from_env();
        service.open_meteo = format!("{base}/weather");
        service.bmkg = format!("{base}/bmkg");
        service.openaq = format!("{base}/aq");
        service.tomtom = format!("{base}/traffic");
        service.openaq_key = Some("fake-openaq-key".into());
        service.tomtom_key = Some("fake-tomtom-key".into());
        Mock { service, server }
    }

    fn query() -> ConditionsQuery {
        ConditionsQuery {
            latitude: -6.2,
            longitude: 106.8,
            adm4: None,
        }
    }

    #[tokio::test]
    async fn authenticated_http_lookup_normalizes_three_providers() {
        let mock = mock(false).await;
        let fixture = crate::auth::test_support::Fixture::new().await;
        let state = crate::db::AppState {
            pool: sqlx::postgres::PgPoolOptions::new()
                .connect_lazy("postgres://localhost/unused_test")
                .unwrap(),
        };
        let app = crate::routes::create_router_with_conditions(
            state,
            fixture.verifier.clone(),
            Arc::new(mock.service.clone()),
        );
        let path = "/api/conditions/current?latitude=-6.2&longitude=106.8";
        let response = app
            .clone()
            .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        let token = fixture.token(uuid::Uuid::new_v4(), "test@example.com");
        let response = app
            .oneshot(
                Request::builder()
                    .uri(path)
                    .header("Authorization", format!("Bearer {token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body: Value =
            serde_json::from_slice(&to_bytes(response.into_body(), 65536).await.unwrap()).unwrap();
        assert_eq!(body["weather"]["status"], "available");
        assert_eq!(body["weather"]["kind"], "model_estimate");
        assert_eq!(body["air_quality"]["data"]["pm25_ug_m3"], 18.5);
        assert!(body["air_quality"]["data"].get("aqi").is_none());
        assert_eq!(body["traffic"]["data"]["speed_kmh"].as_f64(), Some(20.0));
        assert!(body["traffic"]["valid_at"].is_null());
        assert!(!body.to_string().contains("fake-openaq-key"));
        assert!(!body.to_string().contains("fake-tomtom-key"));
    }

    #[tokio::test]
    async fn weather_outage_falls_back_without_discarding_other_signals() {
        let mock = mock(true).await;
        let mut q = query();
        let response = mock.service.lookup(&q).await;
        assert_eq!(response.weather.status, "unavailable");
        assert_eq!(response.air_quality.status, "available");
        q.adm4 = Some("31.71.03.1001".into());
        let response = mock.service.lookup(&q).await;
        assert_eq!(response.weather.source, "bmkg");
        assert_eq!(response.weather.kind, Some("provider_forecast"));
        assert!(response.weather.valid_at.unwrap() > Utc::now());
    }

    #[tokio::test]
    async fn absent_credentials_and_bad_responses_are_explicit() {
        let mut mock = mock(false).await;
        mock.service.openaq_key = None;
        mock.service.tomtom_key = None;
        let response = mock.service.lookup(&query()).await;
        assert_eq!(response.weather.status, "available");
        assert_eq!(response.air_quality.message, "not_configured");
        assert_eq!(response.traffic.message, "not_configured");
        assert!(parse_weather(&json!({})).is_err());
        assert!(parse_traffic(&json!({})).is_err());
        assert_eq!(
            parse_air_quality(
                &station(),
                &latest(Utc::now() - chrono::Duration::hours(5)),
                2.0
            )
            .unwrap()
            .status,
            "stale"
        );
        assert!(
            parse_air_quality(
                &station(),
                &latest(Utc::now() + chrono::Duration::hours(5)),
                2.0
            )
            .is_none()
        );
        let mut wrong_area = query();
        wrong_area.latitude = -6.6;
        assert!(parse_bmkg(&bmkg(), &wrong_area).is_err());
    }

    #[tokio::test]
    async fn http_access_rate_limit_malformed_and_timeout_failures_are_sanitized() {
        let mut mock = mock(false).await;
        let base = mock
            .service
            .open_meteo
            .trim_end_matches("/weather")
            .to_owned();
        for (path, expected) in [
            ("denied", "provider_access_denied"),
            ("limited", "provider_rate_limited"),
            ("malformed", "invalid_provider_response"),
        ] {
            let result = mock
                .service
                .get(mock.service.client.get(format!("{base}/{path}")))
                .await;
            assert_eq!(result.unwrap_err(), expected);
        }
        mock.service.client = reqwest::Client::builder()
            .timeout(Duration::from_millis(30))
            .build()
            .unwrap();
        mock.service.open_meteo = format!("{base}/slow");
        let response = mock.service.lookup(&query()).await;
        assert_eq!(response.weather.status, "unavailable");
        assert_eq!(response.traffic.status, "available");
    }

    #[test]
    fn query_validation_rejects_invalid_or_out_of_scope_coordinates() {
        assert!(query().validate().is_ok());
        for lat in [0.0, f64::NAN, -7.0] {
            let mut q = query();
            q.latitude = lat;
            assert!(q.validate().is_err());
        }
        let mut q = query();
        q.adm4 = Some("invalid".into());
        assert!(q.validate().is_err());
    }
}
