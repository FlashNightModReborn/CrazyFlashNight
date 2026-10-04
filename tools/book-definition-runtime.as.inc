    private static var _data:Object;
    private static var _loading:Boolean = false;
    private static var _loaded:Boolean = false;
    public static function get():Object {
        if (_data == null) _data = fallback();
        return _data;
    }
    public static function ready():Boolean { return _loaded; }
    public static function load():Void {
        if (_loading || _loaded) return;
        _loading = true;
        var loader:org.flashNight.gesh.json.LoadJson.BaseJSONLoader = new org.flashNight.gesh.json.LoadJson.BaseJSONLoader(
            "data/stages/books/repair-campus.runtime.json", "LiteJSON");
        loader.load(function(data:Object):Void {
            org.flashNight.arki.scene.BookDefinition.accept(data);
        }, function(error:String):Void {
            org.flashNight.arki.scene.BookDefinition.loadFailed();
        });
    }
    public static function loadFailed():Void { _loading = false; }
    public static function accept(data:Object):Boolean {
        _loading = false;
        if (!valid(data)) return false;
        _data = data; _loaded = true; return true;
    }
    // Runtime defense for damaged/manual files; the generator also verifies all item/unit identities.
    public static function valid(data:Object):Boolean {
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
            && data.firstClearSp <= 100 && data.recordSpPerTier <= 100;
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
