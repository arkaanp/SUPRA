#!/usr/bin/env python3
"""Loopback-only intelligence service. Axum provides user authentication externally."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import threading
import time
from urllib.parse import parse_qs,urlparse
import torch
from inference import Forecaster
from news import latest_news

class App:
    def __init__(self):
        self.model=Forecaster();self.cache={};self.lock=threading.Lock();self.key_locks={}
        self.permits=threading.BoundedSemaphore(4)
    def cached(self,key,ttl,loader):
        with self.lock:
            key_lock=self.key_locks.setdefault(key,threading.Lock())
        with key_lock:
            with self.lock:entry=self.cache.get(key)
            if entry and time.monotonic()-entry[0]<ttl:return entry[1]
            value=loader()
            with self.lock:
                if len(self.cache)>=64:self.cache.clear()
                self.cache[key]=(time.monotonic(),value)
                # Remove idle key locks; active requests keep their own lock reference.
                if len(self.key_locks)>128:
                    self.key_locks={k:v for k,v in self.key_locks.items() if v.locked()}
            return value
    def get(self,path,query):
        if path=='/health/live':return {'status':'ok','framework':'PyTorch'}
        if path=='/v1/news':return self.cached('news',300,latest_news)
        if path=='/v1/model':
            with self.model.lock:self.model.load();return self.model.state['card']
        if path=='/v1/forecast':
            if set(query)!={'latitude','longitude'}:raise ValueError('Use latitude and longitude')
            lat=float(query['latitude'][0]);lon=float(query['longitude'][0])
            if not math.isfinite(lat) or not math.isfinite(lon) or not (-6.9<=lat<=-5.8 and 106.3<=lon<=107.3):raise ValueError('Location outside Greater Jakarta')
            return self.cached(('forecast',lat,lon,int(time.time()//3600)),600,lambda:self.model.forecast(lat,lon))
        raise KeyError('Unknown endpoint')

app=App()
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if not app.permits.acquire(blocking=False):return self.reply(503,{'error':'Service busy'})
        try:
            parsed=urlparse(self.path)
            try:value=app.get(parsed.path,parse_qs(parsed.query));self.reply(200,value)
            except KeyError:self.reply(404,{'error':'Not found'})
            except ValueError as error:self.reply(422,{'error':str(error)})
            except Exception as error:
                print(f'Request unavailable: {type(error).__name__}',flush=True)
                self.reply(503,{'error':'Provider or trained model unavailable'})
        finally:app.permits.release()
    def reply(self,status,value):
        data=json.dumps(value,allow_nan=False).encode()
        self.send_response(status);self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def log_message(self,format,*args):pass

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--port',type=int,default=8001)
    args=parser.parse_args();torch.set_num_threads(2)
    server=ThreadingHTTPServer(('127.0.0.1',args.port),Handler);server.daemon_threads=True
    print(f'Intelligence service on http://127.0.0.1:{args.port}',flush=True)
    server.serve_forever()
if __name__=='__main__':main()
