use crate::auth::{AuthUser, require_self};
use crate::db::AppState;
use crate::error::{AppError, AppResult};
use crate::models::*;
use crate::validation::{ValidatedJson, ValidatedPath, ValidatedQuery};
use axum::{
    Json,
    extract::{Extension, State},
};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListTripsQuery {
    pub user_id: Option<Uuid>,
}

pub async fn create_trip(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedJson(payload): ValidatedJson<CreateTrip>,
) -> AppResult<Json<Trip>> {
    let trip = sqlx::query_as::<_, Trip>(
        r#"
        INSERT INTO trips (user_id, name, start_location, destination, planned_departure,
            start_latitude, start_longitude, destination_latitude, destination_longitude, confirmed_at,
            transport_mode, active_until, route_waypoints)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CASE WHEN $10 THEN now() ELSE NULL END,
            $11, CASE WHEN $10 THEN now()+interval '4 hours' ELSE NULL END, $12)
        RETURNING *
        "#,
    )
    .bind(user.id)
    .bind(payload.name)
    .bind(payload.start_location)
    .bind(payload.destination)
    .bind(payload.planned_departure)
    .bind(payload.start_latitude)
    .bind(payload.start_longitude)
    .bind(payload.destination_latitude)
    .bind(payload.destination_longitude)
    .bind(payload.confirmed)
    .bind(payload.transport_mode)
    .bind(payload.route_waypoints.unwrap_or_else(|| serde_json::json!([])))
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(trip))
}

pub async fn get_trip(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<Trip>> {
    let trip = sqlx::query_as::<_, Trip>(
        r#"
        SELECT *
        FROM trips WHERE id = $1 AND user_id = $2
        "#,
    )
    .bind(id)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(trip))
}

pub async fn list_trips(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedQuery(query): ValidatedQuery<ListTripsQuery>,
) -> AppResult<Json<Vec<Trip>>> {
    if let Some(id) = query.user_id {
        require_self(&user, id)?;
    }
    let trips = sqlx::query_as::<_, Trip>(
        "SELECT * FROM trips WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user.id)
    .fetch_all(&state.pool)
    .await?;
    Ok(Json(trips))
}

pub async fn get_user_trips(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(user_id): ValidatedPath<Uuid>,
) -> AppResult<Json<Vec<Trip>>> {
    require_self(&user, user_id)?;
    let trips = sqlx::query_as::<_, Trip>(
        r#"
        SELECT *
        FROM trips WHERE user_id = $1
        ORDER BY planned_departure ASC
        "#,
    )
    .bind(user.id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(trips))
}

pub async fn update_trip(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
    ValidatedJson(payload): ValidatedJson<UpdateTrip>,
) -> AppResult<Json<Trip>> {
    let trip = sqlx::query_as::<_, Trip>(
        r#"
        UPDATE trips
        SET name = COALESCE($1, name),
            start_location = COALESCE($2, start_location),
            destination = COALESCE($3, destination),
            planned_departure = COALESCE($4, planned_departure)
        WHERE id = $5 AND user_id = $6
        RETURNING *
        "#,
    )
    .bind(payload.name)
    .bind(payload.start_location)
    .bind(payload.destination)
    .bind(payload.planned_departure)
    .bind(id)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(trip))
}

pub async fn delete_trip(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    let result = sqlx::query("DELETE FROM trips WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(user.id)
        .execute(&state.pool)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}
