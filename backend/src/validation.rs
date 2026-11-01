use axum::{
    Json,
    extract::{FromRequest, FromRequestParts, Path, Query},
    http::{Request, request::Parts},
};
use serde::de::DeserializeOwned;
use serde_json::Value;

use crate::{
    error::AppError,
    handlers::{notifications::ListNotificationsQuery, trips::ListTripsQuery},
    models::{
        CreateNotification, CreatePrediction, CreateRoute, CreateTrip, CreateUser,
        UpdateNotificationPreference, UpdateRoute, UpdateTrip, UpdateUser,
    },
};

pub trait Validate {
    fn validate(&self) -> Result<(), AppError>;
}

/// Converts Axum's extractor rejections and application validation failures to
/// the same JSON error shape as handler and database failures.
pub struct ValidatedJson<T>(pub T);
pub struct ValidatedPath<T>(pub T);
pub struct ValidatedQuery<T>(pub T);

impl<S, T> FromRequest<S> for ValidatedJson<T>
where
    S: Send + Sync,
    T: DeserializeOwned + Validate,
{
    type Rejection = AppError;

    async fn from_request(
        req: Request<axum::body::Body>,
        state: &S,
    ) -> Result<Self, Self::Rejection> {
        let Json(value) = Json::<T>::from_request(req, state)
            .await
            .map_err(|error| AppError::bad_request(error.body_text()))?;
        value.validate()?;
        Ok(Self(value))
    }
}

impl<S, T> FromRequestParts<S> for ValidatedPath<T>
where
    S: Send + Sync,
    T: DeserializeOwned + Send,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let Path(value) = Path::<T>::from_request_parts(parts, state)
            .await
            .map_err(|_| AppError::bad_request("Invalid path parameter"))?;
        Ok(Self(value))
    }
}

impl<S, T> FromRequestParts<S> for ValidatedQuery<T>
where
    S: Send + Sync,
    T: DeserializeOwned + Validate + Send,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let Query(value) = Query::<T>::from_request_parts(parts, state)
            .await
            .map_err(|_| AppError::bad_request("Invalid query parameter"))?;
        value.validate()?;
        Ok(Self(value))
    }
}

fn nonempty(value: &str, field: &str, max: usize) -> Result<(), AppError> {
    if value.trim().is_empty() || value.len() > max || value.chars().any(char::is_control) {
        return Err(AppError::bad_request(format!(
            "{field} must be non-empty, at most {max} bytes, and contain no control characters"
        )));
    }
    Ok(())
}

fn email(value: &str) -> Result<(), AppError> {
    nonempty(value, "email", 255)?;
    let (local, domain) = value
        .split_once('@')
        .ok_or_else(|| AppError::bad_request("Invalid email"))?;
    if local.is_empty()
        || domain.contains('@')
        || !domain.contains('.')
        || domain.starts_with('.')
        || domain.ends_with('.')
        || value.chars().any(char::is_whitespace)
    {
        return Err(AppError::bad_request("Invalid email"));
    }
    Ok(())
}

fn nonnegative(value: f64, field: &str) -> Result<(), AppError> {
    if !value.is_finite() || value < 0.0 {
        return Err(AppError::bad_request(format!(
            "{field} must be a finite non-negative number"
        )));
    }
    Ok(())
}

fn probability(value: f64, field: &str) -> Result<(), AppError> {
    if !value.is_finite() || !(0.0..=1.0).contains(&value) {
        return Err(AppError::bad_request(format!(
            "{field} must be between 0 and 1"
        )));
    }
    Ok(())
}

fn waypoints(value: &Value) -> Result<(), AppError> {
    let points = value
        .as_array()
        .ok_or_else(|| AppError::bad_request("waypoints must be an array"))?;
    if points.is_empty() || points.len() > 1000 {
        return Err(AppError::bad_request(
            "waypoints must contain 1 to 1000 points",
        ));
    }
    for point in points {
        let lat = point.get("lat").and_then(Value::as_f64);
        let lng = point.get("lng").and_then(Value::as_f64);
        if !matches!(lat, Some(v) if v.is_finite() && (-90.0..=90.0).contains(&v))
            || !matches!(lng, Some(v) if v.is_finite() && (-180.0..=180.0).contains(&v))
            || point.as_object().is_none_or(|obj| obj.len() != 2)
        {
            return Err(AppError::bad_request(
                "Each waypoint must have valid lat and lng coordinates",
            ));
        }
    }
    Ok(())
}

impl Validate for CreateUser {
    fn validate(&self) -> Result<(), AppError> {
        nonempty(&self.full_name, "full_name", 255)?;
        email(&self.email)?;
        nonempty(&self.password_hash, "password_hash", 255)
    }
}

impl Validate for UpdateUser {
    fn validate(&self) -> Result<(), AppError> {
        if let Some(name) = &self.full_name {
            nonempty(name, "full_name", 255)?;
        }
        if let Some(email_value) = &self.email {
            email(email_value)?;
        }
        Ok(())
    }
}

impl Validate for CreateTrip {
    fn validate(&self) -> Result<(), AppError> {
        nonempty(&self.name, "name", 255)?;
        nonempty(&self.start_location, "start_location", 255)?;
        nonempty(&self.destination, "destination", 255)
    }
}

