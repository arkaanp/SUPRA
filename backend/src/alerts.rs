//! Deterministic, idempotent inbox alerts. No LLM events or stale hazard evidence.
use crate::{
    auth::AuthUser,
    conditions::{ConditionsQuery, ConditionsResponse, ConditionsService, Signal},
    db::AppState,
    error::AppResult,
};
use axum::{
    Json,
    extract::{Extension, State},
};
use chrono::{DateTime, Datelike, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::FromRow;
use std::{sync::Arc, time::Duration};
use uuid::Uuid;

pub fn distance_km(a: [f64; 2], b: [f64; 2]) -> f64 {
    let lat = (b[0] - a[0]).to_radians();
    let lon = (b[1] - a[1]).to_radians();
    let h = (lat / 2.0).sin().powi(2)
        + a[0].to_radians().cos() * b[0].to_radians().cos() * (lon / 2.0).sin().powi(2);
    6371.0 * 2.0 * h.sqrt().min(1.0).asin()
}
pub fn due_departure(
    now: DateTime<Utc>,
    days: &[i16],
    minute: i32,
    lead: i32,
) -> Option<DateTime<Utc>> {
    let local = now + chrono::Duration::hours(7);
    for delta in 0..=1 {
        let date = local.date_naive() + chrono::Duration::days(delta);
        if !days.contains(&(date.weekday().num_days_from_monday() as i16)) {
            continue;
        }
        let departure = date
            .and_hms_opt((minute / 60) as u32, (minute % 60) as u32, 0)?
            .and_utc()
            - chrono::Duration::hours(7);
        if departure >= now && departure <= now + chrono::Duration::minutes(lead as i64) {
            return Some(departure);
        }
    }
    None
}
#[derive(FromRow)]
struct Target {
    id: Uuid,
    user_id: Uuid,
    label: String,
    mode: String,
    latitude: f64,
    longitude: f64,
    dest_latitude: f64,
    dest_longitude: f64,
    weekdays: Vec<i16>,
    departure_minute: i32,
    lead_minutes: i32,
    news_enabled: bool,
    air: bool,
    rain: bool,
    traffic: bool,
    news: bool,
    route_waypoints: Value,
    planned_departure: DateTime<Utc>,
    is_routine: bool,
}
#[derive(FromRow)]
struct SavedPlace {
    id: Uuid,
    user_id: Uuid,
    label: String,
    latitude: f64,
    longitude: f64,
}

struct Hazard {
    key: &'static str,
    title: &'static str,
    message: String,
    source: &'static str,
    valid_at: Option<DateTime<Utc>>,
    kind: Option<&'static str>,
}
fn fresh(s: &Signal, now: DateTime<Utc>) -> bool {
    s.status == "available"
        && s.kind != Some("provider_forecast")
        && s.data.is_some()
        && match s.valid_at {
            Some(at) => at <= now + chrono::Duration::minutes(10) && at >= now - chrono::Duration::hours(3),
            None => s.kind == Some("provider_live_estimate"),
        }
}
fn number(s: &Signal, key: &str) -> Option<f64> {
    s.data.as_ref()?[key]
        .as_f64()
        .filter(|v| v.is_finite() && *v >= 0.0)
}
fn hazards(
    c: &ConditionsResponse,
    now: DateTime<Utc>,
    air: bool,
    rain: bool,
    traffic: bool,
) -> Vec<Hazard> {
    let mut out = Vec::new();
    if air
        && fresh(&c.air_quality, now)
        && number(&c.air_quality, "pm25_ug_m3").is_some_and(|n| n >= 35.5)
    {
        out.push(Hazard{key:"air",title:"Elevated PM2.5 near your trip",message:format!(
            "Nearby station PM2.5: {:.1} µg/m³. This is an instantaneous station sample, not AQI or route-wide exposure. Consider reducing outdoor exposure.",number(&c.air_quality,"pm25_ug_m3").unwrap()),
            source:c.air_quality.source,valid_at:c.air_quality.valid_at,kind:c.air_quality.kind});
    }
    if rain
        && fresh(&c.weather, now)
        && number(&c.weather, "precipitation_mm").is_some_and(|n| n >= 1.0)
    {
        out.push(Hazard{key:"rain",title:"Rain near your trip",message:format!(
            "Precipitation {:.1} mm in the provider interval. Carry rain protection; wet surfaces may affect outdoor legs. Source is a model estimate, not a verified flood report.",number(&c.weather,"precipitation_mm").unwrap()),
            source:c.weather.source,valid_at:c.weather.valid_at,kind:c.weather.kind});
    }
    let closed = c
        .traffic
        .data
        .as_ref()
        .is_some_and(|d| d["road_closed"] == true);
    if traffic
        && fresh(&c.traffic, now)
        && number(&c.traffic, "confidence").is_some_and(|v| v >= 0.5)
        && (closed
            || matches!((number(&c.traffic,"speed_kmh"),number(&c.traffic,"free_flow_speed_kmh")),(Some(speed),Some(free)) if free>=10.0 && speed<free*0.5))
    {
        out.push(Hazard{key:"traffic",title:"Road disruption near your trip",message:if closed {"Provider reports a nearby road fragment closed.".into()} else {
            "Nearby road speed is below half its free-flow speed. This is not a route-wide delay prediction.".into()},
            source:c.traffic.source,valid_at:c.traffic.valid_at,kind:c.traffic.kind});
    }
    out
}

#[derive(Deserialize)]
struct Incident {
    id: String,
    title: String,
    source_url: String,
    latitude: f64,
    longitude: f64,
    published_at: DateTime<Utc>,
    starts_at: DateTime<Utc>,
    expires_at: DateTime<Utc>,
    verified: bool,
}
fn valid_incident(i: &Incident, now: DateTime<Utc>) -> bool {
    i.verified
        && !i.id.is_empty()
        && i.id.len() <= 200
        && !i.title.trim().is_empty()
        && i.title.len() <= 240
        && crate::commutes::coordinate(i.latitude, i.longitude)
        && i.source_url.len() <= 2000
        && reqwest::Url::parse(&i.source_url).is_ok_and(|u| {
            u.scheme() == "https"
                && u.host_str().is_some()
                && u.username().is_empty()
                && u.password().is_none()
        })
        && i.published_at <= now + chrono::Duration::minutes(5)
        && i.published_at >= now - chrono::Duration::hours(48)
        && i.expires_at > now
        && i.starts_at < i.expires_at
        && i.expires_at <= now + chrono::Duration::days(7)
}
async fn incidents() -> Vec<Incident> {
    let Ok(url) = std::env::var("NEWS_INCIDENTS_URL") else {
        return Vec::new();
    };
    let Ok(client) = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .redirect(reqwest::redirect::Policy::none())
        .build()
    else {
        return Vec::new();
    };
    let Ok(mut response) = client.get(url).send().await else {
        return Vec::new();
    };
    if !response.status().is_success() {
        return Vec::new();
    }
    let mut bytes = Vec::new();
    while let Ok(Some(chunk)) = response.chunk().await {
        if bytes.len() + chunk.len() > 1_000_000 {
            return Vec::new();
        }
        bytes.extend_from_slice(&chunk);
    }
    serde_json::from_slice::<Vec<Incident>>(&bytes)
        .unwrap_or_default()
        .into_iter()
        .take(100)
        .filter(|i| valid_incident(i, Utc::now()))
        .collect()
}
fn relevant(i: &Incident, t: &Target) -> bool {
    let point = [i.latitude, i.longitude];
    let path: Vec<[f64; 2]> = t
        .route_waypoints
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|p| Some([p["lat"].as_f64()?, p["lng"].as_f64()?]))
        .collect();
    if path.len() < 2 {
        return distance_km(point, [t.latitude, t.longitude])
            .min(distance_km(point, [t.dest_latitude, t.dest_longitude]))
            <= 3.0;
    }
    // Local equirectangular segment distance, only on actual saved geometry.
    let scale = 111.32 * point[0].to_radians().cos();
    let xy = |p: [f64; 2]| [p[1] * scale, p[0] * 110.574];
    let p = xy(point);
    path.windows(2).any(|s| {
        let a = xy(s[0]);
        let b = xy(s[1]);
        let dx = b[0] - a[0];
        let dy = b[1] - a[1];
        let len = dx * dx + dy * dy;
        let f = if len == 0.0 {
            0.0
        } else {
            ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len
        }
        .clamp(0.0, 1.0);
        ((p[0] - a[0] - f * dx).powi(2) + (p[1] - a[1] - f * dy).powi(2)).sqrt() <= 1.5
    })
}
/// Verified news can be relevant to a saved place even when no trip is active.
/// This keeps the manual "check now" action useful and prevents a missing
/// routine from turning news alerts into a silent no-op.
async fn evaluate_place_news(
    s: &AppState,
    news: &[Incident],
    user: Option<Uuid>,
    now: DateTime<Utc>,
) -> AppResult<u64> {
    if news.is_empty() {
        return Ok(0);
    }
    let places: Vec<SavedPlace> = sqlx::query_as(
        "SELECT p.id,p.user_id,p.label,p.latitude,p.longitude
         FROM saved_places p
         LEFT JOIN notification_preferences n ON n.user_id=p.user_id
         WHERE COALESCE(n.alert_relevant_news,true)
           AND ($1::uuid IS NULL OR p.user_id=$1)
         ORDER BY p.created_at
         LIMIT 200",
    )
    .bind(user)
    .fetch_all(&s.pool)
    .await?;
    let mut created = 0u64;
    for place in places {
        for i in news.iter().filter(|i| {
            i.starts_at <= now + chrono::Duration::hours(2)
                && i.expires_at > now
                && distance_km(
                    [i.latitude, i.longitude],
                    [place.latitude, place.longitude],
                ) <= 3.0
        }) {
            created += sqlx::query(
                "INSERT INTO notifications(user_id,title,message_body,severity,event_key,source_url,context)
                 VALUES($1,$2,$3,'medium',$4,$5,$6)
                 ON CONFLICT(user_id,event_key) WHERE event_key IS NOT NULL DO NOTHING",
            )
            .bind(place.user_id)
            .bind(&i.title)
            .bind(format!(
                "Saved place \"{}\" · Verified source report relevant near this location. Published {}. Expires {}.",
                place.label, i.published_at, i.expires_at
            ))
            .bind(format!("user:{}:news:{}", place.user_id, i.id))
            .bind(&i.source_url)
            .bind(json!({
                "published_at": i.published_at,
                "expires_at": i.expires_at,
                "place_id": place.id,
                "coverage": "saved_place_3km"
            }))
            .execute(&s.pool)
            .await?
            .rows_affected();
        }
    }
    Ok(created)
}

