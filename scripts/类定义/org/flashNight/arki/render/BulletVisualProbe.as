import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitManager;

/**
 * 首批子弹原生表现影子采样。Host 从 XFL 派生清单协商具体 linkage；
 * 本类只读 MC/单元体的实际显示状态，不隐藏 Flash、不参与碰撞或伤害。
 */
class org.flashNight.arki.render.BulletVisualProbe {
    private static var MAX_ITEMS:Number = 256;
    private static var enabled:Boolean = false;
    private static var nativeEnabled:Boolean = false;
    private static var ordinary:Object = {};
    private static var chainUnits:Object = {};
    private static var gunPrefixes:Object = {};
    private static var normalBullets:Array = [];
    private static var sceneEpoch:Number = 0;

    public static function configure(caps:Object):Void {
        restoreOwned();
        enabled = false;
        nativeEnabled = false;
        ordinary = {};
        chainUnits = {};
        gunPrefixes = {};
        normalBullets.length = 0;
        if (caps == null || caps.version !== 1
            || (caps.mode !== "shadow" && caps.mode !== "native")
            || !(caps.styles instanceof Array) || !(caps.gunChainPrefixes instanceof Array)
            || caps.styles.length < 1 || caps.styles.length > 16
            || caps.gunChainPrefixes.length < 1 || caps.gunChainPrefixes.length > 16) return;
        var styles:Array = caps.styles;
        for (var i:Number = 0; i < styles.length; i++) {
            var item:Object = styles[i];
            if (typeof item.ordinaryLinkage != "string" || typeof item.gunChainUnitLinkage != "string"
                || item.ordinaryLinkage.length == 0 || item.gunChainUnitLinkage.length == 0) return;
            ordinary[item.ordinaryLinkage] = i;
            chainUnits[item.gunChainUnitLinkage] = i;
        }
        var prefixes:Array = caps.gunChainPrefixes;
        for (var j:Number = 0; j < prefixes.length; j++) {
            if (typeof prefixes[j] != "string" || prefixes[j].length == 0) return;
            gunPrefixes[prefixes[j]] = true;
        }
        nativeEnabled = caps.mode === "native";
        enabled = true;
    }

    public static function disconnect():Void {
        restoreOwned();
        enabled = false;
        nativeEnabled = false;
        normalBullets.length = 0;
        sceneEpoch++;
    }

    public static function resetScene():Void {
        restoreOwned();
        normalBullets.length = 0;
        sceneEpoch++;
    }

    public static function registerNormal(bullet):Void {
        if (!enabled || bullet == null) return;
        if (ordinary[bullet.子弹种类] !== undefined && bullet._parent != undefined) {
            bullet.__nativeVisualOwned = nativeEnabled;
            if (nativeEnabled) bullet.__nativeVisualAlpha = bullet._alpha;
            normalBullets[normalBullets.length] = bullet;
            return;
        }
        if (!nativeEnabled || bullet.chainGroup == undefined) return;
        var type:String = bullet.子弹种类;
        var dash:Number = type.indexOf("-");
        if (dash <= 0 || gunPrefixes[type.substring(0, dash)] !== true) return;
        var group:Object = bullet.chainGroup;
        if (group.isObject && chainUnits["单元体-" + group.子弹种类] !== undefined)
            group.nativeVisualOwned = true;
    }

    private static function restoreOwned():Void {
        var list:Array = normalBullets;
        for (var i:Number = 0; i < list.length; i++) {
            var bullet = list[i];
            if (bullet != null && bullet.__nativeVisualOwned === true) {
                if (bullet._parent != undefined) bullet._alpha = bullet.__nativeVisualAlpha;
                bullet.__nativeVisualOwned = false;
            }
        }
        ChainUnitManager.restoreNativeVisuals();
    }

    public static function flush():Void {
        if (!enabled) return;
        var entries:Array = [];
        var normalCount:Number = 0;
        var overflow:Number = 0;
        var list:Array = normalBullets;
        var n:Number = list.length;
        for (var i:Number = 0; i < n;) {
            var bullet = list[i];
            if (bullet == null || bullet._parent == undefined) {
                n--;
                if (i < n) list[i] = list[n];
                continue;
            }
            i++;
            var owned:Boolean = bullet.__nativeVisualOwned === true;
            if (nativeEnabled && !owned) continue;
            var alpha:Number = owned ? bullet.__nativeVisualAlpha : bullet._alpha;
            if (!bullet._visible || !(alpha > 0)) continue;
            var style:Number = ordinary[bullet.子弹种类];
            if (style === undefined || !isFinite(bullet._x + bullet._y + bullet._rotation
                + bullet._xscale + bullet._yscale + alpha)) {
                if (owned) bullet._alpha = alpha;
                continue;
            }
            if (entries.length >= MAX_ITEMS) {
                overflow++;
                if (owned) {
                    bullet._alpha = alpha;
                    bullet.__nativeVisualOwned = false;
                }
                continue;
            }
            entries[entries.length] = style + "," + bullet._x + "," + bullet._y + ","
                + bullet._rotation + "," + bullet._xscale + "," + bullet._yscale + "," + alpha;
            normalCount++;
            if (owned) bullet._alpha = 0;
        }
        list.length = n;
        var chain:Object = ChainUnitManager.appendVisualShadow(entries, chainUnits, gunPrefixes, MAX_ITEMS, nativeEnabled);
        overflow += chain.overflow;
        var payload:String = sceneEpoch + "|" + _root.帧计时器.当前帧数
            + "|" + normalCount + "|" + chain.count + "|" + overflow
            + "|" + (nativeEnabled ? 1 : 0);
        if (entries.length > 0) payload += ";" + entries.join(";");
        org.flashNight.arki.render.FrameBroadcaster.setBulletVisualPayload(payload);
    }
}
