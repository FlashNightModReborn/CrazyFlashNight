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
     * 延迟调度联弹引用审计（非触发式：仅轮询加载器缓存，不主动发起加载，
     * 避免与游戏自身的数据加载编排产生并发竞争）
     */
    private static function scheduleItemAudit():Void {
        EnhancedCooldownWheel.I().addDelayedTask(1000, auditWhenItemsReady);
    }

    private static function auditWhenItemsReady():Void {
        var items = ItemDataLoader.getInstance().getData();
        var mods = EquipModListLoader.getInstance().getModData();
        // 物品与配件任一未就绪则继续等待（约 30 秒窗口），超时后以现状审计并在结果中注明范围
        if ((items == null || mods == null) && auditAttempts < 30) {
            auditAttempts++;
            scheduleItemAudit();
            return;
        }
        auditDataReferences(items, mods);
    }

    /**
     * 审计物品 + 配件数据中的全部联弹组合引用。
     * 递归遍历收集任意深度的 bullet 键，覆盖 data/data_ice/data_fire 等变体块、
     * lifecycle initParam、skill 块、配件 stats(merge/override)/skill 等，不依赖固定路径。
     *
     * 凡形如 "模板-单元体" 的引用：
     * • 模板/单元体必须已声明（双层配置覆盖）
     * • 模板带 casingMap 且单元体材质非"无壳"时，弹壳条目必须已解析存在
     *
     * 已知边界（不在本审计范围内）：
     * • AS2 代码内嵌的子弹名（如装备/单位函数中的硬编码回退值），新增时需人工核对声明
     * • 配件词缀动态合成（PropertyOperators.mergeString 前缀保留拼接）由
     *   "模板×单元体全量派生"间接覆盖：词缀后缀只要是已声明单元体，任意模板组合都已派生；
     *   新增联弹词缀配件时，后缀必须是已声明单元体
     */
    public static function auditDataReferences(items, mods):Void {
        var server = ServerManager.getInstance();
        if (items == null) {
            server.sendServerMessage("[联弹配置] 联弹引用审计跳过：物品数据未就绪");
            return;
        }

        // 收集全部 bullet 键引用
        var refs:Array = [];
        for (var i:Number = 0; i < items.length; i++) {
            collectBulletRefs(items[i], String(items[i].name), refs, 0);
        }
        if (mods != null) {
            for (var m:Number = 0; m < mods.length; m++) {
                collectBulletRefs(mods[m], "配件:" + String(mods[m].name), refs, 0);
            }
        }

        // 同名引用去重后逐一校验
        var warnCount:Number = 0;
        var checked:Object = {};
        for (var r:Number = 0; r < refs.length; r++) {
            var key:String = refs[r].name;
            if (checked[key] != undefined) continue;
            checked[key] = true;
            warnCount += checkComboRef(key, refs[r].owner, server);
        }

        var scope:String = (mods != null) ? "物品+配件全字段" : "物品全字段（配件数据未就绪，未覆盖）";
        server.sendServerMessage("[联弹配置] 联弹引用审计完成（范围：" + scope + "）："
            + (warnCount > 0 ? ("发现 " + warnCount + " 处缺失！") : "未发现缺失"));
    }

    /**
     * 递归收集节点树中所有 bullet 键的字符串值
     */
    private static function collectBulletRefs(node, ownerName:String, out:Array, depth:Number):Void {
        if (node == null || typeof node != "object" || depth > 8) return;
        for (var k:String in node) {
            var v = node[k];
            if (k == "bullet" && typeof v == "string") {
                out.push({name: v, owner: ownerName});
            } else if (typeof v == "object") {
                collectBulletRefs(v, ownerName, out, depth + 1);
            }
        }
    }

    /**
     * 校验单个联弹组合引用（非 "X联弹-Y" 格式直接放行）
     * @return Number 告警条数
     */
    private static function checkComboRef(key:String, owner:String, server):Number {
        var idx:Number = key.indexOf("联弹-");
        if (idx < 0) return 0;
        var count:Number = 0;
        var dashIdx:Number = idx + 2;
        var prefix:String = key.substring(0, dashIdx);
        var suffix:String = key.substring(dashIdx + 1);

        var tpl:Object = auditTemplateMap[prefix];
        var unit:Object = auditUnitMap[suffix];
        if (tpl == undefined) {
            server.sendServerMessage("[联弹配置] 审计告警：「" + owner + "」引用 " + key + "，但模板「" + prefix + "」未声明");
            count++;
        }
        if (unit == undefined) {
            server.sendServerMessage("[联弹配置] 审计告警：「" + owner + "」引用 " + key + "，但单元体「" + suffix + "」未声明");
            count++;
            return count;
        }
        // 弹壳覆盖检查（材质明确且模板具备弹壳派生能力时，解析结果必须存在）
        if (tpl != undefined && tpl.casingMap != undefined
            && unit.material != null && unit.material != "无壳"
            && auditShellData[key] == undefined) {
            server.sendServerMessage("[联弹配置] 审计告警：「" + owner + "」引用 " + key + "，弹壳未解析（材质「" + unit.material + "」未命中模板 casingMap？）");
            count++;
        }
        return count;
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