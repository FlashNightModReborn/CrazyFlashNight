/**
 * 文件：org/flashNight/arki/map/MapPanelCatalog.as
 * 说明：WebView 地图面板的静态目录表。
 *
 * 包含：基地热点列表、分组热点列表、分组解锁元信息、导航帧名映射、热点→页签映射。
 * 所有数据在类加载时通过 initTables() 一次性初始化；运行时只读。
 *
 * 与 MapPanelService / MapHotspotResolver 配合使用。
 */

class org.flashNight.arki.map.MapPanelCatalog {
    public static var BASE_HOTSPOT_IDS:Array;
    public static var GROUPED_HOTSPOT_IDS:Object;
    public static var UNLOCK_META:Object;
    public static var NAVIGATE_TARGETS:Object;
    public static var HOTSPOT_PAGES:Object;

    private static var _inited:Boolean = initTables();

    private static function initTables():Boolean {
        BASE_HOTSPOT_IDS = [
            "base_roof",
            "base_lobby",
            "base_entrance",
            "base_garage",
            "merc_bar",
            "infirmary",
            "dormitory",
            "basement1",
            "gym",
            "armory",
            "cafeteria",
            "corridor",
            "lab",
            "underground_water"
        ];

        GROUPED_HOTSPOT_IDS = {
            warlord: ["warlord_base", "warlord_tent", "firing_range"],
            rock: ["rock_park", "rock_rehearsal"],
            blackiron: ["blackiron_training", "blackiron_pavilion"],
            fallen: ["fallen_bar", "fallen_street"],
            defense: ["first_defense"],
            restricted: ["alliance_dock", "alliance_corridor"],
            schoolOutside: ["union_university"],
            schoolInside: [
                "workshop",
                "university_interior",
                "university_playground",
                "dorm_downstairs",
                "school_dormitory",
                "office",
                "kendo_club",
                "science_class",
                "arts_class",
                "teaching_interior",
                "teaching_right"
            ]
        };

        UNLOCK_META = {
            warlord: { label: "军阀线路", lockedReason: "军阀线路尚未开放" },
            rock: { label: "摇滚线路", lockedReason: "摇滚线路尚未开放" },
            blackiron: { label: "黑铁会线路", lockedReason: "黑铁会线路尚未开放" },
            fallen: { label: "堕落城线路", lockedReason: "堕落城线路尚未开放" },
            defense: { label: "第一防线", lockedReason: "第一防线尚未开放" },
            restricted: { label: "禁区", lockedReason: "禁区尚未开放" },
            schoolOutside: { label: "学校外部", lockedReason: "学校外部尚未开放" },
            schoolInside: { label: "学校内部", lockedReason: "学校内部尚未开放" }
        };

        NAVIGATE_TARGETS = {
            base_roof: "基地房顶",
            base_lobby: "基地1层",
            base_entrance: "基地门口",
            base_garage: "基地车库",
            merc_bar: "佣兵酒吧",
            infirmary: "医务室",
            dormitory: "房间",
            basement1: "地下室1层",
            gym: "健身房",
            armory: "武器库",
            cafeteria: "地图-食堂",
            corridor: "地图-走廊",
            lab: "地图-实验室",
            underground_water: "地下2层",
            warlord_base: "地图-军阀基地",
            warlord_tent: "地图-军阀帐篷",
            firing_range: "地图-靶场",
            rock_park: "地图-摇滚公园",
            rock_rehearsal: "地图-摇滚排练室",
            blackiron_training: "地图-黑铁会修炼场",
            blackiron_pavilion: "地图-黑铁阁",
            fallen_bar: "地图-堕落城酒吧",
            fallen_street: "地图-堕落城商业街",
            first_defense: "地图-第一防线防区",
            alliance_dock: "地图-同盟卸货站",
            alliance_corridor: "地图-同盟通路",
            workshop: "地图-大学地下工坊",
            union_university: "地图-联合大学",
            university_interior: "地图-大学内部",
            university_playground: "地图-大学操场",
            dorm_downstairs: "地图-大学宿舍楼下",
            school_dormitory: "地图-大学宿舍",
            office: "地图-教学楼办公室",
            kendo_club: "地图-剑道社",
            science_class: "地图-理科教室",
            arts_class: "地图-文科教室",
            teaching_interior: "地图-教学楼内部",
            teaching_right: "地图-教学楼内部右侧"
        };

        HOTSPOT_PAGES = {
            base_roof: "base",
            base_lobby: "base",
            base_entrance: "base",
            base_garage: "base",
            merc_bar: "base",
            infirmary: "base",
            dormitory: "base",
            basement1: "base",
            gym: "base",
            armory: "base",
            cafeteria: "base",
            corridor: "base",
            lab: "base",
            underground_water: "base",
            warlord_base: "faction",
            warlord_tent: "faction",
            firing_range: "faction",
            rock_park: "faction",
            rock_rehearsal: "faction",
            blackiron_training: "faction",
            blackiron_pavilion: "faction",
            fallen_bar: "faction",
            fallen_street: "faction",
            first_defense: "defense",
            alliance_dock: "defense",
            alliance_corridor: "defense",
            workshop: "school",
            union_university: "school",
            university_interior: "school",
            university_playground: "school",
            dorm_downstairs: "school",
            school_dormitory: "school",
            office: "school",
            kendo_club: "school",
            science_class: "school",
            arts_class: "school",
            teaching_interior: "school",
            teaching_right: "school"
        };

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
