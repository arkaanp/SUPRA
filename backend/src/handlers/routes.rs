use axum::{
    extract::{State, Path},
    Json,
};
use crate::db::AppState;
use crate::error::AppResult;
use crate::models::*;
use uuid::Uuid;

pub async fn create_route(
    State(state): State<AppState>,
    Json(payload): Json<CreateRoute>,
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
    Path(id): Path<Uuid>,
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
    Path(trip_id): Path<Uuid>,
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
    Path(id): Path<Uuid>,
    Json(payload): Json<UpdateRoute>,
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
    Path(id): Path<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    sqlx::query("DELETE FROM routes WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await?;

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}
