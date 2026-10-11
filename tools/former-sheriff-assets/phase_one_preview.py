"""Decode isolated Flash BitmapData trace into an honest native-frame review."""
import argparse,json,re,html
from pathlib import Path
from PIL import Image

p=argparse.ArgumentParser();p.add_argument('--trace',required=True);p.add_argument('--out',required=True);p.add_argument('--diagnostic',action='store_true');p.add_argument('--verification');args=p.parse_args()
text=Path(args.trace).read_text('utf-8-sig');out=Path(args.out);out.mkdir(parents=True,exist_ok=True)
assert args.diagnostic or 'FormerSheriffTest Tests Failed: 0' in text,'Only a passing native run can be presented as the final preview'
frames=[];current=None
for line in text.splitlines():
 m=re.match(r'\[ASSET_BITMAP_BEGIN\] (\S+) (\d+) (\d+)',line)
 if m:
  name,width,height=m.group(1),int(m.group(2)),int(m.group(3));current=Image.new('RGBA',(width,height));continue
 m=re.match(r'\[ASSET_BITMAP_ROW\] (\d+) (.*)',line)
 if m and current:
  y=int(m.group(1));row=[]
  for part in m.group(2).split(','):
   if not part:continue
   color,count=part.split(':');value=int(color,16);rgba=((value>>16)&255,(value>>8)&255,value&255,(value>>24)&255);row.extend([rgba]*int(count))
  assert len(row)==width,(name,y,len(row));current.paste(Image.frombytes('RGBA',(width,1),bytes(v for px in row for v in px)),(0,y));continue
 if line.startswith('[ASSET_BITMAP_END]') and current:
  current.save(out/(name+'.png'));frames.append(name);current=None
assert frames,'No native frames found; use the focused runner -Capture'
titles={'opening-8':'开场：兴奋剂','opening-42':'开场动作衔接','opening-88':'开场：铁布衫','far-pistol':'远距：单持手枪','medium-shotgun':'中距：霰弹枪','near-baton':'近距：警棍','roll-reload':'受击：翻滚换弹','hop':'受击：后跳','phase-two-held':'二阶段交接：脱盔持盾'}
cards=[]
helmet_frames=[name for name in frames if name.startswith('sheriff-helmet-')]
if helmet_frames:
 helmet_images=[]
 for name in helmet_frames:
  rgba=Image.open(out/(name+'.png')).convert('RGBA')
  canvas=Image.new('RGB',rgba.size,'#faf9f4');canvas.paste(rgba,(0,0),rgba);helmet_images.append(canvas)
 helmet_images[0].save(out/'helmet-landing.gif',save_all=True,append_images=helmet_images[1:],duration=170,loop=0,disposal=2)
 cards.append('<figure><img src="helmet-landing.gif"><figcaption>飞盔落地：共享碎片动画；每 5 个原生帧采样</figcaption></figure>')
titles['safe-reload']='安全空闲：切枪换弹'
for name in frames:
 if name in helmet_frames:continue
 short=name.removeprefix('sheriff-');title=titles.get(short,('转阶段 · 测试第 '+short[11:]+' 帧') if short.startswith('transition-') else '受击盾冲 · '+short)
 cards.append('<figure><img src="'+html.escape(name)+'.png"><figcaption>'+html.escape(title)+'</figcaption></figure>')
