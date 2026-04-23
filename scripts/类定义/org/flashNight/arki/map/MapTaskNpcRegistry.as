/**
 * 文件：org/flashNight/arki/map/MapTaskNpcRegistry.as
 * 说明：WebView 地图面板的任务 NPC 坐标 registry。
 *
 * 职责：
 *   - 维护 NPC 原名 → marker 定义的映射（包括 alias 别名与小写 fallback 查询）
 *   - 类加载时 seed 全部硬编码 NPC 坐标
 *   - 对外提供按 _root.tasks_to_do 筛选的 marker 投影（buildTaskNpcMarkers）
 *
 * marker 结构：{ pageId:String, hotspotId:String, point:{x:Number, y:Number} }
 */

class org.flashNight.arki.map.MapTaskNpcRegistry {
    private static var _aliases:Object;
    private static var _markers:Object;
    private static var _markersLower:Object;

    private static var _seeded:Boolean = seedAll();

    /**
     * 登记一个 NPC marker。小写 fallback key 遵循 "先来先占" 语义：
     * 同一小写键只在未被占用时写入。
     */
    public static function register(npcName:String, pageId:String,
                                     hotspotId:String, x:Number, y:Number):Void {
        var markerDef:Object = {
            pageId: pageId,
            hotspotId: hotspotId,
            point: { x: x, y: y }
        };
        _markers[npcName] = markerDef;

        var normalizedKey:String = String(npcName).toLowerCase();
        if (_markersLower[normalizedKey] == undefined) {
            _markersLower[normalizedKey] = markerDef;
        }
    }

    /** 查 alias 表；未命中返回原名 */
    public static function resolveAliasKey(npcName:String):String {
        if (npcName == undefined || npcName == "") return "";
        if (_aliases[npcName] != undefined) {
            return String(_aliases[npcName]);
        }
        return npcName;
    }

    /** 三级查询：原样 → alias → 小写 fallback */
    public static function findMarker(npcName:String):Object {
        if (npcName == undefined || npcName == "") return undefined;

        var resolvedName:String = resolveAliasKey(String(npcName));
        if (_markers[resolvedName] != undefined) {
            return _markers[resolvedName];
        }

        var normalizedKey:String = String(resolvedName).toLowerCase();
        if (_markersLower[normalizedKey] != undefined) {
            return _markersLower[normalizedKey];
        }

        return undefined;
    }

    /**
     * 扫描当前 _root.tasks_to_do，对每个已完成前置条件的任务，
     * 按 finish_npc 找到 marker 并去重投影为 marker 数组。
     */
    public static function buildTaskNpcMarkers():Array {
        var markers:Array = [];
        var seen:Object = {};
        var tasks:Array = _root.tasks_to_do;
        if (tasks == undefined) return markers;

        for (var i:Number = 0; i < tasks.length; i++) {
            if (!_root.taskCompleteCheck(i)) continue;

            var taskData:Object = _root.getTaskData(tasks[i].id);
            if (taskData == undefined) continue;
            if (taskData.finish_npc == undefined) continue;

            var finishNpc:String = resolveAliasKey(String(taskData.finish_npc));
            if (finishNpc == "" || seen[finishNpc]) continue;

            var markerDef:Object = findMarker(finishNpc);
            if (markerDef == undefined) continue;

            seen[finishNpc] = true;
            markers.push({
                id: "task_npc_" + finishNpc,
                kind: "taskNpc",
                pageId: markerDef.pageId,
                hotspotId: markerDef.hotspotId,
                point: {
                    x: markerDef.point.x,
                    y: markerDef.point.y
                }
            });
        }

        return markers;
    }

