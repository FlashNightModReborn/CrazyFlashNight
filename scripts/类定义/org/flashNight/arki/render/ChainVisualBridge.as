import org.flashNight.arki.bullet.BulletComponent.Chain.*;

/**
 * 枪式联弹组级表现协议。出生传 AS2 已采样的角度，后续只传组推进及删除事件。
 * 碰撞、RNG、补弹、霰弹预算仍全由 AS2 决定。配对原生必需模式：能力载荷
 * 校验失败只产生一次受控故障报告；预留耗尽明确报告，不创建回退 MC；
 * 宿主暂停呈现时保留全部存活组，恢复时按当前对象继续发包。
 */
class org.flashNight.arki.render.ChainVisualBridge {
    private static var MAX_UNITS:Number = 15360;
    private static var enabled:Boolean = false;
    private static var granted:Boolean = false;
    private static var faultReported:Boolean = false;
    private static var styles:Object = {};
    private static var prefixes:Object = {};
    private static var groups:Array = [];
    private static var births:Array = [];
    private static var deaths:Array = [];
    private static var epoch:Number = 0;
    private static var sequence:Number = 0;
    private static var nextId:Number = 0;
    private static var nextUnitId:Number = 0;
    private static var reserved:Number = 0;
    private static var maxUnits:Number = MAX_UNITS;
    private static var presenting:Boolean = false;
    public static var overflowGroups:Number = 0;

    public static function configure(caps:Object):Void {
        // 配对原生必需模式：maxUnits 必须与三层统一预留 15360 精确一致。
        var valid:Boolean = caps != null && caps.version === 1
            && (caps.mode === "native" || caps.mode === "shadow")
            && (caps.styles instanceof Array) && (caps.gunChainPrefixes instanceof Array)
            && caps.styles.length >= 1 && caps.styles.length <= 16
            && caps.maxUnits === MAX_UNITS;
        if (!valid) {
            disconnect();
            reportFault("caps_invalid");
            return;
        }
        var nextStyles:Object = {};
        var nextPrefixes:Object = {};
        var list:Array = caps.styles;
        for (var i:Number = 0; i < list.length; i++) {
            var linkage:String = list[i].gunChainUnitLinkage;
            if (linkage === null || linkage === undefined) continue;
            if (typeof linkage != "string" || length(linkage) == 0) {
                disconnect();
                reportFault("caps_style_invalid");
                return;
            }
            nextStyles[linkage] = i;
        }
        list = caps.gunChainPrefixes;
        if (list.length < 1 || list.length > 6) {
            disconnect();
            reportFault("caps_prefix_invalid");
            return;
        }
        for (i = 0; i < list.length; i++) {
            var name:String = list[i];
            // 仅六种对象化枪式；拖尾、滑翔、爆炸不进入本协议。
            if (name != "横向联弹" && name != "横向机枪联弹" && name != "横向手枪联弹"
                && name != "纵向联弹" && name != "纵向机枪联弹" && name != "纵向手枪联弹") {
                disconnect();
                reportFault("caps_prefix_invalid");
                return;
            }
            nextPrefixes[name] = true;
        }
        styles = nextStyles;
        prefixes = nextPrefixes;
        maxUnits = caps.maxUnits;
        if (caps.mode === "native") {
            // 授予或恢复呈现：宿主可能已重置引擎，以新 epoch 全量重发存活组。
            if (!presenting) resyncLiveGroups();
            granted = true;
            enabled = true;
            presenting = true;
        } else {
            // 授予后的 shadow 仅表示宿主暂停呈现；存活组与发包状态全部保留。
            enabled = granted;
            presenting = false;
        }
    }

    public static function disconnect():Void {
        // 传输断连不清空存活组跟踪：nativeGroupOwned 与预留记账原样保留，
        // 重新授予时由 configure 的 resyncLiveGroups 以新 epoch 全量重发
        // 当前存活单元体——不建任何回退 MC，也不带空跟踪继续游戏。
        // 丢弃的只有属于已死连接代的在途增量事件。
        enabled = false;
        granted = false;
        presenting = false;
        births.length = 0;
        deaths.length = 0;
        maxUnits = MAX_UNITS;
        sequence = 0;
        faultReported = false;
    }

