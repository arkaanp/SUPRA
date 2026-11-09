use crate::{
    auth::AuthUser,
    db::AppState,
    error::{AppError, AppResult},
    validation::{Validate, ValidatedJson, ValidatedPath},
};
use axum::{
    Json,
    extract::{Extension, State},
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

pub fn valid_mode(mode: &str) -> bool {
    matches!(mode, "car" | "motorcycle" | "walk" | "public_transit")
}
pub fn coordinate(lat: f64, lon: f64) -> bool {
    lat.is_finite()
        && lon.is_finite()
        && (-6.9..=-5.8).contains(&lat)
        && (106.3..=107.3).contains(&lon)
}
fn label(value: &str) -> bool {
    !value.trim().is_empty() && value.len() <= 120 && !value.chars().any(char::is_control)
}

#[derive(Serialize, FromRow)]
pub struct Place {
    pub id: Uuid,
    pub user_id: Uuid,
    pub label: String,
    pub kind: String,
    pub latitude: f64,
    pub longitude: f64,
    pub created_at: DateTime<Utc>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PlaceInput {
    pub label: String,
    pub kind: String,
    pub latitude: f64,
    pub longitude: f64,
}
impl Validate for PlaceInput {
    fn validate(&self) -> AppResult<()> {
        if !label(&self.label)
            || !matches!(self.kind.as_str(), "home" | "work" | "school" | "custom")
            || !coordinate(self.latitude, self.longitude)
        {
            return Err(AppError::bad_request(
                "Provide a label, place kind and coordinates in Greater Jakarta",
            ));
        }
        Ok(())
    }
}
pub async fn list_places(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
) -> AppResult<Json<Vec<Place>>> {
    Ok(Json(
        sqlx::query_as("SELECT * FROM saved_places WHERE user_id=$1 ORDER BY created_at")
            .bind(u.id)
            .fetch_all(&s.pool)
            .await?,
    ))
}
pub async fn create_place(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
    ValidatedJson(p): ValidatedJson<PlaceInput>,
) -> AppResult<Json<Place>> {
    Ok(Json(sqlx::query_as("INSERT INTO saved_places(user_id,label,kind,latitude,longitude) VALUES($1,$2,$3,$4,$5) RETURNING *")
        .bind(u.id).bind(p.label.trim()).bind(p.kind).bind(p.latitude).bind(p.longitude).fetch_one(&s.pool).await?))
}
pub async fn update_place(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
    ValidatedJson(p): ValidatedJson<PlaceInput>,
) -> AppResult<Json<Place>> {
    Ok(Json(sqlx::query_as("UPDATE saved_places SET label=$1,kind=$2,latitude=$3,longitude=$4 WHERE id=$5 AND user_id=$6 RETURNING *")
        .bind(p.label.trim()).bind(p.kind).bind(p.latitude).bind(p.longitude).bind(id).bind(u.id).fetch_one(&s.pool).await?))
}
pub async fn delete_place(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    let r = sqlx::query("DELETE FROM saved_places WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(u.id)
        .execute(&s.pool)
        .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    Ok(Json(serde_json::json!({"status":"deleted"})))
}

#[derive(Serialize, FromRow)]
pub struct Routine {
    pub id: Uuid,
    pub user_id: Uuid,
    pub label: String,
    pub origin_id: Uuid,
    pub destination_id: Uuid,
    pub mode: String,
    pub weekdays: Vec<i16>,
    pub departure_minute: i32,
    pub timezone: String,
    pub lead_minutes: i32,
    pub enabled: bool,
    pub alerts_enabled: bool,
    pub news_enabled: bool,
    pub last_checked_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RoutineInput {
    pub label: String,
    pub origin_id: Uuid,
    pub destination_id: Uuid,
    pub mode: String,
    pub weekdays: Vec<i16>,
    pub departure_minute: i32,
    pub timezone: String,
    pub lead_minutes: i32,
    pub enabled: bool,
    pub alerts_enabled: bool,
    pub news_enabled: bool,
}
impl Validate for RoutineInput {
    fn validate(&self) -> AppResult<()> {
        if !label(&self.label)
            || self.origin_id == self.destination_id
            || !valid_mode(&self.mode)
            || self.weekdays.is_empty()
            || self.weekdays.len() > 7
            || self.weekdays.iter().any(|d| !(0..=6).contains(d))
            || self
                .weekdays
                .iter()
                .collect::<std::collections::HashSet<_>>()
                .len()
                != self.weekdays.len()
            || !(0..1440).contains(&self.departure_minute)
            || !(5..=180).contains(&self.lead_minutes)
            || self.timezone != "Asia/Jakarta"
        {
            return Err(AppError::bad_request(
                "Invalid routine: use owned distinct places, valid mode, weekdays, time and Asia/Jakarta timezone",
            ));
        }
        Ok(())
    }
}
pub async fn list_routines(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
) -> AppResult<Json<Vec<Routine>>> {
    Ok(Json(
        sqlx::query_as("SELECT * FROM routine_trips WHERE user_id=$1 ORDER BY created_at")
            .bind(u.id)
            .fetch_all(&s.pool)
            .await?,
    ))
}
async fn own_places(s: &AppState, user: Uuid, p: &RoutineInput) -> AppResult<()> {
    let n: i64 =
        sqlx::query_scalar("SELECT count(*) FROM saved_places WHERE user_id=$1 AND id IN ($2,$3)")
            .bind(user)
            .bind(p.origin_id)
            .bind(p.destination_id)
            .fetch_one(&s.pool)
            .await?;
    if n != 2 {
        return Err(AppError::NotFound);
    }
    Ok(())
}
pub async fn create_routine(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
    ValidatedJson(p): ValidatedJson<RoutineInput>,
) -> AppResult<Json<Routine>> {
    own_places(&s, u.id, &p).await?;
    Ok(Json(sqlx::query_as("INSERT INTO routine_trips(user_id,label,origin_id,destination_id,mode,weekdays,departure_minute,timezone,lead_minutes,enabled,alerts_enabled,news_enabled) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *")
        .bind(u.id).bind(p.label.trim()).bind(p.origin_id).bind(p.destination_id).bind(p.mode).bind(p.weekdays)
        .bind(p.departure_minute).bind(p.timezone).bind(p.lead_minutes).bind(p.enabled).bind(p.alerts_enabled).bind(p.news_enabled).fetch_one(&s.pool).await?))
}
pub async fn update_routine(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
    ValidatedJson(p): ValidatedJson<RoutineInput>,
) -> AppResult<Json<Routine>> {
    own_places(&s, u.id, &p).await?;
    Ok(Json(sqlx::query_as("UPDATE routine_trips SET label=$1,origin_id=$2,destination_id=$3,mode=$4,weekdays=$5,departure_minute=$6,timezone=$7,lead_minutes=$8,enabled=$9,alerts_enabled=$10,news_enabled=$11,last_checked_at=NULL WHERE id=$12 AND user_id=$13 RETURNING *")
        .bind(p.label.trim()).bind(p.origin_id).bind(p.destination_id).bind(p.mode).bind(p.weekdays).bind(p.departure_minute)
        .bind(p.timezone).bind(p.lead_minutes).bind(p.enabled).bind(p.alerts_enabled).bind(p.news_enabled).bind(id).bind(u.id).fetch_one(&s.pool).await?))
}
pub async fn delete_routine(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    let r = sqlx::query("DELETE FROM routine_trips WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(u.id)
        .execute(&s.pool)
        .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    Ok(Json(serde_json::json!({"status":"deleted"})))
}
pub async fn finish_trip(
    State(s): State<AppState>,
    Extension(u): Extension<AuthUser>,
    ValidatedPath(id): ValidatedPath<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    let r = sqlx::query("UPDATE trips SET active_until=now() WHERE id=$1 AND user_id=$2")
        .bind(id)
        .bind(u.id)
        .execute(&s.pool)
        .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    Ok(Json(serde_json::json!({"status":"finished"})))
}
