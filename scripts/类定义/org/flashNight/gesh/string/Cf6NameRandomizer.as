import org.flashNight.gesh.string.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Event.*;

/**
 * 闪客快打6（毒刺行动 / 61计划）单位番号与称号随机器
 *
 * 文化母题：
 * 1. C.T特种兵与安保干员：3XF 塔罗编制（16宫廷牌驻防分队 + 40小阿卡那数牌 + 22大阿卡那正/逆位）
 * 2. 星轨斩铁机兵（大刀机器人）：黄道十二宫星链节点（12宫 × α/β/γ/δ = 48机）+ 第十三序列·蛇夫座
 * 3. 「翼」型克隆特工（Wings）：3XF 拉丁/北约克隆体序列（3XF-W01·Alpha ~ 3XF-W26·Zulu + W00 零号/镜影）
 */
class org.flashNight.gesh.string.Cf6NameRandomizer {
    private static var _initialized:Boolean = false;
    private static var _courtPool:BaseNameRandomizer;
    private static var _minorArcanaPool:BaseNameRandomizer;
    private static var _majorArcanaPool:BaseNameRandomizer;
    private static var _zodiacPool:BaseNameRandomizer;
    private static var _wingsPool:BaseNameRandomizer;

    private static var _lockedCourtName:String = null;
    private static var _lockedSceneKey:String = null;
    private static var _isCourtLocked:Boolean = false;
    private static var _wingsZeroToggle:Number = 0;
    private static var _lastRunKey:String = null;

    private static function createPool(items:Array):BaseNameRandomizer {
        var pool:BaseNameRandomizer = new BaseNameRandomizer();
        pool.setRandomEngine(LinearCongruentialEngine.getInstance());
        pool.setUniqueUntilExhaustion(true);
        pool.setNames(items);
        return pool;
    }

    private static function currentRunKey():String {
        var run:Object = (_root != null && _root._saveExt != null) ? _root._saveExt.bookRun : null;
        if (run != null && run.bookId == "cf6-sting") {
            return String(run.slot) + "|" + String(run.routeId) + "|" + String(run.seed) + "|" + String(run.startedAt);
        }
        return "__non_book_run__";
    }

    private static function currentSceneKey():String {
        var timerScene:String = (_root != null && _root.gameworld != null && _root.gameworld.帧计时器 != null)
            ? String(_root.gameworld.帧计时器.当前场景名)
            : "";
        var bgText:String = (_root != null && _root.gameworld != null) ? String(_root.gameworld.背景文字) : "";
        var mgr:Object = org.flashNight.arki.scene.StageManager.instance;
        var stageIdx:String = (mgr != null && mgr.currentStage !== undefined) ? String(mgr.currentStage) : "";
        var bookMapId:String = (mgr != null && typeof mgr.currentBookMapId == "function") ? String(mgr.currentBookMapId()) : "";
        return String(_root.当前通关关卡) + "|" + String(_root.关卡标志) + "|" + bgText + "|" + timerScene + "|" + stageIdx + "|" + bookMapId;
    }

    public static function isCourtDetachmentRoom(mapId:String):Boolean {
        return mapId == "A02" || mapId == "A03" || mapId == "A04" || mapId == "A05" || mapId == "A06"
            || mapId == "A09" || mapId == "A10" || mapId == "A11" || mapId == "A12" || mapId == "A13"
            || mapId == "A14" || mapId == "A15" || mapId == "A17" || mapId == "A18" || mapId == "A19"
            || mapId == "A20";
    }

    public static function bindRoomCourtDetachment(world:Object, mapId:String):String {
        if (!isCourtDetachmentRoom(mapId)) {
            return null;
        }
        var title:String = getCourtDetachmentTitle();
        if (world != null) {
            world.cf6CourtDetachment = title;
        }
        return title;
    }

    public static function resetPools():Void {
        _courtPool = createPool([
            "权杖侍从·先锋组", "权杖骑士·突击组", "权杖王后·火力组", "权杖国王·督战组",
            "圣杯侍从·勤务组", "圣杯骑士·机动组", "圣杯王后·支援组", "圣杯国王·卫戍组",
            "宝剑侍从·侦察组", "宝剑骑士·截击组", "宝剑王后·肃清组", "宝剑国王·裁决组",
            "星币侍从·巡逻组", "星币骑士·重装组", "星币王后·壁垒组", "星币国王·防务组"
        ]);

        // 排除 E1 关卡固定具名数字牌（宝剑十·军械队长），其余 39 张小阿卡那数字牌入池
        var suits:Array = ["权杖", "圣杯", "宝剑", "星币"];
        var ranks:Array = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"];
        var minorCards:Array = [];
        for (var s:Number = 0; s < suits.length; s++) {
            for (var r:Number = 0; r < ranks.length; r++) {
                var cardName:String = suits[s] + ranks[r];
                if (cardName != "宝剑十") {
                    minorCards.push(cardName + "·特勤");
                }
            }
        }
        _minorArcanaPool = createPool(minorCards);

        // 排除 7 张关卡固定具名大阿卡那（VII·战车、XII·倒吊人、XV·恶魔、XVI·高塔、XVII·星星、XX·审判、XXI·世界）
        _majorArcanaPool = createPool([
            "0·愚者", "I·魔术师", "II·女祭司", "III·女皇", "IV·皇帝",
            "V·教皇", "VI·恋人", "VIII·力量", "IX·隐者", "X·命运之轮",
            "XI·正义", "XIII·死神", "XIV·节制", "XVIII·月亮", "XIX·太阳"
        ]);

        var signs:Array = [
            "白羊座", "金牛座", "双子座", "巨蟹座", "狮子座", "处女座",
            "天秤座", "天蝎座", "射手座", "摩羯座", "水瓶座", "双鱼座"
        ];
        var stars:Array = ["α", "β", "γ", "δ"];
        var zodiacNodes:Array = [];
        for (var z:Number = 0; z < signs.length; z++) {
            for (var g:Number = 0; g < stars.length; g++) {
                zodiacNodes.push("黄道星链·" + signs[z] + "·" + stars[g]);
            }
        }
        _zodiacPool = createPool(zodiacNodes);

        _wingsPool = createPool([
            "3XF-W01·Alpha", "3XF-W02·Bravo", "3XF-W03·Charlie", "3XF-W04·Delta",
            "3XF-W05·Echo", "3XF-W06·Foxtrot", "3XF-W07·Golf", "3XF-W08·Hotel",
            "3XF-W09·India", "3XF-W10·Juliet", "3XF-W11·Kilo", "3XF-W12·Lima",
            "3XF-W13·Mike", "3XF-W14·November", "3XF-W15·Oscar", "3XF-W16·Papa",
            "3XF-W17·Quebec", "3XF-W18·Romeo", "3XF-W19·Sierra", "3XF-W20·Tango",
            "3XF-W21·Uniform", "3XF-W22·Victor", "3XF-W23·Whiskey", "3XF-W24·Xray",
            "3XF-W25·Yankee", "3XF-W26·Zulu"
        ]);

        _wingsZeroToggle = 0;
        _isCourtLocked = false;
        _lockedCourtName = null;
        _lockedSceneKey = null;
        _lastRunKey = currentRunKey();
    }

