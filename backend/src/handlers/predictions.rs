use crate::auth::AuthUser;
use crate::db::AppState;
use crate::error::{AppError, AppResult};
use crate::models::*;
use crate::validation::ValidatedPath;
use axum::{
    Json,
    extract::{Extension, State},
};
use uuid::Uuid;

pub async fn get_prediction(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<Prediction>> {
    let prediction = sqlx::query_as::<_, Prediction>(
        r#"
        SELECT p.id, p.route_id, p.target_time, p.predicted_aqi, p.predicted_rainfall_prob, p.predicted_traffic_density, p.generated_at
        FROM predictions p JOIN routes r ON r.id = p.route_id JOIN trips t ON t.id = r.trip_id
        WHERE p.id = $1 AND t.user_id = $2
        "#,
    )
    .bind(id)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(prediction))
}

pub async fn list_predictions(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
) -> AppResult<Json<Vec<Prediction>>> {
    let predictions = sqlx::query_as::<_, Prediction>(
        r#"
        SELECT p.id, p.route_id, p.target_time, p.predicted_aqi, p.predicted_rainfall_prob, p.predicted_traffic_density, p.generated_at
        FROM predictions p JOIN routes r ON r.id = p.route_id JOIN trips t ON t.id = r.trip_id
        WHERE t.user_id = $1 ORDER BY p.target_time ASC
        "#,
    )
    .bind(user.id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(predictions))
}

pub async fn get_route_predictions(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(route_id): ValidatedPath<Uuid>,
) -> AppResult<Json<Vec<Prediction>>> {
    let owned: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM routes r JOIN trips t ON t.id = r.trip_id WHERE r.id = $1 AND t.user_id = $2)")
        .bind(route_id).bind(user.id).fetch_one(&state.pool).await?;
    if !owned {
        return Err(AppError::NotFound);
    }
    let predictions = sqlx::query_as::<_, Prediction>(
        r#"
        SELECT p.id, p.route_id, p.target_time, p.predicted_aqi, p.predicted_rainfall_prob, p.predicted_traffic_density, p.generated_at
        FROM predictions p JOIN routes r ON r.id = p.route_id JOIN trips t ON t.id = r.trip_id
        WHERE p.route_id = $1 AND t.user_id = $2 ORDER BY p.target_time ASC
        "#,
    )
    .bind(route_id)
    .bind(user.id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(predictions))
}
