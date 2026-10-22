#!/usr/bin/env python3
"""Promote one verified web directory, preserve the prior build and verify served hashes."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,shutil,subprocess,uuid
ROOT=Path(__file__).resolve().parents[1]

def verify_tests(tests,manifest):
 if not tests.get('passed') or not tests.get('fullSuite') or not tests.get('suites') or not all(suite.get('passed') for suite in tests['suites']):
  raise SystemExit('A current full headless suite must pass before promotion.')
 fingerprint=tests.get('fingerprint',{})
 if fingerprint.get('schemaVersion')!=manifest.get('schemaVersion') or not fingerprint.get('sourceHash') or fingerprint.get('sourceHash')!=manifest.get('sourceHash'):
  raise SystemExit('Headless tests do not match the staged game source. Run npm test after the final changes.')

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--source',default='dist')
 p.add_argument('--live',default='build/web',help='Published directory; may be an absolute service runtime path')
 p.add_argument('--url',default='http://127.0.0.1:8080')
 p.add_argument('--report',default='tests/artifacts/deployment-report.json')
 a=p.parse_args()
 source=(ROOT/a.source).resolve();live=(ROOT/a.live).resolve()
 required=['index.html','engine.js','engine.wasm','engine.pck','app.js','i18n.js','style.css','storage.js','quality-metrics.js','debrief.js','meta.js','map-editor.js','asset-manifest.json','engine-export-manifest.json']
 for name in required:
  if not (source/name).is_file() or not (source/(name+'.gz')).is_file(): raise SystemExit('Incomplete staged build: '+name)
 if source==live: raise SystemExit('Source must be a separate staging directory')
 verified=subprocess.run(['node',str(ROOT/'scripts/build_fingerprint.mjs'),'--verify-package',str(source)],capture_output=True,text=True)
 if verified.returncode: raise SystemExit(verified.stderr.strip() or 'Staged package validation failed.')
 manifest=json.loads(verified.stdout)
 tests=json.loads((ROOT/'tests/artifacts/headless-report.json').read_text())
 verify_tests(tests,manifest)
 stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]
 ready=live.with_name(live.name+'-ready-'+stamp);backup=live.with_name(live.name+'-backup-'+stamp)
 shutil.copytree(source,ready)
 expected={name:hashlib.sha256((ready/name).read_bytes()).hexdigest() for name in required}
 previous=live.exists()
 if previous: os.replace(live,backup)
 try:
  os.replace(ready,live)
  served={}
  for name,wanted in expected.items():
   response=subprocess.run(['curl','--fail','--silent','--show-error','--compressed','--max-time','30',a.url.rstrip('/')+'/'+name],check=True,capture_output=True).stdout
   served[name]=hashlib.sha256(response).hexdigest()
   if served[name]!=wanted: raise RuntimeError('Served content differs: '+name)
 except BaseException:
  if live.exists(): os.replace(live,live.with_name(live.name+'-failed-'+stamp))
  if previous: os.replace(backup,live)
  raise
 report={'deployed_at':datetime.datetime.now().isoformat(),'url':a.url,'live':str(live),'backup':str(backup) if previous else None,'source':str(source),'sha256':expected,'served_sha256':served,'verified':True,'sourceHash':manifest['sourceHash'],'test_checks':tests['checks'],'test_suites':len(tests['suites'])}
 target=ROOT/a.report;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__': main()
