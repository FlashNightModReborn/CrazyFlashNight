"""Static CF6 cash/stock model. Reads live item data; never changes prices or saves."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE = HERE / 'balance-input.json'
README = HERE / 'README-budget.md'
sys.path.insert(0, str(ROOT / 'tools'))
from choice_reward_catalog import item_catalog, load as choices_catalog
from cf6_economy import validate_historical_budget

ROUTE = [f'A{i:02d}' for i in range(1, 23) if i != 21]
RULE_FILES = {
    'enhancement': 'scripts/类定义/org/flashNight/arki/item/EquipmentTuningService.as',
    'ammo': 'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponAmmoRuntime.as',
    'shop': 'scripts/逻辑系统分区/商店系统_兼容.as',
    'pickup': 'scripts/类定义/org/flashNight/arki/unit/Action/PickUp/PickUpManager.as',
    'actor': 'tools/cf6-actor-template/actor.fragment.json',
    'historicalEligibility': 'tools/cf6-roguelike-content/weapon-pools.source.json',
    'historicalRules': 'tools/cf6_economy.py',
}


def require(ok, message):
    if not ok: raise ValueError(message)


def integer(value, low=0, high=10_000_000):
    require(type(value) is int and low <= value <= high, 'invalid bounded integer')
    return value


def stone_cost(start, target, smith=0):
    integer(start, 1, 13); integer(target, start, 13); integer(smith, 0, 10)
    # Integer arithmetic exactly models floor((1 - smith*.05)*(i-1)^3 + 1).
    return sum(((20-smith)*(i-1)**3)//20 + 1 for i in range(start, target))


def source_rules():
    text = {key:(ROOT/path).read_text('utf-8-sig') for key,path in RULE_FILES.items() if key != 'actor'}
    checks = [
        ('enhancement', 'multiplier = Math.max(1 - Number(smith.等级) * 0.05, 0)'),
        ('enhancement', 'cost += Math.floor(multiplier * (i - 1) * (i - 1) * (i - 1) + 1)'),
        ('enhancement', 'String(sourceRaw.use) != String(targetRaw.use)'),
        ('enhancement', 'afterSource.level = otherLevel;'),
        ('enhancement', 'afterTarget.level = sourceLevel;'),
        ('ammo', 'Math.ceil((rounds - state.reserve) / state.capacity)'),
        ('ammo', 'state.reserve += packs * state.capacity - rounds'),
        ('shop', 'multiplySafeNonNegativeIntegers(level, 30)'),
        ('pickup', 'var 数量上限 = 50 + _root.等级 * 3000;'),
        ('pickup', '数量 = 数量上限 + random((数量 - 数量上限) / 5);'),
    ]
    for kind, needle in checks: require(needle in text[kind], 'source rule changed; review budget model: '+kind)
    convert = text['enhancement'].split('} else if (operation == "convert") {',1)[1].split('} else if (operation == "install_tier")',1)[0]
    require('materialDeltas[' not in convert and '金钱' not in convert, 'conversion fee model changed')
    return {path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in RULE_FILES.values()}


def build_report(data=None):
    data = json.loads(SOURCE.read_text('utf-8')) if data is None else copy.deepcopy(data)
    require(data['schema']=='cf6-historical-budget.v1' and data['bookId']=='cf6-sting'
            and data['routeId']=='historical', 'wrong budget scope')
    require(data['goldPickupContract']['externalReward']==0 and data['shopRules']['externalSPGoldK']==0
            and data['shopRules']['guaranteedSaleIncome']==0 and not data['shopRules']['freeSourcesCountedAsCash'], 'external or double-counted income')
    require(data['goldPickupContract']['exactCurrencyOverride'] is False, 'no exact-currency override in selected proposal')
    require(data['goldPickupContract']['a07TransitionOwner'].startswith('A07 only'), 'A07 allowance owner changed')
    items = item_catalog(); prices={}
    validate_historical_budget(data, items)
    def item(name):
        require(name in items, 'unknown budget item '+str(name)); return items[name]
    def price(name, count=1):
        integer(count); raw=item(name).findtext('price')
        require(raw is not None and raw.isdigit(), 'missing/noninteger item price '+name)
        prices[name]=int(raw); require(prices[name]>0, 'zero-price item must not become a sale budget')
        return prices[name]*count
    def weapon(name):
        row=item(name)
        require(row.findtext('type')=='武器' and row.findtext('use') in ('长枪','手枪'), 'not a gun '+name)
        ammo=row.findtext('data/clipname'); require(ammo and item(ammo).findtext('use')=='弹夹', 'gun has no valid packet '+name)
        capacity=int(row.findtext('data/capacity','0')); integer(capacity,1,100000)
        return dict(name=name,level=int(row.findtext('data/level')),use=row.findtext('use'),price=price(name),
                    ammo=ammo,ammoPrice=price(ammo),baseCapacity=capacity)
    source_hashes=source_rules()
    starting=integer(data['startingMoney']); require(starting==30000,'starting cash proposal changed')
    plans={}
    correction_cap=50+60*3000
    for key, rows in data['goldPlans'].items():
        require([r['mapId'] for r in rows]==ROUTE,'gold plan must contain the exact 21-source-map route')
        running=starting; ledger=[]
        for row in rows:
            integer(row['value']); running+=row['value']
            ledger.append(dict(mapId=row['mapId'],rawPickup=row['value'],cumulativeNominalIncome=running,
                               correctionThresholdExceeded=row['value']>correction_cap))
        require(running-starting==data['goldPickupContract']['nominalTotal']==910000,'cash budget total changed')
        plans[key]=dict(ledger=ledger,totalRawPickups=running-starting,totalNominalIncome=running)
    selected=plans[data['goldPlanForAssembly']]
    require(not any(r['correctionThresholdExceeded'] for r in selected['ledger']), 'selected single pickup crosses level-60 correction cap')
    selected_values={r['mapId']:r['rawPickup'] for r in selected['ledger']}
    require(selected_values['A18']==90000 and selected_values['A19']==180000 and selected_values['A20']==0,
            'selected late merchant timing differs from agreed proposal')
    require(selected_values['A07']==40000 and selected_values['A08']==0,'A07 allowance must be issued once without an A08 duplicate')
    nodes=data['merchantNodes']; require([n['mapId'] for n in nodes]==['A01','A08','A11','A16','A19'],'merchant timing mismatch')
    require([n['maxItemLevel'] for n in nodes]==[35,40,45,55,60],'merchant item ceiling mismatch')
    stock=[]; stock_by_map={}; shops=[]; weapon_rows={}; shop_ids=set()
    for name in data['commonShopItems']: price(name); stock.append(name)
    for node in nodes:
        require(node['shopId'] not in shop_ids,'duplicate shop identity'); shop_ids.add(node['shopId'])
        for name in node['addWeapons']:
            info=weapon(name); require(info['level']<=node['maxItemLevel'],'weapon listed before its stage: '+name)
            require(name not in stock,'duplicate cumulative weapon addition '+name)
            stock.append(name); weapon_rows[name]=info
            if info['ammo'] not in stock: stock.append(info['ammo'])
        for name in stock:
            require(int(item(name).findtext('data/level','0'))<=node['maxItemLevel'],'retained stock exceeds current ceiling')
        stock_by_map[node['mapId']]=set(stock)
        shops.append(dict(mapId=node['mapId'],maxItemLevel=node['maxItemLevel'],
                          shop=dict(schema='npc-shop.v2',shopId=node['shopId'],title=node['title'],catalog={str(i):n for i,n in enumerate(stock)})))
    require(data['shopRules']['baselineEloquenceLevel']==0 and data['shopRules']['baselineSmithLevel']==0,'baseline must not assume learned discounts')
    actor=json.loads((ROOT/RULE_FILES['actor']).read_text('utf-8-sig'))['actor']
    donor=next(e for e in actor['equipment'] if e['slot']=='长枪')
    require(donor['enhancement']==11 and item(donor['name']).findtext('use')=='长枪','initial transfer donor changed')
    require(not {'口才','铁匠'} & {s['name'] for s in actor['skills']},'initial discounts changed; re-evaluate baseline')
    cf6_pools=[p for p in choices_catalog()['pools'] if p['scope']=={'kind':'book','bookId':'cf6-sting'}]
    require(len(cf6_pools)==data['shopRules']['freeChoicePools']==5,'free choice source count changed')
    def basket(row, gun):
        info=weapon(row['ammoWeapon'] if 'ammoWeapon' in row else row['weapon'])
        integer(row['ammoPacks'],0,1000); integer(row['largeHP'],0,1000); integer(row['largeMP'],0,1000)
        target=integer(row['secondaryEnhancementTarget'],1,7)
        stones=stone_cost(1,target)
        entries=[dict(itemName=info['ammo'],quantity=row['ammoPacks'],cost=price(info['ammo'],row['ammoPacks'])),
                 dict(itemName='大HP药剂',quantity=row['largeHP'],cost=price('大HP药剂',row['largeHP'])),
                 dict(itemName='大MP药剂',quantity=row['largeMP'],cost=price('大MP药剂',row['largeMP'])),
                 dict(itemName='强化石',quantity=stones,cost=price('强化石',stones))]
        if gun:
            require(item(gun).findtext('use')=='长枪','primary route must buy one long gun, not one half of a pistol pair')
            entries.insert(0,dict(itemName=gun,quantity=1,cost=price(gun)))
        require(all(e['itemName'] in stock_by_map[row['mapId']] for e in entries),'basket contains a missing shop item')
        return dict(entries=entries,total=sum(e['cost'] for e in entries),
                    purchasedBaseCapacityRounds=row['ammoPacks']*info['baseCapacity'],ammoInfo=info,
                    optionalSecondaryStones=stones,primaryEnhancementSwapCash=0)
    require([r['mapId'] for r in data['shoppingRoute']]==[n['mapId'] for n in nodes],'route and merchant timing differ')
    nominal={r['mapId']:r['cumulativeNominalIncome'] for r in selected['ledger']}
    route=[]; spent=0; before_spending={}
    for row in data['shoppingRoute']:
        purchase=basket(row,row['purchaseWeapon']); available=nominal[row['mapId']]-spent
        before_spending[row['mapId']]=available
        require(purchase['total']<=available,'candidate conservative shopping route exceeds cash at '+row['mapId'])
        spent+=purchase['total']
        route.append(dict(mapId=row['mapId'],purchaseWeapon=row['purchaseWeapon'],nominalIncome=nominal[row['mapId']],
                          cashBefore=available,cashAfter=nominal[row['mapId']]-spent,**purchase))
    stress=[]
    for row in data['stressPurchases']:
        purchase=basket(row,row['weapon']);available=before_spending[row['mapId']]
        stress.append(dict(mapId=row['mapId'],weapon=row['weapon'],total=purchase['total'],
                           nominalGrossIncome=nominal[row['mapId']],cashAfterEarlierRoute=available,
                           grossIncomeShortfall=max(0,purchase['total']-nominal[row['mapId']]),
                           routeCashShortfall=max(0,purchase['total']-available),ammoInfo=purchase['ammoInfo']))
    first_alternative=price('M4A1科技白')+price('突击步枪通用弹药',12)+price('大HP药剂',3)+price('普通mp药剂',10)+price('强化石',3)
    final_map=nodes[-1]['mapId'];final_index=ROUTE.index(final_map)
    for plan in plans.values():
        plan['rawCashAfterLastMerchant']=sum(r['rawPickup'] for r in plan['ledger'][final_index+1:])
    item_source_files=[]
    for entry in ET.parse(ROOT/'data/items/list.xml').findall('items'):
        path=ROOT/'data/items'/entry.text
        if path.is_file() and any(node.findtext('name') in prices for node in ET.parse(path).findall('item')):
            relative=path.relative_to(ROOT).as_posix();item_source_files.append(relative)
            source_hashes[relative]=hashlib.sha256(path.read_bytes()).hexdigest()
    return dict(schema='cf6-historical-budget-report.v1',status=data['status'],bookId=data['bookId'],routeId=data['routeId'],
                selectedGoldPlan=data['goldPlanForAssembly'],startingMoney=starting,plans=plans,shops=shops,
                goldPickups=[dict(mapId=r['mapId'],Name='金币',Value=r['rawPickup']) for r in selected['ledger'] if r['rawPickup']>0],
                correctionThreshold=correction_cap,guaranteedSales=0,freeChoiceCash=0,externalRewards=0,
                route=route,totalShoppingCost=spent,finalNominalBalance=selected['totalNominalIncome']-spent,
                stress=stress,weaponPrices=list(weapon_rows.values()),itemPrices=prices,
                initialTransferDonor=donor,firstNodeAlternativeCost=first_alternative,
                enhancement=[dict(target=t,stones=stone_cost(1,t),gold=price('强化石',stone_cost(1,t)),
                                  smith10Stones=stone_cost(1,t,10)) for t in (3,5,7,11)],
                sourceHashes=source_hashes,itemSourceFiles=item_source_files,boundaries=data['modelBoundaries'])


def markdown(report):
    f=lambda n:f'{n:,}'
    lines=['# CF6 史实线首版金币候选账本','',
           '**状态：未平衡候选；静态可购买性通过，实际拾取、存盘、武器与生存体验未验收。**','',
           '编辑源为 [balance-input.json](balance-input.json)，运行 `python tools/cf6-prototype/economy-budget.py --write-readme` 更新本文，`--check` 校验输入、现役价格和正文；`--json` 输出供装配读取的纯数据。工具只读物品与源码，不修改价格、AS2、源片段或存档。','',
           '## 选定投放与消费者','',
           '起始 30,000，加 910,000 原始金币 Pickup，总名义预算 **940,000**。A18=90,000、A19=180,000、A20=0；把原 A20 的 110,000 分别前移 20,000/90,000，在最后商人之前取得。原提案保留在 `goldPlans.requested`，装配选 `beforeFinalMerchant`。','',
           '每个非零节点仅一堆 `Name=金币` 原生 Pickup，落于已验证 PlayerX/PlayerY；零值不生成（创建器会把非正数量改为 1）。不把钱放到精英掉落中，也不引入精确货币参数特例。A07 车战恢复后，原移到 A08 的 40,000 回到 A07，A08 配给归零；车辆服务不直接发钱，总预算不变。','',
           '现役金钱在非 Easy 下的单堆修正阈值是 `50 + 等级×3000`，60级为 **180,050**；初装设置 difficultyMode=0，不能把关卡难度文案“简单”当成 Easy 模式。曾考虑 A19 单堆 200,000，但它会进入 `180050 + random((200000-180050)/5)`，所以未选用。选定各堆未越阈值，仍不把 Value 或本表当作实际入账回执。','',
           '| 图 | 原始金币 | 累计名义现金（未扣消费） |','| --- | ---: | ---: |']
    for row in report['plans'][report['selectedGoldPlan']]['ledger']:
        lines.append(f"| {row['mapId']} | {f(row['rawPickup'])} | {f(row['cumulativeNominalIncome'])} |")
    lines += ['', '## 商人时机与目录', '',
              '采用 A01（35）、A08（40）、A11（45）、A16（55）、A19（60）。A01 能用本图 15,000 后再购物；若把首商人前移到教学，则只有初始 30,000，必须重新核首购。后档保留前档商品，每把枪都带其真实 clipname 弹药，不提前在 A11 上架50—55级枪。技能学习目录仍由章节内容装配，本文件只给商品目录。','',
              '下表是预算输入派生的基础目录；章节装配器还会为已经投放的免费枪补齐真实弹药，最终商品项数以生成的NPC目录为准，不把基础目录的计数当成装配完成计数。','',
              '史实目录仅纳入年代白名单；M4A1科技白、SPAS12、PKM战术版及量子能量枪提供现价下的路线选择，不修改共享价格。昂贵枪仍可作为储蓄/卖装/口才路线，不能声称每阶段都买得起。统合后期、钛合金61配套和年代不明的特殊型号保留为未来资料，本轮不进入史实商店。','',
              '| 商人图 | 装备等级上限 | 累计商品数 |','| --- | ---: | ---: |']
    for node in report['shops']: lines.append(f"| {node['mapId']} | {node['maxItemLevel']} | {len(node['shop']['catalog'])} |")
    lines += ['', '## 可购买路线（不计任何出售或免费配给折现）','',
              '下表按口才0、铁匠0、原价计算。第一段保留已有 M4A1战术版#11；以后各商人购买一把长枪，并给出弹药、大HP/大MP和一份可选副武器1→5强化石储备。每堆药与弹药是否足够应按实战消耗复核，此表只证明现金和商品引用能闭合。五个免费自选包、随机枪、精英枪与免费弹药均不记收入，也不抵扣下表；卖出后只能按真实回款记一次。','',
              '| 节点 | 买枪 | 本次弹药包/未改装普通弹容等价 | 大HP/大MP | 可选强化石 | 本次支出 | 购买前现金 | 购买后现金 |',
              '| --- | --- | --- | --- | ---: | ---: | ---: | ---: |']
    for row in report['route']:
        entries={e['itemName']:e for e in row['entries']};ammo=row['ammoInfo']
        lines.append(f"| {row['mapId']} | {row['purchaseWeapon'] or '沿用初装'} | {entries[ammo['ammo']]['quantity']}包 / {f(row['purchasedBaseCapacityRounds'])}发 | {entries['大HP药剂']['quantity']}/{entries['大MP药剂']['quantity']} | {row['optionalSecondaryStones']} | {f(row['total'])} | {f(row['cashBefore'])} | {f(row['cashAfter'])} |")
    lines += ['',f"该路线总支出 **{f(report['totalShoppingCost'])}**，名义结余 **{f(report['finalNominalBalance'])}**；尚未分配的现金可供技能、额外药弹或其他装备，不能自动算成已支付。原提案有110,000到最后商人之后才到手，选定时序方案为0。",'',
              f"如首节点一定要买35级替代枪：M4A1科技白 + 12包通用步枪弹 + 3大HP + 10普通MP + 3强化石，原价 **{f(report['firstNodeAlternativeCost'])}**，45,000中只余{f(45000-report['firstNodeAlternativeCost'])}；恢复储备显著缩水，因此推荐首段用初装。",'',
              '## 贵枪缺口与弹药包装', '',
              '| 节点/目标 | 枪+对应弹药+恢复+有限强化 | 不扣此前消费的名义总额 | 即使不扣前购仍缺 | 按上述前段消费后的缺口 |',
              '| --- | ---: | ---: | ---: | ---: |']
    for row in report['stress']:
        lines.append(f"| {row['mapId']} {row['weapon']} | {f(row['total'])} | {f(row['nominalGrossIncome'])} | {f(row['grossIncomeShortfall'])} | {f(row['routeCashShortfall'])} |")
    lines += ['', '因此94万支持按上述数量预算的购装与补给，不支持把各档昂贵主武器全部购买一遍。若章节最终提供M60E3/AA12等有限免费来源，可相应减少购买需求；本账没有预支其收益，也不能把免费留用和再出售同时当作两份保证购买力。','',
              '| 枪械 | 等级/槽位 | 枪价 | 弹药 | 每包价格 | XML普通弹容 |','| --- | --- | ---: | --- | ---: | ---: |']
    for w in report['weaponPrices']: lines.append(f"| {w['name']} | {w['level']}/{w['use']} | {f(w['price'])} | {w['ammo']} | {f(w['ammoPrice'])} | {f(w['baseCapacity'])} |")
    lines += ['', 'WeaponAmmoRuntime 用当前普通弹容折算一包，不是“一包一发”：一次付费拆包把 `packs×capacity` 放入余额，再按装填取用。上表只用未改装XML弹容换算，不把额外留膛/超装算成免费包容量，也不把满级枪械师回收、初始装填或免费弹药计入保证预算。火箭/能量枪与大弹仓机枪的持续弹费差异很大；价低不等于已通过火力/经济平衡。','',
              '大HP、MP均2,500一份，各基础恢复1,500（炼金与实际角色能力另验）；技能点1,500、K点50、强化石300，均沿原生商品链，仅限本局。口才启用时购买倍率为 `(1000−等级×30)/1000` 后向下取整，10级为七折；学习成本和取得时机未计入基准，因此不预支折扣。','',
              '## 强化转移与有限强化','',
              '现役 EquipmentTuningService 的 convert 对相同 use 的装备**交换强化等级**，背包↔背包或已穿戴↔背包均有入口；该分支不扣金币/强化石。初始 M4A1战术版#11 可以手动交换到一把后得长枪#1，原枪回到#1；不会同时得到两把#11，不会自动转移插件，也不应给每次换枪重复记1→11成本。是否实际操作成功仍走现役交易与未知结果恢复。','',
              '| 从1升至 | 无铁匠强化石 | 按300折合金币 | 铁匠10级强化石（不预先假定取得） |','| --- | ---: | ---: | ---: |']
    for e in report['enhancement']: lines.append(f"| {e['target']} | {f(e['stones'])} | {f(e['gold'])} | {f(e['smith10Stones'])} |")
    lines += ['', '每步成本为 `floor(max(1−铁匠等级×0.05,0)×(当前强化度−1)^3+1)`。当前临时角色新任务进度0对应普通提升上限7；10级铁匠可增到8，1→11这里只是价格对照，不是本局允许直接升到11。已有#11通过convert互换不走enhance上限检查。基准仅购买5份各40石的可选副武器储备，总200石，不复制初装强化。','',
              '## 装配与验证边界','',
              '`build_report()` 返回选定 `goldPickups`（只含正值，字段mapId/Name/Value）和 `shops`（mapId/maxItemLevel/shop，shop为完整npc-shop.v2且已累计旧商品）。根装配器负责合法坐标、NPC技能目录、XML注册、唯一投送和当前地图碰撞。`--self-test` 检查遗漏/重复地图、越阶段商品、预算不足、外部奖励与公式漂移等静态失败，不能替代游戏。','',
              '待实机：逐节点记录拾取前后金币、每次购买扣款与材料变化、弹药包消耗、转换后的两件装备、药剂实效、未花预算及失败原因。无真实存档试写，不改变持久写恢复，不提前授权61线预算。','',
              '源码依据：','']
    for key,path in RULE_FILES.items(): lines.append(f'- [{key}]({"../../"+path})：当前源SHA-256 `{report["sourceHashes"][path]}`。')
    lines += ['', '现价、弹药类型、普通弹容与药效来自以下运行XML；其SHA-256另包含在 `--json` 的sourceHashes中：','']
    for path in report['itemSourceFiles']: lines.append(f'- [{Path(path).name}](../../{path})')
    lines.append('')
    return '\n'.join(lines)


def self_test():
    base=json.loads(SOURCE.read_text('utf-8')); report=build_report(base); checks=0
    require(report['totalShoppingCost']==608800 and report['finalNominalBalance']==331200,'current shopping arithmetic changed'); checks+=1
    require(stone_cost(1,5)==40 and stone_cost(1,7)==231 and stone_cost(1,11)==2035,'enhancement arithmetic failed');checks+=1
    mutations=[lambda d:d['goldPlans']['beforeFinalMerchant'].pop(),
               lambda d:d['goldPlans']['beforeFinalMerchant'][0].update(mapId='A07'),
               lambda d:d['goldPlans']['beforeFinalMerchant'][0].update(value=True),
               lambda d:d['goldPlans']['beforeFinalMerchant'][17].update(value=200000),
               lambda d:d['merchantNodes'][0]['addWeapons'].append('M60E3'),
               lambda d:d['merchantNodes'][1]['addWeapons'].append('M4A1科技白'),
               lambda d:d['shoppingRoute'][1].update(purchaseWeapon='M60E3',ammoWeapon='M60E3',ammoPacks=100),
               lambda d:d['shopRules'].update(guaranteedSaleIncome=1),
               lambda d:d['goldPickupContract'].update(exactCurrencyOverride=True),
               lambda d:d['shoppingRoute'][2].update(purchaseWeapon='钛合金P90')]
    for mutate in mutations:
        bad=copy.deepcopy(base);mutate(bad)
        try: build_report(bad)
        except ValueError: checks+=1
        else: raise AssertionError('invalid budget accepted')
    return checks


def main():
    parser=argparse.ArgumentParser(__doc__)
    parser.add_argument('--json',action='store_true');parser.add_argument('--check',action='store_true')
    parser.add_argument('--write-readme',action='store_true');parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args(); report=build_report(); rendered=markdown(report)
    if args.write_readme: README.write_text(rendered,encoding='utf-8',newline='\n')
    if args.check: require(README.is_file() and README.read_text('utf-8')==rendered,'README-budget.md stale; run --write-readme')
    if args.self_test: print('budget self-tests:',self_test(),'passed')
    if args.json: print(json.dumps(report,ensure_ascii=False,indent=2))
    else: print('CF6 budget candidate: nominal cash 940000, shopping',report['totalShoppingCost'],
                'remaining',report['finalNominalBalance'],'shops',len(report['shops']),'gold pickups',len(report['goldPickups']),'; not gameplay acceptance')

if __name__=='__main__': main()
