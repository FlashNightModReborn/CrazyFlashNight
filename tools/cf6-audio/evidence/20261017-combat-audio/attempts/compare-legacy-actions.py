from pathlib import Path
import collections,hashlib,json,struct,sys,zipfile
R=Path.cwd();T=R/'tmp/cf6-combat-audio-20261017';sys.path.insert(0,str(R/'tools/cf6-audio'))
from source import Source,scan
with zipfile.ZipFile(T/'legacy-before-cues.zip') as z:original=z.read('flashswf/arts/new/素材库-诺亚新敌人.swf')
p=T/'legacy-before-cues.swf'
if p.exists():assert p.read_bytes()==original
else:p.write_bytes(original)
def actions(src):
    d=src.data;b=scan.Bits(d);n=b.u(5)
    for _ in range(4):b.s(n)
    b.align();rows=[]
    def walk(start,end,owner):
        p=start;frame=1
        while p<end-1:
            h=struct.unpack_from('<H',d,p)[0];p+=2;code,size=h>>6,h&63
            if size==63:size=struct.unpack_from('<I',d,p)[0];p+=4
            if code==39:walk(p+4,p+size,struct.unpack_from('<H',d,p)[0])
            if code==12:rows.append({'owner':owner,'frame':frame,'sha256':hashlib.sha256(d[p:p+size]).hexdigest(),'bytes':size})
            p+=size
            if code==0:break
            if code==1:frame+=1
    walk(b.byte+4,len(d),0);return rows
old=Source(p);new=Source(R/'flashswf/arts/new/素材库-诺亚新敌人.swf');a=actions(old);b=actions(new)
ca=collections.Counter(r['sha256'] for r in a);cb=collections.Counter(r['sha256'] for r in b)
removed=[r for r in a if r['sha256'] in ca-cb];added=[r for r in b if r['sha256'] in cb-ca]
result={'scope':'DoAction bodies only; excludes placement records and ClipActions','oldSha256':old.sha256,'newSha256':new.sha256,
 'beforeActions':len(a),'afterActions':len(b),'removed':removed,'added':added,
 'beforeExports':old.exports,'afterExports':new.exports}
(T/'legacy-action-delta.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({k:result[k] for k in ['beforeActions','afterActions','removed','added']},ensure_ascii=False))
