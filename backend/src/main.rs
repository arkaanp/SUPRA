mod db;
mod error;
mod models;
mod routes;
mod handlers;
#[cfg(test)]
mod db_tests;

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

    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "supra_backend=info,tower_http=debug".into()),
        ))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL environment variable must be set (e.g. postgres://user:pass@host:5432/db)");

    let state = AppState::new(&database_url).await.expect("Failed to connect to database");
    tracing::info!("Database connection pool established");

    if command.as_deref() == Some("migrate") {
        db::MIGRATOR.run(&state.pool).await.expect("Failed to apply migrations");
        tracing::info!("Database migrations applied");
        return;
    }

    let app: Router = create_router(state).layer(CorsLayer::permissive());

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    tracing::info!("Supra backend listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.expect("Failed to bind address");
    axum::serve(listener, app).await.expect("Server failed");
}
