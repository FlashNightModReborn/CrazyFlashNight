import org.flashNight.gesh.xml.XMLParser;

/**
 * 文件：org/flashNight/arki/map/MapPanelCatalog.as
 * 说明：WebView 地图面板的静态目录表。
 *
 * 包含：基地热点列表、分组热点列表、分组解锁元信息、导航帧名映射、热点→页签映射。
 * 数据由 data/map/map_panel.xml 在启动时通过 MapPanelLoader + applyFromXml 填充。
 * XML 未到达前 5 张表保持"安全零值"（空集合；GROUPED_HOTSPOT_IDS 预置 8 个空数组，
 * 因为 MapPanelService.buildEnabledHotspotIds 会直接读 .xxx.length，undefined 会崩）。
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

    public static var isLoaded:Boolean = false;

    // Canonical whitelist：XML 实际集合必须精确等于这些（Phase 2 语义）
    // 新增/改名 hotspot 属于设计变更，需同步更新此处 + XML + launcher 侧 manifest
    private static var REQUIRED_GROUP_IDS:Array = [
        "base", "warlord", "rock", "blackiron", "fallen",
        "defense", "restricted", "schoolOutside", "schoolInside"
    ];
    private static var REQUIRED_HOTSPOT_IDS:Array = [
        "base_roof", "base_lobby", "base_entrance", "base_garage",
        "merc_bar", "infirmary", "dormitory", "basement1",
        "gym", "armory", "cafeteria", "corridor", "lab", "underground_water",
        "warlord_base", "warlord_tent", "firing_range",
        "rock_park", "rock_rehearsal",
        "blackiron_training", "blackiron_pavilion",
        "fallen_bar", "fallen_street",
        "first_defense",
        "alliance_dock", "alliance_corridor",
        "union_university",
        "workshop", "university_interior", "university_playground",
        "dorm_downstairs", "school_dormitory", "office",
        "kendo_club", "science_class", "arts_class",
        "teaching_interior", "teaching_right"
    ];
    private static var VALID_PAGE_IDS:Array = ["base", "faction", "defense", "school"];

    /**
     * 从 XML parse 结果填表。任一校验失败 → trace + 回退空表 + 返回 false。
     * 失败时绝不部分填表（避免"加载成功但数据残缺"的误导）。
     *
     * @param raw  MapPanelLoader 成功回调拿到的 data 对象（即 <map_panel> 内容，非 {map_panel: ...}）
     * @return Boolean 是否成功
     */
    public static function applyFromXml(raw:Object):Boolean {
        if (raw == null) { trace("[MapPanelCatalog] raw 为 null"); return false; }

        var groupList:Array = XMLParser.configureDataAsArray(raw.groups.group);
        var hotspotList:Array = XMLParser.configureDataAsArray(raw.hotspots.hotspot);
        if (groupList.length == 0) { trace("[MapPanelCatalog] groups/group 为空"); return false; }
        if (hotspotList.length == 0) { trace("[MapPanelCatalog] hotspots/hotspot 为空"); return false; }

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

        // Canonical 精确相等校验
        if (!setEquals(groupIdSet, REQUIRED_GROUP_IDS, "group", "MapPanelCatalog")) return false;
        if (!setEquals(hotspotIdSet, REQUIRED_HOTSPOT_IDS, "hotspot", "MapPanelCatalog")) return false;

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
            meta[g2.id] = {
                label: String(g2.label),
                lockedReason: (g2.lockedReason == undefined) ? "" : String(g2.lockedReason)
            };
        }

        // 原子替换（校验全过后才动 public 字段）
        BASE_HOTSPOT_IDS = base_;
        GROUPED_HOTSPOT_IDS = grouped;
        NAVIGATE_TARGETS = navigate;
        HOTSPOT_PAGES = pages;
        UNLOCK_META = meta;
        isLoaded = true;
        return true;
    }

    // ── 内部工具 ──

    private static function inList(list:Array, value):Boolean {
        for (var i:Number = 0; i < list.length; i++) {
            if (list[i] == value) return true;
        }
        return false;
    }

    /** 校验 XML 实际 id 集合（Object 形式的 set）与 required 列表精确相等；trace 缺失/多余条目 */
    private static function setEquals(actualSet:Object, required:Array, kindLabel:String, cls:String):Boolean {
        var requiredSet:Object = {};
        var i:Number;
        for (i = 0; i < required.length; i++) requiredSet[required[i]] = true;

        var missing:Array = [];
        for (i = 0; i < required.length; i++) {
            if (actualSet[required[i]] == undefined) missing.push(required[i]);
        }
        var extra:Array = [];
        for (var k:String in actualSet) {
            if (requiredSet[k] == undefined) extra.push(k);
        }
        if (missing.length > 0 || extra.length > 0) {
            if (missing.length > 0) trace("[" + cls + "] REQUIRED_" + kindLabel + " 缺少: " + missing.join(", "));
            if (extra.length > 0) trace("[" + cls + "] " + kindLabel + " 存在多余条目（未在 whitelist 内）: " + extra.join(", "));
            return false;
        }
        return true;
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
