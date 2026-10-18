from pathlib import Path
import zipfile,re,json
ROOT=Path(__file__).resolve().parents[2]
TMP=Path(__file__).resolve().parent
head=ROOT/'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6HeadbotRenderTest.as'
decoder=ROOT/'tools/cf6-headbot-assets/decode-native-capture.py'
with zipfile.ZipFile(TMP/'render-pass1/headbot/capture-source-before-framing.zip','x',zipfile.ZIP_DEFLATED) as z:
    for p in [head,decoder]:z.writestr(p.relative_to(ROOT).as_posix(),p.read_bytes())
s=head.read_text('utf-8-sig')
assert '(point.side==0?300:800)' in s
s=s.replace('(point.side==0?300:800)','(point.side==0?(point.state=="空手攻击"?285:300):800)')
a='        var visible:Number=0;\n        for(var y:Number=0;y<500;y+=5)for(var x:Number=0;x<1100;x+=5)if((bitmap.getPixel32(x,y)>>>24)>0)visible++;\n'
b='        var drawn:Object=bitmap.getColorBoundsRect(0xffffffff,0,false);\n        var visible:Number=drawn.width*drawn.height;\n'
assert a in s;s=s.replace(a,b,1).replace('var fullBounds:Object=bitmap.getColorBoundsRect(0xffffffff,0,false);','var fullBounds:Object=drawn;',1).replace('+" pixels="+visible','+" boundsArea="+visible')
elder=(ROOT/'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderRenderTest.as').read_text('utf-8-sig')
start=elder.index('    private static function capture(');end=elder.index('    private static function pixelHex(',start)
chunk=elder[start:end].replace('ELDER_IMAGE_','HEADBOT_IMAGE_')
start=s.index('    private static function capture(');end=s.index('    private static function pixelHex(',start)
s=s[:start]+chunk+s[end:];head.write_text(s,'utf-8-sig',newline='\n')
old=decoder.read_text('utf8');expected=re.search(r'^    expected = (\{.*\})$',old,re.M)[1]
s=(ROOT/'tools/cf6-elder-assets/decode-native-capture.py').read_text('utf8').replace('ELDER_IMAGE_','HEADBOT_IMAGE_').replace('Elder capture','Headbot capture')
s=s.replace("    parser.add_argument('--partial',", "    parser.add_argument('--fragment', action='store_true')\n    parser.add_argument('--partial',",1)
s=re.sub(r'^    expected = \{.*\}$','    expected = '+expected+'\n    if args.fragment: expected = {\'death-31\'}',s,count=1,flags=re.M)
decoder.write_text(s,'utf8',newline='\n')
plan=json.loads((TMP/'render-plan1.json').read_text('utf8'));plan['output']='render-pass2';plan['runs']=plan['runs'][:1]
(TMP/'render-plan2.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n','utf8')
(TMP/'render-only-harness-changes.json').write_text(json.dumps({'paths':[head.relative_to(ROOT).as_posix(),decoder.relative_to(ROOT).as_posix()],
 'reason':'First capture clipped the second headbot beam by about eight pixels; camera moves fifteen pixels left. Head capture uses the established chunked lossless row encoder and exact nonzero bounds to avoid costly output-panel row updates.',
 'productionResourcesChanged':False},ensure_ascii=False,indent=2)+'\n','utf8')
print('Head capture framing corrected; game resources and behavior code unchanged')
