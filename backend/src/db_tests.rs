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
            Some(json!({"username": id.simple().to_string()})),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{profile}");
        assert_eq!(profile["id"], id.to_string());
        assert!(profile.get("password_hash").is_none());
        assert!(profile.get("email").is_none());
    }
    let new_handle = format!("rider_{}", &alice.simple().to_string()[..12]);
    let (status, profile) = request(&app, &token_a, "PUT", "/api/profile",
        Some(json!({"username":new_handle.to_uppercase()}))).await;
    assert_eq!(status, StatusCode::OK, "{profile}");
    let (_, refreshed) = request(&app, &token_a, "POST", "/api/users", Some(json!({}))).await;
    assert_eq!(refreshed["username"], new_handle);
    let (duplicate, _) = request(&app, &token_b, "PUT", "/api/profile",
        Some(json!({"username":new_handle}))).await;
    assert_eq!(duplicate, StatusCode::CONFLICT);
    if std::env::var_os("SUPRA_TEST_AUTH_FIXTURE").is_some() {
        check_username_login(&state, alice, &new_handle).await;
    }
    // Exercise the real upload transaction and profile response, not just image parsing.
    let mut png = std::io::Cursor::new(Vec::new());
    image::DynamicImage::new_rgb8(16, 16)
        .write_to(&mut png, image::ImageFormat::Png).unwrap();
    let upload = Request::builder().method("POST").uri("/api/profile/avatar")
        .header("authorization", format!("Bearer {token_a}"))
        .header("content-type", "application/octet-stream")
        .body(Body::from(png.into_inner())).unwrap();
    let response = tokio::time::timeout(std::time::Duration::from_secs(2),
        app.clone().oneshot(upload)).await.expect("avatar upload should finish promptly").unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let profile: Value = serde_json::from_slice(&to_bytes(response.into_body(), 1024*1024).await.unwrap()).unwrap();
    assert!(profile["avatar_url"].as_str().unwrap().ends_with(".png"));

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
    assert!(trip["confirmed_at"].is_null());
    let (status, confirmed) = request(
        &app,
        &token_a,
        "POST",
        "/api/trips",
        Some(json!({
            "name": "Confirmed commute", "start_location": "A", "destination": "B",
            "planned_departure": "2030-01-01T12:00:00Z", "confirmed": true,
            "start_latitude": -6.2, "start_longitude": 106.8,
            "destination_latitude": -6.3, "destination_longitude": 106.9
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{confirmed}");
    assert!(confirmed["confirmed_at"].is_string());
    assert_eq!(confirmed["start_latitude"], -6.2);
    let confirmed_id = confirmed["id"].as_str().unwrap();
    let (status, _) = request(
        &app,
        &token_b,
        "DELETE",
        &format!("/api/trips/{confirmed_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, saved) = request(
        &app,
        &token_a,
        "GET",
        &format!("/api/trips/{confirmed_id}"),
        None,
    )
    .await;
    assert_eq!(saved["destination_longitude"], 106.9);
    let owned=crate::handlers::agent::owned_trip(&state,alice,Some(Uuid::parse_str(confirmed_id).unwrap())).await.unwrap().unwrap();
    assert_eq!(owned.origin,[-6.2,106.8]);
    assert!(matches!(crate::handlers::agent::owned_trip(&state,bob,Some(Uuid::parse_str(confirmed_id).unwrap())).await,Err(crate::error::AppError::NotFound)));
    let (status, _) = request(
        &app,
        &token_a,
        "DELETE",
        &format!("/api/trips/{confirmed_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = request(
        &app,
        &token_a,
        "GET",
        &format!("/api/trips/{confirmed_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
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
    // Publisher news writes use real inbox constraints, preference flags and per-user deduplication.
    let now = chrono::Utc::now();
    let news: crate::alerts::Incident = serde_json::from_value(json!({
        "id":"integration-news-1","title":"Test publisher report: transit in Jakarta",
        "source_url":"https://www.antaranews.com/berita/integration-fixture-only",
        "source_name":"ANTARA","latitude":-6.2,"longitude":106.8,
        "location_label":"Jakarta","location_radius_km":10,"verified":false,
        "published_at":now-chrono::Duration::hours(1),"starts_at":now-chrono::Duration::hours(1),
        "expires_at":now+chrono::Duration::hours(24)
    }))
    .unwrap();
    assert_eq!(
        crate::alerts::store_news_for_user(&state, bob, &[news.clone()])
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        crate::alerts::store_news_for_user(&state, bob, &[news.clone()])
            .await
            .unwrap(),
        0
    );
    let count:i64=sqlx::query_scalar("SELECT COUNT(*) FROM notifications WHERE user_id=$1 AND event_key='news:integration-news-1'")
        .bind(alice).fetch_one(&state.pool).await.unwrap();
    assert_eq!(
        count, 0,
        "publisher notification must not leak to another account"
    );
    let (status,minimum)=request(&app,&token_b,"PUT",&format!("/api/users/{bob}/preferences"),Some(json!({"news_min_severity":"medium"}))).await;
    assert_eq!(status,StatusCode::OK);assert_eq!(minimum["news_min_severity"],"medium");assert_eq!(minimum["alert_relevant_news"],true);
    // Previously delivered low news is hidden using saved settings even with a stale low query.
    let (status,visible)=request(&app,&token_b,"GET",&format!("/api/users/{bob}/notifications?news_min_severity=low"),None).await;
    assert_eq!(status,StatusCode::OK);assert!(visible.as_array().unwrap().is_empty());
    let (_,visible)=request(&app,&token_b,"GET","/api/notifications",None).await;
    assert!(visible.as_array().unwrap().is_empty());
    let report=|id:&str,severity:&str| serde_json::from_value::<crate::alerts::Incident>(json!({
        "id":id,"title":"Test severity classification in Jakarta","source_url":"https://www.antaranews.com/berita/fixture-only",
        "source_name":"ANTARA","latitude":-6.2,"longitude":106.8,"severity":severity,"published_at":now,
        "starts_at":now,"expires_at":now+chrono::Duration::hours(24),"verified":false
    })).unwrap();
    assert_eq!(crate::alerts::store_news_for_user(&state,bob,&[report("test-low","low")]).await.unwrap(),0);
    assert_eq!(crate::alerts::store_news_for_user(&state,bob,&[report("test-medium","medium"),report("test-high","high")]).await.unwrap(),2);
    sqlx::query("INSERT INTO notifications(user_id,title,message_body,severity) VALUES($1,'Weather fixture','Local alert','low')").bind(bob).execute(&state.pool).await.unwrap();
    let (status,filtered)=request(&app,&token_b,"GET",&format!("/api/users/{bob}/notifications?news_min_severity=high"),None).await;
    assert_eq!(status,StatusCode::OK);
    let filtered=filtered.as_array().unwrap();assert_eq!(filtered.len(),2,"high news and independent weather alert survive");
    assert!(filtered.iter().any(|n|n["severity"]=="high"));assert!(filtered.iter().any(|n|n["source_url"].is_null()));
    let sent_before:chrono::DateTime<chrono::Utc>=sqlx::query_scalar("UPDATE notifications SET is_read=true WHERE user_id=$1 AND event_key='news:integration-news-1' RETURNING sent_at").bind(bob).fetch_one(&state.pool).await.unwrap();
    assert_eq!(crate::alerts::store_news_for_user(&state,bob,&[report("integration-news-1","high")]).await.unwrap(),1);
    let (read,level,sent_after):(bool,String,chrono::DateTime<chrono::Utc>)=sqlx::query_as("SELECT is_read,severity,sent_at FROM notifications WHERE user_id=$1 AND event_key='news:integration-news-1'").bind(bob).fetch_one(&state.pool).await.unwrap();
    assert!(read);assert_eq!(level,"high");assert_eq!(sent_before,sent_after);
    let (status,_)=request(&app,&token_b,"PUT",&format!("/api/users/{bob}/preferences"),Some(json!({"news_min_severity":"urgent"}))).await;
    assert_eq!(status,StatusCode::BAD_REQUEST);
    // Single and selected unread preserve ownership, are atomic, and are idempotent.
    let test_high:Uuid=sqlx::query_scalar("SELECT id FROM notifications WHERE user_id=$1 AND event_key='news:test-high'").bind(bob).fetch_one(&state.pool).await.unwrap();
    let (status,_)=request(&app,&token_b,"PUT",&format!("/api/notifications/{test_high}/read"),None).await;assert_eq!(status,StatusCode::OK);
    let (status,unread)=request(&app,&token_b,"PUT",&format!("/api/notifications/{test_high}/unread"),None).await;assert_eq!(status,StatusCode::OK);assert_eq!(unread["is_read"],false);
    let (status,_)=request(&app,&token_b,"PUT",&format!("/api/notifications/{notification_id}/unread"),None).await;assert_eq!(status,StatusCode::NOT_FOUND);
    let selected:Uuid=sqlx::query_scalar("SELECT id FROM notifications WHERE user_id=$1 AND event_key='news:integration-news-1'").bind(bob).fetch_one(&state.pool).await.unwrap();
    let (status,_)=request(&app,&token_b,"PUT","/api/notifications/unread",Some(json!({"ids":[selected,notification_id]}))).await;assert_eq!(status,StatusCode::NOT_FOUND);
    let remains_read:bool=sqlx::query_scalar("SELECT is_read FROM notifications WHERE id=$1").bind(selected).fetch_one(&state.pool).await.unwrap();assert!(remains_read,"mixed-owner selection must not partially update");
    let (status,unread)=request(&app,&token_b,"PUT","/api/notifications/unread",Some(json!({"ids":[selected]}))).await;assert_eq!(status,StatusCode::OK);assert_eq!(unread["updated"],1);
    let (_,again)=request(&app,&token_b,"PUT","/api/notifications/unread",Some(json!({"ids":[selected]}))).await;assert_eq!(again["updated"],0);
    let (status,_)=request(&app,&token_b,"PUT","/api/notifications/unread",Some(json!({"ids":[]}))).await;assert_eq!(status,StatusCode::BAD_REQUEST);
    request(&app,&token_b,"PUT",&format!("/api/notifications/{selected}/read"),None).await;
    // Dismiss only this user's read alerts. Event keys survive scheduled reevaluation.
    sqlx::query("UPDATE notifications SET is_read=true WHERE id=$1").bind(notification_id).execute(&state.pool).await.unwrap();
    let (status,removed)=request(&app,&token_b,"DELETE","/api/notifications/read",None).await;
    assert_eq!(status,StatusCode::OK);assert_eq!(removed["deleted"],1);
    let (status,other)=request(&app,&token_a,"GET",&format!("/api/notifications/{notification_id}"),None).await;
    assert_eq!(status,StatusCode::OK);assert_eq!(other["is_read"],true);
    let (_,visible)=request(&app,&token_b,"GET",&format!("/api/users/{bob}/notifications"),None).await;
    assert_eq!(visible.as_array().unwrap().len(),3,"unread news and alerts are preserved");
    let (_,again)=request(&app,&token_b,"DELETE","/api/notifications/read",None).await;assert_eq!(again["deleted"],0);
    let dismissed:Uuid=sqlx::query_scalar("SELECT id FROM notifications WHERE user_id=$1 AND event_key='news:integration-news-1'").bind(bob).fetch_one(&state.pool).await.unwrap();
    let (status,_)=request(&app,&token_b,"GET",&format!("/api/notifications/{dismissed}"),None).await;assert_eq!(status,StatusCode::NOT_FOUND);
    let (status,_)=request(&app,&token_b,"PUT",&format!("/api/notifications/{dismissed}/unread"),None).await;assert_eq!(status,StatusCode::NOT_FOUND);
    crate::alerts::store_news_for_user(&state,bob,&[report("integration-news-1","critical")]).await.unwrap();
    let (_,visible)=request(&app,&token_b,"GET","/api/notifications",None).await;
    assert!(!visible.as_array().unwrap().iter().any(|n|n["id"]==dismissed.to_string()),"dismissed articles must not reappear");

    let (status, _) = request(
        &app,
        &token_b,
        "PUT",
        &format!("/api/users/{bob}/preferences"),
        Some(json!({"alert_relevant_news":false})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_,visible)=request(&app,&token_b,"GET",&format!("/api/users/{bob}/notifications"),None).await;
    assert_eq!(visible.as_array().unwrap().len(),1,"turning news off hides previous news but keeps the unrelated alert");
    let rain_id:Uuid=sqlx::query_scalar("INSERT INTO notifications(user_id,title,message_body,severity,context) VALUES($1,'Rain fixture','Rain','medium','{\"rule\":\"rain\"}'::jsonb) RETURNING id").bind(bob).fetch_one(&state.pool).await.unwrap();
    let (status,_)=request(&app,&token_b,"PUT",&format!("/api/users/{bob}/preferences"),Some(json!({"alert_heavy_rain":false}))).await;assert_eq!(status,StatusCode::OK);
    let (_,visible)=request(&app,&token_b,"GET",&format!("/api/users/{bob}/notifications"),None).await;
    assert!(!visible.as_array().unwrap().iter().any(|n|n["id"]==rain_id.to_string()));
    let (_,marked)=request(&app,&token_b,"PUT","/api/notifications/read",None).await;assert_eq!(marked["updated"],1,"bulk read touches only the remaining eligible generic alert");
    let high_unread:bool=sqlx::query_scalar("SELECT NOT is_read FROM notifications WHERE id=$1").bind(test_high).fetch_one(&state.pool).await.unwrap();assert!(high_unread,"hidden news is not marked read");
    let mut different=serde_json::to_value(json!({"id":"integration-news-2","title":"Test publisher report", "source_url":"https://www.antaranews.com/berita/fixture-two", "source_name":"ANTARA","latitude":-6.2,"longitude":106.8,"verified":false,"published_at":now,"starts_at":now,"expires_at":now+chrono::Duration::hours(24)})).unwrap();
    let second = serde_json::from_value(different.take()).unwrap();
    assert_eq!(
        crate::alerts::store_news_for_user(&state, bob, &[second])
            .await
            .unwrap(),
        0,
        "disabled news preference is respected"
    );

    // Saved places isolation
    let (status, home) = request(&app, &token_a, "POST", "/api/places", Some(json!({
        "label": "Home", "kind": "home", "latitude": -6.2, "longitude": 106.8
    }))).await;
    assert_eq!(status, StatusCode::OK, "{home}");
    let home_id = home["id"].as_str().unwrap();

    let (status, work) = request(&app, &token_a, "POST", "/api/places", Some(json!({
        "label": "Work", "kind": "work", "latitude": -6.25, "longitude": 106.85
    }))).await;
    assert_eq!(status, StatusCode::OK, "{work}");
    let work_id = work["id"].as_str().unwrap();

    let (status, b_places) = request(&app, &token_b, "GET", "/api/places", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(b_places.as_array().unwrap().len(), 0);

    let (status, _) = request(&app, &token_b, "PUT", &format!("/api/places/{home_id}"), Some(json!({
        "label": "Stolen", "kind": "home", "latitude": -6.2, "longitude": 106.8
    }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = request(&app, &token_b, "DELETE", &format!("/api/places/{home_id}"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, updated_home) = request(&app, &token_a, "PUT", &format!("/api/places/{home_id}"), Some(json!({
        "label": "Apartment", "kind": "home", "latitude": -6.205, "longitude": 106.805
    }))).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(updated_home["label"], "Apartment");

    // Routines isolation and validation
    let (status, routine) = request(&app, &token_a, "POST", "/api/routines", Some(json!({
        "label": "Morning Commute",
        "origin_id": home_id,
        "destination_id": work_id,
        "mode": "motorcycle",
        "weekdays": [0, 1, 2, 3, 4],
        "departure_minute": 450,
        "timezone": "Asia/Jakarta",
        "lead_minutes": 30,
        "enabled": true,
        "alerts_enabled": true,
        "news_enabled": true
    }))).await;
    assert_eq!(status, StatusCode::OK, "{routine}");
    let routine_id = routine["id"].as_str().unwrap();

    let (status, b_routines) = request(&app, &token_b, "GET", "/api/routines", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(b_routines.as_array().unwrap().len(), 0);

    let (status, _) = request(&app, &token_b, "PUT", &format!("/api/routines/{routine_id}"), Some(json!({
        "label": "Stolen Routine",
        "origin_id": home_id,
        "destination_id": work_id,
        "mode": "car",
        "weekdays": [0],
        "departure_minute": 450,
        "timezone": "Asia/Jakarta",
        "lead_minutes": 30,
        "enabled": true,
        "alerts_enabled": true,
        "news_enabled": false
    }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = request(&app, &token_b, "DELETE", &format!("/api/routines/{routine_id}"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = request(&app, &token_b, "POST", "/api/routines", Some(json!({
        "label": "Cross-user Places Routine",
        "origin_id": home_id,
        "destination_id": work_id,
        "mode": "car",
        "weekdays": [0],
        "departure_minute": 450,
        "timezone": "Asia/Jakarta",
        "lead_minutes": 30,
        "enabled": true,
        "alerts_enabled": true,
        "news_enabled": false
    }))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Trip finish isolation
    let (status, active_trip) = request(&app, &token_a, "POST", "/api/trips", Some(json!({
        "name": "Active Commute", "start_location": "A", "destination": "B",
        "planned_departure": "2030-01-01T12:00:00Z", "confirmed": true,
        "start_latitude": -6.2, "start_longitude": 106.8,
        "destination_latitude": -6.3, "destination_longitude": 106.9
    }))).await;
    assert_eq!(status, StatusCode::OK);
    let active_id = active_trip["id"].as_str().unwrap();

    let (status, _) = request(&app, &token_b, "POST", &format!("/api/trips/{active_id}/finish"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, finished) = request(&app, &token_a, "POST", &format!("/api/trips/{active_id}/finish"), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(finished["status"], "finished");

    // Alerts evaluation queued endpoint
    let (status, eval) = request(&app, &token_a, "POST", "/api/alerts/evaluate", None).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    assert_eq!(eval["queued"], true);
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

async fn check_username_login(state: &AppState, id: Uuid, username: &str) {
    use axum::{Json, routing::post};
    // The Auth email deliberately differs from the cached profile email.
    sqlx::query("INSERT INTO auth.users (id,email) VALUES ($1,'current@example.invalid')")
        .bind(id).execute(&state.pool).await.unwrap();
    let pool = state.pool.clone();
    let provider = Router::new().route("/token", post(move |Json(body): Json<Value>| async move {
        if body["email"] == "current@example.invalid" && body["password"] == "correct" {
            (StatusCode::OK, Json(json!({"refresh_token":"refresh", "user":{"id":id}})))
        } else {
            (StatusCode::BAD_REQUEST, Json(json!({"message":"Upstream detail"})))
        }
    })).route("/admin/users", post(move |headers: axum::http::HeaderMap, Json(body): Json<Value>| {
        let pool = pool.clone();
        async move {
            assert_eq!(headers["apikey"], "test-admin-key");
            let alias = body["email"].as_str().unwrap();
            assert!(alias.ends_with("@accounts.supra.invalid"));
            assert_eq!(body["email_confirm"], true);
            assert_eq!(body["password"], "tester-password");
            let id = Uuid::new_v4();
            let created = sqlx::query("INSERT INTO auth.users (id,email,raw_user_meta_data) VALUES ($1,$2,$3)")
                .bind(id).bind(alias).bind(&body["user_metadata"]).execute(&pool).await;
            match created {
                Ok(_) => (StatusCode::CREATED, Json(json!({"id":id}))),
                Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({}))),
            }
        }
    }));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move { axum::serve(listener, provider).await.unwrap() });
    let mut fixture = Fixture::new().await;
    fixture.password_endpoint(format!("{origin}/token"));
    fixture.admin_endpoint(format!("{origin}/admin/users"));
    let app = create_router(state.clone(), fixture.verifier.clone());
    let new_handle = format!("new_{}", &id.simple().to_string()[..12]);
    for status in [StatusCode::CREATED, StatusCode::CONFLICT] {
        let (actual, body) = request(&app, "", "POST", "/api/auth/register",
            Some(json!({"username":new_handle.to_uppercase(),"password":"tester-password"}))).await;
        assert_eq!(actual, status, "{body}");
        assert!(body.get("email").is_none());
    }
    let count = sqlx::query_scalar::<_, i64>(
        "SELECT count(*) FROM public.users WHERE username = $1 AND email LIKE '%@accounts.supra.invalid'",
    ).bind(new_handle).fetch_one(&state.pool).await.unwrap();
    assert_eq!(count, 1);
    for (name, password, expected) in [
        (username.to_uppercase(), "correct", StatusCode::OK),
        (username.to_owned(), "wrong", StatusCode::UNAUTHORIZED),
        ("unknown".into(), "correct", StatusCode::UNAUTHORIZED),
    ] {
        let (status, body) = request(&app, "", "POST", "/api/auth/username-login",
            Some(json!({"username":name,"password":password}))).await;
        assert_eq!(status, expected, "{body}");
        if status == StatusCode::OK {
            assert_eq!(body["user"]["id"], id.to_string());
        } else {
            assert_eq!(body["code"], "invalid_credentials");
            assert!(body.get("user").is_none());
        }
    }
    server.abort();
}
