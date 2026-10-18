from pathlib import Path
import subprocess,json,hashlib
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';sha=lambda b:hashlib.sha256(b).hexdigest();paths={}
for family in ('headbot','elder','bladebot','manman','wings','soldier','guard','zombie'):
 m=json.loads((R/f'tools/cf6-{family}-assets/native-manifest.json').read_text('utf-8-sig'))
 for row in m.get('buildInputs',[]):paths[row['path']]={'sha256':row['sha256'],'lineEndingNormalization':row.get('lineEndingNormalization')}
 for row in m['outputs']+m['projectFiles']:paths[m['owner']+'/'+row['path']]={'sha256':row['sha256']}
for row in json.loads((R/'tools/cf6-audio/assets.json').read_text('utf8'))['files']:paths[row['path']]={'sha256':row['sha256']}
index={}
for record in subprocess.check_output(['git','ls-files','--stage','-z']).split(b'\0'):
 if not record:continue
 meta,path=record.split(b'\t',1);mode,oid,stage=meta.decode('ascii').split();assert stage=='0';index[path.decode('utf8')]=oid
ordered=sorted(paths);assert all(p in index for p in ordered)
attrs={p:{} for p in ordered}
out=subprocess.check_output(['git','check-attr','--cached','-z','--stdin','text','eol','filter'],input=('\0'.join(ordered)+'\0').encode('utf8')).decode('utf8').split('\0')
assert out[-1]==''
for i in range(0,len(out)-1,3):attrs[out[i]][out[i+1]]=out[i+2]
oids=sorted(set(index[p] for p in ordered));raw=subprocess.check_output(['git','cat-file','--batch'],input=('\n'.join(oids)+'\n').encode('ascii'));pos=0;blobs={}
for oid in oids:
 end=raw.index(b'\n',pos);parts=raw[pos:end].decode('ascii').split();assert parts[:2]==[oid,'blob'];n=int(parts[2]);start=end+1;data=raw[start:start+n];assert raw[start+n:start+n+1]==b'\n';pos=start+n+1;blobs[oid]=data
assert pos==len(raw)
rows=[];mismatch=[];filtered=0
for p in ordered:
 at=attrs[p];b=blobs[index[p]];method='raw-index-preserved-by-attributes'
 if not (at['filter'] in ('unspecified','unset') and (at['text']=='unset' or at['eol']=='lf')):
  b=subprocess.check_output(['git','cat-file','--filters',':'+p]);method='filtered-checkout';filtered+=1
 workingRaw=(R/p).read_bytes();normalization=paths[p].get('lineEndingNormalization');assert normalization in (None,'lf');working=sha(workingRaw.replace(b'\r\n',b'\n') if normalization=='lf' else workingRaw);checkout=sha(b.replace(b'\r\n',b'\n') if normalization=='lf' else b);row={'path':p,'manifestSha256':paths[p]['sha256'],'lineEndingNormalization':normalization,'workingSha256':working,'checkoutSha256':checkout,'rawWorkingSha256':sha(workingRaw),'rawCheckoutSha256':sha(b),'attributes':at,'method':method,'matches':working==paths[p]['sha256']==checkout};rows.append(row)
 if not row['matches']:mismatch.append(row)
with (O/'staged-native-input-verification-final.json').open('x',encoding='utf8') as f:json.dump({'ok':not mismatch,'files':rows,'mismatches':mismatch,'boundary':'Raw staged blobs for byte-preserving attributes, otherwise actual git cat-file --filters output, using the current host checkout configuration. Explicit manifest LF normalization is applied only to entries declaring it; raw hashes remain recorded.'},f,ensure_ascii=False,indent=2)
print(json.dumps({'ok':not mismatch,'checked':len(rows),'filtered':filtered,'mismatches':mismatch},ensure_ascii=False))
if mismatch:raise SystemExit(1)
