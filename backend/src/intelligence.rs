//! Authenticated bridge to the loopback Python/PyTorch service.
use crate::{
    conditions::ConditionsQuery,
    error::{AppError, AppResult},
    validation::ValidatedQuery,
};
use axum::{Json, extract::Extension};
use chrono::{DateTime, Duration, Utc};
use serde_json::Value;
use std::sync::Arc;

pub struct IntelligenceService {
    client: reqwest::Client,
    base: String,
}
impl IntelligenceService {
    pub fn from_env() -> Self {
        Self {
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(12))
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .expect("ML HTTP configuration"),
            base: base_url(),
        }
    }
    async fn get(&self, path: &str) -> AppResult<Value> {
        let mut response = self
            .client
            .get(format!("{}{path}", self.base))
            .send()
            .await
            .map_err(|error| {
                tracing::warn!(timed_out = error.is_timeout(), "Forecast worker request failed");
                AppError::Unavailable
            })?;
        if !response.status().is_success() {
            tracing::warn!(status = %response.status(), "Forecast worker returned an error");
            return Err(AppError::Unavailable);
        }
        let mut bytes = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(|_| AppError::Unavailable)? {
            if bytes.len() + chunk.len() > 1_000_000 {
                return Err(AppError::Unavailable);
            }
            bytes.extend_from_slice(&chunk);
        }
        serde_json::from_slice(&bytes).map_err(|_| AppError::Unavailable)
    }
    pub async fn forecast(&self, q: &ConditionsQuery) -> AppResult<Value> {
        let value = self
            .get(&format!(
                "/v1/forecast?latitude={}&longitude={}",
                q.latitude, q.longitude
            ))
            .await?;
        if valid_forecast(&value, q, Utc::now()) {
            Ok(value)
        } else {
            tracing::warn!("Forecast rejected because its timestamps, coordinates or values were invalid");
            Err(AppError::Unavailable)
        }
    }
}
pub fn base_url() -> String {
    std::env::var("INTELLIGENCE_URL")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| "http://127.0.0.1:8001".into())
        .trim_end_matches('/')
        .into()
}
pub async fn forecast(
    Extension(service): Extension<Arc<IntelligenceService>>,
    ValidatedQuery(q): ValidatedQuery<ConditionsQuery>,
) -> AppResult<Json<Value>> {
    Ok(Json(service.forecast(&q).await?))
}
fn date(v: &Value, key: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(v[key].as_str()?)
        .ok()
        .map(|d| d.with_timezone(&Utc))
}
fn valid_forecast(v: &Value, q: &ConditionsQuery, now: DateTime<Utc>) -> bool {
    let check = || -> Option<bool> {
        if v["framework"] != "PyTorch" || v["model_id"].as_str()?.is_empty() {
            return Some(false);
        }
        if (v["latitude"].as_f64()? - q.latitude).abs() > 0.0001
            || (v["longitude"].as_f64()? - q.longitude).abs() > 0.0001
        {
            return Some(false);
        }
        let generated = date(v, "generated_at")?;
        let input = date(v, "input_through")?;
        if generated > now + Duration::minutes(5)
            || generated < now - Duration::minutes(30)
            || input > now
            || input < now - Duration::hours(2)
            || date(v, "expires_at")? <= now
        {
            return Some(false);
        }
        let rows = v["hourly"].as_array()?;
        if rows.is_empty() || rows.len() > 12 {
            return Some(false);
        }
        let mut previous = None;
        for row in rows {
            let at = date(row, "target_time")?;
            if at <= now
                || at > now + Duration::hours(13)
                || previous.is_some_and(|p| at - p != Duration::hours(1))
            {
                return Some(false);
            }
            previous = Some(at);
            for (key, min, max) in [
                ("temperature_c", -50., 60.),
                ("precipitation_mm", 0., 500.),
                ("pm25_ug_m3", 0., 2000.),
                ("aqi", 0., 1000.),
                ("rain_probability", 0., 1.),
            ] {
                let n = row[key].as_f64()?;
                if !n.is_finite() || n < min || n > max {
                    return Some(false);
                }
            }
            // Traffic has not been trained. Reject mislabeled numeric output.
            if !row["traffic_speed_kmh"].is_null() || !row["traffic_density"].is_null() {
                return Some(false);
            }
        }
        Some(true)
    };
    check() == Some(true)
}
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn rejects_stale_wrong_location_invalid_probability_and_unsupported_traffic() {
        let now = Utc::now();
        let q = ConditionsQuery {
            latitude: -6.2,
            longitude: 106.8,
            adm4: None,
        };
        let good = json!({"latitude":-6.2,"longitude":106.8,"framework":"PyTorch","model_id":"test",
            "generated_at":now,"input_through":now-Duration::minutes(30),"expires_at":now+Duration::hours(1),
            "hourly":[{"target_time":now+Duration::hours(1),"temperature_c":29.,"precipitation_mm":0.5,
                        "pm25_ug_m3":20.,"aqi":70.,"rain_probability":0.6,"traffic_speed_kmh":null,"traffic_density":null}]});
        assert!(valid_forecast(&good, &q, now));
        for (key, value) in [
            ("latitude", json!(-6.4)),
            ("expires_at", json!(now - Duration::hours(1))),
            ("input_through", json!(now - Duration::hours(4))),
        ] {
            let mut bad = good.clone();
            bad[key] = value;
            assert!(!valid_forecast(&bad, &q, now));
        }
        let mut bad = good.clone();
        bad["hourly"][0]["rain_probability"] = json!(65);
        assert!(!valid_forecast(&bad, &q, now));
        bad = good.clone();
        bad["hourly"][0]["traffic_speed_kmh"] = json!(24);
        assert!(!valid_forecast(&bad, &q, now));
    }
}
