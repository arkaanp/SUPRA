use axum::{
    extract::{State, Path},
    Json,
};
use crate::db::AppState;
use crate::error::AppResult;
use crate::models::*;
use uuid::Uuid;

pub async fn get_preferences(
    State(state): State<AppState>,
    Path(user_id): Path<Uuid>,
) -> AppResult<Json<NotificationPreference>> {
    let pref = sqlx::query_as::<_, NotificationPreference>(
        r#"
        SELECT id, user_id, alert_unhealthy_aqi, alert_heavy_rain, alert_severe_traffic, updated_at
        FROM notification_preferences WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(pref))
}

pub async fn update_preferences(
    State(state): State<AppState>,
    Path(user_id): Path<Uuid>,
    Json(payload): Json<UpdateNotificationPreference>,
) -> AppResult<Json<NotificationPreference>> {
    let pref = sqlx::query_as::<_, NotificationPreference>(
        r#"
        INSERT INTO notification_preferences (user_id, alert_unhealthy_aqi, alert_heavy_rain, alert_severe_traffic)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (user_id) DO UPDATE
        SET alert_unhealthy_aqi = COALESCE(EXCLUDED.alert_unhealthy_aqi, notification_preferences.alert_unhealthy_aqi),
            alert_heavy_rain = COALESCE(EXCLUDED.alert_heavy_rain, notification_preferences.alert_heavy_rain),
            alert_severe_traffic = COALESCE(EXCLUDED.alert_severe_traffic, notification_preferences.alert_severe_traffic),
            updated_at = NOW()
        RETURNING id, user_id, alert_unhealthy_aqi, alert_heavy_rain, alert_severe_traffic, updated_at
        "#,
    )
    .bind(user_id)
    .bind(payload.alert_unhealthy_aqi)
    .bind(payload.alert_heavy_rain)
    .bind(payload.alert_severe_traffic)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(pref))
}
