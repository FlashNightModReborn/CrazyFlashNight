from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
for key in ['manman','wings','headbot','bladebot','elder','soldier','guard','zombie']:
 p=ROOT/f'tools/cf6-{key}-assets/build.py';s=p.read_text('utf8')
 if 'cf6_audio_native' in s:raise ValueError('Already connected '+key)
 if key=='zombie':
  s=s.replace('import hashlib\n','import hashlib\nimport importlib.util\n',1)
  marker="HERE = pathlib.Path(__file__).resolve().parent\n"
  inject="_audio_spec=importlib.util.spec_from_file_location('cf6_audio_native',ROOT/'tools/cf6-audio/build.py')\naudio=importlib.util.module_from_spec(_audio_spec)\n_audio_spec.loader.exec_module(audio)\n"
  s=s.replace(marker,marker+inject,1)
  needle="    rows = write_workspace(combined, [male_report['root'], female_report['root']])"
  s=s.replace(needle,"    audio_receipt=audio.apply(combined,OWNER,make_sparse_layer)\n"+needle,1)
 else:
  needle="native = module('manman_native', ROOT / 'tools/cf6-zombie-assets/build.py')" if key=='manman' else next(line for line in s.splitlines() if line.startswith('common = module(') or line.startswith('common=module('))
  s=s.replace(needle,"audio = module('cf6_audio_native',ROOT/'tools/cf6-audio/build.py')\n"+needle,1)
  needle=next(line for line in s.splitlines() if ('outputs' in line and 'write_workspace(' in line))
  obj='generated' if key in ('manman','wings') else 'symbols'
  s=s.replace(needle,f'    audio_receipt=audio.apply({obj},OWNER,native.make_sparse_layer)\n'+needle,1)
 needle=next(line for line in s.splitlines() if "native-manifest.json').write_text" in line)
 s=s.replace(needle,"    manifest['audio']=audio_receipt\n"+needle,1)
 pos=s.index('def check():')
 a,b=s[:pos],s[pos:]
 needle=next(line for line in b.splitlines() if 'manifest' in line and 'json.loads(' in line)
 b=b.replace(needle,needle+'\n    audio.check(manifest,OWNER)',1)
 p.write_text(a+b,'utf8',newline='\n')
 print(key)
