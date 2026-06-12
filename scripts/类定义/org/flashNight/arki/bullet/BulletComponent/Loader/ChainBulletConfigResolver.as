import org.flashNight.gesh.xml.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.neur.Server.*;
import org.flashNight.neur.ScheduleTimer.*;

/**
 * ChainBulletConfigResolver —— 联弹「模板 × 单元体」双层配置派生器
 *
 * 背景：联弹的弹壳/属性配置按完整子弹名（"模板-单元体"）在 shellData / attributeData
 * 中全名查表，历史上每个组合都要手写一条 <bullet> 条目，极易漏配
 * （如 纵向机枪联弹-次级穿刺子弹 曾遗漏弹壳配置）。
 *
 * 治理方案（双层配置）：
 * • 模板层：<chainTemplate> 节点声明联弹前缀（如 横向联弹）、弹壳派生规则
 *   （casingMap：单元体材质 → 弹壳名）与属性覆盖（attributeOverride，仅替换已存在键，
 *   如横向系霰弹式发射将穿刺上限特判为 2）
 * • 单元体层：在单元体自身 <bullet> 条目上用 <chainUnit><material>…</material></chainUnit>
 *   声明参与派生及其弹壳材质（材质未命中 casingMap 则该组合不派生弹壳，如 无壳）
 *
 * 合并契约：
 * • 显式 "模板-单元体" 条目始终优先，派生仅补缺（shellData / attributeData 按各自键独立判断）
 * • 派生发生在 InfoLoader 聚合完成之后、回调分发之前，
 *   故 ShellSystem 弹壳池初始化天然包含派生条目，两个消费端热路径零改动
 * • 漂移校验：显式 "X联弹-Y" 条目若模板或单元体未声明，发服务器告警（治理绕过信号）
 */
class org.flashNight.arki.bullet.BulletComponent.Loader.ChainBulletConfigResolver {

    // ---------- 武器引用审计状态（resolve 后留存，供物品数据就绪后审计） ----------
    private static var auditTemplateMap:Object = null;
    private static var auditUnitMap:Object = null;
    private static var auditShellData:Object = null;
    private static var auditAttempts:Number = 0;

