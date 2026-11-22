"""PyTorch PM2.5 forecasting from twelve past hours, with projected NowCast indices."""
import datetime as dt
from functools import lru_cache
import hashlib
import json
import math

import torch

from data import InputUnavailable, ROOT, parse_time
from station_history import load_station

ARTIFACT = ROOT/'artifacts/air_model.json'
LOOKBACK = 12
HORIZON = 14


def features(point, at, values):
    hour = (at.hour+7)*math.tau/24
    return [1, *[math.log1p(v) for v in values], math.sin(hour), math.cos(hour),
            math.sin(2*hour), math.cos(2*hour), point[0]+6.3, point[1]-106.8]


def nowcast_aqi(values):
    high, low = max(values), min(values)
    weight = max(0.5, low/high) if high else 1
    weights = [weight**age for age in range(len(values))]
    concentration = math.floor(sum(v*w for v,w in zip(reversed(values), weights))/sum(weights)*10+1e-9)/10
    bands = [(0,9,0,50),(9.1,35.4,51,100),(35.5,55.4,101,150),
             (55.5,125.4,151,200),(125.5,225.4,201,300),(225.5,325.4,301,500)]
    lo, hi, ilo, ihi = next((b for b in bands if concentration <= b[1]), bands[-1])
    return math.floor((ihi-ilo)/(hi-lo)*(concentration-lo)+ilo+0.5)


@lru_cache(maxsize=1)
def load():
    card = json.loads(ARTIFACT.read_text())
    return card, torch.tensor(card['weights'], dtype=torch.float64)


def forecast(latitude, longitude, now):
    card, weights = load()
    if now-parse_time(card['data_through']) > dt.timedelta(days=90):
        raise InputUnavailable('Air forecast model requires retraining')
    times, values, station = load_station(latitude, longitude, now)
    anchor = times[-1]
    x = torch.tensor(features((latitude, longitude), anchor, values), dtype=weights.dtype)
    with torch.inference_mode():
        predicted = torch.expm1((x @ weights).clamp(0, math.log1p(2000))).tolist()
    history = values[:]
    hours = {}
    for lead, pm in enumerate(predicted, 1):
        history.append(pm)
        at = anchor+dt.timedelta(hours=lead)
        if at > now:
            hours[at] = {'estimated_aqi': nowcast_aqi(history[-12:]), 'estimated_pm25': pm}
    return hours, {
        'model_id': card['model_id'], 'input_through': anchor.isoformat(),
        'expires_at': (anchor+dt.timedelta(hours=2)).isoformat(),
        'station': station, 'validation': card['validation'],
        'attribution': 'Pengukuran stasiun per jam OpenAQ (https://openaq.org/). '
                       'Prakiraan percobaan PM2.5 PyTorch SUPRA dan proyeksi indeks EPA NowCast. '
                       'Target pelatihan menggunakan riwayat model CAMS melalui Open-Meteo, CC BY 4.0.',
        'limitations': 'Validasi menggunakan riwayat model CAMS yang dipisahkan dari pelatihan. Akurasi terhadap pengamatan stasiun OpenAQ belum diukur.',
    }


def train():
    path = ROOT/'data/history.json'
    sites = json.loads(path.read_text())['sites']
    last = min(parse_time(site['rows'][-1]['time']) for site in sites)
    test_start = last-dt.timedelta(days=7)
    validation_start = test_start-dt.timedelta(days=7)
    groups = [[], [], []]
    for site in sites:
        rows = site['rows']
        for i in range(LOOKBACK-1, len(rows)-HORIZON):
            at = parse_time(rows[i]['time'])
            end = parse_time(rows[i+HORIZON]['time'])
            window = rows[i-LOOKBACK+1:i+HORIZON+1]
            if any(parse_time(row['time']) != at+dt.timedelta(hours=h-LOOKBACK+1) for h,row in enumerate(window)):
                continue
            if end < validation_start:
                group = groups[0]
            elif at-dt.timedelta(hours=LOOKBACK-1) >= validation_start and end < test_start:
                group = groups[1]
            elif at-dt.timedelta(hours=LOOKBACK-1) >= test_start:
                group = groups[2]
            else:
                continue
            values = [r['values'][2] for r in rows[i-LOOKBACK+1:i+1]]
            targets = [r['values'][2] for r in rows[i+1:i+HORIZON+1]]
            group.append((features(site['point'], at, values), targets, values[-1]))
    arrays = [(torch.tensor(x, dtype=torch.float64), torch.tensor(y, dtype=torch.float64),
               torch.tensor(base, dtype=torch.float64)) for x,y,base in (zip(*g) for g in groups)]
    x, y, _ = arrays[0]
    weights = torch.linalg.solve(x.T @ x + torch.eye(x.shape[1])*0.1, x.T @ torch.log1p(y))
    card = {'model_id': 'supra-air-'+last.strftime('%Y%m%dT%H'),
            'data_through':last.isoformat(),'dataset_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'architecture':'Direct ridge regression, 12 past PM2.5 hours, 14 lead hours, PyTorch CPU',
            'samples':[len(g) for g in groups], 'weights':weights.tolist()}
    for name,(x,y,base) in zip(('validation','test'),arrays[1:]):
        pred = torch.expm1((x@weights).clamp(0,math.log1p(2000)))
        card[name] = {'pm25_mae_ug_m3':float((pred-y).abs().mean()),
                      'persistence_mae_ug_m3':float((base[:,None]-y).abs().mean()),
                      'per_lead_mae_ug_m3':(pred-y).abs().mean(0).tolist()}
    ARTIFACT.write_text(json.dumps(card,indent=2)+'\n')
    print(card['model_id'],card['samples'],card['validation'],card['test'])


if __name__ == '__main__':
    train()
