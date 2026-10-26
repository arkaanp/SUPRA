use axum::{
    routing::{get, post, put},
    Router,
};
use crate::db::AppState;
use crate::handlers::{
    users, trips, routes as route_handlers, predictions,
    notification_preferences, notifications,
};

pub fn create_router(state: AppState) -> Router {
    Router::new()
        // ====================================================================
        // Users
        // ====================================================================
        .route("/api/users", post(users::create_user).get(users::list_users))
        .route(
            "/api/users/:id",
            get(users::get_user)
                .put(users::update_user)
                .delete(users::delete_user),
        )

        // ====================================================================
        // Trips
        // ====================================================================
        .route("/api/trips", post(trips::create_trip).get(trips::list_trips))
        .route(
            "/api/trips/:id",
            get(trips::get_trip)
                .put(trips::update_trip)
                .delete(trips::delete_trip),
        )
        .route(
            "/api/users/:user_id/trips",
            get(trips::get_user_trips),
        )

        // ====================================================================
        // Routes
        // ====================================================================
        .route("/api/routes", post(route_handlers::create_route).get(route_handlers::list_routes))
        .route(
            "/api/routes/:id",
            get(route_handlers::get_route)
                .put(route_handlers::update_route)
                .delete(route_handlers::delete_route),
        )
        .route(
            "/api/trips/:trip_id/routes",
            get(route_handlers::get_trip_routes),
        )

        // ====================================================================
        // Predictions
        // ====================================================================
        .route(
            "/api/predictions",
            post(predictions::create_prediction).get(predictions::list_predictions),
        )
        .route(
            "/api/predictions/:id",
            get(predictions::get_prediction).delete(predictions::delete_prediction),
        )
        .route(
            "/api/routes/:route_id/predictions",
            get(predictions::get_route_predictions),
        )

        // ====================================================================
        // Notification Preferences
        // ====================================================================
        .route(
            "/api/users/:user_id/preferences",
            get(notification_preferences::get_preferences)
                .put(notification_preferences::update_preferences),
        )

        // ====================================================================
        // Notifications
        // ====================================================================
        .route(
            "/api/notifications",
            post(notifications::create_notification).get(notifications::list_notifications),
        )
        .route(
            "/api/notifications/:id",
            get(notifications::get_notification),
        )
        .route(
            "/api/notifications/:id/read",
            put(notifications::mark_notification_read),
        )
        .route(
            "/api/users/:user_id/notifications",
            get(notifications::get_user_notifications),
        )
        .with_state(state)
}