    /**
     * 对 InfoLoader 聚合后的组件数据做联弹组合派生合并。
     *
     * @param data        bullets_cases.xml 解析后的原始数据（含 chainTemplate / bullet 节点）
     * @param resultData  聚合后的组件数据（shellData / attributeData / movementData）
     */
    public static function resolve(data:Object, resultData:Object):Void {
        var templates:Array = XMLParser.configureDataAsArray(data.chainTemplate);
        if (templates.length == 0) {
            return; // 未声明任何模板，维持原始行为
        }

        var server = ServerManager.getInstance();

        // ---------- 1. 模板注册表 ----------
        var templateMap:Object = {};
        for (var i:Number = 0; i < templates.length; i++) {
            var node:Object = templates[i];
            if (node.prefix == undefined || node.prefix == "") continue;
            var tpl:Object = {};
            var shellNode:Object = node.shell;
            if (shellNode != undefined && shellNode.casingMap != undefined) {
                var entries:Array = XMLParser.configureDataAsArray(shellNode.casingMap.entry);
                var casingMap:Object = {};
                for (var e:Number = 0; e < entries.length; e++) {
                    var entry:Object = entries[e];
                    if (entry.material != undefined && entry.casing != undefined) {
                        casingMap[String(entry.material)] = String(entry.casing);
                    }
                }
                tpl.casingMap = casingMap;
                tpl.myX = (shellNode.xOffset != undefined) ? Number(shellNode.xOffset) : 0;
                tpl.myY = (shellNode.yOffset != undefined) ? Number(shellNode.yOffset) : 0;
                tpl.simulationMethod = (shellNode.simulationMethod != undefined) ? String(shellNode.simulationMethod) : "标准";
            }
            if (node.attributeOverride != undefined) {
                tpl.attributeOverride = node.attributeOverride;
            }
            templateMap[String(node.prefix)] = tpl;
        }

        // ---------- 2. 单元体声明（扫描 bullet 节点上的 chainUnit 标记） ----------
        var bulletNodes:Array = XMLParser.configureDataAsArray(data.bullet);
        var unitMap:Object = {};
        for (var b:Number = 0; b < bulletNodes.length; b++) {
            var bn:Object = bulletNodes[b];
            if (bn.chainUnit == undefined || bn.name == undefined || bn.name == "") continue;
            var unitInfo:Object = {};
            unitInfo.material = (bn.chainUnit.material != undefined) ? String(bn.chainUnit.material) : null;
            unitMap[String(bn.name)] = unitInfo;
        }

        // ---------- 3. 交叉派生（显式条目优先，仅补缺） ----------
        if (resultData.shellData == undefined) resultData.shellData = {};
        if (resultData.attributeData == undefined) resultData.attributeData = {};
        var shellData:Object = resultData.shellData;
        var attrData:Object = resultData.attributeData;
        var derivedShellCount:Number = 0;
        var derivedAttrCount:Number = 0;

        for (var prefix:String in templateMap) {
            var t:Object = templateMap[prefix];
            for (var unitName:String in unitMap) {
                var key:String = prefix + "-" + unitName;

                // 3a. 弹壳派生：模板需有 casingMap 且单元体材质命中
                if (shellData[key] == undefined && t.casingMap != undefined) {
                    var material:String = unitMap[unitName].material;
                    var casing:String = (material != null) ? t.casingMap[material] : null;
                    if (casing != undefined) {
                        var shellInfo:Object = {};
                        shellInfo.弹壳 = casing;
                        shellInfo.myX = t.myX;
                        shellInfo.myY = t.myY;
                        shellInfo.模拟方式 = t.simulationMethod;
                        shellData[key] = shellInfo;
                        derivedShellCount++;
                    }
                }

                // 3b. 属性派生：浅拷贝单元体本体属性，模板覆盖仅替换已存在键
                if (attrData[key] == undefined) {
                    var base:Object = attrData[unitName];
                    if (base != undefined) {
                        var derived:Object = {};
                        for (var dk:String in base) {
                            derived[dk] = base[dk];
                        }
                        var ov:Object = t.attributeOverride;
                        if (ov != undefined) {
                            for (var ok:String in ov) {
                                if (derived[ok] != undefined) {
                                    derived[ok] = (typeof derived[ok] == "number") ? Number(ov[ok]) : ov[ok];
                                }
                            }
                        }
                        attrData[key] = derived;
                        derivedAttrCount++;
                    }
                }
            }
        }

        // ---------- 4. 漂移校验：显式联弹组合的模板/单元体必须已声明 ----------
        var warnCount:Number = 0;
        warnCount += validateMapKeys(shellData, templateMap, unitMap, server, "shell");
        warnCount += validateMapKeys(attrData, templateMap, unitMap, server, "attribute");

        server.sendServerMessage("[联弹配置] 模板派生完成：弹壳 +" + derivedShellCount
            + "，属性 +" + derivedAttrCount
            + (warnCount > 0 ? ("，漂移告警 " + warnCount + " 条") : ""));

        // ---------- 5. 武器引用审计：物品数据就绪后，校验实际使用中的联弹组合全部被治理覆盖 ----------
        auditTemplateMap = templateMap;
        auditUnitMap = unitMap;
        auditShellData = shellData;
        auditAttempts = 0;
        scheduleItemAudit();
    }

    /**
     * 延迟调度物品引用审计（非触发式：仅轮询 ItemDataLoader 缓存，不主动发起加载，
     * 避免与游戏自身的物品数据加载编排产生并发竞争）
     */
    private static function scheduleItemAudit():Void {
        EnhancedCooldownWheel.I().addDelayedTask(1000, auditWhenItemsReady);
    }

