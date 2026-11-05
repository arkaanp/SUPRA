use std::time::Duration;

use axum::{Json, extract::State};
use serde_json::{Value, json};

use crate::{
    db::AppState,
    error::{AppError, AppResult},
};

const READINESS_TIMEOUT: Duration = Duration::from_secs(2);

/// Process liveness only; no database or external authentication calls.
pub async fn live() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

/// Includes pool acquisition and the query in one bounded readiness check.
/// This checks connectivity, not schema compatibility or upstream providers.
pub async fn ready(State(state): State<AppState>) -> AppResult<Json<Value>> {
    readiness_result(sqlx::query_scalar::<_, i32>("SELECT 1").fetch_one(&state.pool)).await
}

async fn readiness_result(
    check: impl std::future::Future<Output = Result<i32, sqlx::Error>>,
) -> AppResult<Json<Value>> {
    match tokio::time::timeout(READINESS_TIMEOUT, check).await {
        Ok(Ok(1)) => Ok(Json(json!({ "status": "ready" }))),
        _ => Err(AppError::Unavailable),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test(start_paused = true)]
    async fn readiness_bounds_pool_acquisition() {
        // Simulate a query/pool acquisition that never completes, without
        // depending on a running database or nondeterministic network failure.
        let started = tokio::time::Instant::now();
        let result = readiness_result(std::future::pending()).await;
        assert!(matches!(result, Err(AppError::Unavailable)));
        assert_eq!(started.elapsed(), READINESS_TIMEOUT);
    }

    #[tokio::test]
    async fn readiness_success_and_failure() {
        let ready = readiness_result(async { Ok(1) }).await.unwrap();
        assert_eq!(ready.0, json!({"status": "ready"}));
        let failed = readiness_result(async { Err(sqlx::Error::PoolClosed) }).await;
        assert!(matches!(failed, Err(AppError::Unavailable)));
    }
}
