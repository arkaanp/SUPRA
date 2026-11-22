use super::*;
use std::{collections::HashMap, path::Path};
type Row = HashMap<String, String>;
fn rows(dir: &Path, file: &str, optional: bool) -> anyhow::Result<Vec<Row>> {
    let path = dir.join(file);
    if optional && !path.exists() {
        return Ok(Vec::new());
    }
    let mut reader = csv::ReaderBuilder::new()
        .trim(csv::Trim::All)
        .from_path(path)?;
    reader
        .deserialize()
        .collect::<Result<Vec<Row>, _>>()
        .map_err(Into::into)
}
fn field<'a>(r: &'a Row, k: &str) -> &'a str {
    r.get(k).map(String::as_str).unwrap_or("")
}
fn time(r: &Row, k: &str) -> anyhow::Result<i64> {
    clock(field(r, k)).ok_or_else(|| anyhow::anyhow!("Invalid GTFS {k}"))
}
#[derive(Clone)]
struct Stop {
    name: String,
    p: Coord,
}
struct Calendar {
    start: NaiveDate,
    end: NaiveDate,
    days: [bool; 7],
}
impl Calendar {
    fn active(&self, d: NaiveDate) -> bool {
        d >= self.start && d <= self.end && self.days[d.weekday().num_days_from_monday() as usize]
    }
}
struct Frequency {
    start: i64,
    end: i64,
    headway: i64,
    exact: bool,
}
struct Timing {
    stop: usize,
    arr: i64,
    dep: i64,
    pickup: bool,
    dropoff: bool,
    shape: usize,
}
struct Trip {
    service: String,
    line: String,
    headsign: String,
    times: Vec<Timing>,
    shape: Arc<Vec<Coord>>,
    frequencies: Vec<Frequency>,
}
#[derive(Clone)]
struct Label {
    at: DateTime<Utc>,
    legs: Vec<Leg>,
}
pub struct Feed {
    stops: Vec<Stop>,
    trips: Vec<Trip>,
    calendar: HashMap<String, Calendar>,
    exceptions: HashMap<(String, NaiveDate), bool>,
    transfers: Vec<Vec<(usize, i64)>>,
    forbidden: std::collections::HashSet<(usize, usize)>,
}
impl Feed {
    pub fn load(dir: &Path) -> anyhow::Result<Self> {
        let agencies = rows(dir, "agency.txt", false)?;
        anyhow::ensure!(
            agencies
                .iter()
                .all(|r| field(r, "agency_timezone") == "Asia/Jakarta"),
            "GTFS timezone must be Asia/Jakarta"
        );
        let mut stops = Vec::new();
        let mut indices = HashMap::new();
        for r in rows(dir, "stops.txt", false)? {
            if !matches!(field(&r, "location_type"), "" | "0") {
                continue;
            }
            let p = [
                field(&r, "stop_lat").parse::<f64>()?,
                field(&r, "stop_lon").parse::<f64>()?,
            ];
            anyhow::ensure!(
                p[0].is_finite() && p[1].is_finite() && p[0].abs() <= 90. && p[1].abs() <= 180.,
                "Invalid stop coordinate"
            );
            let id = field(&r, "stop_id").to_string();
            anyhow::ensure!(!indices.contains_key(&id), "Duplicate stop id");
            indices.insert(id.clone(), stops.len());
            stops.push(Stop {
                name: field(&r, "stop_name").into(),
                p,
            });
        }
        let mut calendar = HashMap::new();
        for r in rows(dir, "calendar.txt", true)? {
            let keys = [
                "monday",
                "tuesday",
                "wednesday",
                "thursday",
                "friday",
                "saturday",
                "sunday",
            ];
            calendar.insert(
                field(&r, "service_id").into(),
                Calendar {
                    start: NaiveDate::parse_from_str(field(&r, "start_date"), "%Y%m%d")?,
                    end: NaiveDate::parse_from_str(field(&r, "end_date"), "%Y%m%d")?,
                    days: keys.map(|k| field(&r, k) == "1"),
                },
            );
        }
        let mut exceptions = HashMap::new();
        for r in rows(dir, "calendar_dates.txt", true)? {
            exceptions.insert(
                (
                    field(&r, "service_id").to_string(),
                    NaiveDate::parse_from_str(field(&r, "date"), "%Y%m%d")?,
                ),
                field(&r, "exception_type") == "1",
            );
        }
        let routes = rows(dir, "routes.txt", false)?
            .into_iter()
            .map(|r| {
                (
                    field(&r, "route_id").to_string(),
                    format!(
                        "{} · {}",
                        field(&r, "route_short_name"),
                        field(&r, "route_long_name")
                    ),
                )
            })
            .collect::<HashMap<_, _>>();
        let mut shapes: HashMap<String, Vec<(u32, Coord)>> = HashMap::new();
        for r in rows(dir, "shapes.txt", false)? {
            let point = [
                field(&r, "shape_pt_lat").parse::<f64>()?,
                field(&r, "shape_pt_lon").parse::<f64>()?,
            ];
            anyhow::ensure!(
                point[0].is_finite()
                    && point[1].is_finite()
                    && point[0].abs() <= 90.
                    && point[1].abs() <= 180.,
                "Invalid shape coordinate"
            );
            shapes
                .entry(field(&r, "shape_id").into())
                .or_default()
                .push((field(&r, "shape_pt_sequence").parse()?, point));
        }
        let shapes = shapes
            .into_iter()
            .map(|(k, mut v)| {
                v.sort_by_key(|v| v.0);
                (k, Arc::new(v.into_iter().map(|v| v.1).collect::<Vec<_>>()))
            })
            .collect::<HashMap<_, _>>();
        let mut times: HashMap<String, Vec<(u32, Timing)>> = HashMap::new();
        for r in rows(dir, "stop_times.txt", false)? {
            let Some(&stop) = indices.get(field(&r, "stop_id")) else {
                continue;
            };
            times.entry(field(&r, "trip_id").into()).or_default().push((
                field(&r, "stop_sequence").parse()?,
                Timing {
                    stop,
                    arr: time(&r, "arrival_time")?,
                    dep: time(&r, "departure_time")?,
                    pickup: matches!(field(&r, "pickup_type"), "" | "0"),
                    dropoff: matches!(field(&r, "drop_off_type"), "" | "0"),
                    shape: 0,
                },
            ));
        }
        let mut frequencies: HashMap<String, Vec<Frequency>> = HashMap::new();
        for r in rows(dir, "frequencies.txt", true)? {
            let f = Frequency {
                start: time(&r, "start_time")?,
                end: time(&r, "end_time")?,
                headway: field(&r, "headway_secs").parse()?,
                exact: field(&r, "exact_times") == "1",
            };
            anyhow::ensure!(f.headway > 0 && f.end > f.start, "Invalid GTFS frequency");
            frequencies
                .entry(field(&r, "trip_id").into())
                .or_default()
                .push(f);
        }
        let mut trips = Vec::new();
        for r in rows(dir, "trips.txt", false)? {
            let Some(mut timings) = times.remove(field(&r, "trip_id")) else {
                continue;
            };
            timings.sort_by_key(|t| t.0);
            let Some(shape) = shapes.get(field(&r, "shape_id")) else {
                continue;
            };
            if shape.len() < 2 || timings.len() < 2 {
                continue;
            }
            let mut last = 0;
            let mut previous = -1;
            let mut valid = true;
            for (_, t) in &mut timings {
                if t.arr < previous || t.dep < t.arr {
                    valid = false;
                    break;
                }
                previous = t.dep;
                let nearest = (last..shape.len())
                    .min_by(|&a, &b| {
                        distance(stops[t.stop].p, shape[a])
                            .total_cmp(&distance(stops[t.stop].p, shape[b]))
                    })
                    .unwrap_or(last);
                if distance(stops[t.stop].p, shape[nearest]) > 0.5 {
                    valid = false;
                    break;
                }
                t.shape = nearest;
                last = nearest;
            }
            if !valid {
                continue;
            }
            trips.push(Trip {
                service: field(&r, "service_id").into(),
                line: routes
                    .get(field(&r, "route_id"))
                    .cloned()
                    .unwrap_or_else(|| field(&r, "route_id").into()),
                headsign: field(&r, "trip_headsign").into(),
                times: timings.into_iter().map(|t| t.1).collect(),
                shape: shape.clone(),
                frequencies: frequencies.remove(field(&r, "trip_id")).unwrap_or_default(),
            });
        }
        anyhow::ensure!(!trips.is_empty(), "GTFS contains no usable trips/shapes");
        let mut explicit = HashMap::new();
        for r in rows(dir, "transfers.txt", true)? {
            if let (Some(&a), Some(&b)) = (
                indices.get(field(&r, "from_stop_id")),
                indices.get(field(&r, "to_stop_id")),
            ) {
                let seconds = if field(&r, "transfer_type") == "3" {
                    -1
                } else {
                    field(&r, "min_transfer_time").parse::<i64>().unwrap_or(0)
                };
                explicit.insert((a, b), seconds);
            }
        }
        let mut transfers = vec![Vec::new(); stops.len()];
        // Spatial buckets avoid an O(n²) scan of the supplied stop directory.
        let bucket = |p: Coord| ((p[0] / 0.003).floor() as i32, (p[1] / 0.003).floor() as i32);
        let mut grid: HashMap<_, Vec<usize>> = HashMap::new();
        for (i, s) in stops.iter().enumerate() {
            grid.entry(bucket(s.p)).or_default().push(i)
        }
        for (i, s) in stops.iter().enumerate() {
            let (x, y) = bucket(s.p);
            for dx in -1..=1 {
                for dy in -1..=1 {
                    for &j in grid.get(&(x + dx, y + dy)).into_iter().flatten() {
                        if i == j {
                            continue;
                        }
                        let km = distance(s.p, stops[j].p);
                        if km <= 0.25 && explicit.get(&(i, j)) != Some(&-1) {
                            transfers[i].push((
                                j,
                                walk_seconds(km).max(*explicit.get(&(i, j)).unwrap_or(&0)),
                            ))
                        }
                    }
                }
            }
        }
        let forbidden = explicit
            .iter()
            .filter(|(_, v)| **v < 0)
            .map(|(k, _)| *k)
            .collect();
        for ((i, j), seconds) in explicit {
            if seconds >= 0 && !transfers[i].iter().any(|(to, _)| *to == j) {
                transfers[i].push((
                    j,
                    seconds.max(walk_seconds(distance(stops[i].p, stops[j].p))),
                ));
            }
        }
        Ok(Self {
            stops,
            trips,
            calendar,
            exceptions,
            transfers,
            forbidden,
        })
    }
    pub fn trip_count(&self) -> usize {
        self.trips.len()
    }
    fn active(&self, service: &str, date: NaiveDate) -> bool {
        self.exceptions
            .get(&(service.into(), date))
            .copied()
            .unwrap_or_else(|| self.calendar.get(service).is_some_and(|c| c.active(date)))
    }
    pub fn plan(&self, a: Coord, b: Coord, at: DateTime<Utc>) -> Option<Itinerary> {
        let date = (at + Duration::hours(7)).date_naive();
        let horizon = at + Duration::hours(6);
        let mut labels: Vec<Option<Label>> = self
            .stops
            .iter()
            .map(|s| {
                let km = distance(a, s.p);
                (km <= 1.5).then(|| {
                    let leg = Leg::walk("Start", &s.name, a, s.p, at, 0);
                    Label {
                        at: leg.arrival_at,
                        legs: vec![leg],
                    }
                })
            })
            .collect();
        let mut best: Option<Itinerary> = None;
        // Bounded rounds: up to three vehicle boardings, interleaved with nearby walks.
        for _ in 0..3 {
            let old = labels.clone();
            let mut next = labels.clone();
            for trip in &self.trips {
                for delta in [-1, 0, 1] {
                    let day = date + Duration::days(delta);
                    if !self.active(&trip.service, day) {
                        continue;
                    }
                    let base = midnight(day);
                    let mut onboard: Option<(i64, usize, Label)> = None;
                    for (i, t) in trip.times.iter().enumerate() {
                        if i > 0 && t.dropoff {
                            if let Some((offset, board, label)) = &onboard {
                                let arr = base + Duration::seconds(t.arr + offset);
                                if arr <= horizon
                                    && next[t.stop].as_ref().is_none_or(|l| arr < l.at)
                                {
                                    let start = &trip.times[*board];
                                    let slice = &trip.shape[start.shape..=t.shape];
                                    if slice.len() < 2 {
                                        continue;
                                    }
                                    let km =
                                        slice.windows(2).map(|p| distance(p[0], p[1])).sum::<f64>();
                                    let mut legs = label.legs.clone();
                                    legs.push(Leg {
                                        mode: "BUS".into(),
                                        line: format!(
                                            "Transjakarta {} → {}",
                                            trip.line, trip.headsign
                                        ),
                                        from: self.stops[start.stop].name.clone(),
                                        to: self.stops[t.stop].name.clone(),
                                        departure_at: base + Duration::seconds(start.dep + offset),
                                        arrival_at: arr,
                                        distance_km: km,
                                        geometry_kind: "gtfs_shape".into(),
                                        estimated: trip.frequencies.iter().any(|f| !f.exact),
                                        waypoints: slice.to_vec(),
                                    });
                                    next[t.stop] = Some(Label { at: arr, legs });
                                }
                            }
                        }
                        if !t.pickup {
                            continue;
                        }
                        let Some(label) = &old[t.stop] else { continue };
                        if self.forbidden.contains(&(t.stop, t.stop))
                            && label.legs.iter().any(|l| l.mode != "WALK")
                        {
                            continue;
                        }
                        let ready = label.at
                            + Duration::seconds(if label.legs.iter().any(|l| l.mode != "WALK") {
                                120
                            } else {
                                0
                            });
                        let seconds = (ready - base).num_seconds();
                        let offset = if trip.frequencies.is_empty() {
                            (t.dep >= seconds).then_some(0)
                        } else {
                            trip.frequencies
                                .iter()
                                .filter_map(|f| {
                                    let offset_to_stop = t.dep - trip.times[0].dep;
                                    let earliest = (seconds - offset_to_stop).max(f.start);
                                    let run = if f.exact {
                                        f.start
                                            + ((earliest - f.start + f.headway - 1) / f.headway)
                                                * f.headway
                                    } else {
                                        earliest + f.headway
                                    };
                                    (run < f.end).then_some(run - trip.times[0].dep)
                                })
                                .min()
                        };
                        if let Some(offset) = offset {
                            if onboard.as_ref().is_none_or(|(o, _, _)| offset < *o) {
                                onboard = Some((offset, i, label.clone()))
                            }
                        }
                    }
                }
            }
            // Transfers use feed restrictions/minimum times and short schematic walking links.
            let arrived = next.clone();
            for (i, label) in arrived.iter().enumerate() {
                let Some(label) = label else { continue };
                if !label.legs.iter().any(|l| l.mode != "WALK") {
                    continue;
                }
                for &(j, seconds) in &self.transfers[i] {
                    let end = label.at + Duration::seconds(seconds);
                    if end <= horizon && next[j].as_ref().is_none_or(|l| end < l.at) {
                        let mut legs = label.legs.clone();
                        legs.push(Leg::walk(
                            &self.stops[i].name,
                            &self.stops[j].name,
                            self.stops[i].p,
                            self.stops[j].p,
                            label.at,
                            seconds,
                        ));
                        next[j] = Some(Label { at: end, legs });
                    }
                }
            }
            for (i, label) in next.iter().enumerate() {
                let Some(label) = label else { continue };
                if !label.legs.iter().any(|l| l.mode != "WALK") {
                    continue;
                }
                if distance(self.stops[i].p, b) > 1.5 {
                    continue;
                }
                let last = Leg::walk(
                    &self.stops[i].name,
                    "Destination",
                    self.stops[i].p,
                    b,
                    label.at,
                    0,
                );
                if last.arrival_at <= horizon
                    && best.as_ref().is_none_or(|p| last.arrival_at < p.arrival_at)
                {
                    let mut legs = label.legs.clone();
                    legs.push(last.clone());
                    best=Some(Itinerary{source:"transjakarta_gtfs".into(),departure_at:at,arrival_at:last.arrival_at,fare_idr:None,legs,
                    attribution:"Transjakarta — GTFS tersedia. Waktu tunggu berdasarkan frekuensi dan waktu berjalan merupakan perkiraan. Jalur penghubung bersifat skematis, bukan navigasi jalan. Pelacakan kendaraan langsung belum tersedia.".into()});
                }
            }
            labels = next;
        }
        best
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> Feed {
        Feed::load(&PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/transit")).unwrap()
    }
    fn at(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
    }
    #[test]
    fn csv_calendar_frequencies_shapes_and_transfer_route() {
        let feed = fixture();
        assert_eq!(feed.stops[0].name, "Alpha, Gate");
        let p = feed
            .plan([-6.2, 106.8], [-6.24, 106.84], at("2026-11-16T01:01:00Z"))
            .unwrap();
        let rides = p
            .legs
            .iter()
            .filter(|l| l.mode == "BUS")
            .collect::<Vec<_>>();
        assert_eq!(rides.len(), 2);
        assert!(rides[0].estimated);
        assert!(!rides[1].estimated);
        assert_eq!(rides[0].geometry_kind, "gtfs_shape");
        assert!(rides[1].departure_at >= rides[0].arrival_at + Duration::seconds(120));
        assert!(p.duration() > 2400. && p.duration() < 7200.);
        assert!(
            feed.plan([-6.2, 106.8], [-6.24, 106.84], at("2030-11-16T01:01:00Z"))
                .is_none()
        );
        assert!(
            feed.plan([-6.8, 107.2], [-6.24, 106.84], at("2026-11-16T01:01:00Z"))
                .is_none()
        );
    }
    #[test]
    fn service_exceptions_and_after_midnight_service_day() {
        let mut feed = fixture();
        let today = NaiveDate::from_ymd_opt(2026, 11, 16).unwrap();
        feed.exceptions.insert(("DAILY".into(), today), false);
        assert!(
            feed.plan([-6.2, 106.8], [-6.24, 106.84], at("2026-11-16T01:01:00Z"))
                .is_none()
        );
        feed.exceptions.clear();
        for trip in &mut feed.trips {
            for t in &mut trip.times {
                t.arr += 17 * 3600;
                t.dep += 17 * 3600
            }
            trip.frequencies.clear();
        }
        let p = feed
            .plan([-6.2, 106.8], [-6.2, 106.84], at("2026-11-16T17:59:00Z"))
            .unwrap();
        assert_eq!(
            p.legs
                .iter()
                .find(|l| l.mode == "BUS")
                .unwrap()
                .departure_at,
            at("2026-11-16T18:00:00Z")
        );
        assert_eq!(clock("25:00:00"), Some(90000));
        assert_eq!(clock("08:60:00"), None);
    }
    #[test]
    fn pickup_and_forbidden_same_stop_transfer_are_respected() {
        let mut feed = fixture();
        feed.forbidden.insert((2, 2));
        let at = at("2026-11-16T01:01:00Z");
        assert!(feed.plan([-6.2, 106.8], [-6.24, 106.84], at).is_none());
        feed.forbidden.clear();
        feed.trips[0].times[0].pickup = false;
        assert!(feed.plan([-6.2, 106.8], [-6.2, 106.84], at).is_none());
    }

    #[test]
    #[ignore = "requires the user-supplied file_gtfs directory"]
    fn supplied_transjakarta_feed_routes_blok_m_to_kota() {
        let feed =
            Feed::load(&PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../file_gtfs")).unwrap();
        println!("Loaded {} usable trips", feed.trip_count());
        let p = feed
            .plan(
                [-6.2435, 106.7985],
                [-6.1376, 106.8178],
                at("2026-11-16T01:00:00Z"),
            )
            .expect("Corridor 1 should be routable");
        println!(
            "{} minutes, {} legs, {} geometry points",
            p.duration() / 60.,
            p.legs.len(),
            p.points().len()
        );
        assert!(
            p.legs
                .iter()
                .any(|l| l.mode == "BUS" && l.geometry_kind == "gtfs_shape")
        );
    }
}
