from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from urllib.parse import parse_qs
from pathlib import Path
import hashlib,argparse
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
import json,re,threading,sys

parser=argparse.ArgumentParser(description='Collect exact native CF6 RLE frames over loopback')
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--capture-set',choices=('motion','close-combat'),default='motion')
args=parser.parse_args()
out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
images=out/'rle';images.mkdir()
expected={f'r12scene-{mode}-{frame}' for mode in ('smoke','instructorLine','instructorBareLine','run','evasion','retreatBlocked') for frame in range(190,279,2)}
if args.capture_set=='close-combat':
    expected={f'r13scene-{mode}-{frame}' for mode,last in (('chargeNear',250),('instructorShieldClose',320),('instructorChargeClose',320)) for frame in range(190,last+1,2)}
inputs={'assetSha256':sha(ROOT/'flashswf/arts/new/Codex特种兵素材.swf'),
        'suiteSha256':sha(ROOT/'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6SoldierAssetTest.as'),
        'expectedImages':len(expected),'runId':None}
lock=threading.Lock()
(out/'inputs.json').write_text(json.dumps(inputs,indent=2),encoding='utf-8')
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_POST(self):
        size=int(self.headers.get('Content-Length','0'))
        if self.path!='/report' or not 0<size<4000000:self.send_error(400);return
        fields=parse_qs(self.rfile.read(size).decode('utf-8'),strict_parsing=True)
        run=fields.get('run',[''])[0];key=fields.get('key',[''])[0];data=fields.get('data',[''])[0]
        with lock:
            if not re.fullmatch('[0-9a-f]{32}',run) or key not in expected or (images/(key+'.txt')).exists():
                self.send_error(409);return
            if inputs['runId'] is None:
                inputs['runId']=run;inputs['hostSha256']=sha(ROOT/'scripts/Cf6SoldierNativeHost.swf')
                (out/'inputs.json').write_text(json.dumps(inputs,indent=2),encoding='utf-8')
            if run!=inputs['runId']:self.send_error(409);return
            if not data.startswith(f'[SOLDIER_IMAGE_BEGIN] {key} 960 430\n') or not data.endswith(f'[SOLDIER_IMAGE_END] {key}\n'):
                self.send_error(400);return
            (images/(key+'.txt')).write_text(data,encoding='utf-8')
            count=len(list(images.glob('*.txt')))
            if count%30==0:print('Native captures received',count,flush=True)
        self.send_response(200);self.send_header('Content-Type','application/x-www-form-urlencoded');self.end_headers();self.wfile.write(b'ok=1')
print('Owned native image collector: 127.0.0.1:8773',flush=True)
ThreadingHTTPServer(('127.0.0.1',8773),Handler).serve_forever()
