import org.flashNight.gesh.xml.XMLParser;

/**
 * 文件：org/flashNight/arki/map/MapPanelCatalog.as
 * 说明：WebView 地图面板的静态目录表。
 *
 * 包含：基地热点列表、分组热点列表、分组解锁元信息、导航帧名映射、热点→页签映射、头像可见性表。
 * 两路独立填充（boot 期，见 asLoader.xml）：
 *   - 拓扑（groups/hotspots）← DataQueryService("map_catalog") → applyFromCatalogJson
 *       （map_catalog.json 由 build.ps1 Step 1c 从 launcher web map-panel-data.js 派生）
 *   - 头像可见性 ← MapAvatarVisibilityLoader 读 data/map/map_panel.xml → applyAvatarVisibilityFromXml
 * 数据未到达前各表保持"安全零值"（空集合；GROUPED_HOTSPOT_IDS 预置 8 个空数组，
 * 因为 MapPanelService.buildEnabledHotspotIds 会直接读 .xxx.length，undefined 会崩）。
 *
 * 失败语义：两个入口各自开头无条件 reset 自己那部分表，任一校验失败直接 return false，
 * 保证 reload 场景下不会留下混合陈旧态；isLoaded（仅反映 catalog）同步复位。
 * 集合正确性由派生期 gate 保证，运行期不再做 canonical 白名单精确相等校验。
 *
 * 与 MapPanelService / MapHotspotResolver 配合使用。
 */

class org.flashNight.arki.map.MapPanelCatalog {
    // 安全零值：XML 未到达前这些表允许被读取，只会返回空结果，不崩
    public static var BASE_HOTSPOT_IDS:Array = [];
    public static var GROUPED_HOTSPOT_IDS:Object = {
        warlord: [], rock: [], blackiron: [], fallen: [],
        defense: [], restricted: [], schoolOutside: [], schoolInside: []
    };
    public static var UNLOCK_META:Object = {};
    public static var NAVIGATE_TARGETS:Object = {};
    public static var HOTSPOT_PAGES:Object = {};
    // avatar_visibility 派生表：{ avatarId: [rule, rule, ...] }
    // rule = { chain?:String, min?:Number, requireInfra?:Array<String>, avatarId:String }
    // 同一 npc 多条 rule = AND；空表 = 无门控 = 默认可见。
    public static var AVATAR_VISIBILITY_RULES:Object = {};
    // 反查表：launcher slot id → npc name（snapshot.avatarVisibility 用 slot id 作 key 下发给 Web）
    public static var AVATAR_ID_TO_NPC:Object = {};

    public static var isLoaded:Boolean = false;

    // 拓扑集合不再硬编码白名单（旧 REQUIRED_GROUP_IDS / REQUIRED_HOTSPOT_IDS 已删）：
    // groups/hotspots 由 data/map/map_catalog.json 提供，该文件 build.ps1 Step 1c 经
    // tools/derive-map-catalog.js 从 launcher/web/modules/map-panel-data.js 派生，集合正确性
    // 在派生期 gate 保证。运行期只做结构校验（见 applyFromCatalogJson）。
    // 收益：加/改 hotspot 不再需要改本文件 + 重编译 SWF，只需改 web SOT + 跑 build/derive。
    private static var VALID_PAGE_IDS:Array = ["base", "faction", "defense", "school"];
    // 与 SaveManager.REPAIR_DICT_TASK_CHAINS 必须一致；任何 schema 扩展须同时同步两边。
    private static var VALID_CHAIN_NAMES:Array = [
        "主线", "引导", "支线", "挑战", "废城",
        "彩蛋", "异形", "大学", "后勤", "预览", "铁枪会"
    ];
    private static var VALID_INFRA_NAMES:Array = ["自行车", "摩托车", "越野车"];