report={'evidence':'isolated native Flash runtime; real compiled SWF, actual controller/animation/buffs/reload/death; final bullet sink and rewards are spies; no live save or campaign result verification','frames':frames,'unitId':458,'checks':[x for x in text.splitlines() if x.startswith('FormerSheriffTest ')]}
(out/'native-evidence.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf8')
body=''.join(cards)
page="""<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>前治安官 · 一阶段原生验收</title><style>body{margin:0;background:#eeece5;color:#20282b;font:16px/1.65 system-ui,Microsoft YaHei,sans-serif}main{max-width:1280px;margin:auto;padding:38px 26px}h1{font-size:30px;margin:0 0 14px}p{max-width:980px}small{color:#606866}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}figure{margin:0;background:#faf9f4;border:1px solid #d9d9d2;border-radius:8px;overflow:hidden}img{display:block;width:100%;height:auto}figcaption{padding:10px 16px;background:#e2e6df}code{background:#dce2d8;padding:2px 5px}a{color:#216670}table{border-collapse:collapse;margin:18px 0}td,th{border:1px solid #c5cdc4;padding:8px 14px;text-align:left}</style><main><h1>前治安官 · R46 固定装备、血条与飞盔</h1><p>独立决策与固定装备素材：护甲、手套、战靴和武器已直接装配在 NPC 时间轴，动作切换不再运行人形换装；玩家仍使用原有换装动作。远距单持手枪、中距霰弹枪、近距警棍；安全空闲时各施放一次兴奋剂与铁布衫。受击按盾冲 → 翻滚换弹 → 小跳的条件进入专属反应。</p><p>姓名和血条沿用共享信息组件，读取原生头顶锚点并同步受伤更新缓存，避免落到脚下。头盔脱落只切到预制的露发头部帧，盾冲也使用 NPC 自己的固定装备容器。</p><p>首次归零：击倒、飞盔、起身、变盾、衔接盾冲，然后停在二阶段持盾交接状态。本轮未制作二阶段常态战斗。</p><p><strong>图像证据：</strong>以下均从修复后的 CS6 原生测试播放器采样。只移除镜头位移，保留原生注册点、装备、图层和影子。它们是关键帧，不是完整帧率录像。</p><p><strong>验证边界：</strong>隔离测试使用真实 XML、初始化器、动作、换弹、增益和死亡记录；子弹命中与奖励发放使用模拟统计；本轮场景包含正式血条素材；不接触真实存档，实际关卡仍需重新加载后体验。<a href="native-evidence.json">查看本次记录</a></p><h2>本地检验</h2><p>单位已登记为 <code>兵种458 / 敌人-前治安官</code>，可在使用本次源码与素材的本地环境中通过自定义战选择。两处商人没有改成战斗敌人。距离、冷却、独行者倍率和盾冲数值仍为首轮占位，可继续按体验调整。</p><p>重点体验：姓名与血条是否保持头顶、切换各种姿势时是否缺件、飞盔后的发型是否保持一致。此次消除的是运行时换装挂载开销，未把专项结果换算成帧率收益。玩家既有盾冲另有独立回归。</p><div class="grid">{{CARDS}}</div></main></html>"""
if args.verification:
 verification=json.loads(Path(args.verification).read_text('utf8'))
 report['verification']=verification
 summary='<p><strong>最终验证：</strong>一阶段行为 '+str(verification['npc']['passed'])+' 项、玩家盾冲 '+str(verification['playerShieldRush']['passed'])+' 项、灯光 '+str(verification['equipmentLight']['passed'])+' 项均通过，CS6 素材与逻辑编译通过。<a href="verification.json">查看完整验证记录</a> · <a href="实现与本地检验.txt">本地检验与参数说明</a></p>'
 page=page.replace('<div class="grid">',summary+'<div class="grid">')
if helmet_frames:
 page=page.replace('<h2>本地检验</h2>','<p>飞盔使用与地图碎片、人物死亡掉武器相同的 FragmentAnimator，包含反弹、摩擦及自然停止。原生回归还检查了小数地面高度与停稳后的连续 50 帧；落地动图来自对应片段的固定间隔采样。</p><h2>本地检验</h2>')
if args.diagnostic:
 page=page.replace('<main>','<main><p style="background:#ffd2a8;padding:18px"><strong>诊断快照：本轮尚未通过完整验收，不作为完成证据。</strong></p>')
 report['diagnosticOnly']=True
(out/'native-evidence.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf8')
(out/'review.html').write_text(page.replace('{{CARDS}}',body),'utf8')
print(json.dumps({'frames':len(frames),'review':str(out/'review.html')},ensure_ascii=False))