    private static function seedAll():Boolean {
        _aliases = {};
        _markers = {};
        _markersLower = {};

        _aliases["∞天ㄙ★使的剪∞"] = "杀马特";

        // ── base ──
        register("Pig", "base", "base_garage", 171.55, 217.85);
        register("Boy", "base", "base_garage", 212.95, 246.0);
        register("King", "base", "base_garage", 265.35, 217.85);
        register("冷兵器商人", "base", "base_garage", 120.5, 222.05);
        register("杀马特", "base", "base_garage", 365.95, 217.6);
        register("酒保", "base", "merc_bar", 444.85, 136.15);
        register("格格巫", "base", "merc_bar", 567.05, 173.8);
        register("丽丽丝", "base", "merc_bar", 621.55, 173.8);
        register("舞女", "base", "merc_bar", 389.55, 140.2);
        register("宝石线人", "base", "base_lobby", 564.15, 249.75);
        register("前治安官", "base", "base_lobby", 625.5, 237.2);
        register("黑铁会外交部长", "base", "base_lobby", 363.25, 264.75);
        register("学生妹", "base", "base_lobby", 414.1, 245.45);
        register("幸存老兵", "base", "base_lobby", 466.5, 259.35);
        register("The Girl", "base", "basement1", 436.25, 332.65);
        register("Andy Law", "base", "basement1", 497.55, 329.4);
        register("Shop Girl", "base", "basement1", 549.95, 291.2);
        register("Blue", "base", "basement1", 620.9, 336.8);
        register("小F", "base", "basement1", 609.15, 279.75);
        register("厨师", "base", "cafeteria", 324.85, 431.85);

        // ── faction ──
        register("general", "faction", "warlord_base", 239.3, 170.6);
        register("gazer", "faction", "warlord_base", 128.95, 168.1);
        register("director", "faction", "warlord_tent", 190.85, 125.0);
        register("itinerant", "faction", "firing_range", 154.35, 293.6);
        register("surveyor", "faction", "firing_range", 254.35, 264.1);
        register("singer", "faction", "rock_park", 540.55, 158.5);
        register("keyboard", "faction", "rock_park", 603.75, 187.7);
        register("guitar", "faction", "rock_park", 476.95, 186.1);
        register("火凤", "faction", "blackiron_training", 135.7, 425.45);
        register("翅虎", "faction", "blackiron_training", 230.95, 412.7);
        register("黑龙", "faction", "blackiron_pavilion", 277.5, 433.2);
        register("黑铁", "faction", "blackiron_pavilion", 186.9, 514.5);
        register("牛仔", "faction", "fallen_bar", 522.75, 471.7);
        register("假肢仙人", "faction", "fallen_street", 753.55, 488.45);
        register("吸特乐", "faction", "fallen_street", 675.8, 482.0);

        // ── defense ──
        register("artist", "defense", "first_defense", 161.65, 155.15);
        register("soldier", "defense", "first_defense", 250.7, 162.6);
        register("排骨", "defense", "alliance_dock", 137.45, 332.3);
        register("机哥", "defense", "alliance_dock", 189.45, 333.65);
        register("阿波", "defense", "alliance_dock", 241.2, 331.65);
        register("PROPHET", "defense", "alliance_corridor", 228.45, 392.45);

        // ── school ──
        register("黑仔", "school", "union_university", 430.05, 508.2);
        register("Bat", "school", "union_university", 471.4, 529.7);
        register("Tomboy", "school", "union_university", 516.9, 513.2);
        register("武器订购系统", "school", "union_university", 570.4, 516.7);
        register("体育老师", "school", "university_playground", 539.2, 428.65);
        register("室友", "school", "school_dormitory", 130.3, 347.3);
        register("程铮", "school", "teaching_interior", 486.65, 255.75);
        register("剑道社长", "school", "kendo_club", 663.3, 213.1);
        register("冯佑权", "school", "teaching_interior", 593.3, 211.9);
        register("理科教授", "school", "science_class", 744.65, 212.35);
        register("文科老师", "school", "arts_class", 810.9, 213.1);
        register("Vanshuther", "school", "university_interior", 555.75, 327.2);
        register("教导主任", "school", "office", 538.9, 104.15);

        return true;
    }
}
