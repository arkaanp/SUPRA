#!/usr/bin/env python3
"""Inspect live public-provider timestamps and nearby OpenAQ recency; never print keys."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import shlex
from urllib.request import Request, urlopen

def probe(item):
    name,url,headers=item
    try:
        with urlopen(Request(url,headers=headers),timeout=8) as r:
            d=json.load(r)
        if name=='BMKG':
            entries=[e for a in d.get('data',[]) for group in a.get('cuaca',[]) for e in group]
            return {'source':name,'issued':sorted(set(e.get('analysis_date','') for e in entries)),
                    'valid_times':[e.get('utc_datetime') for e in entries[:4]]}
        if name=='OpenAQ':
            return {'source':name,'stations':[{'id':s.get('id'),'last':s.get('datetimeLast')}
                                              for s in d.get('results',[])]}
        return {'source':name,'current':d.get('current'),'units':d.get('current_units')}
    except Exception as e:
        return {'source':name,'error':type(e).__name__, 'http_status':getattr(e,'code',None)}

def main():
    print('UTC now:',datetime.now(timezone.utc).isoformat())
    items=[('Open-Meteo weather','https://api.open-meteo.com/v1/forecast?latitude=-6.2&longitude=106.82&current=temperature_2m,precipitation&timezone=GMT',{}),
           ('CAMS air quality','https://air-quality-api.open-meteo.com/v1/air-quality?latitude=-6.2&longitude=106.82&current=pm2_5,us_aqi&domains=cams_global&timezone=GMT',{}),
           ('BMKG','https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=31.71.03.1001',{})]
    path=Path(__file__).resolve().parents[2]/'backend/.env'
    if path.exists():
        for line in path.read_text().splitlines():
            if line.startswith('OPENAQ_API_KEY='):
                values=shlex.split(line.split('=',1)[1],comments=True)
                if values and values[0]:
                    items.append(('OpenAQ','https://api.openaq.org/v3/locations?coordinates=-6.2,106.82&radius=25000&parameters_id=2&limit=100',{'X-API-Key':values[0]}))
    with ThreadPoolExecutor(max_workers=4) as pool:
        for result in pool.map(probe,items):print(json.dumps(result))
if __name__=='__main__': main()
