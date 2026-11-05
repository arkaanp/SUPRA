//! Opt-in integration test against a disposable PostgreSQL database named *_test.
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
    auth::test_support::Fixture,
    db::{AppState, MIGRATOR},
    routes::create_router,
};

async fn request(
    app: &Router,
    token: &str,
    method: &str,
    path: &str,
    payload: Option<Value>,
) -> (StatusCode, Value) {
    let req = Request::builder()
        .method(method)
        .uri(path)
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(payload.map_or_else(Body::empty, |v| Body::from(v.to_string())))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = to_bytes(res.into_body(), 1024 * 1024).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}

#[tokio::test]
#[ignore = "requires SUPRA_TEST_DATABASE_URL and a dedicated PostgreSQL *_test database"]
async fn migrated_schema_enforces_user_boundaries() {
    let url = std::env::var("SUPRA_TEST_DATABASE_URL").expect("set SUPRA_TEST_DATABASE_URL");
    let opts = PgConnectOptions::from_str(&url).expect("valid test DB URL");
    assert!(
        opts.get_database().is_some_and(|db| db.ends_with("_test")),
        "test database name must end in _test"
    );
    assert_ne!(
        std::env::var("DATABASE_URL").ok().as_deref(),
        Some(url.as_str())
    );
    let state = AppState::new(&url).await.expect("connect test DB");
    MIGRATOR.run(&state.pool).await.expect("migrate test DB");
    MIGRATOR
        .run(&state.pool)
        .await
        .expect("idempotent migration");
    let fixture = Fixture::new().await;
    let app = create_router(state.clone(), fixture.verifier.clone());

    let alice = Uuid::new_v4();
    let bob = Uuid::new_v4();
    let token_a = fixture.token(alice, &format!("{alice}@example.invalid"));
    let token_b = fixture.token(bob, &format!("{bob}@example.invalid"));
    for (token, id) in [(&token_a, alice), (&token_b, bob)] {
        let (status, profile) = request(
            &app,
            token,
            "POST",
            "/api/users",
            Some(json!({"full_name": "API Test"})),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{profile}");
        assert_eq!(profile["id"], id.to_string());
        assert!(profile.get("password_hash").is_none());
    }
    let (status, _) = request(&app, &token_a, "GET", &format!("/api/users/{bob}"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, profiles) = request(&app, &token_a, "GET", "/api/users", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(profiles.as_array().unwrap().len(), 1);

    let (status, trip) = request(&app, &token_a, "POST", "/api/trips", Some(json!({
        "name": "API Test", "start_location": "A", "destination": "B", "planned_departure": "2030-01-01T12:00:00Z"
    }))).await;
    assert_eq!(status, StatusCode::OK, "{trip}");
    assert_eq!(trip["user_id"], alice.to_string());
    let trip_id: Uuid = trip["id"].as_str().unwrap().parse().unwrap();
    let (status, route) = request(
        &app,
        &token_a,
        "POST",
        "/api/routes",
        Some(json!({
            "trip_id": trip_id, "waypoints": [{"lat": -6.2, "lng": 106.8}], "total_distance": 1.2
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{route}");
    let route_id: Uuid = route["id"].as_str().unwrap().parse().unwrap();

    let prediction_id: Uuid = sqlx::query_scalar("INSERT INTO predictions (route_id, target_time, predicted_aqi, predicted_rainfall_prob, predicted_traffic_density) VALUES ($1, NOW(), 80, 0.5, 0.5) RETURNING id")
        .bind(route_id).fetch_one(&state.pool).await.unwrap();
    let notification_id: Uuid = sqlx::query_scalar("INSERT INTO notifications (user_id, title, message_body, severity) VALUES ($1, 'Demo', 'Test only', 'low') RETURNING id")
        .bind(alice).fetch_one(&state.pool).await.unwrap();

    for path in [
        format!("/api/trips/{trip_id}"),
        format!("/api/routes/{route_id}"),
        format!("/api/predictions/{prediction_id}"),
        format!("/api/notifications/{notification_id}"),
        format!("/api/trips/{trip_id}/routes"),
        format!("/api/routes/{route_id}/predictions"),
        format!("/api/users/{alice}/trips"),
        format!("/api/users/{alice}/preferences"),
        format!("/api/users/{alice}/notifications"),
        format!("/api/trips?user_id={alice}"),
    ] {
        let (status, body) = request(&app, &token_b, "GET", &path, None).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{path}: {body}");
    }
    for path in [
        "/api/trips",
        "/api/routes",
        "/api/predictions",
        "/api/notifications",
    ] {
        let (status, body) = request(&app, &token_b, "GET", path, None).await;
        assert_eq!(status, StatusCode::OK, "{path}: {body}");
        assert_eq!(body.as_array().unwrap().len(), 0, "{path}: cross-user leak");
    }
    for (method, path, payload) in [
        (
            "PUT",
            format!("/api/trips/{trip_id}"),
            json!({"name": "stolen"}),
        ),
        ("DELETE", format!("/api/trips/{trip_id}"), json!(null)),
        (
            "PUT",
            format!("/api/routes/{route_id}"),
            json!({"total_distance": 9}),
        ),
        ("DELETE", format!("/api/routes/{route_id}"), json!(null)),
        (
            "PUT",
            format!("/api/notifications/{notification_id}/read"),
            json!(null),
        ),
        (
            "PUT",
            format!("/api/users/{alice}/preferences"),
            json!({"alert_heavy_rain": false}),
        ),
    ] {
        let (status, body) = request(&app, &token_b, method, &path, Some(payload)).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{method} {path}: {body}");
    }
    let (status, body) = request(
        &app,
        &token_b,
        "POST",
        "/api/routes",
        Some(json!({
            "trip_id": trip_id, "waypoints": [{"lat": -6.2, "lng": 106.8}], "total_distance": 2
        })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    for path in ["/api/predictions", "/api/notifications"] {
        let (status, _) = request(&app, &token_a, "POST", path, Some(json!({}))).await;
        assert_eq!(
            status,
            StatusCode::METHOD_NOT_ALLOWED,
            "{path} must not allow user writes"
        );
    }

    let (status, prefs) = request(
        &app,
        &token_a,
        "PUT",
        &format!("/api/users/{alice}/preferences"),
        Some(json!({"alert_heavy_rain": false})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{prefs}");
    assert_eq!(prefs["alert_unhealthy_aqi"], true);
    let (status, prefs) = request(
        &app,
        &token_a,
        "PUT",
        &format!("/api/users/{alice}/preferences"),
        Some(json!({"alert_severe_traffic": false})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{prefs}");
    assert_eq!(prefs["alert_heavy_rain"], false);
    let (status, _) = request(
        &app,
        &token_a,
        "DELETE",
        &format!("/api/users/{alice}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = request(&app, &token_b, "DELETE", &format!("/api/users/{bob}"), None).await;
    assert_eq!(status, StatusCode::OK);
    let (remaining,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM trips WHERE id = $1")
        .bind(trip_id)
        .fetch_one(&state.pool)
        .await
        .unwrap();
    assert_eq!(remaining, 0);
}
