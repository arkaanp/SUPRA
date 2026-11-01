//! Database-backed API smoke test. Run explicitly with `cargo test -- --ignored`.
//! The database name must end in `_test` and must not be the application DB.
use std::str::FromStr;

use axum::{
    Router,
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};
use serde_json::{Value, json};
use sqlx::postgres::PgConnectOptions;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::{AppState, MIGRATOR},
    routes::create_router,
};

async fn request(
    app: &Router,
    method: &str,
    path: &str,
    payload: Option<Value>,
) -> (StatusCode, Value) {
    let body = payload.map_or_else(Body::empty, |value| Body::from(value.to_string()));
    let request = Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json")
        .body(body)
        .expect("valid request");
    let response = app.clone().oneshot(request).await.expect("router response");
    let status = response.status();
    let bytes = to_bytes(response.into_body(), 1024 * 1024)
        .await
        .expect("response body");
    let value = serde_json::from_slice(&bytes).expect("JSON response");
    (status, value)
}

#[tokio::test]
#[ignore = "requires SUPRA_TEST_DATABASE_URL and a dedicated PostgreSQL *_test database"]
async fn migrated_schema_supports_existing_handlers_and_constraints() {
    let database_url = std::env::var("SUPRA_TEST_DATABASE_URL")
        .expect("set SUPRA_TEST_DATABASE_URL to a dedicated PostgreSQL *_test database");
    let options = PgConnectOptions::from_str(&database_url).expect("valid PostgreSQL test URL");
    assert!(
        options
            .get_database()
            .is_some_and(|name| name.ends_with("_test")),
        "SUPRA_TEST_DATABASE_URL must name a dedicated database ending in _test"
    );
    assert_ne!(
        std::env::var("DATABASE_URL").ok().as_deref(),
        Some(database_url.as_str()),
        "test database must not be the application database"
    );

    let state = AppState::new(&database_url).await.expect("connect test DB");
    MIGRATOR
        .run(&state.pool)
        .await
        .expect("apply schema to test DB");
    MIGRATOR
        .run(&state.pool)
        .await
        .expect("migrations are repeatable");
    let app = create_router(state.clone());

    let (status, user) = request(
        &app,
        "POST",
        "/api/users",
        Some(json!({
            "full_name": "API Test", "email": format!("{}@example.invalid", Uuid::new_v4()),
            "password_hash": "test-only-placeholder"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{user}");
    let user_id = user["id"].as_str().expect("user id");
    assert!(user.get("password_hash").is_none());

    let (status, trip) = request(
        &app,
        "POST",
        "/api/trips",
        Some(json!({
            "user_id": user_id, "name": "Test trip", "start_location": "A",
            "destination": "B", "planned_departure": "2030-01-01T12:00:00Z"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{trip}");
    let trip_id = trip["id"].as_str().expect("trip id");

    let (status, route) = request(
        &app,
        "POST",
        "/api/routes",
        Some(json!({
            "trip_id": trip_id, "waypoints": [{"lat": -6.2, "lng": 106.8}],
            "total_distance": 1.2
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{route}");
    let route_id = route["id"].as_str().expect("route id");

    let forecast = json!({
        "route_id": route_id, "target_time": "2030-01-01T13:00:00Z",
        "predicted_aqi": 75.0, "predicted_rainfall_prob": 0.25,
        "predicted_traffic_density": 0.5
    });
    let (status, prediction) =
        request(&app, "POST", "/api/predictions", Some(forecast.clone())).await;
    assert_eq!(status, StatusCode::OK, "{prediction}");
    let (status, again) = request(&app, "POST", "/api/predictions", Some(forecast)).await;
    assert_eq!(status, StatusCode::OK, "{again}");
    assert_eq!(prediction["id"], again["id"], "upsert retains cache row");

    let (status, list) = request(
        &app,
        "GET",
        &format!("/api/routes/{route_id}/predictions"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().expect("predictions").len(), 1);

    let (status, prefs) = request(
        &app,
        "PUT",
        &format!("/api/users/{user_id}/preferences"),
        Some(json!({
            "alert_unhealthy_aqi": true, "alert_heavy_rain": false, "alert_severe_traffic": true
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{prefs}");
    assert_eq!(prefs["alert_heavy_rain"], false);

    let (status, notification) = request(
        &app,
        "POST",
        "/api/notifications",
        Some(json!({
            "user_id": user_id, "title": "Demo", "message_body": "Test only", "severity": "low"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{notification}");
    let notification_id = notification["id"].as_str().expect("notification id");
    let (status, read) = request(
        &app,
        "PUT",
        &format!("/api/notifications/{notification_id}/read"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{read}");
    assert_eq!(read["is_read"], true);

    // Historical observations are schema-only for now (no handler yet).
    sqlx::query("INSERT INTO historical_data (location_point, recorded_at, actual_aqi, actual_rainfall, actual_traffic) VALUES ($1, NOW(), 80, 1, 0.4)")
        .bind(format!("test-{user_id}"))
        .execute(&state.pool).await.expect("historical data schema");

    let invalid = sqlx::query("INSERT INTO predictions (route_id, target_time, predicted_aqi, predicted_rainfall_prob, predicted_traffic_density) VALUES ($1, NOW(), 80, 1.5, 0.5)")
        .bind(Uuid::parse_str(route_id).expect("route UUID"))
        .execute(&state.pool).await;
    assert!(
        invalid.is_err(),
        "rain probability constraint must reject > 1"
    );

    let (status, _) = request(&app, "DELETE", &format!("/api/users/{user_id}"), None).await;
    assert_eq!(status, StatusCode::OK);
    let (remaining,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM trips WHERE id = $1")
        .bind(Uuid::parse_str(trip_id).expect("trip UUID"))
        .fetch_one(&state.pool)
        .await
        .expect("verify cascade");
    assert_eq!(remaining, 0);
    sqlx::query("DELETE FROM historical_data WHERE location_point = $1")
        .bind(format!("test-{user_id}"))
        .execute(&state.pool)
        .await
        .expect("clean up observation");
}
