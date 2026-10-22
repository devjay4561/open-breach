import importlib.util
import io
import os
from email.message import Message
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

def module(name):
 spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/f'{name}.py')
 loaded=importlib.util.module_from_spec(spec)
 spec.loader.exec_module(loaded)
 return loaded

class ReleasePipelineTest(unittest.TestCase):
 def request(self,directory,headers):
  serve=module('serve')
  class Request(serve.Handler):
   def __init__(self):
    self.directory=str(directory);self.path='/engine.wasm';self.command='GET'
    self.headers=Message()
    for key,value in headers.items(): self.headers[key]=value
    self.response=None;self.sent_headers={};self.request_version='HTTP/1.1'
    self.wfile=io.BytesIO();self._headers_buffer=[]
   def send_response(self,status,message=None): self.response=status
   def send_header(self,key,value): self.sent_headers[key]=value
   def log_message(self,*args): pass
  request=Request();body=request.send_head()
  if body:
   with body: data=body.read()
  else: data=b''
  return request.response,request.sent_headers,data

 def test_compression_negotiation_and_fallback(self):
  with tempfile.TemporaryDirectory(prefix='breach-http-') as directory:
   root=Path(directory)
   for suffix,data in [('',b'original'),('.gz',b'gzip'),('.br',b'brotli')]:
    (root/('engine.wasm'+suffix)).write_bytes(data)
   for accepted,encoding,data in [('gzip, br','br',b'brotli'),('br;q=0, gzip','gzip',b'gzip'),('br;q=0.2, gzip;q=0.9','gzip',b'gzip'),('br;q=broken, gzip','gzip',b'gzip'),('gzip;q=0, br;q=0',None,b'original'),('',None,b'original')]:
    with self.subTest(accepted=accepted):
     status,headers,body=self.request(root,{'Accept-Encoding':accepted})
     self.assertEqual(status,200);self.assertEqual(headers.get('Content-Encoding'),encoding)
     self.assertEqual(body,data);self.assertEqual(headers.get('Content-Type',headers.get('Content-type')),'application/wasm')
     self.assertEqual(headers['Vary'],'Accept-Encoding')
   (root/'engine.wasm.br').unlink()
   self.assertEqual(self.request(root,{'Accept-Encoding':'br, gzip'})[1]['Content-Encoding'],'gzip')
   os.utime(root/'engine.wasm.gz',(1,1))
   self.assertEqual(self.request(root,{'Accept-Encoding':'gzip'})[2],b'original')

 def test_compressed_assets_revalidate_and_changed_assets_reload(self):
  with tempfile.TemporaryDirectory(prefix='breach-http-cache-') as directory:
   root=Path(directory)
   for suffix in ['','.gz','.br']: (root/('engine.wasm'+suffix)).write_bytes(b'first-version')
   for encoding in ['gzip','br']:
    accepted={'Accept-Encoding':encoding}
    status,original,_=self.request(root,accepted)
    self.assertEqual(status,200)
    for conditional in [{'If-None-Match':original['ETag']},{'If-None-Match':'W/'+original['ETag']},{'If-Modified-Since':original['Last-Modified']}]:
     status,headers,body=self.request(root,{**accepted,**conditional})
     self.assertEqual(status,304);self.assertEqual(body,b'')
     self.assertEqual(headers['ETag'],original['ETag']);self.assertNotIn('Content-Length',headers)
    self.assertEqual(self.request(root,{**accepted,'If-Modified-Since':'invalid-date'})[0],200)
    self.assertEqual(self.request(root,{**accepted,'If-None-Match':'"old"','If-Modified-Since':original['Last-Modified']})[0],200)
   status,gzip,_=self.request(root,{'Accept-Encoding':'gzip'})
   self.assertEqual(self.request(root,{'Accept-Encoding':'br','If-None-Match':gzip['ETag']})[0],200)
   (root/'engine.wasm.gz').write_bytes(b'changed-version-with-a-new-size')
   status,changed,body=self.request(root,{'Accept-Encoding':'gzip','If-None-Match':gzip['ETag']})
   self.assertEqual(status,200);self.assertNotEqual(changed['ETag'],gzip['ETag'])
   self.assertEqual(body,b'changed-version-with-a-new-size')

 def test_full_suite_matches_staged_source(self):
  promote=module('promote_web')
  manifest={'schemaVersion':2,'sourceHash':'current-source'}
  report={'passed':True,'fullSuite':True,'suites':[{'name':'test_runner','passed':True}], 'fingerprint':manifest.copy()}
  promote.verify_tests(report,manifest)
  for field,value in [('fullSuite',False),('passed',False),('fingerprint',{'schemaVersion':2,'sourceHash':'previous-source'}),('fingerprint',{})]:
   with self.subTest(field=field,value=value),self.assertRaises(SystemExit):
    promote.verify_tests({**report,field:value},manifest)

 def test_font_corpus_ignores_docs_and_preserves_user_glyphs(self):
  fonts=module('subset_fonts')
  with tempfile.TemporaryDirectory(prefix='breach-font-corpus-') as directory:
   root=Path(directory)
   (root/'web').mkdir();(root/'web/app.js').write_text('한글 Runtime text')
   (root/'research').mkdir();(root/'research/audit.md').write_text('龜 unrelated research')
   (root/'game/tests').mkdir(parents=True);(root/'game/tests/fixture.gd').write_text('龍 test text')
   (root/'game/assets/fonts').mkdir(parents=True)
   shutil.copy2(ROOT/'game/assets/fonts/NotoSansKR.ttf',root/'game/assets/fonts/NotoSansKR.ttf')
   before=fonts.korean_corpus(root)
   (root/'research/audit.md').write_text('龜龍龘 unrelated expanded research')
   self.assertEqual(before,fonts.korean_corpus(root))
   self.assertTrue(set('한글 Runtime text').issubset(before))
   try:
    from fontTools.ttLib import TTFont
   except ImportError:
    self.skipTest('fonttools is unavailable; committed subsets are preserved without regeneration')
   with TTFont(root/'game/assets/fonts/NotoSansKR.ttf',lazy=True) as font:
    self.assertTrue({chr(code) for code in font.getBestCmap()}.issubset(before))

if __name__=='__main__': unittest.main()
