use crate::auth::{AuthUser, require_self};
use crate::db::AppState;
use crate::error::{AppError, AppResult};
use crate::models::*;
use crate::validation::{ValidatedJson, ValidatedPath};
use axum::{
    Json,
    body::Bytes,
    extract::{Extension, Path, State},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use std::path::PathBuf;
use uuid::Uuid;

fn avatars_dir() -> PathBuf {
    PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/uploads/avatars"))
}

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
        RETURNING id, full_name, email, avatar_url, created_at
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
        SELECT id, full_name, email, avatar_url, created_at FROM users WHERE id = $1
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
        SELECT id, full_name, email, avatar_url, created_at FROM users WHERE id = $1
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
        SET full_name  = COALESCE($1, full_name),
            email      = COALESCE($2, email),
            avatar_url = COALESCE($3, avatar_url)
        WHERE id = $4
        RETURNING id, full_name, email, avatar_url, created_at
        "#,
    )
    .bind(payload.full_name)
    .bind(user.email)
    .bind(payload.avatar_url)
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(user))
}

pub async fn get_profile(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
) -> AppResult<Json<User>> {
    let profile = sqlx::query_as::<_, User>(
        r#"
        SELECT id, full_name, email, avatar_url, created_at FROM users WHERE id = $1
        "#,
    )
    .bind(user.id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(profile))
}

pub async fn update_profile(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    ValidatedJson(payload): ValidatedJson<UpdateUser>,
) -> AppResult<Json<User>> {
    let updated = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (id, full_name, email, avatar_url)
        VALUES ($1, COALESCE($2, 'Supra user'), $3, $4)
        ON CONFLICT (id) DO UPDATE
        SET full_name  = COALESCE($2, users.full_name),
            email      = EXCLUDED.email,
            avatar_url = COALESCE($4, users.avatar_url)
        RETURNING id, full_name, email, avatar_url, created_at
        "#,
    )
    .bind(user.id)
    .bind(payload.full_name)
    .bind(user.email)
    .bind(payload.avatar_url)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(updated))
}

pub async fn upload_avatar(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
    headers: HeaderMap,
    bytes: Bytes,
) -> AppResult<Json<User>> {
    if bytes.is_empty() {
        return Err(AppError::bad_request("Avatar image body cannot be empty"));
    }
    if bytes.len() > 5 * 1024 * 1024 {
        return Err(AppError::bad_request(
            "Avatar image must be at most 5 MB",
        ));
    }

    let ext: String = if bytes.starts_with(&[0x89, b'P', b'N', b'G']) {
        "png".to_string()
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        "jpg".to_string()
    } else if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        "webp".to_string()
    } else if bytes.starts_with(b"GIF8") {
        "gif".to_string()
    } else {
        headers
            .get("x-file-name")
            .and_then(|v| v.to_str().ok())
            .and_then(|name| name.rsplit('.').next())
            .map(|e| e.to_ascii_lowercase())
            .filter(|e| matches!(e.as_str(), "png" | "jpg" | "jpeg" | "webp" | "gif"))
            .unwrap_or_else(|| "png".to_string())
    };

    let dir = avatars_dir();
    tokio::fs::create_dir_all(&dir)
        .await
        .map_err(|_| AppError::bad_request("Failed to prepare avatar storage directory"))?;

    let timestamp = chrono::Utc::now().timestamp_millis();
    let filename = format!("{}_{}.{}", user.id, timestamp, ext);
    let file_path = dir.join(&filename);

    tokio::fs::write(&file_path, &bytes)
        .await
        .map_err(|_| AppError::bad_request("Failed to save uploaded avatar"))?;

    let host = headers
        .get(header::HOST)
        .and_then(|h| h.to_str().ok())
        .filter(|h| !h.trim().is_empty())
        .unwrap_or("127.0.0.1:3000");
    let avatar_url = format!("http://{host}/uploads/avatars/{filename}");

    let updated = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (id, full_name, email, avatar_url)
        VALUES ($1, 'Supra user', $2, $3)
        ON CONFLICT (id) DO UPDATE
        SET avatar_url = EXCLUDED.avatar_url,
            email      = EXCLUDED.email
        RETURNING id, full_name, email, avatar_url, created_at
        "#,
    )
    .bind(user.id)
    .bind(user.email)
    .bind(avatar_url)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(updated))
}

pub async fn serve_avatar(Path(filename): Path<String>) -> Result<Response, AppError> {
    if filename.is_empty()
        || filename.contains("..")
        || filename.contains('/')
        || filename.contains('\\')
        || !filename
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.'))
    {
        return Err(AppError::NotFound);
    }

    let path = avatars_dir().join(&filename);
    let bytes = tokio::fs::read(&path)
        .await
        .map_err(|_| AppError::NotFound)?;

    let content_type = match filename.rsplit('.').next().map(|s| s.to_ascii_lowercase()) {
        Some(ref ext) if ext == "png" => "image/png",
        Some(ref ext) if ext == "jpg" || ext == "jpeg" => "image/jpeg",
        Some(ref ext) if ext == "webp" => "image/webp",
        Some(ref ext) if ext == "gif" => "image/gif",
        _ => "application/octet-stream",
    };

    Ok((
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, content_type),
            (header::CACHE_CONTROL, "public, max-age=86400"),
        ],
        bytes,
    )
        .into_response())
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

pub async fn delete_account(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
) -> AppResult<Json<serde_json::Value>> {
    let result = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(user.id)
        .execute(&state.pool)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }

    // Best-effort sync with Supabase Auth Admin API if SUPABASE_SERVICE_ROLE_KEY is configured.
    if let (Ok(supabase_url), Ok(service_role_key)) = (
        std::env::var("SUPABASE_URL"),
        std::env::var("SUPABASE_SERVICE_ROLE_KEY"),
    ) {
        let service_role_key = service_role_key.trim();
        if !service_role_key.is_empty() {
            let admin_url = format!(
                "{}/auth/v1/admin/users/{}",
                supabase_url.trim_end_matches('/'),
                user.id
            );
            if let Ok(client) = reqwest::Client::builder().build() {
                let _ = client
                    .delete(&admin_url)
                    .header("apikey", service_role_key)
                    .bearer_auth(service_role_key)
                    .send()
                    .await;
            }
        }
    }

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}
