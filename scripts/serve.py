#!/usr/bin/env python3
"""OPEN BREACH local-only static server with compressed, revalidated assets."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from functools import partial
from urllib.parse import urlsplit, unquote
from urllib.request import urlopen
from email.utils import parsedate_to_datetime
from datetime import timezone
import argparse, json, mimetypes, os, socket, subprocess, sys, webbrowser

ROOT=Path(__file__).resolve().parents[1]
mimetypes.add_type('application/wasm','.wasm')
mimetypes.add_type('application/javascript','.js')
mimetypes.add_type('application/octet-stream','.pck')
mimetypes.add_type('font/woff2','.woff2')

class Handler(SimpleHTTPRequestHandler):
 server_version='OpenBreach/1.0'
 def __init__(self,*args,**kwargs):
  self._encoding=None
  super().__init__(*args,**kwargs)
 def end_headers(self):
  self.send_header('X-Open-Breach','1')
  self.send_header('Cache-Control','no-cache')
  self.send_header('X-Content-Type-Options','nosniff')
  self.send_header('Cross-Origin-Opener-Policy','same-origin')
  self.send_header('Cross-Origin-Resource-Policy','same-origin')
  self.send_header('Vary','Accept-Encoding')
  if self._encoding: self.send_header('Content-Encoding',self._encoding)
  super().end_headers()
 def do_GET(self):
  if urlsplit(self.path).path=='/__health':
   data=json.dumps({'app':'open-breach','status':'ready'}).encode()
   self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
  else: super().do_GET()
 def send_head(self):
  self._encoding=None
  full=Path(self.translate_path(self.path)).resolve()
  root=Path(self.directory).resolve()
  if not full.is_relative_to(root):
   self.send_error(403,'Outside served directory'); return None
  accepted={}
  for part in self.headers.get('Accept-Encoding','').lower().split(','):
   coding,*params=part.strip().split(';')
   quality=1.0
   for param in params:
    if param.strip().startswith('q='):
     try: quality=float(param.strip()[2:])
     except ValueError: quality=0.0
   accepted[coding.strip()]=quality if 0.0<=quality<=1.0 else 0.0
  if full.is_file():
   source_stat=full.stat()
   variants=[]
   for encoding,suffix in [('br','.br'),('gzip','.gz')]:
    compressed=full.with_name(full.name+suffix)
    quality=accepted.get(encoding,accepted.get('*',0.0))
    if quality>0 and compressed.is_file() and compressed.stat().st_mtime>=source_stat.st_mtime:
     variants.append((quality,encoding,compressed))
   if variants:
    _,self._encoding,compressed=max(variants,key=lambda value:value[0])
    compressed_stat=compressed.stat()
    etag='"%x-%x-%s"' % (compressed_stat.st_mtime_ns,compressed_stat.st_size,self._encoding)
    unchanged=False
    if 'If-None-Match' in self.headers:
     unchanged=any(tag.strip().removeprefix('W/') in [etag,'*'] for tag in self.headers['If-None-Match'].split(','))
    elif 'If-Modified-Since' in self.headers:
     try:
      since=parsedate_to_datetime(self.headers['If-Modified-Since'])
      if since.tzinfo is None: since=since.replace(tzinfo=timezone.utc)
      unchanged=int(source_stat.st_mtime)<=since.timestamp()
     except (ValueError,TypeError,OverflowError): pass
    self.send_response(304 if unchanged else 200)
    self.send_header('ETag',etag)
    self.send_header('Last-Modified',self.date_time_string(source_stat.st_mtime))
    if not unchanged:
     self.send_header('Content-Type',self.guess_type(str(full)))
     self.send_header('Content-Length',str(compressed_stat.st_size))
    self.end_headers()
    return None if unchanged else compressed.open('rb')
  return super().send_head()
 def list_directory(self,path):
  self.send_error(404,'No directory index'); return None

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--port',type=int,default=8080)
 parser.add_argument('--bind',default='127.0.0.1')
 parser.add_argument('--directory',type=Path,default=ROOT/'dist')
 parser.add_argument('--open',action='store_true',help='Open the game in the default browser')
 parser.add_argument('--reuse',action='store_true',help='Reuse a running OPEN BREACH server')
 parser.add_argument('--find-port',action='store_true',help='Choose next port if another app is already listening')
 args=parser.parse_args()
 if not (args.directory/'index.html').is_file():
  parser.error(f'Build not found: {args.directory}/index.html. Run npm run build first.')
 if (args.directory/'engine.wasm').is_file():
  verified=subprocess.run(['node',str(ROOT/'scripts/build_fingerprint.mjs'),'--verify-package',str(args.directory.resolve())],capture_output=True,text=True)
  if verified.returncode: parser.error(verified.stderr.strip() or 'Web package verification failed. Run npm run build.')
 for port in range(args.port,args.port+(20 if args.find_port else 1)):
  url=f'http://{args.bind}:{port}'
  if args.reuse:
   try:
    with urlopen(url+'/__health',timeout=.25) as response:
     health=json.load(response)
    if health.get('app')=='open-breach':
     print(f'OPEN BREACH is already running: {url}',flush=True)
     if args.open: webbrowser.open(url)
     return
   except (OSError,ValueError): pass
  try:
   server=ThreadingHTTPServer((args.bind,port),partial(Handler,directory=str(args.directory.resolve())))
   break
  except OSError:
   if not args.find_port: raise
 else: raise SystemExit('No free local port in the requested range.')
 print(f'OPEN BREACH · {url}\nPress Ctrl+C to stop.',flush=True)
 if args.open: webbrowser.open(url)
 try: server.serve_forever(poll_interval=.25)
 except KeyboardInterrupt: print('\nServer stopped.')
 finally: server.server_close()

if __name__=='__main__': main()