impl Validate for UpdateTrip {
    fn validate(&self) -> Result<(), AppError> {
        if let Some(name) = &self.name {
            nonempty(name, "name", 255)?;
        }
        if let Some(start) = &self.start_location {
            nonempty(start, "start_location", 255)?;
        }
        if let Some(destination) = &self.destination {
            nonempty(destination, "destination", 255)?;
        }
        Ok(())
    }
}

impl Validate for CreateRoute {
    fn validate(&self) -> Result<(), AppError> {
        waypoints(&self.waypoints)?;
        nonnegative(self.total_distance, "total_distance")
    }
}

impl Validate for UpdateRoute {
    fn validate(&self) -> Result<(), AppError> {
        if let Some(value) = &self.waypoints {
            waypoints(value)?;
        }
        if let Some(value) = self.total_distance {
            nonnegative(value, "total_distance")?;
        }
        Ok(())
    }
}

impl Validate for CreatePrediction {
    fn validate(&self) -> Result<(), AppError> {
        nonnegative(self.predicted_aqi, "predicted_aqi")?;
        probability(self.predicted_rainfall_prob, "predicted_rainfall_prob")?;
        probability(self.predicted_traffic_density, "predicted_traffic_density")
    }
}

impl Validate for UpdateNotificationPreference {
    fn validate(&self) -> Result<(), AppError> {
        Ok(())
    }
}

impl Validate for CreateNotification {
    fn validate(&self) -> Result<(), AppError> {
        nonempty(&self.title, "title", 255)?;
        nonempty(&self.message_body, "message_body", 4000)?;
        if !matches!(
            self.severity.as_str(),
            "low" | "medium" | "high" | "critical"
        ) {
            return Err(AppError::bad_request(
                "severity must be low, medium, high, or critical",
            ));
        }
        Ok(())
    }
}

impl Validate for ListNotificationsQuery {
    fn validate(&self) -> Result<(), AppError> {
        if self.limit.is_some_and(|v| !(1..=100).contains(&v)) || self.offset.is_some_and(|v| v < 0)
        {
            return Err(AppError::bad_request(
                "limit must be 1–100 and offset must be non-negative",
            ));
        }
        Ok(())
    }
}

impl Validate for ListTripsQuery {
    fn validate(&self) -> Result<(), AppError> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db::AppState, routes::create_router};
    use axum::{
        body::{Body, to_bytes},
        http::{Request, StatusCode},
    };
    use tower::ServiceExt;

    #[test]
    fn reject_invalid_route_and_probability() {
        assert!(waypoints(&serde_json::json!([[-6.2, 106.8]])).is_err());
        assert!(waypoints(&serde_json::json!([{"lat": 91, "lng": 106}])).is_err());
        assert!(waypoints(&serde_json::json!([{"lat": -6.2, "lng": 106.8}])).is_ok());
        assert!(probability(1.5, "rain").is_err());
    }

    #[tokio::test]
    async fn invalid_requests_return_json_without_accessing_database() {
        let pool = sqlx::postgres::PgPoolOptions::new()
            .connect_lazy("postgres://localhost/supra_test")
            .expect("valid test URL");
        let router = create_router(AppState { pool });
        let cases = [
            (
                "POST",
                "/api/routes",
                serde_json::json!({"trip_id": "00000000-0000-4000-8000-000000000001", "waypoints": [[-6.2, 106.8]], "total_distance": 1}),
            ),
            (
                "POST",
                "/api/predictions",
                serde_json::json!({"route_id": "00000000-0000-4000-8000-000000000001", "target_time": "2030-01-01T00:00:00Z", "predicted_aqi": 42, "predicted_rainfall_prob": 1.2, "predicted_traffic_density": 0.5}),
            ),
            (
                "POST",
                "/api/notifications",
                serde_json::json!({"user_id": "00000000-0000-4000-8000-000000000001", "title": "Alert", "message_body": "Body", "severity": "invalid"}),
            ),
            (
                "POST",
                "/api/users",
                serde_json::json!({"full_name": "", "email": "not-an-email", "password_hash": "x"}),
            ),
            (
                "POST",
                "/api/users",
                serde_json::json!({"full_name": "A", "email": "a@example.com", "password_hash": "x", "typo": true}),
            ),
            (
                "PUT",
                "/api/trips/invalid-uuid",
                serde_json::json!({"name": "A"}),
            ),
            (
                "GET",
                "/api/users/00000000-0000-4000-8000-000000000001/notifications?limit=-1",
                serde_json::json!(null),
            ),
            (
                "GET",
                "/api/trips?user_id=invalid-uuid",
                serde_json::json!(null),
            ),
        ];
        for (method, path, value) in cases {
            let request = Request::builder()
                .method(method)
                .uri(path)
                .header("content-type", "application/json")
                .body(Body::from(value.to_string()))
                .expect("request");
            let response = router.clone().oneshot(request).await.expect("response");
            assert_eq!(
                response.status(),
                StatusCode::BAD_REQUEST,
                "{method} {path}"
            );
            let bytes = to_bytes(response.into_body(), 1024 * 1024)
                .await
                .expect("body");
            let body: Value = serde_json::from_slice(&bytes).expect("JSON error");
            assert_eq!(body["code"], "invalid_request", "{method} {path}: {body}");
        }
    }
}
