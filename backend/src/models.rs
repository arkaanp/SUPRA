use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde_json::Value;

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub full_name: String,
    pub email: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateUser {
    pub full_name: String,
    pub email: String,
    pub password_hash: String,
}

#[derive(Debug, Deserialize)]
pub struct UpdateUser {
    pub full_name: Option<String>,
    pub email: Option<String>,
}

// ---------------------------------------------------------------------------
// Trips
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Trip {
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub start_location: String,
    pub destination: String,
    pub planned_departure: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateTrip {
    pub user_id: Uuid,
    pub name: String,
    pub start_location: String,
    pub destination: String,
    pub planned_departure: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateTrip {
    pub name: Option<String>,
    pub start_location: Option<String>,
    pub destination: Option<String>,
    pub planned_departure: Option<DateTime<Utc>>,
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Route {
    pub id: Uuid,
    pub trip_id: Uuid,
    pub waypoints: Value,
    pub total_distance: f64,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateRoute {
    pub trip_id: Uuid,
    pub waypoints: Value,
    pub total_distance: f64,
}

#[derive(Debug, Deserialize)]
pub struct UpdateRoute {
    pub waypoints: Option<Value>,
    pub total_distance: Option<f64>,
}

// ---------------------------------------------------------------------------
// Predictions
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Prediction {
    pub id: Uuid,
    pub route_id: Uuid,
    pub target_time: DateTime<Utc>,
    pub predicted_aqi: f64,
    pub predicted_rainfall_prob: f64,
    pub predicted_traffic_density: f64,
    pub generated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreatePrediction {
    pub route_id: Uuid,
    pub target_time: DateTime<Utc>,
    pub predicted_aqi: f64,
    pub predicted_rainfall_prob: f64,
    pub predicted_traffic_density: f64,
}

// ---------------------------------------------------------------------------
// Notification Preferences
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct NotificationPreference {
    pub id: Uuid,
    pub user_id: Uuid,
    pub alert_unhealthy_aqi: bool,
    pub alert_heavy_rain: bool,
    pub alert_severe_traffic: bool,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateNotificationPreference {
    pub alert_unhealthy_aqi: Option<bool>,
    pub alert_heavy_rain: Option<bool>,
    pub alert_severe_traffic: Option<bool>,
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Notification {
    pub id: Uuid,
    pub user_id: Uuid,
    pub title: String,
    pub message_body: String,
    pub severity: String,
    pub sent_at: DateTime<Utc>,
    pub is_read: bool,
}

#[derive(Debug, Deserialize)]
pub struct CreateNotification {
    pub user_id: Uuid,
    pub title: String,
    pub message_body: String,
    pub severity: String,
}
