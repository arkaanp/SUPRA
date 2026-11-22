"""Direct weather-only PyTorch regression using the current temperature and local time."""
import datetime as dt
from functools import lru_cache
import hashlib
import json
import math

import torch

from data import ROOT, parse_time, utcnow
from met_weather import SOURCE, weather_at

ARTIFACT = ROOT / 'artifacts/weather_model.json'


def features(point, at, temp):
    hour = (at.hour + 7) * math.tau / 24
    t = (temp - 28) / 5
    return [1, t, t*t, math.sin(hour), math.cos(hour), math.sin(2*hour), math.cos(2*hour),
            t*math.sin(hour), t*math.cos(hour), point[0]+6.3, point[1]-106.8]


def predict(x, weights):
    output = (x @ weights).reshape(-1, 12, 3)
    output[:, :, 1].clamp_(min=0)
    output[:, :, 2].clamp_(0, 1)
    return output


@lru_cache(maxsize=1)
def load():
    card = json.loads(ARTIFACT.read_text())
    return card, torch.tensor(card['weights'], dtype=torch.float64)


def forecast(latitude, longitude, now=None):
    now = now or utcnow()
    card, weights = load()
    if now - parse_time(card['data_through']) > dt.timedelta(days=90):
        raise ValueError('Model needs retraining')
    try:
        weather = weather_at(latitude, longitude, now)
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise ValueError('MET Norway fallback inputs unavailable') from error
    anchor = parse_time(weather['valid_at'])
    x = torch.tensor(features((latitude, longitude), anchor, weather['temperature_c']), dtype=weights.dtype)
    with torch.inference_mode():
        values = predict(x, weights)[0].tolist()
    hourly = []
    for h, (temp, rain, probability) in enumerate(values, 1):
        if not (-50 <= temp <= 60 and 0 <= rain <= 500 and 0 <= probability <= 1):
            raise ValueError('Invalid weather model output')
        hourly.append({'target_time': (anchor + dt.timedelta(hours=h)).isoformat(),
                       'temperature_c': temp, 'precipitation_mm': rain, 'rain_probability': probability,
                       'aqi': None, 'pm25_ug_m3': None})
    return {'model_id': card['model_id'], 'scope': 'weather_only', 'framework': 'PyTorch',
            'latitude': latitude, 'longitude': longitude, 'generated_at': now.isoformat(),
            'input_through': anchor.isoformat(), 'expires_at': (anchor + dt.timedelta(hours=1)).isoformat(),
            'sources': {'attribution': SOURCE + ' Weather-only model trained on Open-Meteo weather (CC BY 4.0).',
                        'provider_issued_at': weather['issued_at']},
            'validation': card['validation'], 'hourly': hourly}


def train():
    dataset = ROOT / 'data/history.json'
    sites = json.loads(dataset.read_text())['sites']
    last = min(parse_time(site['rows'][-1]['time']) for site in sites)
    test_start = last - dt.timedelta(days=7)
    validation_start = test_start - dt.timedelta(days=7)
    groups = [[], [], []]
    for site in sites:
        rows = site['rows']
        for i in range(len(rows) - 12):
            at = parse_time(rows[i]['time'])
            end = parse_time(rows[i+12]['time'])
            future = rows[i+1:i+13]
            if any(parse_time(row['time']) != at + dt.timedelta(hours=h) for h, row in enumerate(future, 1)):
                continue
            if end < validation_start:
                group = groups[0]
            elif at >= validation_start and end < test_start:
                group = groups[1]
            elif at >= test_start:
                group = groups[2]
            else:
                continue
            targets = [[r['values'][0], r['values'][1], float(r['values'][1] >= 0.1)] for r in future]
            group.append((features(site['point'], at, rows[i]['values'][0]), targets))
    arrays = [(torch.tensor(x, dtype=torch.float64), torch.tensor(y, dtype=torch.float64))
              for x, y in (zip(*group) for group in groups)]
    x, y = arrays[0]
    # Ridge regression for each lead hour. Wet-hour targets give a linear probability model.
    weights = torch.linalg.solve(x.T @ x + torch.eye(x.shape[1]) * 0.1, x.T @ y.flatten(1))
    card = {'model_id': 'supra-weather-' + last.strftime('%Y%m%dT%H'),
            'data_through': last.isoformat(), 'dataset_sha256': hashlib.sha256(dataset.read_bytes()).hexdigest(),
            'samples': [len(group) for group in groups], 'weights': weights.tolist()}
    for name, (x, y) in zip(('validation', 'test'), arrays[1:]):
        delta = predict(x, weights) - y
        card[name] = {'temperature_mae_c': float(delta[:,:,0].abs().mean()),
                      'rain_mae_mm': float(delta[:,:,1].abs().mean()),
                      'rain_brier': float(delta[:,:,2].square().mean())}
    ARTIFACT.write_text(json.dumps(card, indent=2) + '\n')
    print(card['model_id'], card['samples'], card['test'])


if __name__ == '__main__':
    train()
