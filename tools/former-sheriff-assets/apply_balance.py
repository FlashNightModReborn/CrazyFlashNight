"""Apply the reviewed formula report only to the eight registered sheriff items.

Run the canonical TypeScript model first. This edits no acquisition sources.
Armor plan and weapon ledger remain their family's balance authorities.
"""
from pathlib import Path
import json, re
from lxml import etree as E

ROOT=Path(__file__).resolve().parents[2]
REPORT=ROOT/'tmp/former-sheriff-integration/balance-report.json'
EVIDENCE='tools/former-sheriff-assets/README.md'
WORKBOOK='0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx'

def replace_item(path, name, edit):
    raw=path.read_bytes()
    pattern=rb'<item\b[^>]*>(?:(?!</item>)[\s\S])*?<name>'+name.encode()+rb'</name>(?:(?!</item>)[\s\S])*?</item>'
    def patch(m):
        item=E.fromstring(m.group()); edit(item); E.indent(item,space='  ')
        nl=b'\r\n' if b'\r\n' in raw else b'\n'
        return E.tostring(item,encoding='utf8',with_tail=False).replace(b'\n',nl)
    updated,n=re.subn(pattern,patch,raw); assert n==1,name
    if updated!=raw:path.write_bytes(updated)

def put(parent,key,value):
    el=parent.find(key)
    if el is None:el=E.SubElement(parent,key)
    el.text=str(value)

def append_record(path, record, identity):
    raw=path.read_bytes(); root=E.fromstring(raw)
    assert not any(identity(r) for r in root.findall('records/record')),'Record already exists; update its canonical entry'
    E.indent(record,space='  ')
    nl=b'\r\n' if b'\r\n' in raw else b'\n'
    text=E.tostring(record,encoding='utf8',with_tail=False).replace(b'\n',nl)
    assert raw.count(b'</records>')==1
    path.write_bytes(raw.replace(b'  </records>',b'    '+text+nl+b'  </records>'))

