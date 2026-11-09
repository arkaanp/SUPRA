mod alerts;
mod auth;
mod commutes;
mod conditions;
mod db;
#[cfg(test)]
mod db_tests;
mod error;
mod handlers;
mod mobility;
mod models;
mod routes;
mod validation;

use axum::Router;
use db::AppState;
use routes::create_router;
use std::net::SocketAddr;
use tower_http::cors::CorsLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() {
    let command = std::env::args().nth(1);
    if !matches!(command.as_deref(), None | Some("migrate")) {
        eprintln!("Usage: supra_backend [migrate]");
        std::process::exit(2);
    }

    // Load the backend's local .env regardless of the working directory.
    // dotenvy leaves variables already supplied by the environment unchanged.
    let env_path = concat!(env!("CARGO_MANIFEST_DIR"), "/.env");
    if let Err(error) = dotenvy::from_path(env_path) {
        match &error {
            dotenvy::Error::Io(io_error) if io_error.kind() == std::io::ErrorKind::NotFound => {}
            _ => panic!("Failed to load backend/.env: {error}"),
        }
    }

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG")
                .unwrap_or_else(|_| "supra_backend=info,tower_http=debug".into()),
        ))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let database_url = std::env::var("DATABASE_URL").expect(
        "DATABASE_URL environment variable must be set (e.g. postgres://user:pass@host:5432/db)",
    );

    let state = match AppState::new(&database_url).await {
        Ok(state) => {
            tracing::info!("Database connection pool established");
            state
        }
        Err(primary_err) => {
            tracing::warn!(
                error = %primary_err,
                "Immediate DB connection unavailable (e.g. IPv6 DNS unreachable); using lazy pool for Supabase DATABASE_URL so server starts immediately"
            );
            AppState::new_lazy(&database_url).expect("Invalid DATABASE_URL format")
        }
    };

    if command.as_deref() == Some("migrate") {
        if let Err(sqlx::migrate::MigrateError::VersionMismatch(version)) =
            db::MIGRATOR.run(&state.pool).await
        {
            tracing::warn!(
                version,
                "Detected migration checksum mismatch (e.g. CRLF vs LF line endings); syncing _sqlx_migrations checksums"
            );
            for migration in db::MIGRATOR.iter() {
                let _ = sqlx::query(
                    "UPDATE _sqlx_migrations SET checksum = $1 WHERE version = $2",
                )
                .bind(migration.checksum.as_ref())
                .bind(migration.version)
                .execute(&state.pool)
                .await;
            }
        }
        db::MIGRATOR
            .run(&state.pool)
            .await
            .expect("Failed to apply migrations");
        tracing::info!("Database migrations applied");
        return;
    }

    let supabase_url = std::env::var("SUPABASE_URL").expect("SUPABASE_URL must be set");
    let audience =
        std::env::var("SUPABASE_JWT_AUDIENCE").unwrap_or_else(|_| "authenticated".into());
    let verifier =
        auth::AuthVerifier::new(&supabase_url, &audience).expect("Invalid Supabase configuration");
    let conditions = std::sync::Arc::new(conditions::ConditionsService::from_env());
    alerts::start(state.clone(), conditions);
    let app: Router = create_router(state, verifier).layer(CorsLayer::permissive());

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    tracing::info!("Supra backend listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("Failed to bind address");
    axum::serve(listener, app).await.expect("Server failed");
}
