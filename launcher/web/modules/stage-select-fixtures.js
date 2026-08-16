// 选关界面 fixtures（P1-B 2026-08-16 自 stage-select-data.js 机械拆出，内容逐字节同源）。
// 职责：dev harness / qa-suite 的 fixture 选择器数据源 + 生产 bridge 失败时面板 snapshot 兜底
//   （非纯 dev：runtime bridge 挂掉时面板用 fixture 合并兜底，见 stage-select/stage-select-view-model.js snapshot 合并逻辑；
//     故 runtime 必须随面板加载，见 panels-lazy-registry.js stage-select 注册项）。
// 消费路径：StageSelectData.getFixture(name) 委托本全局（typeof 守卫，缺载语境回退空 stages）；
//   面板 / harness / qa-suite 均不直接引用本全局。map 闭包只载 data 不载 fixtures（不调 getFixture）。
// 形态：与 stage-select-data.js 相同的纯 script 全局（无 IIFE），保证 vm.runInContext 沙箱可读。
var StageSelectFixtures = {
    "allUnlocked": {
        "name": "allUnlocked",
        "challenge": false,
        "stages": {
            "被摧毁的武器仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "被攻击的黑铁会": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "被清扫的虫洞": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "被偷袭的基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "被炸毁的防御地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "被终结者占领的诺亚前线基地兵工厂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "冰雪之心": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "补给仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "残垣断壁": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "超市废墟": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "虫洞": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "虫洞洞口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "虫洞内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "虫洞入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "虫洞外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "初心者": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "大学城周边": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "地铁站": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "地铁站隧道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "第三集结点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "第一防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "电子战接入设备间": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "堕落城保卫战": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "堕落城区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "堕落城深处": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "堕落城下水道入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "二级防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "防御地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船储备舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船繁殖舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船监视点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船控制舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船燃料舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船推进舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船武器舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船休息舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "菲尼克斯Lv10": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "菲尼克斯Lv16": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "废城环线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "废墟武器店": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "革命军哨所": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "关口小道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "核电站": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会翅虎堂内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会翅虎堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会黑龙堂内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会黑龙堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会火凤堂内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会火凤堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会总部边缘": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会总堂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会总堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "基地禁区边缘地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "集结点A": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "集结点B": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "集结点C": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "僵尸卫队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "交战热点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "郊区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "解救A兵团士兵": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "禁区边缘": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "锯刺陷阱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "决战之地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "军队据点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "军阀据点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "军阀临时补给点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "军阀秘密基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "军阀前线基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "军团驻地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "绿洲深处": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "绿洲外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "秘密通道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "难民营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "闹市区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚精英部队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚前线基地兵工厂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚前线基地哨岗": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚雪山": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚雪山部队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚雪山山顶": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚雪山山脊": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚雪山山脚": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "盆地入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "贫民窟": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "熔岩广场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "熔岩基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "熔岩基地外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "熔岩秘洞": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "熔岩隧道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "熔岩营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "三级防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "山洞入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "商业区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "哨兵据点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "深入禁区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "尸母巢穴": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "试炼场深处入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "试验场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "隧道入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "铁血临时营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "铁血营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "同盟卸货站": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-第一防线防区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-堕落城酒吧": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-堕落城商业街": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-黑铁会修炼场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-军阀": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-联合大学": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-摇滚公园": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "温泉关口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "武器仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "锡蒙利Lv10": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "锡蒙利Lv16": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "袭杀与圈套": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "新手练习场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "幸存者营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "雪地平原": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "雪山入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "雪原防御带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "雪原基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "雪原坡地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "雪原深处": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "训练场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "压制摇滚公园": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "研究院": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "摇滚公园": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "摇滚内战": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "一级防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "医院": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "游寇基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "指挥部大厅": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "指挥部外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "指挥营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的被摧毁的武器仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的防御地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的秘密通道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的诺亚精英部队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的诺亚雪山山顶": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的诺亚雪山山脚": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的熔岩广场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的熔岩基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的熔岩隧道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的武器仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的雪地平原": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的雪山入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的研究院": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的指挥部大厅": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船储备舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船控制舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船燃料舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船推进舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船武器舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船休息舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "自来水厂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "A兵团试炼场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "DEATH MATCH角斗场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "DEATH MATCH入门赛": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            }
        }
    },
    "mixed": {
        "name": "mixed",
        "challenge": false,
        "stages": {
            "被摧毁的武器仓库": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "被攻击的黑铁会": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "被清扫的虫洞": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "被偷袭的基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "被炸毁的防御地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "被终结者占领的诺亚前线基地兵工厂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "冰雪之心": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "补给仓库": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "残垣断壁": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "超市废墟": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "虫洞": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "虫洞洞口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "虫洞内部": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "虫洞入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "虫洞外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "初心者": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "大学城周边": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "地铁站": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "地铁站隧道": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "第三集结点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "第一防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "电子战接入设备间": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "堕落城保卫战": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "堕落城区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "堕落城深处": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "堕落城下水道入口": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "二级防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "防御地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "飞船储备舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船繁殖舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "飞船监视点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船控制舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船燃料舱": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "飞船入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "飞船推进舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "飞船武器舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "飞船休息舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "菲尼克斯Lv10": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "菲尼克斯Lv16": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "废城环线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "废墟武器店": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "革命军哨所": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "关口小道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "核电站": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "黑铁会": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会翅虎堂内部": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会翅虎堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "黑铁会黑龙堂内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会黑龙堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "黑铁会火凤堂内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "黑铁会火凤堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "黑铁会总部边缘": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "黑铁会总堂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "黑铁会总堂外围": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "基地禁区边缘地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "集结点A": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "集结点B": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "集结点C": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "僵尸卫队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "交战热点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "郊区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "解救A兵团士兵": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "禁区边缘": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "锯刺陷阱": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "决战之地": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "军队据点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "军阀据点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "军阀临时补给点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "军阀秘密基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "军阀前线基地": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "军团驻地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "绿洲深处": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "绿洲外围": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "秘密通道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "难民营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "闹市区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚精英部队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "诺亚前线基地兵工厂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚前线基地哨岗": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "诺亚雪山": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "诺亚雪山部队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "诺亚雪山山顶": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚雪山山脊": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "诺亚雪山山脚": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "盆地入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "贫民窟": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "熔岩广场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "熔岩基地": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "熔岩基地外围": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "熔岩秘洞": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "熔岩隧道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "熔岩营地": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "三级防线": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "山洞入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "商业区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "哨兵据点": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "深入禁区": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "尸母巢穴": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "试炼场深处入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "试验场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "隧道入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "铁血临时营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "铁血营地": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "同盟卸货站": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-第一防线防区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "外交-堕落城酒吧": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-堕落城商业街": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-黑铁会修炼场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-军阀": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-联合大学": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "外交-摇滚公园": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "温泉关口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "武器仓库": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "锡蒙利Lv10": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "锡蒙利Lv16": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "袭杀与圈套": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "新手练习场": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "幸存者营地": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "雪地平原": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "雪山入口": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "雪原防御带": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "雪原基地": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "雪原坡地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "雪原深处": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "训练场": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "压制摇滚公园": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "研究院": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "摇滚公园": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "摇滚内战": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "一级防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "医院": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "游寇基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "指挥部大厅": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "指挥部外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "指挥营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的被摧毁的武器仓库": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的防御地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的秘密通道": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "终结者占领的诺亚精英部队": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "终结者占领的诺亚雪山山顶": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的诺亚雪山山脚": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "终结者占领的熔岩广场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的熔岩基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的熔岩隧道": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "终结者占领的武器仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "终结者占领的雪地平原": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的雪山入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "终结者占领的研究院": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "终结者占领的指挥部大厅": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船储备舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船控制舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "坠毁的飞船燃料舱": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "坠毁的飞船入口": {
                "unlocked": false,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船推进舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "坠毁的飞船外围": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "修罗",
                "detail": ""
            },
            "坠毁的飞船武器舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "冒险",
                "detail": ""
            },
            "坠毁的飞船休息舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "自来水厂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "A兵团试炼场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "DEATH MATCH角斗场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "简单",
                "detail": ""
            },
            "DEATH MATCH入门赛": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            }
        }
    },
    "challenge": {
        "name": "challenge",
        "challenge": true,
        "stages": {
            "被摧毁的武器仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "被攻击的黑铁会": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "被清扫的虫洞": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "被偷袭的基地": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "被炸毁的防御地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "被终结者占领的诺亚前线基地兵工厂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "冰雪之心": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "补给仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "残垣断壁": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "超市废墟": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "虫洞": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "虫洞洞口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "虫洞内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "虫洞入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "虫洞外围": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "初心者": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "大学城周边": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "地铁站": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "地铁站隧道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "第三集结点": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "第一防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "电子战接入设备间": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "堕落城保卫战": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "堕落城区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "堕落城深处": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "堕落城下水道入口": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "二级防线": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "防御地带": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船储备舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船繁殖舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船监视点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船控制舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船燃料舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船推进舱": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船武器舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "飞船休息舱": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "菲尼克斯Lv10": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "菲尼克斯Lv16": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "废城环线": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "废墟武器店": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "革命军哨所": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "关口小道": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "核电站": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会翅虎堂内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会翅虎堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会黑龙堂内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会黑龙堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会火凤堂内部": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会火凤堂外围": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会总部边缘": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会总堂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "黑铁会总堂外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "基地禁区边缘地带": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "集结点A": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "集结点B": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "集结点C": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "僵尸卫队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "交战热点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "郊区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "解救A兵团士兵": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "禁区边缘": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "锯刺陷阱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "决战之地": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "军队据点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "军阀据点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "军阀临时补给点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "军阀秘密基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "军阀前线基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "军团驻地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "绿洲深处": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "绿洲外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "秘密通道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "难民营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "闹市区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚精英部队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚前线基地兵工厂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚前线基地哨岗": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚雪山": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚雪山部队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚雪山山顶": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚雪山山脊": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "诺亚雪山山脚": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "盆地入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "贫民窟": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "熔岩广场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "熔岩基地": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "熔岩基地外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "熔岩秘洞": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "熔岩隧道": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "熔岩营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "三级防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "山洞入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "商业区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "哨兵据点": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "深入禁区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "尸母巢穴": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "试炼场深处入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "试验场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "隧道入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "铁血临时营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "铁血营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "同盟卸货站": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-第一防线防区": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-堕落城酒吧": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-堕落城商业街": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-黑铁会修炼场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-军阀": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-联合大学": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "外交-摇滚公园": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "温泉关口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "武器仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "锡蒙利Lv10": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "锡蒙利Lv16": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "袭杀与圈套": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "新手练习场": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "幸存者营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "雪地平原": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "雪山入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "雪原防御带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "雪原基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "雪原坡地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "雪原深处": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "训练场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "压制摇滚公园": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "研究院": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "摇滚公园": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "摇滚内战": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "一级防线": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "医院": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "游寇基地": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "指挥部大厅": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "指挥部外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "指挥营地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的被摧毁的武器仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的防御地带": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的秘密通道": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的诺亚精英部队": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的诺亚雪山山顶": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的诺亚雪山山脚": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的熔岩广场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的熔岩基地": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的熔岩隧道": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的武器仓库": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的雪地平原": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的雪山入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的研究院": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "终结者占领的指挥部大厅": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船储备舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船控制舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船燃料舱": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船入口": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船推进舱": {
                "unlocked": true,
                "task": true,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船外围": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船武器舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "坠毁的飞船休息舱": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "自来水厂": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "A兵团试炼场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "DEATH MATCH角斗场": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            },
            "DEATH MATCH入门赛": {
                "unlocked": true,
                "task": false,
                "highestDifficulty": "地狱",
                "detail": ""
            }
        }
    }
};
