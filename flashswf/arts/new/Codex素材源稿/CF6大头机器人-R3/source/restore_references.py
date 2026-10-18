"""Losslessly rehydrate original SVG data URIs from deduplicated package PNGs."""
from pathlib import Path
import json,re,base64,hashlib
R=Path(__file__).resolve().parents[1]
def restore():
 mapping=R/'reference/embedded-bitmap-map.json'
 if not mapping.exists():return
 m=json.loads(mapping.read_text());hashes=json.loads((R/'reference/source-svg-checksums.json').read_text());count=0
 for relative,expected in hashes.items():
  p=R/relative;s=p.read_text()
  def repl(match):
   token=match.group(1);spec=m[token];b=(R/spec['file']).read_bytes();assert hashlib.sha256(b).hexdigest()==token
   return spec['prefix']+base64.b64encode(b).decode('ascii')
  if 'cf6-bitmap://' in s:s=re.sub(r'cf6-bitmap://([a-f0-9]{64})',repl,s);p.write_text(s);count+=1
  assert hashlib.sha256(p.read_bytes()).hexdigest()==expected,('Original reference did not round-trip',relative)
 print('Original SVG references restored byte-for-byte:',count)
if __name__=='__main__':restore()
