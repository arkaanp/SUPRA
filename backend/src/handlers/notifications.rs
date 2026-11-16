use crate::auth::{AuthUser, require_self};
use crate::db::AppState;
use crate::error::{AppError, AppResult};
use crate::models::*;
use crate::validation::{Validate, ValidatedJson, ValidatedPath, ValidatedQuery};
use axum::{
    Json,
    extract::{Extension, State},
};
use serde::Deserialize;
use serde_json::{Value, json};
use uuid::Uuid;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListNotificationsQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    pub unread_only: Option<bool>,
    pub news_min_severity: Option<String>,
}

pub async fn get_notification(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<Notification>> {
    let notification = sqlx::query_as::<_, Notification>(
        r#"
        SELECT *
        FROM notifications WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
        "#,
    )
    .bind(id)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(notification))
}

pub async fn list_notifications(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
) -> AppResult<Json<Vec<Notification>>> {
    Ok(Json(
        visible_notifications(&state, user.id, 1000, 0, false, "low").await?,
    ))
}

async fn visible_notifications(
    state: &AppState,
    user_id: Uuid,
    limit: i64,
    offset: i64,
    unread: bool,
    minimum: &str,
) -> AppResult<Vec<Notification>> {
    let rank = crate::alerts::severity_rank(minimum)
        .ok_or_else(|| crate::error::AppError::bad_request("Invalid news severity"))?
        as i32;
    let rows=sqlx::query_as::<_,Notification>(
        "SELECT n.* FROM notifications n LEFT JOIN notification_preferences p ON p.user_id=n.user_id \
         WHERE n.user_id=$1 AND n.deleted_at IS NULL AND (NOT $5 OR n.is_read=FALSE) \
         AND (n.event_key IS NULL OR NOT (n.event_key LIKE '%:bpbd-jkt-rain-kuningan-2026' OR n.event_key LIKE '%:tmc-polda-sudirman-thamrin-2026' OR n.event_key LIKE '%:dlh-dki-aqi-selatan-2026' OR n.event_key LIKE '%:kci-transjakarta-commuter-update-2026')) \
         AND CASE WHEN n.source_url IS NOT NULL AND trim(n.source_url)<>'' THEN \
             COALESCE(p.alert_relevant_news,true) AND CASE n.severity WHEN 'critical' THEN 3 WHEN 'high' THEN 2 WHEN 'medium' THEN 1 ELSE 0 END >= \
             GREATEST($4,CASE COALESCE(p.news_min_severity,'low') WHEN 'critical' THEN 3 WHEN 'high' THEN 2 WHEN 'medium' THEN 1 ELSE 0 END) \
           ELSE CASE n.context->>'rule' WHEN 'air' THEN COALESCE(p.alert_unhealthy_aqi,true) WHEN 'air_advisory' THEN COALESCE(p.alert_unhealthy_aqi,true) \
             WHEN 'rain' THEN COALESCE(p.alert_heavy_rain,true) WHEN 'traffic' THEN COALESCE(p.alert_severe_traffic,true) ELSE true END END \
         ORDER BY n.sent_at DESC,n.id DESC LIMIT $2 OFFSET $3")
        .bind(user_id).bind(limit).bind(offset).bind(rank).bind(unread).fetch_all(&state.pool).await?;
    Ok(rows)
}

pub async fn get_user_notifications(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(user_id): ValidatedPath<Uuid>,
    ValidatedQuery(query): ValidatedQuery<ListNotificationsQuery>,
) -> AppResult<Json<Vec<Notification>>> {
    require_self(&user, user_id)?;
    let limit = query.limit.unwrap_or(50);
    let offset = query.offset.unwrap_or(0);

    Ok(Json(
        visible_notifications(
            &state,
            user_id,
            limit,
            offset,
            query.unread_only.unwrap_or(false),
            query.news_min_severity.as_deref().unwrap_or("low"),
        )
        .await?,
    ))
}

/// Dismiss all read alerts for the verified account, retaining deduplication keys.
pub async fn delete_read_notifications(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
) -> AppResult<Json<Value>> {
    let deleted=sqlx::query("UPDATE notifications SET deleted_at=now() WHERE user_id=$1 AND is_read=true AND deleted_at IS NULL")
        .bind(user.id).execute(&state.pool).await?.rows_affected();
    Ok(Json(json!({"deleted":deleted})))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UnreadSelection {
    ids: Vec<Uuid>,
}
impl Validate for UnreadSelection {
    fn validate(&self) -> AppResult<()> {
        if self.ids.is_empty()
            || self.ids.len() > 100
            || self
                .ids
                .iter()
                .collect::<std::collections::HashSet<_>>()
                .len()
                != self.ids.len()
        {
            return Err(AppError::bad_request("Select 1–100 distinct alerts"));
        }
        Ok(())
    }
}

pub async fn mark_selected_unread(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedJson(payload): ValidatedJson<UnreadSelection>,
) -> AppResult<Json<Value>> {
    let mut tx = state.pool.begin().await?;
    let owned:Vec<Uuid>=sqlx::query_scalar("SELECT id FROM notifications WHERE user_id=$1 AND id=ANY($2) AND deleted_at IS NULL FOR UPDATE")
        .bind(user.id).bind(&payload.ids).fetch_all(&mut *tx).await?;
    if owned.len() != payload.ids.len() {
        return Err(AppError::NotFound);
    }
    let updated=sqlx::query("UPDATE notifications SET is_read=false WHERE user_id=$1 AND id=ANY($2) AND deleted_at IS NULL AND is_read=true")
        .bind(user.id).bind(&payload.ids).execute(&mut *tx).await?.rows_affected();
    tx.commit().await?;
    Ok(Json(json!({"updated":updated})))
}

pub async fn mark_all_read(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
) -> AppResult<Json<Value>> {
    let ids = visible_notifications(&state, user.id, i64::MAX, 0, true, "low")
        .await?
        .into_iter()
        .map(|n| n.id)
        .collect::<Vec<_>>();
    let updated=sqlx::query("UPDATE notifications SET is_read=true WHERE user_id=$1 AND id=ANY($2) AND deleted_at IS NULL AND is_read=false")
        .bind(user.id).bind(&ids).execute(&state.pool).await?.rows_affected();
    Ok(Json(json!({"updated":updated})))
}

async fn set_read(
    state: &AppState,
    user: Uuid,
    id: Uuid,
    read: bool,
) -> AppResult<Json<Notification>> {
    let notification=sqlx::query_as::<_,Notification>("UPDATE notifications SET is_read=$3 WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL RETURNING *")
        .bind(id).bind(user).bind(read).fetch_one(&state.pool).await?;
    Ok(Json(notification))
}
pub async fn mark_notification_read(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<Notification>> {
    set_read(&state, user.id, id, true).await
}
pub async fn mark_notification_unread(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<Notification>> {
    set_read(&state, user.id, id, false).await
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unread_selection_requires_bounded_distinct_ids() {
        let id = Uuid::new_v4();
        assert!(UnreadSelection { ids: vec![] }.validate().is_err());
        assert!(UnreadSelection { ids: vec![id, id] }.validate().is_err());
        assert!(
            UnreadSelection {
                ids: (0..101).map(|_| Uuid::new_v4()).collect()
            }
            .validate()
            .is_err()
        );
        assert!(UnreadSelection { ids: vec![id] }.validate().is_ok());
    }
}