    /**
     * 从 DataQueryService("map_catalog") 的 result 填充导航/拓扑表。
     * 任一结构校验失败 → trace + 回退空表 + 返回 false（绝不部分填表）。
     * 不再做 canonical 白名单精确相等校验——集合正确性由 build.ps1 Step 1c 的
     * tools/derive-map-catalog.js 派生期 gate 保证。
     *
     * @param raw  DataQueryService callback 的 response.result，形如
     *             { groups:[{id,page,label,lockedReason?}], hotspots:[{id,group,frame}] }（JSON 数组）
     * @return Boolean 是否成功
     */
    public static function applyFromCatalogJson(raw:Object):Boolean {
        // 先无条件重置 catalog 部分（不动 avatar 表）：reload 失败也不留旧数据混合态
        resetCatalogTables();

        if (raw == null) { trace("[MapPanelCatalog] catalog raw 为 null"); return false; }

        var groupList:Array = raw.groups;
        var hotspotList:Array = raw.hotspots;
        if (groupList == undefined || groupList.length == undefined || groupList.length == 0) {
            trace("[MapPanelCatalog] catalog groups 为空或非数组"); return false;
        }
        if (hotspotList == undefined || hotspotList.length == undefined || hotspotList.length == 0) {
            trace("[MapPanelCatalog] catalog hotspots 为空或非数组"); return false;
        }

        // 结构 + 关系校验（同时构建 groupPageMap）
        var groupIdSet:Object = {};
        var groupPageMap:Object = {};
        var i:Number;
        for (i = 0; i < groupList.length; i++) {
            var g:Object = groupList[i];
            if (g.id == undefined || g.id == "") { trace("[MapPanelCatalog] group[" + i + "] 缺 id"); return false; }
            if (g.page == undefined || g.page == "") { trace("[MapPanelCatalog] group '" + g.id + "' 缺 page"); return false; }
            if (g.label == undefined || g.label == "") { trace("[MapPanelCatalog] group '" + g.id + "' 缺 label"); return false; }
            if (!inList(VALID_PAGE_IDS, g.page)) { trace("[MapPanelCatalog] group '" + g.id + "' page='" + g.page + "' 非法"); return false; }
            if (groupIdSet[g.id] != undefined) { trace("[MapPanelCatalog] group id 重复: " + g.id); return false; }
            // 非 base 组必须显式声明 lockedReason（为空会让锁区提示静默消失，违背"坏数据尽早硬失败"）
            if (g.id != "base" && (g.lockedReason == undefined || g.lockedReason == "")) {
                trace("[MapPanelCatalog] group '" + g.id + "' 缺 lockedReason（非 base 组必填）");
                return false;
            }
            groupIdSet[g.id] = true;
            groupPageMap[g.id] = String(g.page);
        }

        var hotspotIdSet:Object = {};
        for (i = 0; i < hotspotList.length; i++) {
            var h:Object = hotspotList[i];
            if (h.id == undefined || h.id == "") { trace("[MapPanelCatalog] hotspot[" + i + "] 缺 id"); return false; }
            if (h.group == undefined || h.group == "") { trace("[MapPanelCatalog] hotspot '" + h.id + "' 缺 group"); return false; }
            if (h.frame == undefined || h.frame == "") { trace("[MapPanelCatalog] hotspot '" + h.id + "' 缺 frame"); return false; }
            if (groupIdSet[h.group] == undefined) { trace("[MapPanelCatalog] hotspot '" + h.id + "' 引用未声明的 group: " + h.group); return false; }
            if (hotspotIdSet[h.id] != undefined) { trace("[MapPanelCatalog] hotspot id 重复: " + h.id); return false; }
            hotspotIdSet[h.id] = true;
        }

        // 通过校验，开始构建（GROUPED_HOTSPOT_IDS 初值已有 8 个空数组 key，此处只 push）
        var base_:Array = [];
        var grouped:Object = {
            warlord: [], rock: [], blackiron: [], fallen: [],
            defense: [], restricted: [], schoolOutside: [], schoolInside: []
        };
        var navigate:Object = {};
        var pages:Object = {};
        for (i = 0; i < hotspotList.length; i++) {
            var h2:Object = hotspotList[i];
            var hid:String = String(h2.id);
            navigate[hid] = String(h2.frame);
            pages[hid] = groupPageMap[h2.group];
            if (h2.group == "base") {
                base_.push(hid);
            } else {
                grouped[h2.group].push(hid);
            }
        }
        var meta:Object = {};
        for (i = 0; i < groupList.length; i++) {
            var g2:Object = groupList[i];
            if (g2.id == "base") continue;  // base 组无 lockedReason，不进 UNLOCK_META（保持与旧表一致）
            // 此处 g2.lockedReason 已在上面校验为非空
            meta[g2.id] = {
                label: String(g2.label),
                lockedReason: String(g2.lockedReason)
            };
        }

        // 原子替换（校验全过后才动 public 字段；不含 avatar 表）
        BASE_HOTSPOT_IDS = base_;
        GROUPED_HOTSPOT_IDS = grouped;
        NAVIGATE_TARGETS = navigate;
        HOTSPOT_PAGES = pages;
        UNLOCK_META = meta;
        isLoaded = true;
        return true;
    }

