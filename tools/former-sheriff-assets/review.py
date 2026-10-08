"""Build a local, read-only review from current formula and baked asset outputs."""
from lxml import etree as E
import argparse
import hashlib
import html
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
report = json.loads((ROOT/'tmp/former-sheriff-integration/balance-report.json').read_text('utf8'))
acquisition = json.loads((ROOT/'tmp/former-sheriff-integration/acquisition-report.json').read_text('utf8'))
for source, digest in acquisition['sourceDigests'].items():
    assert hashlib.sha256((ROOT/source).read_bytes()).hexdigest() == digest, 'Acquisition report is stale: '+source
manifest = json.loads((ROOT/'launcher/web/assets/dressup/manifest.json').read_text('utf8'))
gun = manifest['skinKeys']['枪-长枪-Codex-特勤霰弹枪']
assert gun['export'].get('hiddenOnLoadCount') == 1, 'Flashlight must be off in the static preview'
shutil.copy2(ROOT/'launcher/web/assets/dressup'/gun['export']['uri'], args.output/'shotgun-light-off.png')
shutil.copy2(ROOT/'tmp/former-sheriff-integration/player-published-fit.png', args.output/'player-published-fit.png')
shutil.copy2(ROOT/'tmp/former-sheriff-integration/balance-report.json', args.output/'balance-report.json')
shutil.copy2(ROOT/'tmp/former-sheriff-integration/acquisition-report.json', args.output/'acquisition-report.json')
frames = sorted((ROOT/'tmp/former-sheriff-integration/r30-published-frames').rglob('*.png'),
                key=lambda p: int(p.stem))
assert len(frames) == 15, 'Need all 15 frames read back from the published SWF'
(args.output/'baton-frames').mkdir(exist_ok=True)
for i, frame in enumerate(frames):
    shutil.copy2(frame, args.output/'baton-frames'/f'{i+1:02d}.png')
rows = []
for item in report['armors'] + report['guns'] + [report['melee']]:
    d = item['data']
    if 'hp' in d:
        stats = f"生命 +{d['hp']} · 魔法 +{d['mp']} · 伤害 +{d['damage']} · 防御 {d['defence']}"
        note = f"重量 {d['weight']}"
    elif item['name'] == '特勤警棍':
        stats, note = "棍形：锋利度 220／防御 +165；刃形：锋利度 330", '持用时按 Q 切换'
    else:
        f = item['fixed']
        stats = f"威力 {d['power']} · {f['magSize']} 发 · 间隔 {f['shootInterval']} ms"
        note = '镇暴射线，四项内置，无插件槽' if item['name'] == '特勤霰弹枪' else '单持基础430，长枪加成；双持每把550'
    rows.append(f"<tr><th>{html.escape(item['name'])}</th><td>{stats}</td><td>{item['price']:,}</td><td>{note}</td></tr>")
cost_rows = []
for recipe in acquisition['rows']:
    materials = '、'.join(html.escape(m['name'])+' ×'+str(m['quantity']) for m in recipe['materials'])
    location = '防具合成' if recipe['category'] == '公社防具' else '铁枪会 · 覆写锻炉'
    cost_rows.append(f"<tr><th>{html.escape(recipe['name'])}<br><small>{location}</small></th><td>{materials}</td><td>{recipe['price']:,}</td>"
                     f"<td>{recipe['currentCost']:,.0f} / {recipe['weightedCost']:,.0f}</td><td>{recipe['residual']:+.2%}</td>"
                     f"<td>{recipe['retailTotal']:,}</td></tr>")
lore = []
for spec in report['armors'] + report['guns'] + [report['melee']]:
    item = next(e for e in E.parse(str(ROOT/spec['file'])).getroot().findall('item') if e.findtext('name') == spec['name'])
    lore.append('<article><h3>'+html.escape(spec['name'])+'</h3><p>'+html.escape(item.findtext('description'))+'</p></article>')
