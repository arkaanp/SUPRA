use axum::{
    extract::{State, Path, Query},
    Json,
};
use crate::db::AppState;
use crate::error::AppResult;
use crate::models::*;
use serde::Deserialize;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct ListTripsQuery {
    pub user_id: Option<Uuid>,
}

pub async fn create_trip(
    State(state): State<AppState>,
    Json(payload): Json<CreateTrip>,
) -> AppResult<Json<Trip>> {
    let trip = sqlx::query_as::<_, Trip>(
        r#"
        INSERT INTO trips (user_id, name, start_location, destination, planned_departure)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, user_id, name, start_location, destination, planned_departure, created_at
        "#,
    )
    .bind(payload.user_id)
    .bind(payload.name)
    .bind(payload.start_location)
    .bind(payload.destination)
    .bind(payload.planned_departure)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(trip))
}

pub async fn get_trip(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Trip>> {
    let trip = sqlx::query_as::<_, Trip>(
        r#"
        SELECT id, user_id, name, start_location, destination, planned_departure, created_at
        FROM trips WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(trip))
}

pub async fn list_trips(
    State(state): State<AppState>,
    Query(query): Query<ListTripsQuery>,
) -> AppResult<Json<Vec<Trip>>> {
    match query.user_id {
        Some(user_id) => {
            let trips = sqlx::query_as::<_, Trip>(
                r#"
                SELECT id, user_id, name, start_location, destination, planned_departure, created_at
                FROM trips WHERE user_id = $1
                ORDER BY planned_departure ASC
                "#,
            )
            .bind(user_id)
            .fetch_all(&state.pool)
            .await?;
            Ok(Json(trips))
        }
        None => {
            let trips = sqlx::query_as::<_, Trip>(
                r#"
                SELECT id, user_id, name, start_location, destination, planned_departure, created_at
                FROM trips ORDER BY planned_departure DESC
                "#,
            )
            .fetch_all(&state.pool)
            .await?;
            Ok(Json(trips))
        }
    }
}

pub async fn get_user_trips(
    State(state): State<AppState>,
    Path(user_id): Path<Uuid>,
) -> AppResult<Json<Vec<Trip>>> {
    let trips = sqlx::query_as::<_, Trip>(
        r#"
        SELECT id, user_id, name, start_location, destination, planned_departure, created_at
        FROM trips WHERE user_id = $1
        ORDER BY planned_departure ASC
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(trips))
}

pub async fn update_trip(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
    Json(payload): Json<UpdateTrip>,
) -> AppResult<Json<Trip>> {
    let trip = sqlx::query_as::<_, Trip>(
        r#"
        UPDATE trips
        SET name = COALESCE($1, name),
            start_location = COALESCE($2, start_location),
            destination = COALESCE($3, destination),
            planned_departure = COALESCE($4, planned_departure)
        WHERE id = $5
        RETURNING id, user_id, name, start_location, destination, planned_departure, created_at
        "#,
    )
    .bind(payload.name)
    .bind(payload.start_location)
    .bind(payload.destination)
    .bind(payload.planned_departure)
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(trip))
}

pub async fn delete_trip(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    sqlx::query("DELETE FROM trips WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await?;

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}
