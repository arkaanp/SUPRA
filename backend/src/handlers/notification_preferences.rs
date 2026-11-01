use crate::auth::{AuthUser, require_self};
use crate::db::AppState;
use crate::error::AppResult;
use crate::models::*;
use crate::validation::{ValidatedJson, ValidatedPath};
use axum::{
    Json,
    extract::{Extension, State},
};
use uuid::Uuid;

pub async fn get_preferences(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(user_id): ValidatedPath<Uuid>,
) -> AppResult<Json<NotificationPreference>> {
    require_self(&user, user_id)?;
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
    Extension(user): Extension<AuthUser>,
    ValidatedPath(user_id): ValidatedPath<Uuid>,
    ValidatedJson(payload): ValidatedJson<UpdateNotificationPreference>,
) -> AppResult<Json<NotificationPreference>> {
    require_self(&user, user_id)?;
    let pref = sqlx::query_as::<_, NotificationPreference>(
        r#"
        INSERT INTO notification_preferences (user_id, alert_unhealthy_aqi, alert_heavy_rain, alert_severe_traffic)
        VALUES ($1, COALESCE($2, TRUE), COALESCE($3, TRUE), COALESCE($4, TRUE))
        ON CONFLICT (user_id) DO UPDATE
        SET alert_unhealthy_aqi = COALESCE($2, notification_preferences.alert_unhealthy_aqi),
            alert_heavy_rain = COALESCE($3, notification_preferences.alert_heavy_rain),
            alert_severe_traffic = COALESCE($4, notification_preferences.alert_severe_traffic),
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
