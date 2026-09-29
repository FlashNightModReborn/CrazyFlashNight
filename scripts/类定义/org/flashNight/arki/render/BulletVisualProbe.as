
/**
 * 首批子弹原生表现快照。配对原生必需模式：能力载荷校验失败只产生一次
 * 受控故障报告；容量/能力撤销不再恢复 Flash 画法，原生暂停期间保留全部
 * 存活状态，恢复时按当前对象重发快照。
 */
class org.flashNight.arki.render.BulletVisualProbe {
    private static var ORDINARY_LIMIT:Number = 1024;
    private static var TOTAL_LIMIT:Number = 16384;
    private static var enabled:Boolean = false;
    private static var nativeEnabled:Boolean = false;
    private static var faultReported:Boolean = false;
    private static var ordinary:Object = {};
    private static var normalBullets:Array = [];
    private static var sceneEpoch:Number = 0;

    public static function configure(caps:Object):Void {
        // 任何能力载荷变化都推进呈现 epoch；宿主侧按新 epoch 重同步。
        sceneEpoch++;
        var valid:Boolean = caps != null && caps.version === 1
            && (caps.mode === "shadow" || caps.mode === "native")
            && (caps.styles instanceof Array) && (caps.gunChainPrefixes instanceof Array)
            && caps.styles.length >= 1 && caps.styles.length <= 16
            && caps.gunChainPrefixes.length >= 1 && caps.gunChainPrefixes.length <= 16
            && caps.maxOrdinary === ORDINARY_LIMIT && caps.maxTotal === TOTAL_LIMIT;
        if (!valid) {
            // 配对协议错误：报告一次，不降级到逐发旧协议。
            releaseAll();
            enabled = false;
            nativeEnabled = false;
            reportFault("caps_invalid");
            return;
        }
        ordinary = {};
        var styles:Array = caps.styles;
        for (var i:Number = 0; i < styles.length; i++) {
            var item:Object = styles[i];
            var hasOrdinary:Boolean = typeof item.ordinaryLinkage == "string" && length(item.ordinaryLinkage) > 0;
            var hasUnit:Boolean = typeof item.gunChainUnitLinkage == "string" && length(item.gunChainUnitLinkage) > 0;
            if (!hasOrdinary && !hasUnit) {
                releaseAll();
                enabled = false;
                nativeEnabled = false;
                reportFault("caps_style_invalid");
                return;
            }
            if (hasOrdinary) ordinary[item.ordinaryLinkage] = i;
        }
        var prefixes:Array = caps.gunChainPrefixes;
        for (var j:Number = 0; j < prefixes.length; j++) {
            if (typeof prefixes[j] != "string" || prefixes[j].length == 0) {
                releaseAll();
                enabled = false;
                nativeEnabled = false;
                reportFault("caps_prefix_invalid");
                return;
            }
        }
        enabled = true;
        // shadow 是配对内的暂停呈现：不归还所有权、不清存活记录，仅停止发包；
        // 恢复 native 时 F5 全量快照天然完成重同步。
        nativeEnabled = caps.mode === "native";
    }

    public static function disconnect():Void {
        // 传输断连不归还 alpha、不清存活清单：已隐藏子弹保持隐藏与所有权，
        // 重连授予后 F5 全量快照继续呈现当前存活对象。断连期间新注册的
        // 子弹仍标记原生所有权（隐藏），绝不回交 AS2 画法。
        nativeEnabled = false;
        faultReported = false;
        sceneEpoch++;
    }

    public static function resetScene():Void {
        releaseAll();
        sceneEpoch++;
    }

    public static function registerNormal(bullet):Void {
        if (!enabled || bullet == null) return;
        if (bullet.chainGroup.nativeGroupOwned === true) return;
        if (ordinary[bullet.子弹种类] !== undefined && bullet._parent != undefined) {
            // 已迁移类型从出生即原生所有；暂停呈现期间仅隐藏不绘制，
            // 绝不以 Flash 画法兜底。
            bullet.__nativeVisualOwned = true;
            bullet.__nativeVisualAlpha = bullet._alpha;
            bullet._alpha = 0;
            normalBullets[normalBullets.length] = bullet;
            return;
        }

    }

    private static function releaseAll():Void {
        // 清场只丢弃旧世界的跟踪；不恢复已退休的 Flash 绘制。
        normalBullets.length = 0;
    }

    private static function reportFault(reason:String):Void {
        if (faultReported) return;
        faultReported = true;
        trace("[BulletVisualProbe] visual_fault " + reason);
        var sm = _root.server;
        if (sm == undefined) return;
        // 受控故障通道：socket 存活时走 V 快车道（Host 按当前连接代路由进
        // 会话渲染失败）；连接已死时退回受控日志批，断连路径自行裁决。
        var sent:Boolean = false;
        if (sm.sendSocketMessage != undefined)
            sent = sm.sendSocketMessage("Vbullet|" + reason) === true;
        if (!sent && sm.sendServerMessage != undefined)
            sm.sendServerMessage("visual_fault|channel=bullet|reason=" + reason);
    }

    public static function flush():Void {
        if (!enabled || !nativeEnabled) return;
        var entries:Array = [];
        var normalCount:Number = 0;
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
            if (!owned) continue;
            var alpha:Number = bullet.__nativeVisualAlpha;
            if (!bullet._visible || !(alpha > 0)) continue;
            var style:Number = ordinary[bullet.子弹种类];
            if (style === undefined || !isFinite(bullet._x + bullet._y + bullet._rotation
                + bullet._xscale + bullet._yscale + alpha)) {
                continue;
            }
            entries[entries.length] = style + "," + bullet._x + "," + bullet._y + ","
                + bullet._rotation + "," + bullet._xscale + "," + bullet._yscale + "," + alpha;
            normalCount++;
            bullet._alpha = 0;
        }
        list.length = n;
        var overflow:Number = normalCount > ORDINARY_LIMIT ? normalCount - ORDINARY_LIMIT : 0;
        if (overflow > 0) reportFault("ordinary_overflow:" + normalCount);
        // F5 只携带普通弹快照；六枪式联弹唯一使用 F8 组协议。
        var payload:String = sceneEpoch + "|" + _root.帧计时器.当前帧数
            + "|" + normalCount + "|0|" + overflow + "|1";
        if (entries.length > 0) payload += ";" + entries.join(";");
        org.flashNight.arki.render.FrameBroadcaster.setBulletVisualPayload(payload);
    }
}
