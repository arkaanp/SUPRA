use axum::{
    extract::{State, Path},
    Json,
};
use crate::db::AppState;
use crate::error::AppResult;
use crate::models::*;
use uuid::Uuid;

pub async fn create_prediction(
    State(state): State<AppState>,
    Json(payload): Json<CreatePrediction>,
) -> AppResult<Json<Prediction>> {
    let prediction = sqlx::query_as::<_, Prediction>(
        r#"
        INSERT INTO predictions (route_id, target_time, predicted_aqi, predicted_rainfall_prob, predicted_traffic_density, generated_at)
        VALUES ($1, $2, $3, $4, $5, NOW())
        ON CONFLICT (route_id, target_time) DO UPDATE
        SET predicted_aqi = EXCLUDED.predicted_aqi,
            predicted_rainfall_prob = EXCLUDED.predicted_rainfall_prob,
            predicted_traffic_density = EXCLUDED.predicted_traffic_density,
            generated_at = NOW()
        RETURNING id, route_id, target_time, predicted_aqi, predicted_rainfall_prob, predicted_traffic_density, generated_at
        "#,
    )
    .bind(payload.route_id)
    .bind(payload.target_time)
    .bind(payload.predicted_aqi)
    .bind(payload.predicted_rainfall_prob)
    .bind(payload.predicted_traffic_density)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(prediction))
}

pub async fn get_prediction(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Prediction>> {
    let prediction = sqlx::query_as::<_, Prediction>(
        r#"
        SELECT id, route_id, target_time, predicted_aqi, predicted_rainfall_prob, predicted_traffic_density, generated_at
        FROM predictions WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(prediction))
}

pub async fn list_predictions(
    State(state): State<AppState>,
) -> AppResult<Json<Vec<Prediction>>> {
    let predictions = sqlx::query_as::<_, Prediction>(
        r#"
        SELECT id, route_id, target_time, predicted_aqi, predicted_rainfall_prob, predicted_traffic_density, generated_at
        FROM predictions ORDER BY target_time ASC
        "#,
    )
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(predictions))
}

pub async fn get_route_predictions(
    State(state): State<AppState>,
    Path(route_id): Path<Uuid>,
) -> AppResult<Json<Vec<Prediction>>> {
    let predictions = sqlx::query_as::<_, Prediction>(
        r#"
        SELECT id, route_id, target_time, predicted_aqi, predicted_rainfall_prob, predicted_traffic_density, generated_at
        FROM predictions WHERE route_id = $1
        ORDER BY target_time ASC
        "#,
    )
    .bind(route_id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(predictions))
}

pub async fn delete_prediction(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    sqlx::query("DELETE FROM predictions WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await?;

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}
