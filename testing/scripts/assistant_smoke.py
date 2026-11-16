#!/usr/bin/env python3
"""Read-only preference/filter checks and one real Gemini call using a public Monas–UI selection."""
import json
import time
from pathlib import Path
from urllib.request import Request,urlopen
from urllib.error import HTTPError


def main():
    prefs=json.loads((Path.home()/'.local/share/com.example.supra_mobile_ui/shared_preferences.json').read_text())
    session=next(json.loads(v) for k,v in prefs.items() if k.endswith('-auth-token'))
    token=session['access_token'];user=session['user']['id']
    def request(path,body=None):
        req=Request('http://localhost:3000'+path,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'},
                    data=json.dumps(body).encode() if body is not None else None)
        with urlopen(req,timeout=40) as r:return json.load(r)
    for attempt in range(20):
        try:
            with urlopen('http://localhost:3000/health/live',timeout=1):pass
            break
        except OSError:
            if attempt==19:raise
            time.sleep(0.5)
    saved=request(f'/api/users/{user}/preferences')
    levels=['low','medium','high','critical'];counts={}
    for minimum in levels:
        rows=request(f'/api/users/{user}/notifications?limit=100&news_min_severity={minimum}')
        news=[n for n in rows if n.get('source_url')]
        assert all(levels.index(n['severity'])>=levels.index(minimum) for n in news)
        counts[minimum]=len(news)
    selection={'origin':[-6.1754,106.8272],'destination':[-6.365,106.828],
               'origin_name':'Monas','destination_name':'Universitas Indonesia','mode':'public_transit',
               'waypoints':[[-6.1754,106.8272],[-6.28,106.83],[-6.365,106.828]],
               'instructions':['Selected KRL plan: Juanda → Universitas Indonesia. Walking links are schematic.']}
    result=request('/api/agent/chat',{'message':'For this selected Monas to Universitas Indonesia KRL route, give relevant weather and air-quality advice. Cite sources and times, distinguish forecasts, and identify missing data.',
        'context':{'selected_route':selection,'aqi':499,'weather':'Client supplied values must be ignored'}})
    evidence=result['context_used']
    assert evidence['route']['origin_name']=='Monas' and evidence['route']['destination_name']=='Universitas Indonesia'
    assert len(evidence['samples'])==3 and evidence['route']['mode']=='public_transit'
    assert evidence['samples'][0]['conditions']['latitude']==selection['origin'][0]
    assert evidence['samples'][-1]['conditions']['latitude']==selection['destination'][0]
    print(json.dumps({'engine':result['engine'],'model':result['model'],'reply':result['reply'],
        'route':{'from':'Monas','to':'Universitas Indonesia','mode':'public_transit'},
        'samples':[{'role':s['location_role'],'latitude':s['conditions']['latitude'],'longitude':s['conditions']['longitude'],
                    'sources':{k:{'source':s['conditions'][k]['source'],'status':s['conditions'][k]['status'],'valid_at':s['conditions'][k].get('valid_at')} for k in ['weather','air_quality','traffic']}} for s in evidence['samples']],
        'forecast_status':evidence['forecast_status'],'saved_news_minimum':saved['news_min_severity'],
        'filtered_news_counts':counts},indent=2))
    return 0 if result['engine']=='gemini' else 2
if __name__=='__main__':
    try:raise SystemExit(main())
    except HTTPError as error:
        print(f'HTTP {error.code}; verify the running backend and app sign-in.');raise SystemExit(1)
    except (OSError,ValueError,KeyError,StopIteration,AssertionError) as error:
        print(f'Live check failed ({type(error).__name__}); verify services and the app session.');raise SystemExit(1)
