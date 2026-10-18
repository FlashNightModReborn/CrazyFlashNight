from pathlib import Path
import json,re
from lxml import etree as E
ROOT=Path.cwd();TMP=ROOT/'tmp/cf6-combat-audio-20261017';NS={'x':'http://ns.adobe.com/xfl/2008/'}
assets={a.get('id'):a for a in E.parse(str(ROOT/'data/items/asset_source_map.xml')).getroot().iter('asset')}
rows=[]
for link in ['敌人-诺亚克隆兽','敌人-闪6特工','敌人-延寿克隆兽','敌人-完全体克隆兽']:
    a=assets[link];lib=(ROOT/a.get('swf')).with_suffix('')/'LIBRARY';pending=[a.get('symbolName')];seen=set();calls=[]
    while pending:
        name=pending.pop()
        if name in seen:continue
        seen.add(name);p=lib/(name+'.xml');tree=E.parse(str(p))
        pending.extend(n.get('libraryItemName') for n in tree.findall('.//x:DOMSymbolInstance',NS))
        for frame in tree.findall('.//x:DOMFrame',NS):
            scripts=[s.text or '' for s in frame.findall('.//x:script',NS)]
            matched=[line.strip() for text in scripts for line in text.splitlines() if re.search('播放音效|声音|音效|呐喊',line)]
            if matched:calls.append({'symbol':name,'frame':int(frame.get('index'))+1,'calls':matched})
    rows.append({'linkage':link,'source':a.get('symbolName'),'swf':a.get('swf'),'symbols':len(seen),'calls':calls})
(TMP/'legacy-site-inventory.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n','utf8')
for row in rows:
    print(row['linkage'],row['symbols'])
    for call in row['calls']:
        print(call['symbol'],call['frame'],' / '.join(call['calls'])[:600])