def apply():
    report=json.loads(REPORT.read_text('utf8'))
    assert report['level']==21 and report['weightLayers']==2 and report['priceLayers']==0
    specs=report['armors']+report['guns']+[report['melee']]
    for spec in specs:
        def edit(item):
            for key,value in spec['data'].items():put(item.find('data'),key,value)
            for key in spec.get('removeFields',[]):
                el=item.find('data/'+key)
                if el is not None:item.find('data').remove(el)
            put(item,'price',spec['price'])
            if spec.get('singleHand'):
                profile=item.find('singleHand')
                if profile is None:profile=E.SubElement(item,'singleHand')
                for key in ['power','attackBonusType']:put(profile,key,spec['singleHand'][key])
        replace_item(ROOT/spec['file'],spec['name'],edit)

    plan=ROOT/'tools/cf7-balance-tool/records/armor-balance-plan.xml'
    for spec in report['armors']:
        if any(r.get('itemName')==spec['name'] for r in E.parse(str(plan)).findall('records/record')):continue
        rec=E.Element('record',itemName=spec['name'],sourceFile=spec['file'],weightLayers='2',priceLayers='0',
            category=str(spec['category']),damageTypeFactor='1',adoptedGoldPrice=str(spec['price']),status='unresolved',
            note='21级；高价合成合计2层，物品标价E=0，无购买途径防具系数0.5。合成总成本按独立acquisition.ts复算，实战验收未完成。')
        budget=E.SubElement(rec,'budgetBreakdown')
        E.SubElement(budget,'entry',code='acquisition.crafting',delta='2',ruleRef='ABR-LAYER-001',evidenceRef=EVIDENCE)
        append_record(plan,rec,lambda r:r.get('itemName')==spec['name'])

    ledger=ROOT/'tools/cf7-balance-tool/records/weapon-balance-audit.xml'
    for spec in report['guns']:
        if any(r.findtext('itemName')==spec['name'] for r in E.parse(str(ledger)).findall('records/record')):continue
        f=spec['fixed'];rec=E.Element('record')
        values={'auditRef':'weapon:'+spec['name']+':data','itemName':spec['name'],'profileKey':'data',
            'dualWield':f['dualWieldFactor'],'pierce':f['pierceFactor'],'damageType':1,
            'shotgun':f['shotgunValue'],'magPrice':f['magPrice'],'weightLayers':f['extraWeightLayers'],
            'priceLayers':0,'category':spec['category'],'formula':1,'status':'unresolved','displayEligible':'false',
            'inputDigest':'fnv1a32:00000000','sourceDigest':'sha256:'+'0'*64}
        for k,v in values.items():put(rec,k,v)
        budget=E.SubElement(rec,'budgetBreakdown')
        # Keep the human-approved high-cost layer explicit and unresolved: gun
        # C26 is narrower than synthesis D33. Do not pretend it is purchase-only.
        entries=[('acquisition.unverified',1,'WBR-WL-005'),('acquisition.crafting',1,'WBR-WL-001')]
        if spec['earlyPenalty']:entries.append(('mechanic.early-unlock',-spec['earlyPenalty'],'WBR-WL-008'))
        for code,delta,rule in entries:
            entry=E.SubElement(budget,'entry')
            for k,v in {'code':code,'delta':delta,'ruleRef':rule,'evidenceRef':EVIDENCE}.items():put(entry,k,v)
        refs=E.SubElement(rec,'ruleRefs')
        for field,rule in [('dualWield','WBR-DUAL-001'),('pierce','WBR-PIERCE-001' if spec['pierce']==1 else 'WBR-PIERCE-003'),
            ('damageType','WBR-DMG-001'),('shotgun','WBR-SHOT-001' if f['shotgunValue']==1 else 'WBR-SHOT-002'),
            ('magPrice','WBR-AMMO-001'),('weightLayers','WBR-WL-001'),('category','WBR-CAT-002'),('formula','WBR-AUTH-001')]:
            ref=E.SubElement(refs,'ref')
            evidence=EVIDENCE
            if field=='category':evidence=WORKBOOK+'#装备价格!D13'
            elif field in ['pierce','damageType']:evidence='data/items/bullets_cases.xml#bullet='+('穿刺子弹' if spec['pierce']==2 else '横向联弹-普通子弹')
            elif field=='magPrice':evidence='data/items/消耗品_弹夹.xml#item='+('马格南手枪弹药' if spec['pierce']==2 else '12号霰弹弹药')+'/price='+str(f['magPrice'])
            for k,v in {'id':rule,'target':'input.'+field,'evidenceRef':evidence}.items():put(ref,k,v)
        put(rec,'note','2026-10-08维护者指定21级、高价1+合成1；E=0；合成成本按合成表成本D33的2层复算。枪械C26的购买限定与高价合成口径不同，额外1层保持unverified，不宣称通用公式全部确认。面板按averageDPS≈weightedDPS反求，弹药按现役消耗品。真实战斗尚未验收。'+
            ('保留250ms穿刺、去掉占位8%斩杀；21级保守按超前扣1层，DPS有效1层。' if spec['earlyPenalty'] else '沿XM1014普通霰弹、8发7联弹、250ms；内置手电仅照明。'))
        append_record(ledger,rec,lambda r:r.findtext('itemName')==spec['name'])

    regpath=ROOT/'tools/former-sheriff-assets/registration.json'; reg=json.loads(regpath.read_text('utf8'))
    for item in reg['items']:
        item['level']='21';item['artDonor']=item.pop('placeholderFrom',item.get('artDonor'))
    reg['armorDesignBrief']['status']='stats_and_acquisition_configured_gameplay_pending'
    reg['armorDesignBrief']['priceLayers']=0
    reg['armorDesignBrief']['category']=0.5
    reg['armorDesignBrief']['note']='2026-10-08：21级M=2，合成专属；E=0，防具无购买途径系数0.5。配方在公社防具，前置物由前治安官出售。'
    reg['balanceModel']='tools/cf7-balance-tool/models/former-sheriff/model.ts'
    reg['deferred']=[v for v in reg['deferred'] if v!='acquisition sources']
    reg['weaponDesignBrief'].update({'level':21,'weightLayers':2,'priceLayers':0,'shotgunFlashlight':'active',
        'pistolEarlyPenalty':1,'meleeModes':report['melee']['modes']})
    regpath.write_text(json.dumps(reg,ensure_ascii=False,indent=2)+'\n','utf8')
    print('Applied 8 level-21 items; existing canonical records retained; acquisition sources are maintained separately.')

if __name__=='__main__':apply()
