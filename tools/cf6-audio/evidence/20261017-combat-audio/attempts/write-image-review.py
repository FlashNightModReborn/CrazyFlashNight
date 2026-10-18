from pathlib import Path
import hashlib,json,re
from PIL import Image,ImageDraw,ImageFont
ROOT=Path.cwd();TMP=ROOT/'tmp/cf6-combat-audio-20261017'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
config={'headbot':('final-images-head-fixed','head-final-pass1/headbot-render','Codex大头机器人素材'),
    'elder':('final-images/elder','death-render-pass2/elder','Codex老头素材'),
    'bladebot':('final-images-blade-fixed','blade-final-pass1/bladebot-render','Codex大刀机器人素材')}
rows=[]
for family,(images,run,owner) in config.items():
    folder=TMP/run;result=json.loads((folder/'result.json').read_text('utf-8-sig'));assert result['exitCode']==0 and result['bindingsUnchanged']
    trace=(folder/'flashlog.txt').read_text('utf-8-sig');assert '[TEST_FAIL]' not in trace
    images=sorted((TMP/images).glob('*.png'));assert len(images)==8
    runid=re.findall(r'FocusedTestRunId \S+ Start: (\w+)',trace);assert len(runid)==1
    swf='flashswf/arts/new/'+owner+'.swf';before=json.loads((folder/'bindings-before.json').read_text('utf-8-sig'))
    assert next(r['sha256'] for r in before if r['path']==swf).lower()==sha(ROOT/swf)
    for p in images:rows.append({'family':family,'image':p.relative_to(TMP).as_posix(),'sha256':sha(p),
        'nativeRun':run,'runId':runid[0],'testSwfSha256':sha(folder/'TestLoader.swf'),
        'consumer':swf,'consumerSha256':sha(ROOT/swf),'agentImageInspected':True})
out=TMP/'image-review.json';assert not out.exists()
out.write_text(json.dumps({'images':rows,'nativePixelImages':24,'headbotVisibleFragments':14,
    'scope':'Native pixels inspected at fixed scale: visible body pieces, explosion alignment, mirror and final remains. Isolated body rendering does not attest in-game corpse map blitting, audio output or human aesthetic acceptance.',
    'headbotRepair':'Nine new fragment Includes were empty in the first published SWF; corrected exact DOMSymbolItem IDs and added nonempty native-pixel assertions for every fragment.',
    'bladebotRepair':'Explosion and death attack moved together to frame 32, the first torn-body atlas frame; previous frame-5 version retained as an earlier attempt.',
    'humanAcceptance':False},ensure_ascii=False,indent=2)+'\n','utf8')
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24);page=Image.new('RGB',(1200,410),(232,230,226));draw=ImageDraw.Draw(page)
keys=[('death-1','死亡开始'),('death-23','爆炸与碎裂'),('death-58','14 块机体残骸')]
preview=[]
for i,(key,label) in enumerate(keys):
    p=TMP/'final-images-head-fixed'/(key+'.png');im=Image.open(p);box=im.getbbox();assert box[0]>=100 and box[1]>=30 and box[2]<=500 and box[3]<=400
    crop=im.crop((100,30,500,400));page.paste(crop,(400*i,40),crop);draw.text((400*i+20,8),label,fill='#222222',font=font)
    preview.append({'path':p.relative_to(TMP).as_posix(),'sha256':sha(p),'crop':[100,30,500,400],'nativeScale':1})
previewPath=TMP/'head-death-preview.png';assert not previewPath.exists();page.save(previewPath)
(TMP/'head-death-preview.json').write_text(json.dumps({'sources':preview,'alphaBackground':[232,230,226],'imageSha256':sha(previewPath)},ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'images':len(rows),'humanAcceptance':False}))