    private static function auditWhenItemsReady():Void {
        var items = ItemDataLoader.getInstance().getData();
        if (items == null) {
            // 物品数据尚未就绪，最多重试 30 次（约 30 秒窗口）
            auditAttempts++;
            if (auditAttempts < 30) scheduleItemAudit();
            return;
        }
        auditItemReferences(items);
    }

    /**
     * 扫描全部物品的 data.bullet 引用，凡形如 "模板-单元体" 的联弹组合：
     * • 模板/单元体必须已声明（双层配置覆盖）
     * • 模板带 casingMap 且单元体材质非"无壳"时，弹壳条目必须已解析存在
     * 任何缺失都发服务器告警（实际在用却未被治理覆盖 = 漏配）。
     */
    public static function auditItemReferences(items):Void {
        var server = ServerManager.getInstance();
        var warnCount:Number = 0;
        var checked:Object = {}; // 同名子弹只审一次
        for (var i:Number = 0; i < items.length; i++) {
            var it:Object = items[i];
            var bulletName:String = (it.data != undefined) ? it.data.bullet : undefined;
            if (bulletName == undefined || checked[bulletName] != undefined) continue;
            checked[bulletName] = true;

            var key:String = String(bulletName);
            var idx:Number = key.indexOf("联弹-");
            if (idx < 0) continue;
            var dashIdx:Number = idx + 2;
            var prefix:String = key.substring(0, dashIdx);
            var suffix:String = key.substring(dashIdx + 1);

            var tpl:Object = auditTemplateMap[prefix];
            var unit:Object = auditUnitMap[suffix];
            if (tpl == undefined) {
                server.sendServerMessage("[联弹配置] 审计告警：武器「" + it.name + "」引用 " + key + "，但模板「" + prefix + "」未声明");
                warnCount++;
            }
            if (unit == undefined) {
                server.sendServerMessage("[联弹配置] 审计告警：武器「" + it.name + "」引用 " + key + "，但单元体「" + suffix + "」未声明");
                warnCount++;
                continue;
            }
            // 弹壳覆盖检查（材质明确且模板具备弹壳派生能力时，解析结果必须存在）
            if (tpl != undefined && tpl.casingMap != undefined
                && unit.material != null && unit.material != "无壳"
                && auditShellData[key] == undefined) {
                server.sendServerMessage("[联弹配置] 审计告警：武器「" + it.name + "」引用 " + key + "，弹壳未解析（材质「" + unit.material + "」未命中模板 casingMap？）");
                warnCount++;
            }
        }
        server.sendServerMessage("[联弹配置] 武器引用审计完成：" + (warnCount > 0 ? ("发现 " + warnCount + " 处缺失！") : "全部覆盖"));
    }

    /**
     * 校验形如 "模板-单元体" 的条目是否落在已声明的模板/单元体集合内，
     * 漏声明视为配置漂移信号（手写条目绕过了双层配置治理）。
     *
     * @return Number 告警条数
     */
    private static function validateMapKeys(map:Object, templateMap:Object, unitMap:Object, server, label:String):Number {
        var count:Number = 0;
        for (var key:String in map) {
            var idx:Number = key.indexOf("联弹-");
            if (idx < 0) continue;
            var dashIdx:Number = idx + 2; // "联弹" 占2字符，"-" 位于其后
            var prefix:String = key.substring(0, dashIdx);
            var suffix:String = key.substring(dashIdx + 1);
            if (templateMap[prefix] == undefined) {
                server.sendServerMessage("[联弹配置] 漂移告警(" + label + ")：模板未声明「" + prefix + "」（条目：" + key + "）");
                count++;
            }
            if (unitMap[suffix] == undefined) {
                server.sendServerMessage("[联弹配置] 漂移告警(" + label + ")：单元体未声明「" + suffix + "」（条目：" + key + "）");
                count++;
            }
        }
        return count;
    }
}