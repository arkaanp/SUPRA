#!/usr/bin/env python3
"""Read-only checks for saved inbox preferences and protected Delete read. Does not delete alerts."""
import json
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request,urlopen


def main():
    base='http://localhost:3000'
    for attempt in range(20):
        try:
            with urlopen(base+'/health/live',timeout=1):pass
            break
        except OSError:
            if attempt==19:raise
            time.sleep(0.5)
    for method,path in [('DELETE','/api/notifications/read'),('PUT','/api/notifications/read'),('PUT','/api/notifications/unread'),('PUT','/api/notifications/00000000-0000-0000-0000-000000000000/unread')]:
        try:
            with urlopen(Request(base+path,method=method),timeout=10):pass
            raise AssertionError('Alert mutations must require authentication')
        except HTTPError as error:assert error.code==401
    data=json.loads((Path.home()/'.local/share/com.example.supra_mobile_ui/shared_preferences.json').read_text())
    session=next(json.loads(v) for k,v in data.items() if k.endswith('-auth-token'))
    token=session['access_token'];user=session['user']['id']
    def get(path):
        with urlopen(Request(base+path,headers={'Authorization':'Bearer '+token}),timeout=12) as response:return json.load(response)
    prefs=get(f'/api/users/{user}/preferences')
    levels=['low','medium','high','critical']
    checks={}
    for name,path in [('account',f'/api/users/{user}/notifications?limit=100&news_min_severity=low'),('inbox','/api/notifications')]:
        rows=get(path)
        for item in rows:
            if item.get('source_url',''):
                assert prefs['alert_relevant_news']
                assert levels.index(item['severity'])>=levels.index(prefs['news_min_severity'])
            else:
                flag={'air':'alert_unhealthy_aqi','air_advisory':'alert_unhealthy_aqi','rain':'alert_heavy_rain','traffic':'alert_severe_traffic'}.get((item.get('context') or {}).get('rule'))
                if flag:assert prefs[flag]
        checks[name]={'visible_alerts':len(rows),'news':sum(bool(i.get('source_url')) for i in rows)}
    print(json.dumps({'delete_read_requires_auth':True,'read_state_actions_require_auth':True,'saved_news_minimum':prefs['news_min_severity'],'saved_preferences_applied':True,'checks':checks},indent=2))
if __name__=='__main__':
    try:main()
    except (OSError,ValueError,KeyError,StopIteration,AssertionError) as error:
        print(f'Alert check failed ({type(error).__name__}); check services and app sign-in.');raise SystemExit(1)
