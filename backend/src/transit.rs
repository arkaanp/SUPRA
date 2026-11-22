//! Jakarta transit: local Transjakarta GTFS plus the public Commute Data API.
mod gtfs;
use crate::error::{AppError, AppResult};
use chrono::{DateTime, Datelike, Duration, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::HashMap, path::PathBuf, sync::Arc, time::Instant};
use tokio::sync::Mutex;
pub type Coord = [f64; 2];
pub fn distance(a: Coord, b: Coord) -> f64 {
    crate::alerts::distance_km(a, b)
}
pub fn walk_seconds(km: f64) -> i64 {
    (km / 4.5 * 3600.0).ceil() as i64
}
pub fn clock(s: &str) -> Option<i64> {
    let v = s
        .split(':')
        .map(str::parse::<i64>)
        .collect::<Result<Vec<_>, _>>()
        .ok()?;
    (v.len() == 3 && (0..=71).contains(&v[0]) && (0..60).contains(&v[1]) && (0..60).contains(&v[2]))
        .then(|| v[0] * 3600 + v[1] * 60 + v[2])
}
pub fn midnight(date: NaiveDate) -> DateTime<Utc> {
    date.and_hms_opt(0, 0, 0).unwrap().and_utc() - Duration::hours(7)
}
pub fn wib(at: DateTime<Utc>) -> String {
    (at + Duration::hours(7)).format("%H:%M WIB").to_string()
}
#[derive(Clone, Debug, Serialize)]
pub struct Leg {
    pub mode: String,
    pub line: String,
    pub from: String,
    pub to: String,
    pub departure_at: DateTime<Utc>,
    pub arrival_at: DateTime<Utc>,
    pub distance_km: f64,
    pub geometry_kind: String,
    pub estimated: bool,
    pub waypoints: Vec<Coord>,
}
impl Leg {
    pub fn walk(from: &str, to: &str, a: Coord, b: Coord, at: DateTime<Utc>, minimum: i64) -> Self {
        let km = distance(a, b);
        Self {
            mode: "WALK".into(),
            line: String::new(),
            from: from.into(),
            to: to.into(),
            departure_at: at,
            arrival_at: at + Duration::seconds(walk_seconds(km).max(minimum)),
            distance_km: km,
            geometry_kind: "schematic_walk_link".into(),
            estimated: true,
            waypoints: vec![a, b],
        }
    }
}
#[derive(Clone, Debug, Serialize)]
pub struct Itinerary {
    pub source: String,
    pub departure_at: DateTime<Utc>,
    pub arrival_at: DateTime<Utc>,
    pub fare_idr: Option<f64>,
    pub legs: Vec<Leg>,
    pub attribution: String,
}
impl Itinerary {
    pub fn duration(&self) -> f64 {
        (self.arrival_at - self.departure_at).num_seconds() as f64
    }
    pub fn points(&self) -> Vec<Coord> {
        let all = self
            .legs
            .iter()
            .flat_map(|l| l.waypoints.clone())
            .collect::<Vec<_>>();
        let stride = all.len().div_ceil(9000).max(1);
        all.iter()
            .enumerate()
            .filter(|(i, _)| i % stride == 0 || *i == all.len() - 1)
            .map(|(_, p)| *p)
            .collect()
    }
    pub fn steps(&self) -> Vec<String> {
        self.legs
            .iter()
            .map(|l| {
                if l.mode == "WALK" {
                    format!(
                        "Walk approximately {:.0} m: {} → {} (walking link, not street navigation)",
                        l.distance_km * 1000.,
                        l.from,
                        l.to
                    )
                } else {
                    format!(
                        "{} {}: board {} at {}; alight {} at {}{}",
                        l.mode,
                        l.line,
                        l.from,
                        wib(l.departure_at),
                        l.to,
                        wib(l.arrival_at),
                        if l.estimated {
                            " (frequency estimate)"
                        } else {
                            " (timetable)"
                        }
                    )
                }
            })
            .collect()
    }
}
#[derive(Clone, Deserialize)]
struct Station {
    id: String,
    name: String,
    latitude: Option<f64>,
    longitude: Option<f64>,
}
impl Station {
    fn coord(&self) -> Option<Coord> {
        if self.id.is_empty()
            || self.id.len() > 100
            || !self
                .id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.'))
        {
            return None;
        }
        let p = [self.latitude?, self.longitude?];
        (p[0].is_finite() && p[1].is_finite() && p[0].abs() <= 90. && p[1].abs() <= 180.)
            .then_some(p)
    }
}
pub struct TransitService {
    client: reqwest::Client,
    base: String,
    feed: Option<Arc<gtfs::Feed>>,
    cache: Mutex<HashMap<String, (Instant, Value)>>,
}
impl TransitService {
    pub fn from_env() -> Self {
        let path = std::env::var_os("TRANSJAKARTA_GTFS_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../file_gtfs"));
        let feed = if cfg!(test) {
            None
        } else {
            match gtfs::Feed::load(&path) {
                Ok(f) => {
                    tracing::info!(trips = f.trip_count(), "Transjakarta GTFS loaded");
                    Some(Arc::new(f))
                }
                Err(e) => {
                    tracing::warn!(error=%e,"Local GTFS unavailable; Commute API remains enabled");
                    None
                }
            }
        };
        Self {
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(3))
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .unwrap(),
            base: std::env::var("COMMUTE_API_URL")
                .unwrap_or_else(|_| "https://api.commute.shiorilabs.id".into())
                .trim_end_matches('/')
                .to_string(),
            feed,
            cache: Mutex::new(HashMap::new()),
        }
    }
    async fn get(&self, path: &str, ttl: u64) -> AppResult<Value> {
        let cache_key = if path.contains("/timetable") {
            format!("{path}|{}", (Utc::now() + Duration::hours(7)).date_naive())
        } else {
            path.into()
        };
        if ttl > 0 {
            if let Some((at, v)) = self.cache.lock().await.get(&cache_key) {
                if at.elapsed().as_secs() < ttl {
                    return Ok(v.clone());
                }
            }
        }
        let mut r = self
            .client
            .get(format!("{}{}", self.base, path))
            .send()
            .await
            .map_err(|_| AppError::Unavailable)?;
        if !r.status().is_success() {
            return Err(AppError::Unavailable);
        }
        let mut bytes = Vec::new();
        while let Some(chunk) = r.chunk().await.map_err(|_| AppError::Unavailable)? {
            if bytes.len() + chunk.len() > 4_000_000 {
                return Err(AppError::Unavailable);
            }
            bytes.extend_from_slice(&chunk);
        }
        let v: Value = serde_json::from_slice(&bytes).map_err(|_| AppError::Unavailable)?;
        if v["status"] != 200 {
            return Err(AppError::Unavailable);
        }
        let data = v.get("data").ok_or(AppError::Unavailable)?.clone();
        if ttl > 0 {
            let mut cache = self.cache.lock().await;
            if cache.len() >= 128 {
                cache.clear();
            }
            cache.insert(cache_key, (Instant::now(), data.clone()));
        }
        Ok(data)
    }
    #[cfg(test)]
    pub async fn plan(&self, a: Coord, b: Coord, at: DateTime<Utc>) -> AppResult<Itinerary> {
        Ok(self.plan_options(a, b, at).await?.remove(0))
    }

    pub async fn plan_options(
        &self,
        a: Coord,
        b: Coord,
        at: DateTime<Utc>,
    ) -> AppResult<Vec<Itinerary>> {
        let feed = self.feed.clone();
        let local = async move {
            if let Some(f) = feed {
                tokio::task::spawn_blocking(move || f.plan(a, b, at))
                    .await
                    .ok()
                    .flatten()
            } else {
                None
            }
        };
        let (local, remote) = tokio::join!(local, self.remote_options(a, b, at));
        let remote_unavailable = remote.is_err();
        let mut options = remote.unwrap_or_default();
        options.extend(local);
        options.sort_by_key(|p| p.arrival_at);
        let mut seen = std::collections::HashSet::new();
        options.retain(|p| {
            seen.insert(
                p.legs
                    .iter()
                    .filter(|l| l.mode != "WALK")
                    .map(|l| (l.mode.clone(), l.line.clone(), l.from.clone(), l.to.clone()))
                    .collect::<Vec<_>>(),
            )
        });
        if options.is_empty() && remote_unavailable {
            Err(AppError::Unavailable)
        } else if options.is_empty() {
            Err(AppError::NotFound)
        } else {
            Ok(options)
        }
    }

    async fn remote_options(
        &self,
        a: Coord,
        b: Coord,
        at: DateTime<Utc>,
    ) -> AppResult<Vec<Itinerary>> {
        let stations: Vec<Station> = serde_json::from_value(self.get("/stations", 21600).await?)
            .map_err(|_| AppError::Unavailable)?;
        let by_id: HashMap<_, _> = stations.iter().map(|s| (s.id.as_str(), s)).collect();
        let pairs = candidate_pairs(&stations, a, b);
        let mut tasks = pairs.into_iter().map(|(sa, sb)| {
            let by_id = &by_id;
            async move {
                tokio::time::timeout(
                    std::time::Duration::from_secs(6),
                    self.remote_pair(a, b, at, sa, sb, by_id),
                )
                .await
                .ok()
                .and_then(Result::ok)
            }
        });
        // Bounded concurrent candidates. A slow/unsupported pair cannot discard
        // a completed rail option or the independent native GTFS result.
        async fn run<F: std::future::Future<Output = Option<Itinerary>>>(
            f: Option<F>,
        ) -> Option<Itinerary> {
            match f {
                Some(f) => f.await,
                None => None,
            }
        }
        let (a, b, c, d) = tokio::join!(
            run(tasks.next()),
            run(tasks.next()),
            run(tasks.next()),
            run(tasks.next())
        );
        Ok([a, b, c, d].into_iter().flatten().collect())
    }
    async fn remote_pair(
        &self,
        a: Coord,
        b: Coord,
        at: DateTime<Utc>,
        sa: &Station,
        sb: &Station,
        stations: &HashMap<&str, &Station>,
    ) -> AppResult<Itinerary> {
        let first = Leg::walk(
            "Start",
            &sa.name,
            a,
            sa.coord().ok_or(AppError::Unavailable)?,
            at,
            0,
        );
        let value = self
            .get(
                &format!(
                    "/fares/{}/{}?at={}",
                    sa.id,
                    sb.id,
                    first
                        .arrival_at
                        .to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
                ),
                0,
            )
            .await?;
        let mut legs = vec![first];
        let mut rides = 0;
        let get_coord = |v: &Value| -> Option<Coord> {
            let id = v["id"].as_str()?;
            stations.get(id)?.coord()
        };
        for l in value["legs"].as_array().ok_or(AppError::Unavailable)? {
            let from = &l["from"];
            let to = &l["to"];
            let start = get_coord(from).ok_or(AppError::Unavailable)?;
            let end = get_coord(to).ok_or(AppError::Unavailable)?;
            let prev = legs.last().unwrap();
            if distance(*prev.waypoints.last().unwrap(), start) > 0.05 {
                return Err(AppError::Unavailable);
            }
            let ready = prev.arrival_at;
            let name = |v: &Value| v["name"].as_str().unwrap_or("Station").to_string();
            if l["type"] == "TRANSFER" {
                legs.push(Leg::walk(&name(from), &name(to), start, end, ready, 0));
                if let Some(meters) = l["distanceM"]
                    .as_f64()
                    .filter(|v| v.is_finite() && *v >= 0.)
                {
                    let leg = legs.last_mut().unwrap();
                    leg.distance_km = meters / 1000.;
                    leg.arrival_at = ready + Duration::seconds(walk_seconds(leg.distance_km));
                }
                continue;
            }
            if l["type"] != "RIDE" {
                return Err(AppError::Unavailable);
            }
            let ready = ready + Duration::seconds(if rides > 0 { 120 } else { 0 });
            let (dep, arr) = match (l["departureAt"].as_str(), l["arrivalAt"].as_str()) {
                (Some(d), Some(t)) => (
                    DateTime::parse_from_rfc3339(d)
                        .map_err(|_| AppError::Unavailable)?
                        .with_timezone(&Utc),
                    DateTime::parse_from_rfc3339(t)
                        .map_err(|_| AppError::Unavailable)?
                        .with_timezone(&Utc),
                ),
                _ => {
                    self.timetable_pair(
                        from,
                        to,
                        l["line"].as_str().ok_or(AppError::Unavailable)?,
                        ready,
                    )
                    .await?
                }
            };
            if dep < ready || arr <= dep || arr > at + Duration::hours(6) {
                return Err(AppError::NotFound);
            }
            let pts = l["stops"]
                .as_array()
                .ok_or(AppError::Unavailable)?
                .iter()
                .map(get_coord)
                .collect::<Option<Vec<_>>>()
                .ok_or(AppError::Unavailable)?;
            if pts.len() < 2 {
                return Err(AppError::Unavailable);
            }
            let km = l["distanceM"]
                .as_f64()
                .filter(|n| n.is_finite() && *n > 0.)
                .ok_or(AppError::Unavailable)?
                / 1000.;
            legs.push(Leg {
                mode: l["operator"].as_str().unwrap_or("TRANSIT").into(),
                line: l["line"].as_str().unwrap_or("").into(),
                from: name(from),
                to: name(to),
                departure_at: dep,
                arrival_at: arr,
                distance_km: km,
                geometry_kind: "schematic_station_sequence".into(),
                estimated: false,
                waypoints: pts,
            });
            rides += 1;
        }
        if rides == 0 {
            return Err(AppError::NotFound);
        }
        let last = legs.last().unwrap();
        if distance(*last.waypoints.last().unwrap(), sb.coord().unwrap()) > 0.05 {
            return Err(AppError::Unavailable);
        }
        legs.push(Leg::walk(
            &sb.name,
            "Destination",
            sb.coord().unwrap(),
            b,
            last.arrival_at,
            0,
        ));
        Ok(Itinerary{source:"commute_shiorilabs".into(),departure_at:at,arrival_at:legs.last().unwrap().arrival_at,
            fare_idr:value["totalFare"].as_f64().filter(|v|v.is_finite()&&*v>=0.),legs,
            attribution:"Commute Data / Shiori Labs — https://data.commute.shiorilabs.id — ODbL-1.0. Station connections and walking links are schematic; schedules are not live arrivals.".into()})
    }
    async fn timetable_pair(
        &self,
        from: &Value,
        to: &Value,
        line: &str,
        ready: DateTime<Utc>,
    ) -> AppResult<(DateTime<Utc>, DateTime<Utc>)> {
        let id = |v: &Value| {
            v["id"]
                .as_str()
                .and_then(|s| s.split_once('-'))
                .map(|(a, b)| format!("{a}/{b}"))
        };
        let date = (ready + Duration::hours(7)).date_naive();
        let day = match date.weekday().number_from_monday() {
            6 => "SAT",
            7 => "SUN",
            _ => "WD",
        };
        let query = if date == (Utc::now() + Duration::hours(7)).date_naive() {
            String::new()
        } else {
            format!("?day={day}")
        };
        let from_path = format!(
            "/stations/{}/timetable{query}",
            id(from).ok_or(AppError::Unavailable)?
        );
        let to_path = format!(
            "/stations/{}/timetable{query}",
            id(to).ok_or(AppError::Unavailable)?
        );
        let (f, t) = tokio::join!(self.get(&from_path, 300), self.get(&to_path, 300));
        let f = f?;
        let t = t?;
        let line = line.split(':').next_back().unwrap_or(line);
        f.as_array()
            .ok_or(AppError::Unavailable)?
            .iter()
            .filter(|r| r["lineCode"] == line)
            .filter_map(|r| {
                let trip = r["tripNumber"].as_str()?;
                if trip.is_empty() {
                    return None;
                }
                let dep =
                    midnight(date) + Duration::seconds(clock(r["estimatedDeparture"].as_str()?)?);
                if dep < ready {
                    return None;
                }
                let dest = t
                    .as_array()?
                    .iter()
                    .find(|v| v["tripNumber"] == trip && v["lineCode"] == line)?;
                // At the destination station use that station's own time, never the
                // origin row's estimatedArrival (which may refer to the terminus).
                let arr = midnight(date)
                    + Duration::seconds(clock(dest["estimatedDeparture"].as_str()?)?);
                (arr > dep && arr - dep < Duration::hours(4)).then_some((dep, arr))
            })
            .min_by_key(|(_, arrival)| *arrival)
            .ok_or(AppError::NotFound)
    }
}

