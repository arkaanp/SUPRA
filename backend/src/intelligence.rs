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
                .timeout(std::time::Duration::from_secs(18))
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .expect("ML HTTP configuration"),
            base: base_url(),
        }
    }
    async fn get(&self, path: &str) -> AppResult<Value> {
        let url = format!("{}{path}", self.base);
        // The Python process imports PyTorch before it starts accepting requests.
        let started = tokio::time::Instant::now();
        let mut response = loop {
            match self.client.get(&url).send().await {
                Ok(response) => break response,
                Err(error) if error.is_connect() && started.elapsed().as_secs() < 8 => {
                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                }
                Err(error) => {
                    tracing::warn!(
                        timed_out = error.is_timeout(),
                        "Forecast worker request failed"
                    );
                    return Err(AppError::ForecastUnavailable(
                        "The forecast worker is unreachable. Try refreshing.",
                    ));
                }
            }
        };
        let status = response.status();
        let mut bytes = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(|_| AppError::Unavailable)? {
            if bytes.len() + chunk.len() > 1_000_000 {
                return Err(AppError::Unavailable);
            }
            bytes.extend_from_slice(&chunk);
        }
        if !status.is_success() {
            let error: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
            let message = forecast_failure(error["error"].as_str().unwrap_or(""));
            tracing::warn!(%status, reason = message, "Forecast worker returned an error");
            return Err(AppError::ForecastUnavailable(message));
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
            tracing::warn!(
                "Forecast rejected because its timestamps, coordinates or values were invalid"
            );
            Err(AppError::Unavailable)
        }
    }
}
fn forecast_failure(reason: &str) -> &'static str {
    match reason {
        "Open-Meteo weather returned HTTP 429" | "Open-Meteo air returned HTTP 429" => {
            "Open-Meteo has rate-limited forecast inputs. Try again later."
        }
        "Stale or discontinuous forecast inputs" | "Insufficient hourly inputs" => {
            "Recent hourly weather or air-quality data is incomplete."
        }
        "Model needs retraining" => "The forecast model needs retraining.",
        "MET Norway fallback inputs unavailable" => {
            "Open-Meteo inputs and the MET Norway fallback are unavailable."
        }
        "Service busy" => "The forecast worker is busy. Try refreshing.",
        other if other.starts_with("Open-Meteo weather ") => {
            "Weather inputs are unavailable from Open-Meteo."
        }
        other if other.starts_with("Open-Meteo air ") => {
            "Air-quality inputs are unavailable from Open-Meteo."
        }
        _ => "The forecast worker could not generate a forecast.",
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
                if v["scope"] == "weather_only" && matches!(key, "pm25_ug_m3" | "aqi") {
                    if !row[key].is_null() {
                        return Some(false);
                    }
                    continue;
                }
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
        let mut partial = good.clone();
        partial["scope"] = json!("weather_only");
        assert!(!valid_forecast(&partial, &q, now));
        partial["hourly"][0]["aqi"] = Value::Null;
        partial["hourly"][0]["pm25_ug_m3"] = Value::Null;
        assert!(valid_forecast(&partial, &q, now));
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
