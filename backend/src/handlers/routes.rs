use crate::auth::AuthUser;
use crate::db::AppState;
use crate::error::{AppError, AppResult};
use crate::models::*;
use crate::validation::{ValidatedJson, ValidatedPath};
use axum::{
    Json,
    extract::{Extension, State},
};
use uuid::Uuid;

pub async fn create_route(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedJson(payload): ValidatedJson<CreateRoute>,
) -> AppResult<Json<Route>> {
    let route = sqlx::query_as::<_, Route>(
        r#"
        INSERT INTO routes (trip_id, waypoints, total_distance)
        SELECT id, $2::jsonb, $3 FROM trips WHERE id = $1 AND user_id = $4
        RETURNING id, trip_id, waypoints, total_distance, created_at
        "#,
    )
    .bind(payload.trip_id)
    .bind(payload.waypoints)
    .bind(payload.total_distance)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(route))
}

pub async fn get_route(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<Route>> {
    let route = sqlx::query_as::<_, Route>(
        r#"
        SELECT r.id, r.trip_id, r.waypoints, r.total_distance, r.created_at
        FROM routes r JOIN trips t ON t.id = r.trip_id WHERE r.id = $1 AND t.user_id = $2
        "#,
    )
    .bind(id)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(route))
}

pub async fn list_routes(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
) -> AppResult<Json<Vec<Route>>> {
    let routes = sqlx::query_as::<_, Route>(
        r#"
        SELECT r.id, r.trip_id, r.waypoints, r.total_distance, r.created_at
        FROM routes r JOIN trips t ON t.id = r.trip_id WHERE t.user_id = $1 ORDER BY r.created_at DESC
        "#,
    )
    .bind(user.id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(routes))
}

pub async fn get_trip_routes(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(trip_id): ValidatedPath<Uuid>,
) -> AppResult<Json<Vec<Route>>> {
    let owned: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM trips WHERE id = $1 AND user_id = $2)")
            .bind(trip_id)
            .bind(user.id)
            .fetch_one(&state.pool)
            .await?;
    if !owned {
        return Err(AppError::NotFound);
    }
    let routes = sqlx::query_as::<_, Route>(
        r#"
        SELECT r.id, r.trip_id, r.waypoints, r.total_distance, r.created_at
        FROM routes r JOIN trips t ON t.id = r.trip_id WHERE r.trip_id = $1 AND t.user_id = $2
        ORDER BY r.created_at ASC
        "#,
    )
    .bind(trip_id)
    .bind(user.id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(routes))
}

pub async fn update_route(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
    ValidatedJson(payload): ValidatedJson<UpdateRoute>,
) -> AppResult<Json<Route>> {
    let route = sqlx::query_as::<_, Route>(
        r#"
        UPDATE routes
        SET waypoints = COALESCE($1::jsonb, waypoints),
            total_distance = COALESCE($2, total_distance)
        WHERE id = $3 AND trip_id IN (SELECT id FROM trips WHERE user_id = $4)
        RETURNING id, trip_id, waypoints, total_distance, created_at
        "#,
    )
    .bind(payload.waypoints)
    .bind(payload.total_distance)
    .bind(id)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(route))
}

pub async fn delete_route(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    let result = sqlx::query(
        "DELETE FROM routes WHERE id = $1 AND trip_id IN (SELECT id FROM trips WHERE user_id = $2)",
    )
    .bind(id)
    .bind(user.id)
    .execute(&state.pool)
    .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}