    private static function ensureInitialized():Void {
        if (!_initialized) {
            EventBus.getInstance().subscribe("SceneChanged", onSceneChanged, Cf6NameRandomizer);
            _initialized = true;
            resetPools();
            return;
        }
        var runKey:String = currentRunKey();
        if (runKey != _lastRunKey) {
            resetPools();
        }
    }

    public static function onSceneChanged():Void {
        _isCourtLocked = false;
        _lockedCourtName = null;
        _lockedSceneKey = null;
    }

    public static function getCourtDetachmentTitle():String {
        ensureInitialized();
        var sceneKey:String = currentSceneKey();
        if (!_isCourtLocked || _lockedCourtName == null || _lockedSceneKey != sceneKey) {
            _lockedCourtName = _courtPool.getRandomName();
            _lockedSceneKey = sceneKey;
            _isCourtLocked = true;
        }
        return _lockedCourtName;
    }

    public static function getMinorArcanaTitle(target:Object):String {
        ensureInitialized();
        if (target != null && typeof target.__minorArcana == "string" && target.__minorArcana.length > 0) {
            return target.__minorArcana;
        }
        var name:String = _minorArcanaPool.getRandomName();
        if (target != null) {
            target.__minorArcana = name;
        }
        return name;
    }

    public static function getMajorArcanaTitle(target:Object, isReversed:Boolean):String {
        ensureInitialized();
        var card:String = (target != null && typeof target.__tarotArcana == "string" && target.__tarotArcana.length > 0)
            ? target.__tarotArcana
            : null;
        if (card == null) {
            card = _majorArcanaPool.getRandomName();
            if (target != null) {
                target.__tarotArcana = card;
            }
        }
        return "阿卡那 " + card + (isReversed ? "（逆位）" : "（正位）");
    }

    public static function formatInstructorTitle(currentTitle:String, isReversed:Boolean):String {
        if (typeof currentTitle != "string" || currentTitle.length == 0) {
            return currentTitle;
        }
        if (isReversed) {
            if (currentTitle.indexOf("（正位）") != -1) {
                return currentTitle.split("（正位）").join("（逆位）");
            }
            if (currentTitle.indexOf("·正位") != -1) {
                return currentTitle.split("·正位").join("·逆位");
            }
        } else {
            if (currentTitle.indexOf("（逆位）") != -1) {
                return currentTitle.split("（逆位）").join("（正位）");
            }
            if (currentTitle.indexOf("·逆位") != -1) {
                return currentTitle.split("·逆位").join("·正位");
            }
        }
        return currentTitle;
    }

    public static function getZodiacTitle(target:Object):String {
        ensureInitialized();
        if (target != null && typeof target.__zodiacTitle == "string" && target.__zodiacTitle.length > 0) {
            return target.__zodiacTitle;
        }
        var name:String = _zodiacPool.getRandomName();
        if (target != null) {
            target.__zodiacTitle = name;
        }
        return name;
    }

    public static function getWingsSerialTitle(target:Object):String {
        ensureInitialized();
        if (target != null && typeof target.__wingsSerial == "string" && target.__wingsSerial.length > 0) {
            return target.__wingsSerial;
        }
        var name:String = _wingsPool.getRandomName();
        if (target != null) {
            target.__wingsSerial = name;
        }
        return name;
    }

    public static function getWingsZeroTitle(target:Object):String {
        ensureInitialized();
        if (target != null && typeof target.__wingsZeroTitle == "string" && target.__wingsZeroTitle.length > 0) {
            return target.__wingsZeroTitle;
        }
        var title:String = (_wingsZeroToggle++ % 2 == 0) ? "3XF-W00「零号·Origin」" : "3XF-W00「镜影·Mirror」";
        if (target != null) {
            target.__wingsZeroTitle = title;
        }
        return title;
    }
}
