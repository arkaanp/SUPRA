use axum::{
    extract::State,
    Json,
};
use crate::db::AppState;
use crate::error::{AppError, AppResult};
use crate::models::*;
use crate::validation::{ValidatedJson, ValidatedPath};
use uuid::Uuid;

pub async fn create_route(
    State(state): State<AppState>,
    ValidatedJson(payload): ValidatedJson<CreateRoute>,
) -> AppResult<Json<Route>> {
    let route = sqlx::query_as::<_, Route>(
        r#"
        INSERT INTO routes (trip_id, waypoints, total_distance)
        VALUES ($1, $2::jsonb, $3)
        RETURNING id, trip_id, waypoints, total_distance, created_at
        "#,
    )
    .bind(payload.trip_id)
    .bind(payload.waypoints)
    .bind(payload.total_distance)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(route))
}

pub async fn get_route(
    State(state): State<AppState>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<Route>> {
    let route = sqlx::query_as::<_, Route>(
        r#"
        SELECT id, trip_id, waypoints, total_distance, created_at
        FROM routes WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(route))
}

pub async fn list_routes(
    State(state): State<AppState>,
) -> AppResult<Json<Vec<Route>>> {
    let routes = sqlx::query_as::<_, Route>(
        r#"
        SELECT id, trip_id, waypoints, total_distance, created_at
        FROM routes ORDER BY created_at DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(routes))
}

pub async fn get_trip_routes(
    State(state): State<AppState>,
    ValidatedPath(trip_id): ValidatedPath<Uuid>,
) -> AppResult<Json<Vec<Route>>> {
    let routes = sqlx::query_as::<_, Route>(
        r#"
        SELECT id, trip_id, waypoints, total_distance, created_at
        FROM routes WHERE trip_id = $1
        ORDER BY created_at ASC
        "#,
    )
    .bind(trip_id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(routes))
}

pub async fn update_route(
    State(state): State<AppState>,
    ValidatedPath(id): ValidatedPath<Uuid>,
    ValidatedJson(payload): ValidatedJson<UpdateRoute>,
) -> AppResult<Json<Route>> {
    let route = sqlx::query_as::<_, Route>(
        r#"
        UPDATE routes
        SET waypoints = COALESCE($1::jsonb, waypoints),
            total_distance = COALESCE($2, total_distance)
        WHERE id = $3
        RETURNING id, trip_id, waypoints, total_distance, created_at
        "#,
    )
    .bind(payload.waypoints)
    .bind(payload.total_distance)
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(route))
}

pub async fn delete_route(
    State(state): State<AppState>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    let result = sqlx::query("DELETE FROM routes WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await?;
    if result.rows_affected() == 0 { return Err(AppError::NotFound); }

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}
