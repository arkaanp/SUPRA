use sqlx::postgres::{PgPool, PgPoolOptions};
use std::time::Duration;

/// Versioned schema, applied explicitly via `cargo run -- migrate` or by tests.
pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
}

impl AppState {
    pub async fn new(database_url: &str) -> Result<Self, sqlx::Error> {
        let pool = PgPoolOptions::new()
            .max_connections(10)
            .acquire_timeout(Duration::from_secs(30))
            .connect(database_url)
            .await?;
        Ok(Self { pool })
    }
}