page = '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>重装特勤 · 合成与供货配置</title>
<style>
:root{font-family:"Microsoft YaHei",sans-serif;color:#273d49;background:#e8e5de}
body{max-width:1440px;margin:auto;padding:32px}h1{font-size:34px;margin:0 0 12px}
h2{font-size:24px;margin:0 0 16px}p,li{line-height:1.9}section{background:#faf9f5;border:1px solid #d0d0c7;border-radius:16px;padding:26px;margin:24px 0}
.tags{display:flex;gap:10px;flex-wrap:wrap}.tag{background:#315c60;color:white;padding:7px 16px;border-radius:24px}
.scroll{overflow:auto}table{width:100%;border-collapse:collapse;min-width:780px}th,td{padding:15px 12px;text-align:left;border-bottom:1px solid #d9ddd7}thead{background:#eef0e9}tbody th{font-weight:600}
.gun{width:min(1060px,100%);display:block;margin:24px auto}.wide{display:block;width:100%}.note{border-left:4px solid #66888b;padding-left:16px;color:#4f656a}
.columns{display:grid;grid-template-columns:1fr 1fr;gap:28px}a{color:#326b79}small{color:#66767b}
.motion{display:flex;align-items:center;gap:42px;flex-wrap:wrap}.motion img{height:390px;object-fit:contain;min-width:220px;background:#eeeee7;border-radius:12px;padding:20px}.controls{flex:1;min-width:240px}button{font:inherit;background:#315c60;color:white;border:0;border-radius:9px;padding:13px 22px;cursor:pointer}input[type=range]{width:100%;margin:24px 0}output{display:block;line-height:1.9}
@media(max-width:760px){body{padding:16px}section{padding:18px}h1{font-size:27px}.columns{grid-template-columns:1fr}}
</style></head><body>
<h1>重装特勤 · 合成与供货配置</h1>
<p>五件防具在第一防线“防具合成”制作；三件武器在铁枪会“覆写锻炉”制作。前治安官供应前置装备与所需材料。</p>
<div class="tags"><span class="tag">全部 21 级</span><span class="tag">高价 1 ＋ 合成 1</span><span class="tag">防具5条／铁枪会3条</span><span class="tag">材料与工费保持</span></div>
<section><h2>合成清单</h2><p>工费是交给合成台的金币；总折算成本包含工费和材料，并按公式折算旧装备。最右栏是假设全部材料新买时的支出，未计技能优惠。</p>
<div class="scroll"><table><thead><tr><th>成品</th><th>消耗材料</th><th>金币工费</th><th>总折算成本 / 目标</th><th>偏差</th><th>全采购支出</th></tr></thead><tbody>COST_ROWS</tbody></table></div>
<p>五件防具消耗对应部位的特战套。普通沙鹰作为升级前置，不要求39级改装版；霰弹枪消耗四个完整插件，完成后仍无可拆卸插件槽。</p>
<p class="note">本套防具无成品购买途径，按工作簿采用0.5种类系数，目标每件33,600；两把枪按穿刺类2核算。物品标价取消购买专属高价层，战斗面板保持。</p>
<p>基地与第一防线的前治安官共用同一供货目录。铁枪会“覆写锻炉”沿用铁枪图腾1级的入口条件；需要重新加载游戏数据后检查实际入口。</p></section>
<section><h2>警棍 ⇄ 匕首</h2><div class="motion"><img id="baton" src="baton-frames/01.png" alt="已发布素材的警棍变形逐帧预览"><div class="controls">
<p>侧柄沿固定转轴收进根部罩壳，再收叠棍身并露出刃面；主握点保持不动。棍棒／短兵动作类型跟随形态切换。</p>
<button id="toggle" type="button">Q · 切换至匕首</button><input id="progress" type="range" min="1" max="15" value="1" aria-label="变形进度"><output id="mode"></output>
<p>持用完整棍形才获得防御加成；变形途中不叠加两种形态的优势。收纳、死亡和换装会移除加成。强化与插件仍沿原装备计算规则。</p>
<p><small>以上 15 帧从实际发布素材回读；网页供逐帧检查，游戏内沿用自己的变形按键设置。</small></p></div></div></section>
<section><h2>当前基础数值</h2><div class="scroll"><table><thead><tr><th>装备</th><th>主要属性</th><th>金币价格</th><th>说明</th></tr></thead><tbody>ROWS</tbody></table></div>
<p>防具沿特战套的属性配比；表中金币价格是物品标价，不是成品购买入口或合成工费。原霰弹基底与其余基础面板按公式拟合；霰弹枪的四项内置增强另外保留。</p>
<p class="note">沙鹰按低等级提前获得快射穿刺支付一层预算，有效伤害预算为1＋1－1。合成成本已复算，但工作簿对枪械高价层与高价合成的说明有差异，两层强度沿已定设计保留待实战审核；没有把经济配平写成全面平衡通过。</p></section>
<section><h2>霰弹枪：封闭改装</h2><img class="gun" src="shotgun-light-off.png" alt="特勤霰弹枪完整外观">
<ul><li>八门金锁镇暴弹：镇暴射线，威力350，单束，散射4，冲击参数2，子弹尺寸42。</li>
<li>战术手电：持枪照明与20点条件闪避，重量增加0.5。</li><li>矢量偏转枪盾：防御20、韧性50、精度−10、重量增加2。</li><li>汲丝虹吸匣：吸血属性3。</li></ul>
<p>最终重量8.5，8发弹容，250ms射击间隔。插件槽为0；四项已成为武器固有属性。没有电力或NOAH标签，因此没有它们的分支奖励。枪盾数值已内置，盾牌变形仍待接入。</p></section>
<section><h2>沙鹰：单持与双持</h2><div class="columns"><div><h3>单持</h3><p>基础威力430，采用长枪的枪械攻击及长枪额外倍率。枪械攻击10级、无其它增益时，每发804。</p></div><div><h3>双持</h3><p>每把基础威力550，主副手沿用普通手枪规则。同条件下，每把每发652.5。</p></div></div>
<p>单持不会同时叠加短枪倍率与手枪专属冲击连携火力。弹药、槽位和双持能力保留；强化和插件在两种配置中分别计算。</p></section>
<section><h2>守住防线，也带人回家。</h2><p>五件防具从前治安官的经历展开：点名与接应、铭牌的责任、拉起不同阵营的人、撤离路线，以及西撤的幸存者。</p><div class="columns">LORE</div></section>
<section><h2>整体穿戴</h2><a href="player-published-fit.png"><img class="wide" src="player-published-fit.png" alt="男女角色的空手、霰弹枪、沙鹰和警棍整体穿戴"></a>
<p><small>由已发布的装备图像与原战斗挂点离线装配。点击查看大图。</small></p></section>
<section><h2>验证与后续</h2><p>R32纠正三件武器的分类，核对五件防具、三件武器各在对应入口，材料与工费和R31一致。之前R30完成的114项Flash专项测试属于历史证据，本轮未改动战斗代码或美术。</p>
<p>R31数据、配方、商店目录、套装与数值同步检查通过；数值测试779项通过，物品文件往返检查102份通过，合成交易边界测试38项通过。</p>
<p class="note">R31完整界面回归未通过：两个商店测试停在提示框共享约束，合成测试停在既有返回按钮。相关测试与界面代码和仓库基线一致，使用的测试配方也不是本次新增内容。R32没有改动这些界面，不能据此声明实际交易与合成已验收。</p>
<p>盾牌变形仍待接入。真实游戏重新加载后的购买、合成、战斗与存档重载需要另行验收；本页不代表这些操作已实测。</p></section>
<script>
const picture=document.getElementById('baton'),range=document.getElementById('progress'),label=document.getElementById('mode'),button=document.getElementById('toggle');
let f=1,goal=1,timer=null;
function draw(){picture.src='baton-frames/'+String(f).padStart(2,'0')+'.png';range.value=f;label.textContent='第 '+f+' / 15 帧 · '+(f===1?'棍棒动作：锋利度 220 · 持用防御 +165':f===15?'短兵动作：锋利度 330 · 无额外防御':'变形途中：锋利度 220 · 无额外防御');button.textContent=goal===15?'Q · 切换至警棍':'Q · 切换至匕首';}
function toggle(){if(timer)return;goal=f===15?1:15;timer=setInterval(()=>{f+=Math.sign(goal-f);draw();if(f===goal){clearInterval(timer);timer=null;}},33);}
button.onclick=toggle;range.oninput=()=>{clearInterval(timer);timer=null;f=Number(range.value);goal=f===15?15:1;draw();};
document.addEventListener('keydown',e=>{if(e.code==='KeyQ'&&!e.repeat){e.preventDefault();toggle();}});draw();
</script></body></html>'''.replace('COST_ROWS', ''.join(cost_rows)).replace('ROWS', ''.join(rows)).replace('LORE', ''.join(lore))
(args.output/'review.html').write_text(page, 'utf8')
print(args.output/'review.html')
