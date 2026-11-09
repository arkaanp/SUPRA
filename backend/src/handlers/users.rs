use crate::auth::{AuthUser, require_self};
use crate::db::AppState;
use crate::error::{AppError, AppResult};
use crate::models::*;
use crate::validation::{ValidatedJson, ValidatedPath};
use axum::{
    Json,
    body::Bytes,
    extract::{Extension, Path, State},
    http::{StatusCode, header},
    response::{IntoResponse, Response},
};
use std::path::PathBuf;
use uuid::Uuid;

fn avatars_dir() -> PathBuf {
    std::env::var_os("AVATAR_STORAGE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("uploads/avatars"))
}

fn public_origin() -> AppResult<String> {
    let origin =
        std::env::var("PUBLIC_BASE_URL").unwrap_or_else(|_| "http://localhost:3000".into());
    let url = reqwest::Url::parse(&origin).map_err(|_| AppError::Unavailable)?;
    if !matches!(url.scheme(), "https" | "http")
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || url.path() != "/"
    {
        return Err(AppError::Unavailable);
    }
    Ok(origin.trim_end_matches('/').to_owned())
}

fn normalize_avatar(bytes: &[u8]) -> AppResult<Vec<u8>> {
    use std::io::Cursor;
    let mut reader = image::ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| AppError::bad_request("Invalid image"))?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(4096);
    limits.max_image_height = Some(4096);
    limits.max_alloc = Some(64 * 1024 * 1024);
    reader.limits(limits);
    let image = reader
        .decode()
        .map_err(|_| AppError::bad_request("Invalid or oversized avatar image"))?;
    let mut output = Cursor::new(Vec::new());
    image
        .thumbnail(512, 512)
        .write_to(&mut output, image::ImageFormat::Png)
        .map_err(|_| AppError::bad_request("Could not normalize image"))?;
    Ok(output.into_inner())
}

async fn remove_owned_avatar(url: Option<&str>, origin: &str, user: Uuid) {
    if let Some(name) = url.and_then(|s| s.strip_prefix(&format!("{origin}/uploads/avatars/"))) {
        if name.starts_with(&format!("{user}_"))
            && !name.contains('/')
            && !name.contains('\\')
            && !name.contains("..")
        {
            let _ = tokio::fs::remove_file(avatars_dir().join(name)).await;
        }
    }
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
    bytes: Bytes,
) -> AppResult<Json<User>> {
    if bytes.is_empty() {
        return Err(AppError::bad_request("Avatar image body cannot be empty"));
    }
    if bytes.len() > 5 * 1024 * 1024 {
        return Err(AppError::bad_request("Avatar image must be at most 5 MB"));
    }

    let origin = public_origin()?;
    let bytes = tokio::task::spawn_blocking(move || normalize_avatar(&bytes))
        .await
        .map_err(|_| AppError::Unavailable)??;
    let mut tx = state.pool.begin().await?;
    // Serialize replacement for an existing profile, including concurrent uploads.
    let previous: Option<String> =
        sqlx::query_scalar("SELECT avatar_url FROM users WHERE id = $1 FOR UPDATE")
            .bind(user.id)
            .fetch_one(&mut *tx)
            .await?;

    let dir = avatars_dir();
    tokio::fs::create_dir_all(&dir)
        .await
        .map_err(|_| AppError::bad_request("Failed to prepare avatar storage directory"))?;

    let filename = format!("{}_{}.png", user.id, Uuid::new_v4());
    let file_path = dir.join(&filename);

    tokio::fs::write(&file_path, &bytes)
        .await
        .map_err(|_| AppError::bad_request("Failed to save uploaded avatar"))?;

    let avatar_url = format!("{origin}/uploads/avatars/{filename}");

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
    .fetch_one(&mut *tx)
    .await;
    let updated = match updated {
        Ok(updated) => updated,
        Err(error) => {
            let _ = tokio::fs::remove_file(&file_path).await;
            return Err(error.into());
        }
    };
    tx.commit().await?;
    remove_owned_avatar(previous.as_deref(), &origin, user.id).await;

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
            (header::X_CONTENT_TYPE_OPTIONS, "nosniff"),
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
    let previous: Option<Option<String>> =
        sqlx::query_scalar("DELETE FROM users WHERE id = $1 RETURNING avatar_url")
            .bind(user.id)
            .fetch_optional(&state.pool)
            .await?;
    if previous.is_none() {
        return Err(AppError::NotFound);
    }
    if let Ok(origin) = public_origin() {
        remove_owned_avatar(previous.flatten().as_deref(), &origin, user.id).await;
    }

    Ok(Json(serde_json::json!({ "status": "deleted" })))
}

pub async fn delete_account(
    State(state): State<AppState>,
    Extension(user): Extension<AuthUser>,
) -> AppResult<Json<serde_json::Value>> {
    let previous: Option<Option<String>> =
        sqlx::query_scalar("DELETE FROM users WHERE id = $1 RETURNING avatar_url")
            .bind(user.id)
            .fetch_optional(&state.pool)
            .await?;
    if previous.is_none() {
        return Err(AppError::NotFound);
    }
    if let Ok(origin) = public_origin() {
        remove_owned_avatar(previous.flatten().as_deref(), &origin, user.id).await;
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

#[cfg(test)]
mod avatar_tests {
    use super::*;
    #[test]
    fn rejects_filename_only_signature_only_and_non_image_uploads() {
        for bytes in [
            b"not an image".as_slice(),
            b"\x89PNG\r\n\x1a\n",
            b"GIF89a",
            b"\xff\xd8\xff",
        ] {
            assert!(normalize_avatar(bytes).is_err());
        }
    }
    #[test]
    fn decodes_resizes_and_reencodes_avatar_as_png() {
        let image = image::DynamicImage::new_rgb8(1024, 768);
        let mut input = std::io::Cursor::new(Vec::new());
        image.write_to(&mut input, image::ImageFormat::Png).unwrap();
        let bytes = normalize_avatar(input.get_ref()).unwrap();
        let output = image::load_from_memory(&bytes).unwrap();
        assert_eq!((output.width(), output.height()), (512, 384));
        assert_eq!(
            image::guess_format(&bytes).unwrap(),
            image::ImageFormat::Png
        );
    }
}
