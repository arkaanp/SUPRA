#!/usr/bin/env python3
"""Read current conditions at three Jakarta coordinates using the desktop session."""
import json
from pathlib import Path
from urllib.request import Request, urlopen

prefs=json.loads((Path.home()/'.local/share/com.example.supra_mobile_ui/shared_preferences.json').read_text())
session=next(json.loads(v) for k,v in prefs.items() if k.endswith('-auth-token'))
for lat,lon in [(-6.2,106.82),(-6.24,106.84),(-6.28,106.86)]:
    req=Request(f'http://localhost:3000/api/conditions/current?latitude={lat}&longitude={lon}',
                headers={'Authorization':'Bearer '+session['access_token']})
    with urlopen(req,timeout=12) as r:
        d=json.load(r)
    print(json.dumps({'coordinate':[lat,lon],**{k:{key:d[k].get(key) for key in ['status','source','kind','valid_at']} for k in ['weather','air_quality']}}))