// Preserve operator diversity: many nearby bus stops must not hide a KRL station.
fn candidate_pairs(stations: &[Station], a: Coord, b: Coord) -> Vec<(&Station, &Station)> {
    let nearest = |p| {
        stations
            .iter()
            .filter_map(|s| Some((distance(p, s.coord()?), s)))
            .filter(|(d, _)| *d <= 1.5)
            .collect::<Vec<_>>()
    };
    let mut pairs = Vec::new();
    for (da, sa) in nearest(a) {
        for (db, sb) in nearest(b) {
            if sa.id != sb.id {
                pairs.push((da + db, sa, sb));
            }
        }
    }
    pairs.sort_by(|a, b| a.0.total_cmp(&b.0));
    let operator = |s: &Station| s.id.split('-').next().unwrap_or("").to_string();
    let mut chosen = Vec::new();
    // Two KRL access choices help when the nearest station has no matching run.
    for (_, sa, sb) in pairs
        .iter()
        .filter(|(_, sa, sb)| operator(sa) == "KCI" && operator(sb) == "KCI")
        .take(2)
    {
        chosen.push((*sa, *sb));
    }
    let mut families = std::collections::HashSet::new();
    families.insert("KCI".to_string());
    for (_, sa, sb) in &pairs {
        let op = operator(sa);
        if chosen.len() < 4 && op == operator(sb) && families.insert(op) {
            chosen.push((*sa, *sb));
        }
    }
    for (_, sa, sb) in pairs {
        if chosen.len() >= 4 {
            break;
        }
        if !chosen.iter().any(|(a, b)| a.id == sa.id && b.id == sb.id) {
            chosen.push((sa, sb));
        }
    }
    chosen
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{Json, Router, routing::get};
    use serde_json::json;
    fn at(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
    }
    #[tokio::test]
    async fn public_api_uses_matching_vehicle_at_both_stations() {
        let app=Router::new()
            .route("/stations",get(||async{Json(json!({"status":200,"data":[
                {"id":"KCI-A","name":"Alpha","latitude":-6.2,"longitude":106.8},
                {"id":"KCI-B","name":"Bravo","latitude":-6.24,"longitude":106.84}]}))}))
            .route("/fares/KCI-A/KCI-B",get(||async{Json(json!({"status":200,"data":{
                "totalFare":4000,"legs":[{"type":"RIDE","operator":"KCI","line":"KCI:B",
                    "from":{"id":"KCI-A","name":"Alpha"},"to":{"id":"KCI-B","name":"Bravo"},
                    "distanceM":6000,"stops":[{"id":"KCI-A"},{"id":"KCI-B"}]}]}}))}))
            .route("/stations/KCI/A/timetable",get(||async{Json(json!({"status":200,"data":[
                {"tripNumber":"42","lineCode":"B","estimatedDeparture":"08:10:00","estimatedArrival":"23:59:00"}]}))}))
            .route("/stations/KCI/B/timetable",get(||async{Json(json!({"status":200,"data":[
                {"tripNumber":"42","lineCode":"B","estimatedDeparture":"08:35:00"}]}))}));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let mut service = TransitService::from_env();
        service.base = base;
        service.feed = Some(Arc::new(
            gtfs::Feed::load(&PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/transit"))
                .unwrap(),
        ));
        let options = service
            .plan_options([-6.2, 106.8], [-6.24, 106.84], at("2026-11-16T01:00:00Z"))
            .await
            .unwrap();
        assert_eq!(options.len(), 2, "keep both valid bus and rail itineraries");
        assert!(options.iter().any(|p| p.source == "transjakarta_gtfs"));
        let route = options
            .iter()
            .find(|p| p.source == "commute_shiorilabs")
            .unwrap();
        assert_eq!(route.source, "commute_shiorilabs");
        assert_eq!(route.fare_idr, Some(4000.));
        assert_eq!(route.arrival_at, at("2026-11-16T01:35:00Z"));
        assert_eq!(route.legs[1].geometry_kind, "schematic_station_sequence");
        service.feed = None;
        assert!(
            service
                .plan([-6.2, 106.8], [-6.24, 106.84], at("2026-11-16T03:00:00Z"))
                .await
                .is_err()
        );
        server.abort();
    }
    #[test]
    fn nearby_bus_stops_do_not_hide_rail_candidates() {
        let stations: Vec<Station> = serde_json::from_value(json!([
            {"id":"TJ-A","name":"Bus A","latitude":-6.2,"longitude":106.8},
            {"id":"TJ-AA","name":"Bus AA","latitude":-6.201,"longitude":106.8},
            {"id":"TJ-AAA","name":"Bus AAA","latitude":-6.202,"longitude":106.8},
            {"id":"TJ-B","name":"Bus B","latitude":-6.24,"longitude":106.84},
            {"id":"KCI-A","name":"Rail A","latitude":-6.205,"longitude":106.8},
            {"id":"KCI-B","name":"Rail B","latitude":-6.245,"longitude":106.84}
        ]))
        .unwrap();
        let pairs = candidate_pairs(&stations, [-6.2, 106.8], [-6.24, 106.84]);
        assert!(
            pairs
                .iter()
                .any(|(a, b)| a.id == "KCI-A" && b.id == "KCI-B")
        );
        assert!(pairs.iter().any(|(a, b)| a.id == "TJ-A" && b.id == "TJ-B"));
        assert!(pairs.len() <= 4);
    }

    #[tokio::test]
    #[ignore = "requires supplied GTFS and calls the public Commute API"]
    async fn live_monas_ui_retains_bus_and_krl() {
        let mut service = TransitService::from_env();
        service.feed = Some(Arc::new(
            gtfs::Feed::load(&PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../file_gtfs"))
                .unwrap(),
        ));
        let options = service
            .plan_options(
                [-6.1754, 106.8272],
                [-6.3650, 106.8280],
                at("2026-11-16T01:00:00Z"),
            )
            .await
            .unwrap();
        for p in &options {
            println!("{}: {:.1} min", p.source, p.duration() / 60.);
            for leg in p.legs.iter().filter(|l| l.mode != "WALK") {
                println!("  {} {}: {} → {}", leg.mode, leg.line, leg.from, leg.to);
            }
        }
        assert!(
            options
                .iter()
                .any(|p| p.legs.iter().any(|l| l.mode == "BUS"))
        );
        assert!(
            options
                .iter()
                .any(|p| p.legs.iter().any(|l| l.mode == "KCI"))
        );
    }

    #[tokio::test]
    #[ignore = "calls the public Commute API"]
    async fn live_commute_api_routes_gondangdia_to_depok() {
        let service = TransitService::from_env();
        let r = service
            .plan(
                [-6.1858, 106.8325],
                [-6.4054, 106.8186],
                at("2026-11-16T01:00:00Z"),
            )
            .await
            .unwrap();
        println!(
            "{} minutes; fare {:?}; {} legs; {}",
            r.duration() / 60.,
            r.fare_idr,
            r.legs.len(),
            r.attribution
        );
        for leg in &r.legs {
            println!(
                "{} {} → {}: {} to {}",
                leg.mode,
                leg.from,
                leg.to,
                wib(leg.departure_at),
                wib(leg.arrival_at)
            );
        }
        assert!(r.legs.iter().any(|l| l.mode == "KCI"));
    }
}

#[cfg(test)]
mod local_tests {
    use super::*;
    #[tokio::test]
    async fn api_outage_keeps_valid_local_bus_itinerary() {
        let mut service = TransitService::from_env();
        service.base = "http://127.0.0.1:1".into();
        service.feed = Some(Arc::new(
            gtfs::Feed::load(&PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/transit"))
                .unwrap(),
        ));
        let at = DateTime::parse_from_rfc3339("2026-11-16T01:01:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let result = service
            .plan([-6.2, 106.8], [-6.24, 106.84], at)
            .await
            .unwrap();
        assert_eq!(result.source, "transjakarta_gtfs");
        assert_eq!(result.legs.iter().filter(|l| l.mode == "BUS").count(), 2);
    }
}
