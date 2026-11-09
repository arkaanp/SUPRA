//! Mode-specific provider routing. Server URLs are operator configuration, not user input.
use crate::{
    error::{AppError, AppResult},
    validation::{Validate, ValidatedJson},
};
use axum::{Json, extract::Extension};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{sync::Arc, time::Duration};
use tokio::{sync::Mutex, time::Instant};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Point {
    pub latitude: f64,
    pub longitude: f64,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PlanInput {
    pub origin: Point,
    pub destination: Point,
    pub mode: String,
}
impl Validate for PlanInput {
    fn validate(&self) -> AppResult<()> {
        if !crate::commutes::coordinate(self.origin.latitude, self.origin.longitude)
            || !crate::commutes::coordinate(self.destination.latitude, self.destination.longitude)
            || !matches!(self.mode.as_str(), "walk" | "motorcycle" | "public_transit")
        {
            return Err(AppError::bad_request(
                "Use valid Greater Jakarta endpoints and walk, motorcycle or public_transit mode",
            ));
        }
        Ok(())
    }
}
#[derive(Serialize)]
pub struct PlannedRoute {
    mode: String,
    source: &'static str,
    fetched_at: DateTime<Utc>,
    duration_seconds: f64,
    distance_km: f64,
    waypoints: Vec<[f64; 2]>,
    steps: Vec<String>,
}
pub struct MobilityService {
    client: reqwest::Client,
    valhalla: String,
    otp: Option<String>,
    gate: Mutex<Instant>,
}
impl MobilityService {
    pub fn from_env() -> Self {
        Self {
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(10))
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .expect("routing HTTP configuration"),
            valhalla: std::env::var("VALHALLA_ROUTE_URL")
                .unwrap_or_else(|_| "https://valhalla1.openstreetmap.de/route".into()),
            otp: std::env::var("OTP_GRAPHQL_URL")
                .ok()
                .filter(|s| !s.trim().is_empty()),
            gate: Mutex::new(Instant::now()),
        }
    }
    #[cfg(test)]
    pub fn for_test(valhalla: String, otp: Option<String>) -> Self {
        Self {
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(5))
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .expect("routing HTTP configuration"),
            valhalla,
            otp,
            gate: Mutex::new(Instant::now()),
        }
    }
    async fn post(&self, url: &str, body: Value) -> AppResult<Value> {
        let response = self
            .client
            .post(url)
            .json(&body)
            .send()
            .await
            .map_err(|_| AppError::Unavailable)?;
        if !response.status().is_success() {
            return Err(AppError::Unavailable);
        }
        let mut response = response;
        let mut bytes = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(|_| AppError::Unavailable)? {
            if bytes.len() + chunk.len() > 2_000_000 {
                return Err(AppError::Unavailable);
            }
            bytes.extend_from_slice(&chunk);
        }
        serde_json::from_slice(&bytes).map_err(|_| AppError::Unavailable)
    }
    async fn route(&self, p: &PlanInput) -> AppResult<PlannedRoute> {
        let (source, distance, duration, points, steps) = if p.mode == "public_transit" {
            let url = self.otp.as_deref().ok_or(AppError::Unavailable)?;
            let local = Utc::now() + chrono::Duration::hours(7);
            // OTP 2.x GTFS API's documented plan query; deployment must contain licensed Jakarta GTFS.
            let query = format!(
                "{{plan(from:{{lat:{},lon:{}}},to:{{lat:{},lon:{}}},date:\"{}\",time:\"{}\",transportModes:[{{mode:WALK}},{{mode:TRANSIT}}],numItineraries:1){{itineraries{{duration legs{{transitLeg mode distance from{{name}} to{{name}} route{{shortName}} legGeometry{{points}}}}}}}}}}",
                p.origin.latitude,
                p.origin.longitude,
                p.destination.latitude,
                p.destination.longitude,
                local.format("%Y-%m-%d"),
                local.format("%H:%M:%S")
            );
            let value = self.post(url, json!({"query":query})).await?;
            parse_otp(&value)?
        } else {
            {
                // Public service limit: at most one request/second, shared by this server process.
                let mut gate = self.gate.lock().await;
                tokio::time::sleep_until(*gate).await;
                *gate = Instant::now() + Duration::from_millis(1100);
            }
            let costing = if p.mode == "walk" {
                "pedestrian"
            } else {
                "motorcycle"
            };
            let value=self.post(&self.valhalla,json!({"locations":[
                {"lat":p.origin.latitude,"lon":p.origin.longitude},
                {"lat":p.destination.latitude,"lon":p.destination.longitude}],
                "costing":costing,"units":"kilometers","language":"en-US","shape_format":"polyline6"})).await?;
            parse_valhalla(&value)?
        };
        if points.len() < 2
            || points.len() > 10000
            || !distance.is_finite()
            || distance <= 0.0
            || distance > 500.0
            || !duration.is_finite()
            || duration <= 0.0
            || duration > 86400.0
            || points.iter().any(|pt| {
                !pt[0].is_finite()
                    || !pt[1].is_finite()
                    || pt[0].abs() > 90.0
                    || pt[1].abs() > 180.0
            })
            || crate::alerts::distance_km(points[0], [p.origin.latitude, p.origin.longitude]) > 2.0
            || crate::alerts::distance_km(
                *points.last().unwrap(),
                [p.destination.latitude, p.destination.longitude],
            ) > 2.0
        {
            return Err(AppError::Unavailable);
        }
        Ok(PlannedRoute {
            mode: p.mode.clone(),
            source,
            fetched_at: Utc::now(),
            duration_seconds: duration,
            distance_km: distance,
            waypoints: points,
            steps,
        })
    }
}
type Parsed = (&'static str, f64, f64, Vec<[f64; 2]>, Vec<String>);
fn parse_valhalla(v: &Value) -> AppResult<Parsed> {
    let trip = &v["trip"];
    if trip["status"].as_i64() != Some(0) {
        return Err(AppError::Unavailable);
    }
    let distance = trip["summary"]["length"]
        .as_f64()
        .ok_or(AppError::Unavailable)?;
    let duration = trip["summary"]["time"]
        .as_f64()
        .ok_or(AppError::Unavailable)?;
    let mut points = Vec::new();
    let mut steps = Vec::new();
    for leg in trip["legs"].as_array().ok_or(AppError::Unavailable)? {
        points.extend(decode_polyline(
            leg["shape"].as_str().ok_or(AppError::Unavailable)?,
            6,
        )?);
        if let Some(items) = leg["maneuvers"].as_array() {
            steps.extend(
                items
                    .iter()
                    .filter_map(|m| m["instruction"].as_str())
                    .take(100)
                    .map(|s| s.chars().take(300).collect::<String>()),
            );
        }
    }
    Ok(("valhalla", distance, duration, points, steps))
}
fn parse_otp(v: &Value) -> AppResult<Parsed> {
    if v.get("errors").is_some() {
        return Err(AppError::Unavailable);
    }
    let itinerary = v
        .pointer("/data/plan/itineraries/0")
        .ok_or(AppError::NotFound)?;
    let legs = itinerary["legs"].as_array().ok_or(AppError::Unavailable)?;
    if !legs.iter().any(|l| l["transitLeg"] == true) {
        return Err(AppError::NotFound);
    }
    let mut points = Vec::new();
    let mut steps = Vec::new();
    let mut distance = 0.0;
    for leg in legs {
        points.extend(decode_polyline(
            leg["legGeometry"]["points"]
                .as_str()
                .ok_or(AppError::Unavailable)?,
            5,
        )?);
        distance += leg["distance"].as_f64().ok_or(AppError::Unavailable)? / 1000.0;
        steps.push(format!(
            "{} {}: {} → {}",
            leg["mode"].as_str().unwrap_or("Transit"),
            leg["route"]["shortName"].as_str().unwrap_or(""),
            leg["from"]["name"].as_str().unwrap_or("Stop"),
            leg["to"]["name"].as_str().unwrap_or("Stop")
        ));
    }
    Ok((
        "opentripplanner_gtfs",
        distance,
        itinerary["duration"]
            .as_f64()
            .ok_or(AppError::Unavailable)?,
        points,
        steps,
    ))
}
fn decode_polyline(encoded: &str, precision: i32) -> AppResult<Vec<[f64; 2]>> {
    let bytes = encoded.as_bytes();
    let mut at = 0;
    let mut lat = 0_i64;
    let mut lon = 0_i64;
    let mut points = Vec::new();
    fn next(bytes: &[u8], at: &mut usize) -> AppResult<i64> {
        let mut value = 0_i64;
        let mut shift = 0;
        loop {
            let raw = *bytes.get(*at).ok_or(AppError::Unavailable)?;
            if !(63..=126).contains(&raw) || shift > 55 {
                return Err(AppError::Unavailable);
            }
            *at += 1;
            let b = (raw - 63) as i64;
            value |= (b & 31) << shift;
            shift += 5;
            if b < 32 {
                break;
            }
        }
        Ok(if value & 1 != 0 {
            !(value >> 1)
        } else {
            value >> 1
        })
    }
    while at < bytes.len() {
        if points.len() >= 10000 {
            return Err(AppError::Unavailable);
        }
        lat = lat
            .checked_add(next(bytes, &mut at)?)
            .ok_or(AppError::Unavailable)?;
        lon = lon
            .checked_add(next(bytes, &mut at)?)
            .ok_or(AppError::Unavailable)?;
        points.push([
            lat as f64 / 10_f64.powi(precision),
            lon as f64 / 10_f64.powi(precision),
        ]);
    }
    Ok(points)
}
pub async fn plan(
    Extension(service): Extension<Arc<MobilityService>>,
    ValidatedJson(p): ValidatedJson<PlanInput>,
) -> AppResult<Json<PlannedRoute>> {
    Ok(Json(service.route(&p).await?))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn decodes_provider_geometry_and_rejects_broken_shapes() {
        assert_eq!(
            decode_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@", 5).unwrap()[0],
            [38.5, -120.2]
        );
        assert!(decode_polyline("~~~~", 6).is_err());
        assert!(
            parse_otp(&json!({"data":{"plan":{"itineraries":[{"legs":[{"transitLeg":false}]}]}}}))
                .is_err()
        );
    }

    fn encode_polyline(points: &[[f64; 2]], precision: i32) -> String {
        let mut out = String::new();
        let mut last_lat = 0_i64;
        let mut last_lon = 0_i64;
        let factor = 10_f64.powi(precision);
        for pt in points {
            let lat = (pt[0] * factor).round() as i64;
            let lon = (pt[1] * factor).round() as i64;
            let d_lat = lat - last_lat;
            let d_lon = lon - last_lon;
            last_lat = lat;
            last_lon = lon;
            for v in [d_lat, d_lon] {
                let mut num = if v < 0 { !(v << 1) } else { v << 1 };
                while num >= 0x20 {
                    out.push((((num & 0x1f) | 0x20) as u8 + 63) as char);
                    num >>= 5;
                }
                out.push(((num & 0x1f) as u8 + 63) as char);
            }
        }
        out
    }

    #[tokio::test]
    async fn real_http_stand_in_routes_valhalla_and_otp() {
        use axum::routing::post;
        let shape6 = encode_polyline(&[[-6.2, 106.8], [-6.21, 106.81]], 6);
        let shape5 = encode_polyline(&[[-6.2, 106.8], [-6.21, 106.81]], 5);

        let valhalla_app = axum::Router::new().route(
            "/route",
            post(move || {
                let shape = shape6.clone();
                async move {
                    axum::Json(json!({
                        "trip": {
                            "status": 0,
                            "summary": {"length": 1.5, "time": 300.0},
                            "legs": [{
                                "shape": shape,
                                "maneuvers": [{"instruction": "Turn left on Jl. Sudirman"}]
                            }]
                        }
                    }))
                }
            }),
        );

        let otp_app = axum::Router::new().route(
            "/graphql",
            post(move || {
                let shape = shape5.clone();
                async move {
                    axum::Json(json!({
                        "data": {
                            "plan": {
                                "itineraries": [{
                                    "duration": 600.0,
                                    "legs": [{
                                        "transitLeg": true,
                                        "mode": "SUBWAY",
                                        "distance": 2000.0,
                                        "from": {"name": "Dukuh Atas"},
                                        "to": {"name": "Bundaran HI"},
                                        "route": {"shortName": "M1"},
                                        "legGeometry": {"points": shape}
                                    }]
                                }]
                            }
                        }
                    }))
                }
            }),
        );

        let listener_v = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port_v = listener_v.local_addr().unwrap().port();
        tokio::spawn(async move {
            axum::serve(listener_v, valhalla_app).await.unwrap();
        });

        let listener_o = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port_o = listener_o.local_addr().unwrap().port();
        tokio::spawn(async move {
            axum::serve(listener_o, otp_app).await.unwrap();
        });

        let service = MobilityService::for_test(
            format!("http://127.0.0.1:{port_v}/route"),
            Some(format!("http://127.0.0.1:{port_o}/graphql")),
        );

        // Walk mode via Valhalla
        let walk = service
            .route(&PlanInput {
                origin: Point {
                    latitude: -6.2,
                    longitude: 106.8,
                },
                destination: Point {
                    latitude: -6.21,
                    longitude: 106.81,
                },
                mode: "walk".into(),
            })
            .await
            .unwrap();
        assert_eq!(walk.source, "valhalla");
        assert_eq!(walk.waypoints.len(), 2);
        assert_eq!(walk.steps, vec!["Turn left on Jl. Sudirman"]);

        // Public transit via OTP
        let transit = service
            .route(&PlanInput {
                origin: Point {
                    latitude: -6.2,
                    longitude: 106.8,
                },
                destination: Point {
                    latitude: -6.21,
                    longitude: 106.81,
                },
                mode: "public_transit".into(),
            })
            .await
            .unwrap();
        assert_eq!(transit.source, "opentripplanner_gtfs");
        assert_eq!(transit.waypoints.len(), 2);
        assert!(transit.steps[0].contains("SUBWAY M1: Dukuh Atas → Bundaran HI"));
    }
}
