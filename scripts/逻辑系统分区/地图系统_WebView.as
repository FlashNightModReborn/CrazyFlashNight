// 地图系统_WebView.as — WebView 面板侧地图命令
// 当前版本：多页面地图快照（基地 / A兵团 / 防线禁区 / 学校）
_root._mapJson = new LiteJSON();

_root._mapLog = function(msg) {
    if (_root.server != undefined) {
        _root.server.sendServerMessage("[MapWV] " + msg);
    }
};

_root._mapBaseHotspotIds = [
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

_root._mapGroupedHotspotIds = {
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

_root._mapUnlockMeta = {
    warlord: { label: "军阀线路", lockedReason: "军阀线路尚未开放" },
    rock: { label: "摇滚线路", lockedReason: "摇滚线路尚未开放" },
    blackiron: { label: "黑铁会线路", lockedReason: "黑铁会线路尚未开放" },
    fallen: { label: "堕落城线路", lockedReason: "堕落城线路尚未开放" },
    defense: { label: "第一防线", lockedReason: "第一防线尚未开放" },
    restricted: { label: "禁区", lockedReason: "禁区尚未开放" },
    schoolOutside: { label: "学校外部", lockedReason: "学校外部尚未开放" },
    schoolInside: { label: "学校内部", lockedReason: "学校内部尚未开放" }
};

_root._mapNavigateTargets = {
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

_root._mapHotspotPages = {
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

_root._mapTaskNpcAliases = {};
_root._mapTaskNpcAliases["∞天ㄙ★使的剪∞"] = "杀马特";

_root._mapTaskNpcMarkers = {};
_root._mapTaskNpcMarkersLower = {};

_root._mapRegisterTaskNpcMarker = function(npcName:String, pageId:String, hotspotId:String, x:Number, y:Number) {
    var markerDef = {
        pageId: pageId,
        hotspotId: hotspotId,
        point: {
            x: x,
            y: y
        }
    };
    _root._mapTaskNpcMarkers[npcName] = markerDef;

    var normalizedKey = String(npcName).toLowerCase();
    if (_root._mapTaskNpcMarkersLower[normalizedKey] == undefined) {
        _root._mapTaskNpcMarkersLower[normalizedKey] = markerDef;
    }
};

_root._mapRegisterTaskNpcMarker("Pig", "base", "base_garage", 171.55, 217.85);
_root._mapRegisterTaskNpcMarker("Boy", "base", "base_garage", 212.95, 246.0);
_root._mapRegisterTaskNpcMarker("King", "base", "base_garage", 265.35, 217.85);
_root._mapRegisterTaskNpcMarker("冷兵器商人", "base", "base_garage", 120.5, 222.05);
_root._mapRegisterTaskNpcMarker("杀马特", "base", "base_garage", 365.95, 217.6);
_root._mapRegisterTaskNpcMarker("酒保", "base", "merc_bar", 444.85, 136.15);
_root._mapRegisterTaskNpcMarker("格格巫", "base", "merc_bar", 567.05, 173.8);
_root._mapRegisterTaskNpcMarker("丽丽丝", "base", "merc_bar", 621.55, 173.8);
_root._mapRegisterTaskNpcMarker("舞女", "base", "merc_bar", 389.55, 140.2);
_root._mapRegisterTaskNpcMarker("宝石线人", "base", "base_lobby", 564.15, 249.75);
_root._mapRegisterTaskNpcMarker("前治安官", "base", "base_lobby", 625.5, 237.2);
_root._mapRegisterTaskNpcMarker("黑铁会外交部长", "base", "base_lobby", 363.25, 264.75);
_root._mapRegisterTaskNpcMarker("学生妹", "base", "base_lobby", 414.1, 245.45);
_root._mapRegisterTaskNpcMarker("幸存老兵", "base", "base_lobby", 466.5, 259.35);
_root._mapRegisterTaskNpcMarker("The Girl", "base", "basement1", 436.25, 332.65);
_root._mapRegisterTaskNpcMarker("Andy Law", "base", "basement1", 497.55, 329.4);
_root._mapRegisterTaskNpcMarker("Shop Girl", "base", "basement1", 549.95, 291.2);
_root._mapRegisterTaskNpcMarker("Blue", "base", "basement1", 620.9, 336.8);
_root._mapRegisterTaskNpcMarker("小F", "base", "basement1", 609.15, 279.75);
_root._mapRegisterTaskNpcMarker("厨师", "base", "cafeteria", 324.85, 431.85);

_root._mapRegisterTaskNpcMarker("general", "faction", "warlord_base", 239.3, 170.6);
_root._mapRegisterTaskNpcMarker("gazer", "faction", "warlord_base", 128.95, 168.1);
_root._mapRegisterTaskNpcMarker("director", "faction", "warlord_tent", 190.85, 125.0);
_root._mapRegisterTaskNpcMarker("itinerant", "faction", "firing_range", 154.35, 293.6);
_root._mapRegisterTaskNpcMarker("surveyor", "faction", "firing_range", 254.35, 264.1);
_root._mapRegisterTaskNpcMarker("singer", "faction", "rock_park", 540.55, 158.5);
_root._mapRegisterTaskNpcMarker("keyboard", "faction", "rock_park", 603.75, 187.7);
_root._mapRegisterTaskNpcMarker("guitar", "faction", "rock_park", 476.95, 186.1);
_root._mapRegisterTaskNpcMarker("火凤", "faction", "blackiron_training", 135.7, 425.45);
_root._mapRegisterTaskNpcMarker("翅虎", "faction", "blackiron_training", 230.95, 412.7);
_root._mapRegisterTaskNpcMarker("黑龙", "faction", "blackiron_pavilion", 277.5, 433.2);
_root._mapRegisterTaskNpcMarker("黑铁", "faction", "blackiron_pavilion", 186.9, 514.5);
_root._mapRegisterTaskNpcMarker("牛仔", "faction", "fallen_bar", 522.75, 471.7);
_root._mapRegisterTaskNpcMarker("假肢仙人", "faction", "fallen_street", 753.55, 488.45);
_root._mapRegisterTaskNpcMarker("吸特乐", "faction", "fallen_street", 675.8, 482.0);

_root._mapRegisterTaskNpcMarker("artist", "defense", "first_defense", 161.65, 155.15);
_root._mapRegisterTaskNpcMarker("soldier", "defense", "first_defense", 250.7, 162.6);
_root._mapRegisterTaskNpcMarker("排骨", "defense", "alliance_dock", 137.45, 332.3);
_root._mapRegisterTaskNpcMarker("机哥", "defense", "alliance_dock", 189.45, 333.65);
_root._mapRegisterTaskNpcMarker("阿波", "defense", "alliance_dock", 241.2, 331.65);
_root._mapRegisterTaskNpcMarker("PROPHET", "defense", "alliance_corridor", 228.45, 392.45);

_root._mapRegisterTaskNpcMarker("黑仔", "school", "union_university", 430.05, 508.2);
_root._mapRegisterTaskNpcMarker("Bat", "school", "union_university", 471.4, 529.7);
_root._mapRegisterTaskNpcMarker("Tomboy", "school", "union_university", 516.9, 513.2);
_root._mapRegisterTaskNpcMarker("武器订购系统", "school", "union_university", 570.4, 516.7);
_root._mapRegisterTaskNpcMarker("体育老师", "school", "university_playground", 539.2, 428.65);
_root._mapRegisterTaskNpcMarker("室友", "school", "school_dormitory", 130.3, 347.3);
_root._mapRegisterTaskNpcMarker("程铮", "school", "teaching_interior", 486.65, 255.75);
_root._mapRegisterTaskNpcMarker("剑道社长", "school", "kendo_club", 663.3, 213.1);
_root._mapRegisterTaskNpcMarker("冯佑权", "school", "teaching_interior", 593.3, 211.9);
_root._mapRegisterTaskNpcMarker("理科教授", "school", "science_class", 744.65, 212.35);
_root._mapRegisterTaskNpcMarker("文科老师", "school", "arts_class", 810.9, 213.1);
_root._mapRegisterTaskNpcMarker("Vanshuther", "school", "university_interior", 555.75, 327.2);
_root._mapRegisterTaskNpcMarker("教导主任", "school", "office", 538.9, 104.15);

_root._mapGetInfrastructure = function() {
    if (_root.基建系统 == undefined) return undefined;
    return _root.基建系统.infrastructure;
};

_root._mapPushList = function(target:Array, source:Array) {
    for (var i:Number = 0; i < source.length; i++) {
        target.push(source[i]);
    }
};

_root._mapIsUnlocked = function(groupName:String):Boolean {
    var progress = _root.task_chains_progress;
    var p_main = (progress != undefined) ? progress.主线 : undefined;
    var p_uni = (progress != undefined) ? progress.大学 : undefined;
    var infra = _root._mapGetInfrastructure();

    switch (groupName) {
        case "warlord":
            return (p_main != undefined && infra != undefined && p_main >= 75 && infra.越野车);
        case "rock":
            return (p_main != undefined && infra != undefined && p_main >= 74 && (infra.摩托车 || infra.越野车));
        case "blackiron":
            return (p_main != undefined && infra != undefined && p_main >= 72 && (infra.摩托车 || infra.越野车));
        case "fallen":
            return (infra != undefined && (infra.摩托车 || infra.越野车));
        case "defense":
            return (p_main != undefined && infra != undefined && p_main >= 14 && (infra.自行车 || infra.摩托车 || infra.越野车));
        case "restricted":
            return (p_main != undefined && infra != undefined && p_main >= 76 && infra.越野车);
        case "schoolOutside":
            if (p_uni != undefined && p_uni >= 7) return true;
            return (p_main != undefined && infra != undefined && p_main >= 28 && (infra.摩托车 || infra.越野车));
        case "schoolInside":
            return (p_uni != undefined && p_uni >= 7);
        default:
            return false;
    }
};

_root._mapBuildEnabledHotspotIds = function() {
    var unlocks = _root._mapBuildUnlockFlags();
    var enabled:Array = [];

    _root._mapPushList(enabled, _root._mapBaseHotspotIds);

    if (unlocks.warlord) {
        _root._mapPushList(enabled, _root._mapGroupedHotspotIds.warlord);
    }
    if (unlocks.rock) {
        _root._mapPushList(enabled, _root._mapGroupedHotspotIds.rock);
    }
    if (unlocks.blackiron) {
        _root._mapPushList(enabled, _root._mapGroupedHotspotIds.blackiron);
    }
    if (unlocks.fallen) {
        _root._mapPushList(enabled, _root._mapGroupedHotspotIds.fallen);
    }
    if (unlocks.defense) {
        _root._mapPushList(enabled, _root._mapGroupedHotspotIds.defense);
    }
    if (unlocks.restricted) {
        _root._mapPushList(enabled, _root._mapGroupedHotspotIds.restricted);
    }
    if (unlocks.schoolOutside) {
        _root._mapPushList(enabled, _root._mapGroupedHotspotIds.schoolOutside);
    }
    if (unlocks.schoolInside) {
        _root._mapPushList(enabled, _root._mapGroupedHotspotIds.schoolInside);
    }

    return enabled;
};

_root._mapBuildUnlockFlags = function() {
    return {
        warlord: _root._mapIsUnlocked("warlord"),
        rock: _root._mapIsUnlocked("rock"),
        blackiron: _root._mapIsUnlocked("blackiron"),
        fallen: _root._mapIsUnlocked("fallen"),
        defense: _root._mapIsUnlocked("defense"),
        restricted: _root._mapIsUnlocked("restricted"),
        schoolOutside: _root._mapIsUnlocked("schoolOutside"),
        schoolInside: _root._mapIsUnlocked("schoolInside")
    };
};

_root._mapBuildHotspotStates = function(unlocks) {
    var states:Object = {};
    var hotspotId:String;
    var groupName:String;
    var enabled:Boolean;
    var meta:Object;

    for (var i:Number = 0; i < _root._mapBaseHotspotIds.length; i++) {
        hotspotId = _root._mapBaseHotspotIds[i];
        states[hotspotId] = {
            enabled: true,
            unlockGroup: "",
            lockedReason: ""
        };
    }

    for (groupName in _root._mapGroupedHotspotIds) {
        enabled = !!unlocks[groupName];
        meta = _root._mapUnlockMeta[groupName];
        for (var j:Number = 0; j < _root._mapGroupedHotspotIds[groupName].length; j++) {
            hotspotId = _root._mapGroupedHotspotIds[groupName][j];
            states[hotspotId] = {
                enabled: enabled,
                unlockGroup: groupName,
                lockedReason: enabled ? "" : (meta != undefined ? meta.lockedReason : "区域尚未开放")
            };
        }
    }

    return states;
};

_root._mapResolveCurrentHotspotId = function() {
    var currentFrameName = String(_root.关卡地图帧值 || "");
    if (currentFrameName == "") return "";

    for (var hotspotId in _root._mapNavigateTargets) {
        if (_root._mapNavigateTargets[hotspotId] == currentFrameName) {
            return hotspotId;
        }
    }
    return "";
};

_root._mapResolveCurrentPageId = function(currentHotspotId:String) {
    if (currentHotspotId != undefined && currentHotspotId != "") {
        if (_root._mapHotspotPages[currentHotspotId] != undefined) {
            return _root._mapHotspotPages[currentHotspotId];
        }
    }
    return "base";
};

_root._mapResolveTaskNpcMarkerKey = function(npcName:String) {
    if (npcName == undefined || npcName == "") return "";
    if (_root._mapTaskNpcAliases[npcName] != undefined) {
        return String(_root._mapTaskNpcAliases[npcName]);
    }
    return npcName;
};

_root._mapFindTaskNpcMarker = function(npcName:String) {
    if (npcName == undefined || npcName == "") return undefined;

    var resolvedName = _root._mapResolveTaskNpcMarkerKey(String(npcName));
    if (_root._mapTaskNpcMarkers[resolvedName] != undefined) {
        return _root._mapTaskNpcMarkers[resolvedName];
    }

    var normalizedKey = String(resolvedName).toLowerCase();
    if (_root._mapTaskNpcMarkersLower[normalizedKey] != undefined) {
        return _root._mapTaskNpcMarkersLower[normalizedKey];
    }

    return undefined;
};

_root._mapBuildTaskNpcMarkers = function() {
    var markers:Array = [];
    var seen:Object = {};
    var tasks = _root.tasks_to_do;
    if (tasks == undefined) return markers;

    for (var i:Number = 0; i < tasks.length; i++) {
        if (!_root.taskCompleteCheck(i)) continue;

        var taskData = _root.getTaskData(tasks[i].id);
        if (taskData == undefined) continue;

        if (taskData.finish_npc == undefined) continue;

        var finishNpc = _root._mapResolveTaskNpcMarkerKey(String(taskData.finish_npc));
        if (finishNpc == "" || seen[finishNpc]) continue;

        var markerDef = _root._mapFindTaskNpcMarker(finishNpc);
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
};

_root._mapBuildMarkers = function(currentHotspotId:String) {
    var markers:Array = _root._mapBuildTaskNpcMarkers();
    if (currentHotspotId == undefined || currentHotspotId == "") return markers;

    markers.push({
        id: "current_location",
        kind: "currentLocation",
        pageId: _root._mapResolveCurrentPageId(currentHotspotId),
        hotspotId: currentHotspotId,
        label: "当前位置",
        tone: "accent"
    });

    return markers;
};

_root._mapBuildTips = function(currentHotspotId:String) {
    var tips:Array = [];
    if (currentHotspotId == undefined || currentHotspotId == "") return tips;

    tips.push({
        id: "current_scene",
        pageId: _root._mapResolveCurrentPageId(currentHotspotId),
        hotspotId: currentHotspotId,
        label: "当前位置",
        tone: "accent"
    });

    return tips;
};

_root._mapBuildSnapshot = function() {
    var roommateGender = "";
    var currentHotspotId = _root._mapResolveCurrentHotspotId();
    var currentPageId = _root._mapResolveCurrentPageId(currentHotspotId);
    var unlocks = _root._mapBuildUnlockFlags();
    if (_root.性别 != undefined) {
        roommateGender = String(_root.性别);
    }

    return {
        version: 2,
        defaultPageId: currentPageId,
        regionId: currentPageId,
        currentHotspotId: currentHotspotId,
        unlocks: unlocks,
        enabledHotspotIds: _root._mapBuildEnabledHotspotIds(),
        hotspotStates: _root._mapBuildHotspotStates(unlocks),
        dynamicAvatarState: {
            roommateGender: roommateGender
        },
        markers: _root._mapBuildMarkers(currentHotspotId),
        tips: _root._mapBuildTips(currentHotspotId)
    };
};

_root.gameCommands["mapPanelSnapshot"] = function(params) {
    var callId = params.callId;
    _root._mapLog("mapPanelSnapshot callId=" + callId);

    var resp = {
        task: "map_response",
        callId: callId,
        success: true,
        snapshot: _root._mapBuildSnapshot()
    };

    _root.server.sendSocketMessage(_root._mapJson.stringify(resp));
};

_root.gameCommands["mapPanelNavigate"] = function(params) {
    var callId = params.callId;
    var targetId = String(params.targetId);
    var targetFrame = _root._mapNavigateTargets[targetId];
    _root._mapLog("mapPanelNavigate callId=" + callId + " targetId=" + targetId + " frame=" + targetFrame);

    var resp = {
        task: "map_response",
        callId: callId
    };

    if (targetFrame == undefined) {
        resp.success = false;
        resp.error = "invalid_target";
        _root.server.sendSocketMessage(_root._mapJson.stringify(resp));
        return;
    }

    _root.关卡结束界面._visible = 0;
    _root.场景进入位置名 = "出生地";
    _root.淡出动画.淡出跳转帧(targetFrame);
    if (_root.地图界面 != undefined && _root.地图界面.gotoAndStop != undefined) {
        _root.地图界面.gotoAndStop(1);
    }

    resp.success = true;
    resp.closePanel = true;
    _root.server.sendSocketMessage(_root._mapJson.stringify(resp));
};

_root.gameCommands["mapPanelClose"] = function(params) {
    _root._mapLog("mapPanelClose");
};
