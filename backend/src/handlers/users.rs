use axum::{
    extract::State,
    Json,
};
use crate::db::AppState;
use crate::error::{AppError, AppResult};
use crate::models::*;
use crate::validation::{ValidatedJson, ValidatedPath};
use uuid::Uuid;

pub async fn create_user(
    State(state): State<AppState>,
    ValidatedJson(payload): ValidatedJson<CreateUser>,
) -> AppResult<Json<User>> {
    let user = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (full_name, email, password_hash)
        VALUES ($1, $2, $3)
        RETURNING id, full_name, email, password_hash, created_at
        "#,
    )
    .bind(payload.full_name)
    .bind(payload.email)
    .bind(payload.password_hash)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(user))
}

pub async fn get_user(
    State(state): State<AppState>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<User>> {
    let user = sqlx::query_as::<_, User>(
        r#"
        SELECT id, full_name, email, password_hash, created_at
        FROM users WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(user))
}

pub async fn list_users(
    State(state): State<AppState>,
) -> AppResult<Json<Vec<User>>> {
    let users = sqlx::query_as::<_, User>(
        r#"
        SELECT id, full_name, email, password_hash, created_at
        FROM users ORDER BY created_at DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(users))
}

pub async fn update_user(
    State(state): State<AppState>,
    ValidatedPath(id): ValidatedPath<Uuid>,
    ValidatedJson(payload): ValidatedJson<UpdateUser>,
) -> AppResult<Json<User>> {
    let user = sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET full_name = COALESCE($1, full_name),
            email     = COALESCE($2, email)
        WHERE id = $3
        RETURNING id, full_name, email, password_hash, created_at
        "#,
    )
    .bind(payload.full_name)
    .bind(payload.email)
    .bind(id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(user))
}

pub async fn delete_user(
    State(state): State<AppState>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    let result = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(id)
        .execute(&state.pool)
        .await?;
    if result.rows_affected() == 0 { return Err(AppError::NotFound); }

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}
