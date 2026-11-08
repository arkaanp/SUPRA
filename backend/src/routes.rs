use crate::db::AppState;
use crate::handlers::{
    agent, health, notification_preferences, notifications, predictions, routes as route_handlers,
    trips, users,
};
use axum::{
    Router,
    routing::{get, post, put},
};

pub fn create_router(state: AppState, verifier: crate::auth::AuthVerifier) -> Router {
    create_router_with_conditions(
        state,
        verifier,
        std::sync::Arc::new(crate::conditions::ConditionsService::from_env()),
    )
}

pub(crate) fn create_router_with_conditions(
    state: AppState,
    verifier: crate::auth::AuthVerifier,
    conditions: std::sync::Arc<crate::conditions::ConditionsService>,
) -> Router {
    Router::new()
        .route("/health/live", get(health::live))
        .route("/health/ready", get(health::ready))
        .merge(protected_routes(verifier))
        .fallback(|| async { crate::error::AppError::NotFound })
        .method_not_allowed_fallback(|| async { crate::error::AppError::MethodNotAllowed })
        .layer(axum::Extension(conditions))
        .with_state(state)
}

fn protected_routes(verifier: crate::auth::AuthVerifier) -> Router<AppState> {
    Router::new()
        .route("/api/conditions/current", get(crate::conditions::current))
        // ====================================================================
        // Users
        // ====================================================================
        .route(
            "/api/users",
            post(users::create_user).get(users::list_users),
        )
        .route(
            "/api/users/{id}",
            get(users::get_user)
                .put(users::update_user)
                .delete(users::delete_user),
        )
        // ====================================================================
        // Trips
        // ====================================================================
        .route(
            "/api/trips",
            post(trips::create_trip).get(trips::list_trips),
        )
        .route(
            "/api/trips/{id}",
            get(trips::get_trip)
                .put(trips::update_trip)
                .delete(trips::delete_trip),
        )
        .route("/api/users/{user_id}/trips", get(trips::get_user_trips))
        // ====================================================================
        // Routes
        // ====================================================================
        .route(
            "/api/routes",
            post(route_handlers::create_route).get(route_handlers::list_routes),
        )
        .route(
            "/api/routes/{id}",
            get(route_handlers::get_route)
                .put(route_handlers::update_route)
                .delete(route_handlers::delete_route),
        )
        .route(
            "/api/trips/{trip_id}/routes",
            get(route_handlers::get_trip_routes),
        )
        // ====================================================================
        // Predictions
        // ====================================================================
        .route("/api/predictions", get(predictions::list_predictions))
        .route("/api/predictions/{id}", get(predictions::get_prediction))
        .route(
            "/api/routes/{route_id}/predictions",
            get(predictions::get_route_predictions),
        )
        // ====================================================================
        // Notification Preferences
        // ====================================================================
        .route(
            "/api/users/{user_id}/preferences",
            get(notification_preferences::get_preferences)
                .put(notification_preferences::update_preferences),
        )
        // ====================================================================
        // Notifications
        // ====================================================================
        .route("/api/notifications", get(notifications::list_notifications))
        .route(
            "/api/notifications/{id}",
            get(notifications::get_notification),
        )
        .route(
            "/api/notifications/{id}/read",
            put(notifications::mark_notification_read),
        )
        .route(
            "/api/users/{user_id}/notifications",
            get(notifications::get_user_notifications),
        )
        // ====================================================================
        // Agent 1: Conversational Trip-Forecast Assistant
        // ====================================================================
        .route("/api/agent/chat", post(agent::chat))
        // Install this before auth so method errors on protected paths cannot
        // bypass authentication. The outer router preserves custom fallbacks.
        .method_not_allowed_fallback(|| async { crate::error::AppError::MethodNotAllowed })
        .route_layer(axum::middleware::from_fn_with_state(
            verifier,
            crate::auth::authenticate,
        ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        body::{Body, to_bytes},
        http::{Request, StatusCode, header},
    };
    use serde_json::{Value, json};
    use tower::ServiceExt;

    fn test_state() -> AppState {
        AppState {
            pool: sqlx::postgres::PgPoolOptions::new()
                .connect_lazy("postgres://localhost/supra_test")
                .unwrap(),
        }
    }

    async fn json_body(response: axum::response::Response) -> Value {
        assert_eq!(response.headers()[header::CONTENT_TYPE], "application/json");
        let bytes = to_bytes(response.into_body(), 4096).await.unwrap();
        serde_json::from_slice(&bytes).unwrap()
    }

    #[tokio::test]
    async fn public_health_routes_do_not_require_auth() {
        let state = test_state();
        // A closed pool fails deterministically without touching a real DB.
        state.pool.close().await;
        let verifier =
            crate::auth::AuthVerifier::new("https://example.supabase.co", "authenticated").unwrap();
        let app = create_router(state, verifier);
        let live = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/health/live")
                    .header(header::AUTHORIZATION, "Bearer invalid")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(live.status(), StatusCode::OK);
        assert_eq!(json_body(live).await, json!({"status": "ok"}));
        let ready = app
            .oneshot(
                Request::builder()
                    .uri("/health/ready")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(ready.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(
            json_body(ready).await,
            json!({"error": "Service not ready", "code": "unavailable"})
        );
    }

    #[tokio::test]
    async fn unmatched_routes_return_json_404() {
        let app = create_router(
            test_state(),
            crate::auth::AuthVerifier::new("https://example.supabase.co", "authenticated").unwrap(),
        );
        for path in ["/missing", "/api/missing", "/health/missing"] {
            let response = app
                .clone()
                .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::NOT_FOUND, "{path}");
            assert_eq!(json_body(response).await["code"], "not_found");
        }
    }

    #[tokio::test]
    async fn method_errors_are_json_and_keep_allow_header() {
        let fixture = crate::auth::test_support::Fixture::new().await;
        let app = create_router(test_state(), fixture.verifier.clone());
        let token = fixture.token(uuid::Uuid::new_v4(), "test@example.com");
        for (path, auth) in [
            ("/health/live", false),
            ("/health/ready", false),
            ("/api/predictions", true),
            ("/api/notifications", true),
        ] {
            let mut request = Request::builder().method("POST").uri(path);
            if auth {
                request = request.header(header::AUTHORIZATION, format!("Bearer {token}"));
            }
            let response = app
                .clone()
                .oneshot(request.body(Body::empty()).unwrap())
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED, "{path}");
            assert!(
                response.headers()[header::ALLOW]
                    .to_str()
                    .unwrap()
                    .split(',')
                    .any(|method| method.trim() == "GET")
            );
            assert_eq!(json_body(response).await["code"], "method_not_allowed");
        }
        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/predictions")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn router_builds_with_axum_capture_syntax() {
        let pool = sqlx::postgres::PgPoolOptions::new()
            .connect_lazy("postgres://localhost/supra_test")
            .expect("valid test database URL");

        let verifier =
            crate::auth::AuthVerifier::new("https://example.supabase.co", "authenticated").unwrap();
        let _router = create_router(AppState { pool }, verifier);
    }
}
