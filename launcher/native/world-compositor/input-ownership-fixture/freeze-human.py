"""Freeze local candidate bytes; qualification and human acceptance remain separate."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil

root=Path(__file__).resolve().parents[4]
parser=argparse.ArgumentParser()
parser.add_argument('bin',type=Path);parser.add_argument('output',type=Path)
args=parser.parse_args()
target=args.output.resolve();target.mkdir(parents=True,exist_ok=False)
binary=target/'bin';binary.mkdir()
for path in args.bin.resolve().iterdir():
    if path.is_file() and (path.suffix in ('.dll','.exe','.pdb') or path.name.endswith(('.deps.json','.runtimeconfig.json'))):shutil.copy2(path,binary/path.name)
shutil.copytree(args.bin.resolve()/'runtimes/win-x64',binary/'runtimes/win-x64')
(binary/'flash').mkdir()
for name in ('C1Bootstrap.swf','C1Island.swf'):shutil.copy2(Path(__file__).parent/name,binary/'flash'/name)
web=root/'launcher/web';entry='modules/input-island/index.html'
paths=[entry]+re.findall(r'<script\s+src="([^"]+)"',(web/entry).read_text(encoding='utf-8'))
paths+=sorted(p.relative_to(web).as_posix() for p in (web/'css').rglob('*.css'))
frozen={name:base64.b64encode((web/name).read_bytes()).decode('ascii') for name in paths}
(binary/'frozen-web.json').write_text(json.dumps(frozen,separators=(',',':')),encoding='utf-8')
manifest={'status':'UNQUALIFIED','scope':'C1 isolated read-only input candidate','files':{
    p.relative_to(target).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(target.rglob('*')) if p.is_file()}}
(target/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'candidate':str(target),'files':len(manifest['files']),'status':manifest['status']}))
