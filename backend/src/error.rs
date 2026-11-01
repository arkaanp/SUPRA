use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;

#[derive(Debug)]
pub enum AppError {
    BadRequest(String),
    NotFound,
    Conflict,
    Internal(sqlx::Error),
}

impl AppError {
    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::BadRequest(message.into())
    }
}

impl From<sqlx::Error> for AppError {
    fn from(error: sqlx::Error) -> Self {
        match &error {
            sqlx::Error::RowNotFound => Self::NotFound,
            sqlx::Error::Database(db_error) => match db_error.code().as_deref() {
                Some("23505") => Self::Conflict, // unique constraint
                Some("23502" | "23503" | "23514" | "22001") => {
                    Self::bad_request("Request violates a database constraint")
                }
                _ => Self::Internal(error),
            },
            _ => Self::Internal(error),
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            Self::BadRequest(message) => (StatusCode::BAD_REQUEST, "invalid_request", message),
            Self::NotFound => (
                StatusCode::NOT_FOUND,
                "not_found",
                "Resource not found".into(),
            ),
            Self::Conflict => (
                StatusCode::CONFLICT,
                "conflict",
                "Resource already exists".into(),
            ),
            Self::Internal(error) => {
                tracing::error!(error = %error, "Database request failed");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "internal_error",
                    "Internal server error".into(),
                )
            }
        };
        (status, Json(json!({ "error": message, "code": code }))).into_response()
    }
}

pub type AppResult<T> = Result<T, AppError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn row_not_found_is_404() {
        let response = AppError::from(sqlx::Error::RowNotFound).into_response();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    #[test]
    fn internal_errors_do_not_expose_details() {
        let response = AppError::from(sqlx::Error::PoolClosed).into_response();
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    }
}