#[derive(Default, Serialize)]
pub struct Evaluation {
    pub evaluated: usize,
    pub created: u64,
    pub news_configured: bool,
    pub scheduler_enabled: bool,
}
pub async fn evaluate(
    s: &AppState,
    conditions: &ConditionsService,
    user: Option<Uuid>,
) -> AppResult<Evaluation> {
    let now = Utc::now();
    let mut targets:Vec<Target>=sqlx::query_as("SELECT r.id,r.user_id,r.label,r.mode,o.latitude,o.longitude,d.latitude AS dest_latitude,d.longitude AS dest_longitude,r.weekdays,r.departure_minute,r.lead_minutes,r.news_enabled,COALESCE(p.alert_unhealthy_aqi,true) AS air,COALESCE(p.alert_heavy_rain,true) AS rain,COALESCE(p.alert_severe_traffic,true) AS traffic,COALESCE(p.alert_relevant_news,true) AS news,'[]'::jsonb AS route_waypoints,now() AS planned_departure,true AS is_routine FROM routine_trips r JOIN saved_places o ON o.id=r.origin_id AND o.user_id=r.user_id JOIN saved_places d ON d.id=r.destination_id AND d.user_id=r.user_id LEFT JOIN notification_preferences p ON p.user_id=r.user_id WHERE r.enabled AND r.alerts_enabled AND ($1::uuid IS NULL OR r.user_id=$1) AND (r.last_checked_at IS NULL OR r.last_checked_at<now()-interval '5 minutes') ORDER BY r.last_checked_at NULLS FIRST LIMIT 20")
        .bind(user).fetch_all(&s.pool).await?;
    targets.extend(sqlx::query_as::<_,Target>("SELECT t.id,t.user_id,t.name AS label,t.transport_mode AS mode,t.start_latitude AS latitude,t.start_longitude AS longitude,t.destination_latitude AS dest_latitude,t.destination_longitude AS dest_longitude,ARRAY[]::smallint[] AS weekdays,0 AS departure_minute,30 AS lead_minutes,true AS news_enabled,COALESCE(p.alert_unhealthy_aqi,true) AS air,COALESCE(p.alert_heavy_rain,true) AS rain,COALESCE(p.alert_severe_traffic,true) AS traffic,COALESCE(p.alert_relevant_news,true) AS news,t.route_waypoints,t.planned_departure,false AS is_routine FROM trips t LEFT JOIN notification_preferences p ON p.user_id=t.user_id WHERE t.active_until>now() AND t.confirmed_at IS NOT NULL AND t.start_latitude IS NOT NULL AND t.planned_departure<=now()+interval '30 minutes' AND ($1::uuid IS NULL OR t.user_id=$1) AND (t.last_checked_at IS NULL OR t.last_checked_at<now()-interval '5 minutes') ORDER BY t.last_checked_at NULLS FIRST LIMIT 20")
        .bind(user).fetch_all(&s.pool).await?);
    let news_configured = std::env::var("NEWS_INCIDENTS_URL").is_ok_and(|s| !s.is_empty());
    let news = if news_configured {
        incidents().await
    } else {
        Vec::new()
    };
    let mut result = Evaluation {
        news_configured,
        scheduler_enabled: enabled(),
        ..Default::default()
    };
    result.created += evaluate_place_news(s, &news, user, now).await?;
    for t in targets {
        let table = if t.is_routine {
            "routine_trips"
        } else {
            "trips"
        };
        let claim=sqlx::query(&format!("UPDATE {table} SET last_checked_at=$1 WHERE id=$2 AND user_id=$3 AND (last_checked_at IS NULL OR last_checked_at<$1-interval '5 minutes')"))
            .bind(now).bind(t.id).bind(t.user_id).execute(&s.pool).await?;
        if claim.rows_affected() == 0 {
            continue;
        }
        let departure = if t.is_routine {
            due_departure(now, &t.weekdays, t.departure_minute, t.lead_minutes)
        } else {
            Some(t.planned_departure)
        };
        let Some(departure) = departure else {
            continue;
        };
        let key = format!(
            "{}:{}",
            t.id,
            if t.is_routine {
                departure.to_rfc3339()
            } else {
                "active".into()
            }
        );
        result.evaluated += 1;
        let mut candidates = Vec::new();
        if t.air || t.rain || t.traffic {
            let q_origin = ConditionsQuery {
                latitude: t.latitude,
                longitude: t.longitude,
                adm4: None,
            };
            let q_dest = ConditionsQuery {
                latitude: t.dest_latitude,
                longitude: t.dest_longitude,
                adm4: None,
            };
            let (c_origin, c_dest) = tokio::join!(
                conditions.lookup(&q_origin),
                conditions.lookup(&q_dest),
            );
            candidates.extend(hazards(&c_origin, now, t.air, t.rain, t.traffic));
            candidates.extend(hazards(&c_dest, now, t.air, t.rain, t.traffic));
        }
        for h in candidates {
            let event = format!("{key}:{}", h.key);
            let context = json!({"rule":h.key,"source":h.source,"kind":h.kind,"valid_at":h.valid_at,"mode":t.mode,"target":t.id});
            let body = format!(
                "{} · {}\n{}\nSource: {} ({}) · checked {}",
                t.label,
                t.mode,
                h.message,
                h.source,
                h.kind.unwrap_or("unknown"),
                now.to_rfc3339()
            );
            result.created+=sqlx::query("INSERT INTO notifications(user_id,title,message_body,severity,event_key,context) VALUES($1,$2,$3,'medium',$4,$5) ON CONFLICT(user_id,event_key) WHERE event_key IS NOT NULL DO NOTHING")
                .bind(t.user_id).bind(h.title).bind(body).bind(event).bind(context).execute(&s.pool).await?.rows_affected();
        }
        if t.news && t.news_enabled {
            for i in news.iter().filter(|i| {
                i.starts_at <= departure + chrono::Duration::hours(2)
                    && i.expires_at > departure
                    && relevant(i, &t)
            }) {
                result.created+=sqlx::query("INSERT INTO notifications(user_id,title,message_body,severity,event_key,source_url,context) VALUES($1,$2,$3,'medium',$4,$5,$6) ON CONFLICT(user_id,event_key) WHERE event_key IS NOT NULL DO NOTHING")
                    .bind(t.user_id).bind(&i.title).bind(format!("{} · Verified source report relevant near your journey. Published {}. Expires {}.",t.label,i.published_at,i.expires_at))
                    .bind(format!("user:{}:news:{}",t.user_id,i.id)).bind(&i.source_url).bind(json!({"published_at":i.published_at,"expires_at":i.expires_at,"target":t.id,"coverage":if t.route_waypoints.as_array().is_some_and(|a| a.len()>1) {"route_corridor"} else {"endpoints_only"}}))
                    .execute(&s.pool).await?.rows_affected();
            }
        }
        sqlx::query("INSERT INTO alert_decisions(user_id,target_key,outcome) VALUES($1,$2,$3)")
            .bind(t.user_id)
            .bind(key)
            .bind(format!(
                "evaluated; {} notifications created so far; fresh signals only",
                result.created
            ))
            .execute(&s.pool)
            .await?;
    }
    Ok(result)
}
pub fn enabled() -> bool {
    std::env::var("ALERTS_ENABLED").is_ok_and(|s| s == "true")
}
pub async fn evaluate_user(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
    Extension(c): Extension<Arc<ConditionsService>>,
) -> (axum::http::StatusCode,Json<Value>) {
    let news_configured = std::env::var("NEWS_INCIDENTS_URL")
        .is_ok_and(|value| !value.trim().is_empty());
    let response=json!({"queued":true,"news_configured":news_configured,"scheduler_enabled":enabled()});
    tokio::spawn(async move {
        if evaluate(&s,&c,Some(u.id)).await.is_err() { tracing::warn!("Requested alert evaluation failed"); }
    });
    (axum::http::StatusCode::ACCEPTED,Json(response))
}
pub fn start(s: AppState, c: Arc<ConditionsService>) {
    if !enabled() {
        return;
    }
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(60));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            interval.tick().await;
            if evaluate(&s, &c, None).await.is_err() {
                tracing::warn!("Alert evaluation failed; no synthetic notifications substituted");
            }
            let _ = sqlx::query(
                "DELETE FROM alert_decisions WHERE checked_at<now()-interval '30 days'",
            )
            .execute(&s.pool)
            .await;
        }
    });
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn handles_midnight_and_weekdays() {
        let now = DateTime::parse_from_rfc3339("2026-11-08T16:50:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let due = due_departure(now, &[0], 10, 30).unwrap();
        assert_eq!(due.to_rfc3339(), "2026-11-08T17:10:00+00:00");
        assert!(due_departure(now, &[1], 10, 30).is_none());
    }
    #[test]
    fn stale_or_forecast_signals_are_not_current_hazards() {
        let s = Signal {
            status: "stale",
            source: "openaq",
            kind: Some("station_observation"),
            valid_at: Some(Utc::now()),
            message: String::new(),
            data: Some(json!({"pm25_ug_m3":100})),
        };
        assert!(!fresh(&s, Utc::now()));
    }

    fn clone_incident(i: &Incident) -> Incident {
        Incident {
            id: i.id.clone(),
            title: i.title.clone(),
            source_url: i.source_url.clone(),
            latitude: i.latitude,
            longitude: i.longitude,
            published_at: i.published_at,
            starts_at: i.starts_at,
            expires_at: i.expires_at,
            verified: i.verified,
        }
    }

    #[test]
    fn incident_validation_and_relevance_rules() {
        let now = Utc::now();
        let valid = Incident {
            id: "inc-1".into(),
            title: "Road closure on Jl. Sudirman".into(),
            source_url: "https://example.com/incident-1".into(),
            latitude: -6.21,
            longitude: 106.82,
            published_at: now - chrono::Duration::hours(1),
            starts_at: now - chrono::Duration::minutes(30),
            expires_at: now + chrono::Duration::hours(2),
            verified: true,
        };
        assert!(valid_incident(&valid, now));

        let unverified = Incident {
            verified: false,
            ..clone_incident(&valid)
        };
        assert!(!valid_incident(&unverified, now));

        let http_url = Incident {
            source_url: "http://example.com/inc".into(),
            ..clone_incident(&valid)
        };
        assert!(!valid_incident(&http_url, now));

        let userpass_url = Incident {
            source_url: "https://user:pass@example.com/inc".into(),
            ..clone_incident(&valid)
        };
        assert!(!valid_incident(&userpass_url, now));

        let expired = Incident {
            expires_at: now - chrono::Duration::minutes(10),
            ..clone_incident(&valid)
        };
        assert!(!valid_incident(&expired, now));

        let out_of_bounds = Incident {
            latitude: -7.5,
            ..clone_incident(&valid)
        };
        assert!(!valid_incident(&out_of_bounds, now));

        let target = Target {
            id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            label: "Daily Commute".into(),
            mode: "motorcycle".into(),
            latitude: -6.20,
            longitude: 106.81,
            dest_latitude: -6.25,
            dest_longitude: 106.85,
            weekdays: vec![0, 1, 2, 3, 4],
            departure_minute: 420,
            lead_minutes: 30,
            news_enabled: true,
            air: true,
            rain: true,
            traffic: true,
            news: true,
            route_waypoints: json!([]),
            planned_departure: now + chrono::Duration::minutes(15),
            is_routine: true,
        };
        // Incident at -6.21, 106.82 is ~1.5km from origin (-6.20, 106.81) -> relevant
        assert!(relevant(&valid, &target));

        // Incident at -6.35, 106.70 is > 15km away -> not relevant
        let distant = Incident {
            latitude: -6.35,
            longitude: 106.70,
            ..clone_incident(&valid)
        };
        assert!(!relevant(&distant, &target));
    }

    #[test]
    fn hazards_detects_air_rain_traffic_and_ignores_low_confidence() {
        let now = Utc::now();
        let resp = ConditionsResponse {
            latitude: -6.2,
            longitude: 106.8,
            retrieved_at: now,
            air_quality: Signal {
                status: "available",
                source: "openaq",
                kind: Some("station_observation"),
                valid_at: Some(now),
                message: "".into(),
                data: Some(json!({"pm25_ug_m3": 40.0})),
            },
            weather: Signal {
                status: "available",
                source: "open_meteo",
                kind: Some("model_estimate"),
                valid_at: Some(now),
                message: "".into(),
                data: Some(json!({"precipitation_mm": 2.5})),
            },
            traffic: Signal {
                status: "available",
                source: "tomtom",
                kind: Some("provider_live_estimate"),
                valid_at: None,
                message: "".into(),
                data: Some(json!({
                    "speed_kmh": 10.0,
                    "free_flow_speed_kmh": 40.0,
                    "confidence": 0.8,
                    "road_closed": false
                })),
            },
        };
        let detected = hazards(&resp, now, true, true, true);
        assert_eq!(detected.len(), 3);
        assert_eq!(detected[0].key, "air");
        assert_eq!(detected[1].key, "rain");
        assert_eq!(detected[2].key, "traffic");

        let low_conf = ConditionsResponse {
            latitude: -6.2,
            longitude: 106.8,
            retrieved_at: now,
            air_quality: resp.air_quality.clone(),
            weather: resp.weather.clone(),
            traffic: Signal {
                status: "available",
                source: "tomtom",
                kind: Some("provider_live_estimate"),
                valid_at: None,
                message: "".into(),
                data: Some(json!({
                    "speed_kmh": 5.0,
                    "free_flow_speed_kmh": 40.0,
                    "confidence": 0.3
                })),
            },
        };
        let detected_low = hazards(&low_conf, now, true, true, true);
        assert_eq!(detected_low.len(), 2);
    }
}