    /**
     * 从 map_panel.xml 的 <avatar_visibility> 段填充头像可见性表。
     * 整段缺失 → 空表（默认全可见）；解析/校验失败 → 回退空表 + 返回 false。
     * 与 applyFromCatalogJson 互不影响（各自只 reset 自己那部分表，boot 期独立加载）。
     *
     * @param raw  MapAvatarVisibilityLoader 成功回调拿到的 <map_panel> 内容
     * @return Boolean 是否成功
     */
    public static function applyAvatarVisibilityFromXml(raw:Object):Boolean {
        resetAvatarTables();
        if (raw == null) { trace("[MapPanelCatalog] avatar raw 为 null"); return false; }

        var visParsed:Object = parseAvatarVisibility(raw.avatar_visibility);
        if (visParsed == null) return false;  // 解析或校验失败

        AVATAR_VISIBILITY_RULES = visParsed.rules;
        AVATAR_ID_TO_NPC = visParsed.idToNpc;
        return true;
    }

    /**
     * 解析 <avatar_visibility> 段。允许整段缺失（返回空表）。
     * 校验失败 → trace + 返回 null。
     * 返回结构：{ rules:Object, idToNpc:Object }
     */
    private static function parseAvatarVisibility(rawSection:Object):Object {
        var rules:Object = {};
        var idToNpc:Object = {};
        if (rawSection == undefined) return { rules: rules, idToNpc: idToNpc };

        var list:Array = XMLParser.configureDataAsArray(rawSection.rule);
        if (list.length == 0) return { rules: rules, idToNpc: idToNpc };

        for (var i:Number = 0; i < list.length; i++) {
            var r:Object = list[i];
            if (r.avatarId == undefined || r.avatarId == "") {
                trace("[MapPanelCatalog] avatar_visibility rule[" + i + "] 缺 avatarId");
                return null;
            }
            if (r.npc == undefined || r.npc == "") {
                trace("[MapPanelCatalog] avatar_visibility rule '" + r.avatarId + "' 缺 npc");
                return null;
            }
            // chain + min 必须配对出现
            var hasChain:Boolean = (r.chain != undefined && r.chain != "");
            var hasMin:Boolean = (r.min != undefined && r.min != "");
            if (hasChain != hasMin) {
                trace("[MapPanelCatalog] avatar_visibility rule '" + r.avatarId + "' chain/min 必须配对");
                return null;
            }
            if (hasChain && !inList(VALID_CHAIN_NAMES, String(r.chain))) {
                trace("[MapPanelCatalog] avatar_visibility rule '" + r.avatarId + "' chain 非白名单: " + r.chain);
                return null;
            }
            if (hasMin && (isNaN(Number(r.min)) || Number(r.min) < 0)) {
                trace("[MapPanelCatalog] avatar_visibility rule '" + r.avatarId + "' min 非法: " + r.min);
                return null;
            }
            // requireInfra 切分并校验白名单
            var infraArr:Array = null;
            if (r.requireInfra != undefined && r.requireInfra != "") {
                infraArr = String(r.requireInfra).split("|");
                for (var k:Number = 0; k < infraArr.length; k++) {
                    var infraName:String = infraArr[k];
                    if (!inList(VALID_INFRA_NAMES, infraName)) {
                        trace("[MapPanelCatalog] avatar_visibility rule '" + r.avatarId + "' requireInfra 非白名单: " + infraName);
                        return null;
                    }
                }
            }

            var ruleObj:Object = { avatarId: String(r.avatarId) };
            if (hasChain) {
                ruleObj.chain = String(r.chain);
                ruleObj.min = Number(r.min);
            }
            if (infraArr != null) ruleObj.requireInfra = infraArr;

            var npcKey:String = String(r.npc);
            var avatarKey:String = String(r.avatarId);
            if (rules[avatarKey] == undefined) rules[avatarKey] = [];
            rules[avatarKey].push(ruleObj);
            // avatarId → npc 反查：同 avatarId 重复声明 = 数据错误
            if (idToNpc[String(r.avatarId)] != undefined && idToNpc[String(r.avatarId)] != npcKey) {
                trace("[MapPanelCatalog] avatar_visibility avatarId '" + r.avatarId + "' 指向不同 npc: " + idToNpc[String(r.avatarId)] + " vs " + npcKey);
                return null;
            }
            idToNpc[String(r.avatarId)] = npcKey;
        }

        return { rules: rules, idToNpc: idToNpc };
    }