    /** 旧世界已销毁时只断开视觉身份，不在新世界重建旧单元。 */
    public static function resetScene():Void {
        for (var i:Number = 0; i < groups.length; i++) groups[i].nativeGroupOwned = false;
        groups.length = 0;
        births.length = 0;
        deaths.length = 0;
        reserved = 0;
        sequence = 0;
        epoch++;
        // 场景退休只清对象/推进 epoch，保留宿主当前授予的呈现状态。
        // registerGroup 首次懒建共享层也会调用此处；若关掉 presenting，
        // 新组仍 nativeGroupOwned 却永远不发 F8，直到下一次能力授予。
        // shadow/断连仍由 configure/disconnect 管理，不由清场重新开启。
    }

    /** 重连/撤销恢复：压实存活组并以新 epoch 全量重排出生，不创建 MC。 */
    private static function resyncLiveGroups():Void {
        births.length = 0;
        deaths.length = 0;
        var alive:Number = 0;
        for (var i:Number = 0; i < groups.length; i++) {
            var group = groups[i];
            if (!group.nativeGroupOwned || group.__removed) {
                if (group.nativeGroupOwned) reserved -= group.nativeReserved;
                group.nativeGroupOwned = false;
                continue;
            }
            groups[alive++] = group;
            var units = group.单元体列表;
            for (var u:Number = 0; u < units.length; u++) {
                var unit = units[u];
                if (unit.nativeLive === true)
                    births[births.length] = {group:group, unit:unit, id:unit.nativeId};
            }
        }
        groups.length = alive;
        epoch++;
        sequence = 0;
    }

    private static function reportFault(reason:String):Void {
        if (faultReported) return;
        faultReported = true;
        trace("[ChainVisualBridge] visual_fault " + reason);
        var sm = _root.server;
        if (sm == undefined) return;
        // 受控故障通道：socket 存活时走 V 快车道（Host 按当前连接代路由进
        // 会话渲染失败）；连接已死时退回受控日志批，断连路径自行裁决。
        var sent:Boolean = false;
        if (sm.sendSocketMessage != undefined)
            sent = sm.sendSocketMessage("Vchain|" + reason) === true;
        if (!sent && sm.sendServerMessage != undefined)
            sm.sendServerMessage("visual_fault|channel=chain|reason=" + reason);
    }

    /** 先 reserve 整组未来峰值。总预留耗尽对已迁移类型是致命源端容量故障：
     *  组仍标记原生所有权（单元体 mc 保持 null，绝不回交 AS2），同时报告一次
     *  由宿主进入会话渲染失败。未被配对白名单承认的组才返回 false 走旧路径。 */
    public static function reserveGroup(group:ChainGroup):Boolean {
        if (!enabled || !group.isObject) return false;
        var b = group.bullet;
        var type:String = b.子弹种类;
        var dash:Number = type.indexOf("-");
        if (dash < 1 || prefixes[type.substring(0, dash)] !== true) return false;
        var style:Number = styles["单元体-" + type.substring(dash + 1)];
        var capacity:Number = Math.ceil(b.霰弹值);
        if (style === undefined || !isFinite(capacity) || capacity < 1) return false;
        group.nativeGroupOwned = true;
        group.nativeGroupId = ++nextId;
        group.nativeStyle = style;
        group.aggregate = true;
        groups[groups.length] = group;
        if (reserved + capacity > maxUnits) {
            // 总硬上限不够：致命源端容量故障。组仍标记原生所有权——调用方据
            // nativeGroupOwned 保持 u.mc 为 null，绝不回交 AS2——但不计入预留、
            // 不发出任何原生单元体，由故障报告经 V 车道结束会话。
            overflowGroups++;
            group.nativeReserved = 0;
            group.nativeStarved = true;
            reportFault("reserve_overflow");
            return true;
        }
        reserved += capacity;
        group.nativeReserved = capacity;
        return true;
    }

