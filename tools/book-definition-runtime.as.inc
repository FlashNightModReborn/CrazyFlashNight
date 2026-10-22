    private static var _data:Object;
    private static var _loading:Boolean = false;
    private static var _loaded:Boolean = false;
    private static var _cf6:Object;
    private static var _cf6Loading:Boolean = false;
    private static function selected(id:String):String {
        if (id != undefined && id != "") return id;
        return _root._saveExt.bookRun.bookId === "cf6-sting" ? "cf6-sting" : "repair-campus";
    }
    public static function supports(id:String):Boolean { return id === "repair-campus" || id === "cf6-sting"; }
    public static function get(id:String):Object {
        id = selected(id);
        if (id === "cf6-sting") return _cf6;
        if (id !== "repair-campus") return null;
        if (_data == null) _data = fallback();
        return _data;
    }
    public static function ready(id:String):Boolean { return selected(id) === "cf6-sting" ? _cf6 != null : selected(id) === "repair-campus" && _loaded; }
    public static function load(id:String):Void {
        id = selected(id);
        if (id === "cf6-sting") {
            if (_cf6Loading || _cf6 != null) return;
            _cf6Loading = true;
            var cf6Loader:org.flashNight.gesh.json.LoadJson.BaseJSONLoader = new org.flashNight.gesh.json.LoadJson.BaseJSONLoader(
                "data/stages/books/cf6-sting.runtime.json", "LiteJSON");
            cf6Loader.load(function(data:Object):Void { org.flashNight.arki.scene.BookDefinition.acceptFor("cf6-sting", data); },
                function(error:String):Void { org.flashNight.arki.scene.BookDefinition.loadFailedFor("cf6-sting"); });
            return;
        }
        if (id !== "repair-campus") return;
        if (_loading || _loaded) return;
        _loading = true;
        var loader:org.flashNight.gesh.json.LoadJson.BaseJSONLoader = new org.flashNight.gesh.json.LoadJson.BaseJSONLoader(
            "data/stages/books/repair-campus.runtime.json", "LiteJSON");
        loader.load(function(data:Object):Void {
            org.flashNight.arki.scene.BookDefinition.acceptFor("repair-campus", data);
        }, function(error:String):Void {
            org.flashNight.arki.scene.BookDefinition.loadFailed();
        });
    }
    public static function loadFailed():Void { _loading = false; }
    public static function loadFailedFor(id:String):Void { if (id === "cf6-sting") _cf6Loading = false; else if (id === "repair-campus") _loading = false; }
    public static function acceptFor(id:String, data:Object):Boolean {
        loadFailedFor(id);
        if (data.id !== id || !valid(data)) return false;
        if (id === "cf6-sting") { if (_cf6 == null) _cf6 = data; return true; }
        return accept(data);
    }
    public static function accept(data:Object):Boolean {
        if (data.id === "cf6-sting") return acceptFor("cf6-sting", data);
        _loading = false;
        if (!valid(data)) return false;
        _data = data; _loaded = true; return true;
    }
    // Runtime defense for damaged/manual files; the generator also verifies all item/unit identities.
    public static function valid(data:Object):Boolean {
        if (data.id === "cf6-sting") return validCf6(data);
        if (!shape(data, fallback(), 0) || data.schema !== "playable-book.v1"
                || data.id !== "repair-campus" || data.stageName !== "书中历险-修理大学"
                || data.maps.length < 6 || data.maps.length > 8) return false;
        for (var i:Number = 0; i < data.maps.length; i++) {
            var map:Object = data.maps[i];
            if (map.background.indexOf("/") >= 0 || map.background.indexOf("\\") >= 0
                    || map.background.indexOf("..") >= 0 || map.background.substr(-4) !== ".swf"
                    || map.enemies.length == 0 || map.equipment.length == 0 || map.armor.length == 0
                    || map.level.length != 2 || map.level[0] < 1 || map.level[1] > 60 || map.level[0] > map.level[1]
                    || map.count.length != 2 || map.count[0] < 1 || map.count[1] > 8 || map.count[0] > map.count[1]
                    || map.waves < 1 || map.waves > 8) return false;
        }
        return data.bossEncounter.mapIndex == data.maps.length - 1 && data.regularSp <= 100
            && data.firstClearSp <= 100 && data.recordSpPerTier <= 100 && data.recordSp <= 100
            && data.kBudget.mapCount == 6 && data.kBudget.guaranteed <= 1000 && data.kBudget.randomMax <= 1000
            && data.optionalLoot.percent <= 100 && data.optionalLoot.firstMap <= data.optionalLoot.lastMap
            && data.optionalLoot.lastMap < data.maps.length;
    }
    private static function whole(value, low:Number, high:Number):Boolean {
        return typeof value == "number" && !isNaN(value) && isFinite(value)
            && Math.floor(value) == value && !(value < low) && !(value > high);
    }
    private static function validCf6(data:Object):Boolean {
        if (!finiteTree(data,0) || data.schema !== "playable-book.v1" || data.routeId !== "historical"
                || data.stageName !== "书中历险-毒刺行动" || typeof data.title != "string"
                || !whole(data.startingMoney,0,10000000) || !whole(data.startingSkillPoints,0,10000)
                || !(data.maps instanceof Array) || data.maps.length < 1 || data.maps.length > 32) return false;
        var actor:Object = data.actor;
        if (actor.level !== 60 || actor.experience !== 157526193 || typeof actor.name != "string"
                || actor.name == "" || actor.gender !== "男" || !whole(actor.height,100,250)
                || typeof actor.face != "string" || typeof actor.hair != "string"
                || !(actor.equipment instanceof Array) || actor.equipment.length < 1 || actor.equipment.length > 10
                || !(actor.skills instanceof Array) || actor.skills.length < 1 || actor.skills.length > 80) return false;
        var seen:Object = {};
        for (var e:Number=0;e<actor.equipment.length;e++) {
            var equipment:Object=actor.equipment[e];
            if (typeof equipment.slot != "string" || typeof equipment.name != "string"
                    || equipment.enhancement !== 11 || seen["slot."+equipment.slot] === true) return false;
            seen["slot."+equipment.slot]=true;
        }
        for (var s:Number=0;s<actor.skills.length;s++) {
            var skill:Object=actor.skills[s];
            if (typeof skill.name != "string" || skill.name == "" || !whole(skill.level,1,100)
                    || seen["skill."+skill.name] === true) return false;
            seen["skill."+skill.name]=true;
        }
        var mapOrder:String="|TUTORIAL|A01|A02|A03|A04|A05|A06|A08|A09|A10|A11|A12|A13|A14|A15|A16|A17|A18|A19|A20|A22|";
        var previousPosition:Number=-1;
        for (var i:Number=0;i<data.maps.length;i++) {
            var map:Object=data.maps[i];
            var position:Number=mapOrder.indexOf("|"+map.id+"|");
            if (typeof map.id != "string" || map.id == "" || map.id.indexOf("|") >= 0 || !(position > previousPosition) || seen["map."+map.id] === true
                    || typeof map.title != "string" || typeof map.background != "string"
                    || map.background !== (map.id === "TUTORIAL" ? "cf6/CF6_Tutorial_BG.swf" : "cf6/CF6_"+map.id+"_BG.swf")
                    || !org.flashNight.arki.scene.Cf6MapPresentation.valid(map.presentation)
                    || map.mechanism.assetScale !== map.presentation.scale
                    || !(map.dialogue instanceof Array) || map.dialogue.length > 32
                    || !(map.stage.Wave.SubWave instanceof Array) || map.stage.Wave.SubWave.length < 1
                    || map.stage.Wave.SubWave.length > 64) return false;
            seen["map."+map.id]=true;
            previousPosition=position;
            for (var w:Number=0;w<map.stage.Wave.SubWave.length;w++) {
                var enemies:Array=map.stage.Wave.SubWave[w].EnemyGroup.Enemy;
                if (!(enemies instanceof Array) || enemies.length > 128) return false;
                for (var n:Number=0;n<enemies.length;n++) {
                    var enemy:Object=enemies[n];
                    if (typeof enemy.Type != "string" || enemy.Type.substr(0,2) !== "兵种"
                            || !whole(Number(enemy.Type.substr(2)),0,1000000)
                            || !whole(enemy.Level,1,60) || !whole(enemy.Quantity,1,100)) return false;
                }
            }
            if (map.stage.BasicInformation.BookBoss != null) return false;
            if (!validCf6Turrets(map)) return false;
            if (!validCf6Boss(map)) return false;
            for (var l:Number=0;l<map.dialogue.length;l++) {
                var line:Object=map.dialogue[l];
                if (typeof line.speaker != "string" || line.speaker.length > 40 || typeof line.text != "string"
                        || line.text.length < 1 || line.text.length > 160) return false;
            }
        }
        return org.flashNight.arki.scene.Cf6EconomyRules.valid(data);
    }
    private static function validCf6Turrets(map:Object):Boolean {
        // A01 教学炮塔挂接规格(r15):有则校验,无则通过(测试夹具/旧存档投影不带)。
        // 身份字段精确钉死;世界坐标已由装配期 native×128/75 一次换算,此处只验有限范围。
        var spec:Object = map.mechanism.turrets;
        if (spec == null) return true;
        if (map.id !== "A01") return false;
        if (spec.assetUrl !== "flashswf/backgrounds/cf6/CF6_A01_Turret.swf"
                || spec.linkage !== "CF6教学炮塔-A01自动炮"
                || spec.filterMarker !== "cf6-a01-turret-zombie"
                || spec.fireIntervalFrames !== 18 || spec.fireFrameOffset !== 11
                || !(spec.turrets instanceof Array) || spec.turrets.length !== 2) return false;
        for (var i:Number = 0; i < 2; i++) {
            var t:Object = spec.turrets[i];
            if (typeof t.x != "number" || typeof t.y != "number" || isNaN(t.x) || isNaN(t.y)
                    || !isFinite(t.x) || !isFinite(t.y)
                    || t.x < 0 || t.x > 5000 || t.y < 0 || t.y > 5000
                    || t.facing !== "right") return false;
        }
        return true;
    }
    private static function validCf6Boss(map:Object):Boolean {
        var plan:Object=map.bossEncounter;
        if (plan == null) return true;
        var types:Object={A06:"兵种463",A17:"兵种472",A20:"兵种473",A22:"兵种474"};
        if (types[map.id] == undefined || plan.instanceName !== "cf6Boss_"+map.id
                || !whole(plan.maxAlive,1,8) || !whole(plan.maxRanged,0,plan.maxAlive)
                || !whole(plan.intervalFrames,1,1800) || !(plan.groups instanceof Array)
                || plan.groups.length < 1 || plan.groups.length > 16) return false;
        var waves:Array=map.stage.Wave.SubWave;
        if (waves.length != 1 || waves[0].EnemyGroup.Enemy.length != 1) return false;
        var boss:Object=waves[0].EnemyGroup.Enemy[0];
        if (boss.Type !== types[map.id] || boss.Quantity !== 1 || boss.InstanceName !== plan.instanceName
                || (map.id === "A20" && boss.Parameters.老头变身 !== false)) return false;
        var previous:Number=2, total:Number=0;
        for (var g:Number=0;g<plan.groups.length;g++) {
            var group:Object=plan.groups[g];
            if (typeof group.hpRatio != "number" || !(group.hpRatio > 0) || group.hpRatio > 1
                    || !(group.hpRatio < previous) || !(group.enemies instanceof Array)
                    || group.enemies.length < 1 || group.enemies.length > 32) return false;
            previous=group.hpRatio;
            for (var n:Number=0;n<group.enemies.length;n++) {
                var enemy:Object=group.enemies[n];
                if (typeof enemy.Type != "string" || enemy.Type.substr(0,2) !== "兵种"
                        || !whole(Number(enemy.Type.substr(2)),0,1000000) || !whole(enemy.Level,1,60)
                        || !whole(enemy.Quantity,1,128) || typeof enemy.ranged != "boolean"
                        || (enemy.ranged && plan.maxRanged == 0) || enemy.InstanceName != undefined) return false;
                var spawn=enemy.SpawnIndex;
                if (spawn !== "left" && spawn !== "right"
                        && (!(map.stage.SpawnPoint.Point instanceof Array)
                            || !whole(spawn,0,map.stage.SpawnPoint.Point.length-1))) return false;
                var p:Object=enemy.Parameters;
                if (p.cf6BossOwnerToken != undefined || p.cf6SupportIdentity != undefined
                        || p.publishStageEvent != undefined || p.产生源 != undefined || p.InstanceName != undefined) return false;
                if ((enemy.x != undefined && typeof enemy.x != "number")
                        || (enemy.y != undefined && typeof enemy.y != "number")) return false;
                total+=enemy.Quantity;
            }
        }
        return total <= 128;
    }
    private static function finiteTree(value, depth:Number):Boolean {
        if (depth > 24) return false;
        if (value == null) return true;
        if (typeof value == "number") return !isNaN(value) && isFinite(value) && Math.abs(value) < 1000000001;
        if (typeof value == "string") return value.length < 4097;
        if (typeof value == "boolean") return true;
        if (typeof value != "object" || (value instanceof Array && value.length > 512)) return false;
        for (var key:String in value) {
            if (key == "__proto__" || key == "constructor" || key == "prototype" || !finiteTree(value[key],depth+1)) return false;
        }
        return true;
    }
    private static function shape(value, example, depth:Number):Boolean {
        if (depth > 12 || value == null || typeof value != typeof example) return false;
        if (typeof example == "number") return !isNaN(value) && isFinite(value) && value >= 0 && value <= 1000000000 && (Math.floor(example) != example || Math.floor(value) == value);
        if (typeof example == "string") return value.length <= 4096;
        if (typeof example == "boolean") return true;
        if (example instanceof Array) {
            if (!(value instanceof Array) || value.length > 256 || (example.length > 0 && value.length == 0)) return false;
            for (var i:Number = 0; i < value.length; i++) {
                if (example.length == 0 || !shape(value[i], example[Math.min(i, example.length - 1)], depth + 1)) return false;
            }
            return true;
        }
        for (var key:String in example) {
            if (key == "dialogue") {
                if (!(value[key] instanceof Array) || value[key].length > 32) return false;
                for (var lineIndex:Number = 0; lineIndex < value[key].length; lineIndex++) {
                    var line:Object = value[key][lineIndex];
                    if (typeof line.speaker != "string" || line.speaker.length > 40
                            || typeof line.text != "string" || line.text.length == 0 || line.text.length > 160) return false;
                }
            } else if (!shape(value[key], example[key], depth + 1)) return false;
        }
        for (var extra:String in value) if (example[extra] == undefined) return false;
        return true;
    }
