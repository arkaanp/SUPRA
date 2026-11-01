use axum::{
    extract::State,
    Json,
};
use crate::db::AppState;
use crate::error::AppResult;
use crate::models::*;
use crate::validation::{ValidatedJson, ValidatedPath, ValidatedQuery};
use serde::Deserialize;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListNotificationsQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    pub unread_only: Option<bool>,
}

pub async fn create_notification(
    State(state): State<AppState>,
    ValidatedJson(payload): ValidatedJson<CreateNotification>,
) -> AppResult<Json<Notification>> {
    let notification = sqlx::query_as::<_, Notification>(
        r#"
        INSERT INTO notifications (user_id, title, message_body, severity, sent_at)
        VALUES ($1, $2, $3, $4, NOW())
        RETURNING id, user_id, title, message_body, severity, sent_at, is_read
        "#,
    )
    .bind(payload.user_id)
    .bind(payload.title)
    .bind(payload.message_body)
    .bind(payload.severity)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(notification))
}

pub async fn get_notification(
    State(state): State<AppState>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<Notification>> {
    let notification = sqlx::query_as::<_, Notification>(
        r#"
        SELECT id, user_id, title, message_body, severity, sent_at, is_read
        FROM notifications WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(notification))
}

pub async fn list_notifications(
    State(state): State<AppState>,
) -> AppResult<Json<Vec<Notification>>> {
    let notifications = sqlx::query_as::<_, Notification>(
        r#"
        SELECT id, user_id, title, message_body, severity, sent_at, is_read
        FROM notifications ORDER BY sent_at DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(notifications))
}

pub async fn get_user_notifications(
    State(state): State<AppState>,
    ValidatedPath(user_id): ValidatedPath<Uuid>,
    ValidatedQuery(query): ValidatedQuery<ListNotificationsQuery>,
) -> AppResult<Json<Vec<Notification>>> {
    let limit = query.limit.unwrap_or(50);
    let offset = query.offset.unwrap_or(0);

    let notifications = if query.unread_only.unwrap_or(false) {
        sqlx::query_as::<_, Notification>(
            r#"
            SELECT id, user_id, title, message_body, severity, sent_at, is_read
            FROM notifications
            WHERE user_id = $1 AND is_read = FALSE
            ORDER BY sent_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.pool)
        .await?
    } else {
        sqlx::query_as::<_, Notification>(
            r#"
            SELECT id, user_id, title, message_body, severity, sent_at, is_read
            FROM notifications
            WHERE user_id = $1
            ORDER BY sent_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.pool)
        .await?
    };

    Ok(Json(notifications))
}

pub async fn mark_notification_read(
    State(state): State<AppState>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<Notification>> {
    let notification = sqlx::query_as::<_, Notification>(
        r#"
        UPDATE notifications
        SET is_read = TRUE
        WHERE id = $1
        RETURNING id, user_id, title, message_body, severity, sent_at, is_read
        "#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(notification))
}