    public static function addUnit(group:ChainGroup, unit:ChainUnitData):Void {
        unit.nativeId = ++nextUnitId;
        unit.nativeSent = false;
        unit.nativeLive = true;
        if (!group.nativeGroupOwned) return;
        // 已饥饿组（reserve 时硬上限耗尽）：消耗本单元体，不建 MC 不发原生出生。
        if (group.nativeStarved === true) { unit.nativeLive = false; return; }
        // 霰弹峰值增长超出出生预留：先在总预算内有界再预留；总预算耗尽是
        // 致命源端故障——保持原生所有权，本单元体不建 MC 也不发原生出生，
        // 由故障报告结束会话，绝不回交 AS2 画法。
        var deficit:Number = group.单元体列表.length - group.nativeReserved;
        if (deficit > 0) {
            if (reserved + deficit <= maxUnits) {
                reserved += deficit;
                group.nativeReserved += deficit;
            } else {
                reportFault("reservation_exceeded");
                unit.nativeLive = false;
                return;
            }
        }
        if (births.length >= 2 * MAX_UNITS) {
            reportFault("queue_overflow");
            unit.nativeLive = false;
            return;
        }
        births[births.length] = {group:group, unit:unit, id:unit.nativeId};
    }

    public static function removeUnit(group:ChainGroup, unit:ChainUnitData):Void {
        if (group.nativeGroupOwned && unit.nativeSent)
            deaths[deaths.length] = {group:group, id:unit.nativeId};
        unit.nativeLive = false;
    }

    public static function releaseGroup(group:ChainGroup):Void {
        if (!group.nativeGroupOwned) return;
        reserved -= group.nativeReserved;
        group.nativeGroupOwned = false;
        group.nativeStarved = false;
    }

    public static function isEnabled():Boolean { return enabled; }

    /** FrameBroadcaster 在每个 F 包生成前恰好调用一次，不能丢弃中间事件。
     *  宿主暂停呈现（shadow/断连）时停止发包但保留全部存活跟踪。 */
    public static function flush():String {
        if (!enabled || !presenting) return null;
        var entries:Array = [];
        var group:ChainGroup;
        var b;
        var alive:Number = 0;
        for (var i:Number = 0; i < groups.length; i++) {
            group = groups[i];
            if (!group.nativeGroupOwned || group.__removed) continue;
            groups[alive++] = group;
            b = group.bullet;
            entries[entries.length] = "G," + group.nativeGroupId + "," + group.nativeStyle + ","
                + group.nativeStep + "," + b._x + "," + b._y + "," + b._rotation + ","
                + b._xscale + "," + b._yscale + "," + b._alpha + "," + (b._visible ? 1 : 0)
                + "," + group.nativeAdvance + "," + (group.nativeAdvanceX ? 1 : 0);
        }
        groups.length = alive;
        for (i = 0; i < births.length; i++) {
            var event:Object = births[i];
            group = event.group;
            var u:ChainUnitData = event.unit;
            if (!group.nativeGroupOwned || group.__removed || !u.nativeLive || u.nativeId != event.id) continue;
            if (group.aggregate) ChainUnitManager.materializeUnit(group, u);
            entries[entries.length] = "B," + group.nativeGroupId + "," + u.nativeId + ","
                + u.x + "," + u.y + "," + u.sin + "," + u.cos + "," + u.rot;
            u.nativeSent = true;
        }
        for (i = 0; i < deaths.length; i++) {
            event = deaths[i];
            group = event.group;
            if (group.nativeGroupOwned && !group.__removed)
                entries[entries.length] = "D," + group.nativeGroupId + "," + event.id;
        }
        births.length = 0;
        deaths.length = 0;
        var tick:Number = _root.帧计时器.当前帧数;
        if (!isFinite(tick) || tick < 0) tick = 0;
        var payload:String = "1|" + epoch + "|" + (++sequence) + "|" + tick;
        return entries.length > 0 ? payload + ";" + entries.join(";") : payload;
    }
}
