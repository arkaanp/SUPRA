#!/usr/bin/env python3
"""Plan sample public-transit journeys through the running authenticated backend. No trip is saved."""
import argparse
import json
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url',default='http://localhost:3000')
    parser.add_argument('--case',choices=['bus','rail','both','monas-ui','all'],default='both')
    args=parser.parse_args()
    # Credentials stay local and are never printed or written to evidence.
    path=Path.home()/'.local/share/com.example.supra_mobile_ui/shared_preferences.json'
    try:
        prefs=json.loads(path.read_text())
        session=next(json.loads(v) for k,v in prefs.items() if k.endswith('-auth-token'))
        token=session['access_token']
    except (OSError,ValueError,StopIteration,KeyError):
        print('Sign in through the Linux app before running this smoke test.')
        return 1
    cases=[('bus',[-6.2435,106.7985],[-6.1376,106.8178]),
           ('rail',[-6.1858,106.8325],[-6.4054,106.8186]),
           ('monas-ui',[-6.1754,106.8272],[-6.3650,106.8280])]
    failures=0
    for name,a,b in cases:
        if args.case != 'all' and args.case != name and not (args.case == 'both' and name in ('bus','rail')):continue
        body={'origin':dict(zip(['latitude','longitude'],a)),
              'destination':dict(zip(['latitude','longitude'],b)), 'mode':'public_transit'}
        req=Request(args.base_url.rstrip('/')+'/api/mobility/plan',data=json.dumps(body).encode(),
                    headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        try:
            with urlopen(req,timeout=15) as r:d=json.load(r)
            options=[d]+d.get('alternatives',[])
            summaries=[]
            modes=set()
            for option in options:
                t=option['transit'];rides=[l for l in t['legs'] if l['mode']!='WALK']
                assert option['mode']=='public_transit' and rides and len(option['waypoints'])>=2
                modes.update(l['mode'] for l in rides)
                summaries.append({'source':option['source'],'duration_minutes':round(option['duration_seconds']/60,1),
                                  'fare_idr':t['fare_idr'],'rides':[{'mode':l['mode'],'line':l['line'],
                                  'from':l['from'],'to':l['to'],'departure_at':l['departure_at'],
                                  'arrival_at':l['arrival_at'],'geometry_kind':l['geometry_kind']} for l in rides]})
            print(json.dumps({'case':name,'options':summaries}))
            if name=='monas-ui':
                assert 'BUS' in modes and 'KCI' in modes, 'Bus and KRL required during service hours'
        except HTTPError as e:
            failures+=1;print(f'{name}: HTTP {e.code}; check session, feed and service hours.')
        except (OSError,URLError,ValueError,KeyError,AssertionError):
            failures+=1;print(f'{name}: failed, invalid itinerary, or expected transit modes unavailable; check service hours/providers.')
    return int(failures>0)

if __name__=='__main__':raise SystemExit(main())
