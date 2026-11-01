use crate::db::AppState;
use crate::handlers::{
    notification_preferences, notifications, predictions, routes as route_handlers, trips, users,
};
use axum::{
    Router,
    routing::{get, post, put},
};

pub fn create_router(state: AppState, verifier: crate::auth::AuthVerifier) -> Router {
    Router::new()
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
        .layer(axum::middleware::from_fn_with_state(
            verifier,
            crate::auth::authenticate,
        ))
        .with_state(state)
}

#[cfg(test)]
mod tests {
    use super::*;

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