    /**
     * 求值：给定 NPC 名是否当前可见。
     * 无规则 = true（默认可见）。任一规则不满足 = false。
     * 读 _root.task_chains_progress 和 _root.基建系统.infrastructure。
     */
    public static function isAvatarVisible(npcName:String):Boolean {
        if (npcName == undefined || npcName == "") return true;
        var rulesForNpc:Array = AVATAR_VISIBILITY_RULES[npcName];
        if (rulesForNpc == undefined || rulesForNpc.length == 0) return true;

        return areVisibilityRulesSatisfied(rulesForNpc);
    }

    public static function isAvatarVisibleById(avatarId:String, npcName:String):Boolean {
        if (avatarId != undefined && avatarId != "") {
            var rulesForAvatar:Array = AVATAR_VISIBILITY_RULES[avatarId];
            if (rulesForAvatar != undefined && rulesForAvatar.length > 0) {
                return areVisibilityRulesSatisfied(rulesForAvatar);
            }
        }
        return isAvatarVisible(npcName);
    }

    private static function areVisibilityRulesSatisfied(rulesForNpc:Array):Boolean {
        var progress:Object = _root.task_chains_progress;
        var infra:Object = (_root.基建系统 != undefined) ? _root.基建系统.infrastructure : undefined;

        for (var i:Number = 0; i < rulesForNpc.length; i++) {
            var r:Object = rulesForNpc[i];
            // chain/min 检查
            if (r.chain != undefined) {
                if (progress == undefined) return false;
                if (Number(progress[r.chain]) < Number(r.min)) return false;
            }
            // requireInfra 检查（OR）
            if (r.requireInfra != undefined) {
                if (infra == undefined) return false;
                var arr:Array = r.requireInfra;
                var anyHit:Boolean = false;
                for (var j:Number = 0; j < arr.length; j++) {
                    if (infra[arr[j]]) { anyHit = true; break; }
                }
                if (!anyHit) return false;
            }
        }
        return true;
    }

    // ── 内部工具 ──

    /** 复位导航/拓扑表（catalog 部分）；isLoaded = false。applyFromCatalogJson 开头无条件调用。 */
    private static function resetCatalogTables():Void {
        BASE_HOTSPOT_IDS = [];
        GROUPED_HOTSPOT_IDS = {
            warlord: [], rock: [], blackiron: [], fallen: [],
            defense: [], restricted: [], schoolOutside: [], schoolInside: []
        };
        UNLOCK_META = {};
        NAVIGATE_TARGETS = {};
        HOTSPOT_PAGES = {};
        isLoaded = false;
    }

    /** 复位头像可见性表（avatar 部分）。applyAvatarVisibilityFromXml 开头无条件调用。 */
    private static function resetAvatarTables():Void {
        AVATAR_VISIBILITY_RULES = {};
        AVATAR_ID_TO_NPC = {};
    }

    private static function inList(list:Array, value):Boolean {
        for (var i:Number = 0; i < list.length; i++) {
            if (list[i] == value) return true;
        }
        return false;
    }

    /** 反查：通过帧名找 hotspotId；未命中返回空串 */
    public static function resolveHotspotIdByFrameName(frameName:String):String {
        if (frameName == undefined || frameName == "") return "";
        var str:String = String(frameName);
        for (var hotspotId:String in NAVIGATE_TARGETS) {
            if (NAVIGATE_TARGETS[hotspotId] == str) {
                return hotspotId;
            }
        }
        return "";
    }

    /** 查询 hotspot 所属页签；未命中默认 "base" */
    public static function resolvePageId(hotspotId:String):String {
        if (hotspotId != undefined && hotspotId != "") {
            if (HOTSPOT_PAGES[hotspotId] != undefined) {
                return HOTSPOT_PAGES[hotspotId];
            }
        }
        return "base";
    }
}
