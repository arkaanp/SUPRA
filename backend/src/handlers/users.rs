use crate::auth::{AuthUser, require_self};
use crate::db::AppState;
use crate::error::{AppError, AppResult};
use crate::models::*;
use crate::validation::{ValidatedJson, ValidatedPath};
use axum::{
    Json,
    extract::{Extension, State},
};
use uuid::Uuid;

pub async fn create_user(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedJson(payload): ValidatedJson<CreateUser>,
) -> AppResult<Json<User>> {
    let user = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (id, full_name, email)
        VALUES ($1, $2, $3)
        ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, email = EXCLUDED.email
        RETURNING id, full_name, email, created_at
        "#,
    )
    .bind(user.id)
    .bind(payload.full_name)
    .bind(user.email)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(user))
}

pub async fn get_user(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<User>> {
    require_self(&user, id)?;
    let user = sqlx::query_as::<_, User>(
        r#"
        SELECT id, full_name, email, created_at FROM users WHERE id = $1
        "#,
    )
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(user))
}

pub async fn list_users(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
) -> AppResult<Json<Vec<User>>> {
    let users = sqlx::query_as::<_, User>(
        r#"
        SELECT id, full_name, email, created_at FROM users WHERE id = $1
        "#,
    )
    .bind(user.id)
    .fetch_all(&state.pool)
    .await?;

    Ok(Json(users))
}

pub async fn update_user(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
    ValidatedJson(payload): ValidatedJson<UpdateUser>,
) -> AppResult<Json<User>> {
    require_self(&user, id)?;
    let user = sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET full_name = COALESCE($1, full_name),
            email     = COALESCE($2, email)
        WHERE id = $3
        RETURNING id, full_name, email, created_at
        "#,
    )
    .bind(payload.full_name)
    .bind(user.email)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(user))
}

pub async fn delete_user(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    require_self(&user, id)?;
    // Deletes the app profile, not the Supabase Auth account.
    let result = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(user.id)
        .execute(&state.pool)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}
