#!/usr/bin/env python3
"""Check authenticated ML forecasts and current publisher reports. Optional --evaluate queues inbox news."""
import argparse
import datetime as dt
import json
from pathlib import Path
import time
from urllib.error import HTTPError
from urllib.request import Request,urlopen

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url',default='http://localhost:3000')
    parser.add_argument('--python-url',default='http://127.0.0.1:8001')
    parser.add_argument('--evaluate',action='store_true')
    args=parser.parse_args()
    def request(base,path,token=None,method='GET'):
        headers={'Authorization':'Bearer '+token} if token else {}
        with urlopen(Request(base+path,headers=headers,method=method),timeout=15) as r:return json.load(r)
    path='/api/forecast/hourly?latitude=-6.2297&longitude=106.8295'
    try:
        request(args.base_url,path)
        raise AssertionError('Forecast must require authentication')
    except HTTPError as error:
        assert error.code==401
    prefs=json.loads((Path.home()/'.local/share/com.example.supra_mobile_ui/shared_preferences.json').read_text())
    session=next(json.loads(v) for k,v in prefs.items() if k.endswith('-auth-token'))
    token=session['access_token']
    forecast=request(args.base_url,path,token)
    assert forecast['framework']=='PyTorch' and 1<=len(forecast['hourly'])<=12
    assert all(0<=h['rain_probability']<=1 and h['traffic_density'] is None for h in forecast['hourly'])
    news=request(args.python_url,'/v1/news')
    now=dt.datetime.now(dt.timezone.utc)
    assert all(i['source_name']=='ANTARA' and i['source_url'].startswith('https://') and
               now-dt.timedelta(hours=48)<=dt.datetime.fromisoformat(i['published_at'])<=now+dt.timedelta(minutes=5) for i in news)
    result={'model_id':forecast['model_id'],'input_through':forecast['input_through'],
            'forecast_hours':len(forecast['hourly']),'model_validation':forecast['validation'],
            'current_publisher_reports':len(news),'latest_publication':news[0]['published_at'] if news else None}
    if args.evaluate:
        result['evaluation']=request(args.base_url,'/api/alerts/evaluate',token,'POST')
        for _ in range(8):
            items=request(args.base_url,'/api/notifications',token)
            count=sum((i.get('context') or {}).get('source_name')=='ANTARA' for i in items)
            if count:break
            time.sleep(1)
        result['publisher_inbox_count']=count
    print(json.dumps(result,indent=2))
if __name__=='__main__':
    try:main()
    except HTTPError as error:
        print(f'HTTP {error.code}: check running services and sign in through the demo app. No credentials were printed.')
        raise SystemExit(1)
    except (OSError,ValueError,StopIteration,KeyError,AssertionError) as error:
        print(f'Live check failed ({type(error).__name__}); verify the app session and intelligence providers.')
        raise SystemExit(1)
