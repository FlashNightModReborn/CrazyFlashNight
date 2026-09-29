import org.flashNight.arki.render.RayStyleRegistry;
import org.flashNight.arki.render.RayVfxManager;
import org.flashNight.arki.render.VisualRandom;
import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;

/** 有界的射线表现事件桥。AS2 保留命中权威，接管时不创建 MC/path，也不消费战斗 RNG。
 * 配对原生必需模式：能力载荷缺字段/版本不符是明确配对错误（报告一次，不降级到
 * 逐发旧协议或无灯模式）；宿主暂停呈现只挂起提交，存活记录全部保留，恢复时按
 * 当前对象以新 epoch 重发。 */
class org.flashNight.arki.render.RayVisualBridge {
    private static var MAX_ARCS:Number = 1024;
    private static var DRAW_LIMIT:Number = 4096;
    private static var CONFIG_LIMIT:Number = 1024;
    private static var EVENT_LIMIT:Number = 4096;
    private static var QUEUE_BYTE_LIMIT:Number = 4 * 1024 * 1024;
    private static var enabled:Boolean = false;
    private static var granted:Boolean = false;
    private static var presenting:Boolean = false;
    private static var negotiated:Boolean = false;
    private static var lightingEnabled:Boolean = false;
    private static var channelsEnabled:Boolean = false;
    private static var channelByKey:Object = {};
    private static var retiredByKey:Object = {};
    private static var retiredChannels:Array = [];
    private static var retiredCursor:Number = 0;
    private static var sourceSerial:Number = 0;
    private static var shotSerial:Number = 0;
    private static var muzzleSerial:Number = 0;
    private static var channelUpdates:Number = 0;
    private static var channelCoalesced:Number = 0;
    private static var generation:Number = -1;
    private static var epoch:Number = 0;
    private static var sequence:Number = 0;
    private static var gameTick:Number = 0;
    private static var nextId:Number = 0;
    private static var nextKey:Number = 0;
    private static var byStyle:Object = {};
    private static var flameByKey:Object = {};
    private static var records:Array = [];
    private static var configs:Array = [];
    private static var queue:Array = [];
    private static var queuedBytes:Number = 0;
    private static var faultReported:Boolean = false;
    private static var defaultConfig:TeslaRayConfig = null;
    private static var fields:Array = [
        "primaryColor", "secondaryColor", "thickness", "visualDuration", "fadeOutDuration",
        "flickerEnabled", "flickerMin", "flickerMax", "branchCount", "branchProbability",
        "segmentLength", "jitter", "shimmerAmp", "shimmerFreq", "forkThicknessMul",
        "paletteScrollSpeed", "stripeCount", "distortAmp", "distortWaveLen", "waveAmp",
        "waveLen", "waveSpeed", "pulseAmp", "pulseRate", "hitRippleSize", "hitRippleAlpha",
        "railSpread", "convergenceRatio", "railCount", "nodeCount", "nodeSpeed", "crosshairScale",
        "slicesCount", "sliceSpacing", "sliceRadius", "sliceCompressX", "angVelDeg", "counterRotate",
        "phaseOffsetDeg", "pulseWidth", "baseIdleAlpha", "mixedColor", "spineColor", "glowAlpha",
        "glowWidthMult", "nDiagonals", "linkerStride", "tongueCount", "tipBloomScale", "smokeColor",
        "flameReuseMaxOriginDist"
    ];

    public static function configure(caps:Object):Void {
        var names:Array = RayStyleRegistry.getStyleNames();
        var valid:Boolean = caps != null && caps.version === 1 && typeof caps.generation == "number"
            && finite(caps.generation) && caps.generation >= 1 && caps.generation <= 1000000000
            && caps.generation == Math.floor(caps.generation) && (caps.styles instanceof Array)
            && caps.styles.length == 12 && caps.maxArcs === MAX_ARCS
            && caps.drawLimit === DRAW_LIMIT && caps.configLimit === CONFIG_LIMIT
            && caps.channelVersion === 1 && caps.lightingVersion === 1;
        var proposed:Object = null;
        if (valid) {
            proposed = {};
            for (var i:Number = 0; i < names.length; i++) {
                if (caps.styles[i].index !== i || caps.styles[i].id !== names[i]) { valid = false; break; }
                proposed[names[i]] = i;
            }
        }
        if (!valid) {
            // 配对协议错误：明确报告一次，不降级到逐发旧协议或无灯模式。
            // negotiated 置回未配对前的归属语义——后续生成的射线不再落回 AS2，
            // 因为 faultReported 已置位，trySpawn 走消耗路径（见 trySpawn 门控）。
            negotiated = false;
            disconnect();
            reportFault("caps_invalid");
            return;
        }
        if (caps.generation < generation) return;
        if (caps.generation != generation) {
            // 新连接代不清空存活跟踪：重新授予时以新 epoch 全量重发当前对象。
            generation = caps.generation;
            granted = false;
            presenting = false;
        }
        var active:Boolean = caps["native"] === true;
        if (active) {
            faultReported = false;
            if (!presenting) {
                // 授予或恢复呈现：宿主侧引擎已重置，丢弃在途增量队列，
                // 以新 epoch 全量重发当前存活配置与记录。
                epoch++;
                sequence = 0;
                queue.length = 0;
                queuedBytes = 0;
                reemitLiveState();
            }
            granted = true;
            enabled = true;
            presenting = true;
        } else {
            // 配对内 shadow 仅表示宿主暂停呈现；所有权与存活记录全部保留，
            // trySpawn 继续入账，flush 停止发包，恢复授予时整体重发。
            presenting = false;
        }
        negotiated = true;
        lightingEnabled = granted;
        channelsEnabled = granted;
        byStyle = proposed;
    }
    public static function applyCaps(caps:Object):Void { configure(caps); }
    public static function requireNative():Void { reportFault("native_unavailable"); }

    public static function disconnect():Void {
        // 传输断连不清空存活记录/配置/通道身份：重新授予后按新 epoch 全量重发，
        // 避免重连后存活射线失去所有权。仅丢弃属于已死连接代的在途队列。
        enabled = false; granted = false; presenting = false;
        lightingEnabled = false; channelsEnabled = false; generation = -1;
        faultReported = false;
        queue.length = 0;
        queuedBytes = 0;
    }
    public static function resetScene():Void {
        epoch++; sequence = 0; gameTick = 0; nextId = 0; nextKey = 0;
        records = []; configs = []; queue = []; queuedBytes = 0; flameByKey = {}; channelByKey = {};
        channelUpdates = 0; channelCoalesced = 0;
        retiredByKey = {}; retiredChannels = []; retiredCursor = 0;
    }
    private static function reportFault(reason:String):Void {
        if (faultReported) return;
        faultReported = true;
        trace("[RayVisualBridge] visual_fault " + reason);
        var sm = _root.server;
        if (sm == undefined) return;
        // 受控故障通道：socket 存活时走 V 快车道（Host 按当前连接代路由进
        // 会话渲染失败）；连接已死时退回受控日志批，断连路径自行裁决。
        var sent:Boolean = false;
        if (sm.sendSocketMessage != undefined)
            sent = sm.sendSocketMessage("Vray|" + reason) === true;
        if (!sent && sm.sendServerMessage != undefined)
            sm.sendServerMessage("visual_fault|channel=ray|reason=" + reason);
    }
    // 恢复呈现时以 'c'/'l'/'s' 重发全部存活定义与记录；不创建任何 MC。
    private static function reemitLiveState():Void {
        for (var c:Number = 0; c < configs.length; c++) {
            var entry:Object = configs[c];
            queue.push(entry.wire); queuedBytes += entry.wire.length + 1;
            if (entry.lightWire != null) { queue.push(entry.lightWire); queuedBytes += entry.lightWire.length + 1; }
        }
        records.sortOn("id", Array.NUMERIC);
        for (var i:Number = 0; i < records.length; i++) {
            var r:Object = records[i];
            var wire:String = spawnWire(r, "s");
            queue.push(wire); queuedBytes += wire.length + 1;
            r.queueIndex = -1;
            r.queueSequence = -1;
            if (queuedBytes > QUEUE_BYTE_LIMIT) reportFault("reemit_overflow");
        }
    }
    /** Snapshot the real committed firing lane before BulletFactory shallow-copies props. */
    public static function captureShot(owner:Object, slot:String, muzzle:MovieClip,
                                       props:Object, weapon:Object):Void {
        if (props == null) return;
        props._rayVisualShot = null;
        if (!channelsEnabled || Number(props.霰弹值) !== 1) return;
        var attribute:Object = BulletInitializer.getAttributeData(props.子弹种类);
        // Factory uses the prepared split, not an assumed one-projectile weapon category.
        if (attribute.rayConfig == undefined
            || (attribute.霰弹值 != undefined && Number(attribute.霰弹值) !== 1)) return;
        var version:Number = Number(owner.version);
        var frame:Number = Number(_root.帧计时器.当前帧数);
        if (typeof owner != "movieclip" || !finite(version) || !(version > 0)
            || version != Math.floor(version) || !finite(frame) || frame < 0
            || typeof slot != "string" || length(slot) == 0 || length(slot) > 64
            || typeof muzzle != "movieclip" || weapon == null || typeof weapon != "object"
            || owner[slot] !== weapon || typeof owner._name != "string") return;
        // Read the actual muzzle ancestry now; never compare a saved MovieClip after unload/rebind.
        var parent:MovieClip = muzzle;
        var belongs:Boolean = false;
        for (var depth:Number = 0; depth < 16 && parent != null; depth++) {
            if (parent === owner) { belongs = true; break; }
            parent = parent._parent;
        }
        if (!belongs) return;
        var muzzleId:Number = Number(muzzle.__rayVisualMuzzleId);
        if (!finite(muzzleId) || !(muzzleId > 0)) {
            muzzleId = ++muzzleSerial;
            muzzle.__rayVisualMuzzleId = muzzleId;
        }
        var state:Object = owner.__rayVisualSources;
        if (state == null || state.version !== version) {
            state = {version:version, entries:[]};
            owner.__rayVisualSources = state;
        }
        var entries:Array = state.entries;
        // Replacing a weapon invalidates that slot even when a prior same-named object returns later.
        for (var oldIndex:Number = entries.length - 1; oldIndex >= 0; oldIndex--) {
            if (entries[oldIndex].slot === slot && entries[oldIndex].weapon !== weapon) {
                entries[oldIndex] = entries[entries.length - 1]; entries.length--;
            }
        }
        var source:Object = null;
        for (var i:Number = 0; i < entries.length; i++) {
            var entry:Object = entries[i];
            if (entry.slot === slot && entry.weapon === weapon && entry.muzzleId === muzzleId) {
                source = entry; break;
            }
        }
        if (source == null) {
            // Bounded per actor: rebuilt poses or unusual script emitters can safely remain independent.
            if (entries.length == 32) return;
            source = {slot:slot, weapon:weapon, muzzleId:muzzleId, id:++sourceSerial};
            entries.push(source);
        }
        if (shotSerial == 1000000000) return;
        props._rayVisualShot = {source:source.id, serial:++shotSerial, version:version,
            ownerName:String(owner._name), frame:frame};
    }

    /** Lifecycle entry. Freeze values, not a live MC/weapon or the mutable gun props object. */
    public static function bindBulletIdentity(bullet:Object):Void {
        bullet._rayVisualIdentity = null;
        bullet._rayVisualPath = "";
        var shot:Object = bullet._rayVisualShot;
        if (shot == null || !channelsEnabled) return;
        var owner:Object = _root.gameworld[bullet.发射者名];
        if (shot.ownerName !== String(bullet.发射者名) || owner.version !== shot.version
            || shot.frame !== Number(_root.帧计时器.当前帧数)
            || !(shot.source > 0) || !(shot.serial > 0)) return;
        bullet._rayVisualIdentity = {source:shot.source, serial:shot.serial};
    }

    /** Capture geometric target topology before hit/kill callbacks can unload or replace an MC. */
    public static function noteTarget(bullet:Object, target:Object):Void {
        if (bullet._rayVisualIdentity == null || bullet._rayVisualPath === null) return;
        var version:Number = Number(target.version);
        var name:String = target._name;
        if (typeof target != "movieclip" || !finite(version) || !(version > 0)
            || version != Math.floor(version) || typeof name != "string" || length(name) == 0) {
            bullet._rayVisualPath = null; return;
        }
        var path:String = bullet._rayVisualPath;
        path += "/" + version + ":" + length(name) + ":" + name;
        bullet._rayVisualPath = length(path) > 512 ? null : path;
    }

    public static function flameKey(bullet:Object):String {
        var identity:Object = bullet._rayVisualIdentity;
        if (channelsEnabled && identity != null) return "source:" + identity.source + ":" + String(bullet.子弹种类);
        return String(bullet.发射者名) + ":" + String(bullet.子弹种类);
    }

    public static function channelMeta(bullet:Object, meta:Object):Object {
        var identity:Object = bullet._rayVisualIdentity;
        if (identity == null || meta == null) return meta;
        var path:String = meta.isHit === false ? "miss" : bullet._rayVisualPath;
        if (path == null || length(path) == 0) return meta;
        meta.visualChannelSource = identity.source;
        meta.visualChannelSerial = identity.serial;
        meta.visualChannelTopology = path;
        return meta;
    }
    private static function finite(value:Number):Boolean { return (value - value) == 0; }
    private static function num(value, fallback:Number):Number {
        if (value == undefined) return fallback;
        var result:Number = Number(value);
        return finite(result) ? result : fallback;
    }
    private static function integer(value, fallback:Number):Number {
        var result:Number = num(value, fallback);
        return result > 0 ? Math.floor(result) : 0;
    }
    public static function copyMeta(meta:Object, ox:Number, oy:Number):Object {
        var result:Object = {};
        if (meta != null) for (var key:String in meta) result[key] = meta[key];
        result.hitPoints = copyPoints(meta.hitPoints, ox, oy);
        result.damageHitPoints = copyPoints(meta.damageHitPoints, ox, oy);
        return result;
    }
    private static function copyPoints(points:Array, ox:Number, oy:Number):Array {
        if (points == null) return null;
        var result:Array = [];
        for (var i:Number = 0; i < points.length; i++) result[i] = {x:points[i].x + ox, y:points[i].y + oy};
        return result;
    }
    private static function pointsWire(points:Array):String {
        if (points == null) return "-";
        if (points.length == 0) return "!";
        if (points.length > 128) return null;
        var output:String = "";
        for (var i:Number = 0; i < points.length; i++) {
            var x:Number = Number(points[i].x), y:Number = Number(points[i].y);
            if (!finite(x) || !finite(y) || Math.abs(x) > 1000000 || Math.abs(y) > 1000000) return null;
            output += (i == 0 ? "" : "/") + x + ":" + y;
        }
        return output;
    }
    private static function configId(config:TeslaRayConfig, style:Number):Number {
        var light:Array = readLight(config);
        if (light == null) return 0;
        if (defaultConfig == null) defaultConfig = new TeslaRayConfig();
        for (var i:Number = configs.length - 1; i >= 0; i--)
            if (configs[i].source === config && configs[i].style == style && sameConfig(config, configs[i], light)) return i + 1;
        if (configs.length == CONFIG_LIMIT) { reportFault("config_overflow"); return 0; }
        var id:Number = configs.length + 1;
        var wire:String = "c," + id + "," + style;
        var values:Array = [];
        for (var k:Number = 0; k < fields.length; k++) {
            var name:String = fields[k];
            var value:Number = (k == 5 || k == 37) ? (config[name] === true ? 1 : 0)
                : num(config[name], Number(defaultConfig[name]));
            var limit:Number = (k == 0 || k == 1 || k == 41 || k == 42 || k == 49) ? 16777215 : 1000000;
            if (!finite(value) || Math.abs(value) > limit) return 0;
            if ((k == 3 || k == 4) && (value < 0 || value > 600)) return 0;
            if (k == 2 && (value < 0 || value > 512)) return 0;
            if (limit == 16777215 && (value < 0 || value != Math.floor(value))) return 0;
            wire += "," + value;
            values[k] = value;
        }
        var palette:Array = config.palette;
        if (palette == null || palette.length == 0) wire += ",-";
        else {
            // 32-float draw record carries seven palette colours; reject larger custom palettes as a pairing error.
            if (palette.length > 7) return 0;
            for (var p:Number = 0; p < palette.length; p++) {
                var color:Number = Number(palette[p]);
                if (!finite(color) || color < 0 || color > 16777215 || color != Math.floor(color)) return 0;
                wire += (p == 0 ? "," : ":") + color;
            }
        }
        var lightWire:String = lightingEnabled ? "l," + id + "," + light[0] + "," + light[1]
            + "," + light[2] + "," + light[3] + "," + light[4] : null;
        if (queuedBytes + wire.length + (lightWire == null ? 0 : lightWire.length + 1) > QUEUE_BYTE_LIMIT) return 0;
        // Config and its optional light record are queued atomically and adjacently.
        queue.push(wire); queuedBytes += wire.length + 1;
        if (lightWire != null) { queue.push(lightWire);queuedBytes += lightWire.length + 1; }
        configs.push({source:config, style:style, values:values, light:light,
            palette:palette == null ? null : palette.slice(0), wire:wire, lightWire:lightWire});
        return id;
    }

    private static function sameConfig(config:TeslaRayConfig, cached:Object, light:Array):Boolean {
        for (var li:Number = 0; li < 5; li++) if (cached.light[li] !== light[li]) return false;
        for (var i:Number = 0; i < fields.length; i++) {
            var name:String = fields[i];
            var value:Number = (i == 5 || i == 37) ? (config[name] === true ? 1 : 0)
                : num(config[name], Number(defaultConfig[name]));
            if (cached.values[i] !== value) return false;
        }
        var a:Array = config.palette, b:Array = cached.palette;
        if (a == null || b == null) return a == null && b == null;
        if (a.length != b.length) return false;
        for (var c:Number = 0; c < a.length; c++) if (a[c] !== b[c]) return false;
        return true;
    }
    private static function readLight(config:TeslaRayConfig):Array {
        var profile = typeof(config.lightProfile) == "undefined" ? "auto" : config.lightProfile;
        if (typeof(profile) != "string" || (profile != "auto" && profile != "none" && profile != "flame"
            && profile != "beam" && profile != "heavy" && profile != "arc" && profile != "glyph")) return null;
        var energy = typeof(config.lightEnergyScale) == "undefined" ? 1 : config.lightEnergyScale;
        var width = typeof(config.lightWidthScale) == "undefined" ? 1 : config.lightWidthScale;
        var color = typeof(config.lightColor) == "undefined" ? -1 : config.lightColor;
        var fade = typeof(config.lightFadeTicks) == "undefined" ? -1 : config.lightFadeTicks;
        if (typeof(energy) != "number" || typeof(width) != "number" || typeof(color) != "number" || typeof(fade) != "number"
            || !finite(energy) || !finite(width) || !finite(color) || !finite(fade)
            || energy < 0 || energy > 2 || width < 0.25 || width > 4
            || color < -1 || color > 16777215 || color != Math.floor(color)
            || fade < -1 || fade > 30 || fade != Math.floor(fade)) return null;
        return [profile, energy, width, color, fade];
    }
    private static function visualAge(r:Object, tick:Number):Number {
        return tick - r.birthTick - (r.delay > 0 ? r.delay - 1 : 0);
    }
    // 's'/'u' wire built from the frozen record fields; identical layout to the
    // live-spawn path so a re-emitted birth parses exactly like the original.
    private static function spawnWire(r:Object, operation:String):String {
        var meta:Object = r.meta;
        var points:String = pointsWire(meta.hitPoints);
        var damagePoints:String = pointsWire(meta.damageHitPoints);
        var intensity:Number = num(meta.intensity, 1);
        var hitIndex:Number = integer(meta.hitIndex, 0), pulseIndex:Number = integer(meta.pulseIndex, 0);
        var pulseCount:Number = integer(meta.pulseCount, 0);
        var flags:Number = (meta.isHotPulse === true ? 1 : 0) + (meta.isDamagePulse !== false ? 2 : 0)
            + (meta.isBlocked === true ? 4 : 0);
        return operation + "," + r.id + "," + r.configId + "," + r.birthTick + "," + r.delay
            + "," + r.startX + "," + r.startY + "," + r.endX + "," + r.endY
            + "," + r.kind + "," + hitIndex + "," + intensity
            + "," + (meta.isHit !== false ? 1 : 0) + "," + r.seed + "," + r.keyId + "," + r.serial
            + "," + r.targetLength + "," + pulseIndex + "," + pulseCount + "," + flags
            + "," + points + "," + damagePoints + ",0";
    }
    private static function materializeOffset(r:Object, ox:Number, oy:Number):Void {
        if (!r.awaitingOffset || visualAge(r, gameTick) < 1) return;
        var dx:Number = ox - r.offsetX, dy:Number = oy - r.offsetY;
        r.startX += dx; r.startY += dy; r.endX += dx; r.endY += dy;
        r.meta = copyMeta(r.meta, dx, dy);
        r.awaitingOffset = false;
    }

    public static function trySpawn(sx:Number, sy:Number, ex:Number, ey:Number,
                                     config:TeslaRayConfig, meta:Object):Boolean {
        // 三态归属：从未配对 → 返回 false，由生产调用方报告原生不可用；
        // 已配对但呈现挂起（断连/shadow）→ 继续入账存活记录，重授予时全量重发；
        // 已报致命故障 → 消耗本次生成，绝不让已迁移射线回交 AS2。
        if (faultReported) return true;
        if (!negotiated) return false;
        if (config == null) return false;
        var style:Number = byStyle[config.vfxStyle];
        if (style == undefined) return false;
        var offset:Object = SceneCoordinateManager.effectOffset;
        var ox:Number = num(offset.x, 0), oy:Number = num(offset.y, 0);
        sx += ox; sy += oy; ex += ox; ey += oy;
        // 已协商通道上的畸形/越界入参是源端协议错误：报告一次并消耗本次
        // 生成（返回 true 不建 Flash MC），由宿主故障路径结束会话。
        if (!finite(sx + sy + ex + ey) || Math.abs(sx) > 1000000 || Math.abs(sy) > 1000000
            || Math.abs(ex) > 1000000 || Math.abs(ey) > 1000000) { reportFault("bounds_invalid"); return true; }
        var saved:Object = copyMeta(meta, ox, oy);
        var kind:Number = saved.segmentKind == "chain" ? 1 : saved.segmentKind == "fork" ? 2
            : saved.segmentKind == "pierce" ? 3 : saved.segmentKind == "flame" ? 4 : 0;
        var delay:Number = Math.ceil(RayVfxManager.computeSegmentDelay(config, saved));
        if (!finite(delay) || delay > 600) { reportFault("delay_invalid"); return true; }
        if (delay < 0) delay = 0;
        var points:String = pointsWire(saved.hitPoints), damagePoints:String = pointsWire(saved.damageHitPoints);
        if (points == null || damagePoints == null) { reportFault("meta_invalid"); return true; }
        var cfg:Number = configId(config, style);
        if (cfg == 0) { reportFault("config_rejected"); return true; }
        var serial:Number = integer(saved.flameVfxSerial, 0);
        var source:Number = integer(saved.visualChannelSource, 0);
        var topology:String = saved.visualChannelTopology;
        var generic:Boolean = channelsEnabled && style < 10 && kind < 4 && delay == 0
            && source > 0 && typeof topology == "string" && length(topology) > 0 && length(topology) <= 512;
        var r:Object = null;
        var prior:Object = null;
        var retired:Object = null;
        var key:String = null;
        if (generic) {
            serial = integer(saved.visualChannelSerial, 0);
            if (!(serial > 0)) generic = false;
        }
        if (generic) {
            key = source + ":" + cfg + ":" + kind + ":" + integer(saved.hitIndex, 0) + ":" + topology;
            prior = channelByKey["$" + key];
            retired = retiredByKey["$" + key];
            if (prior == null && retired != null && serial <= retired.serial) return true;
            r = prior;
            if (r != null && serial < r.serial) return true;
            if (r != null && (visualAge(r, gameTick) > r.life || !canReuseChannel(r, sx, sy, ex, ey))) r = null;
        } else if (style == 11 && kind == 4 && saved.flameVfxKey != undefined) {
            key = String(saved.flameVfxKey);
            r = flameByKey["$" + key]; prior = r;
            if (r != null && r.serial > 0 && serial > 0 && serial < r.serial) return true;
            if (r != null && (r.configId !== cfg || !canReuse(r, sx, sy, ex, ey, serial, config))) r = null;
        }
        var updating:Boolean = r != null;
        var pending:Boolean = updating && r.configId === cfg && r.queueSequence === sequence && r.queueIndex >= 0;
        if (!pending && queue.length >= EVENT_LIMIT) { reportFault("queue_overflow"); return true; }
        if (!updating && records.length >= MAX_ARCS) { reportFault("arc_overflow"); return true; }
        var targetLength:Number = num(saved.targetLength, 0);
        if (targetLength < 0) targetLength = 0;
        if (updating && !generic) {
            // Flame's authored growth/retraction contract is deliberately unchanged.
            var dx:Number = ex - sx, dy:Number = ey - sy;
            var newLength:Number = Math.sqrt(dx * dx + dy * dy);
            var oldX:Number = r.endX - r.startX, oldY:Number = r.endY - r.startY;
            var oldLength:Number = Math.sqrt(oldX * oldX + oldY * oldY);
            if (newLength < oldLength && (!(targetLength > 0) || !(r.targetLength > 0) || targetLength >= r.targetLength - 1)) {
                ex = sx + dx / newLength * oldLength; ey = sy + dy / newLength * oldLength;
                saved.visualLengthKept = true;
            }
            if (r.meta.shotSeed != undefined) saved.shotSeed = r.meta.shotSeed;
        }
        var id:Number = updating ? r.id : nextId + 1;
        var channel:Number = updating ? r.keyId : prior != null ? prior.keyId : retired != null ? retired.keyId : key == null ? 0 : nextKey + 1;
        var seed:Number = updating ? r.seed : VisualRandom.eventSeed(4);
        var intensity:Number = num(saved.intensity, 1);
        var hitIndex:Number = integer(saved.hitIndex, 0), pulseIndex:Number = integer(saved.pulseIndex, 0);
        var pulseCount:Number = integer(saved.pulseCount, 0);
        if (intensity < 0 || intensity > 1000 || hitIndex > 1000000 || pulseIndex > 1000000 || pulseCount > 1000000
            || serial > 1000000000 || targetLength > 1000000) { reportFault("meta_invalid"); return true; }
        var flags:Number = (saved.isHotPulse === true ? 1 : 0) + (saved.isDamagePulse !== false ? 2 : 0)
            + (saved.isBlocked === true ? 4 : 0);
        var pulse:Boolean = !updating || !generic || serial > r.serial;
        var birth:Number = pulse ? gameTick : r.birthTick;
        var phase:Number = generic && updating ? genericPhase(r, gameTick) : 0;
        var operation:String = pending ? r.queueOperation : updating ? "u" : "s";
        var wire:String = operation + "," + id + "," + cfg + "," + birth + "," + delay
            + "," + sx + "," + sy + "," + ex + "," + ey + "," + kind + "," + hitIndex + "," + intensity
            + "," + (saved.isHit !== false ? 1 : 0) + "," + seed + "," + channel + "," + serial
            + "," + targetLength + "," + pulseIndex + "," + pulseCount + "," + flags + "," + points + "," + damagePoints + ",0";
        var queueIndex:Number = -1;
        if (presenting) {
            var oldBytes:Number = pending ? length(queue[r.queueIndex]) + 1 : 0;
            if (queuedBytes - oldBytes + length(wire) + 1 > QUEUE_BYTE_LIMIT) { reportFault("wire_overflow"); return true; }
            queueIndex = pending ? r.queueIndex : queue.length;
            queue[queueIndex] = wire;
            queuedBytes += length(wire) + 1 - oldBytes;
        }
        if (pending) channelCoalesced++;
        if (updating && generic) channelUpdates++;
        if (!updating) {
            nextId = id; if (channel > nextKey) nextKey = channel;
            r = {id:id, key:key, keyId:channel, seed:seed, phaseBirth:birth, kind:kind,
                offsetX:ox, offsetY:oy, awaitingOffset:delay > 1, genericChannel:generic, phaseAtBirth:0};
            records.push(r);
        } else if (generic && pulse) r.phaseAtBirth = phase;
        r.configId = cfg; r.queueSequence = sequence; r.queueIndex = queueIndex; r.queueOperation = operation;
        r.startX = sx; r.startY = sy; r.endX = ex; r.endY = ey;
        r.visualDuration = configs[cfg - 1].values[3]; r.meta = saved; r.delay = delay; r.birthTick = birth;
        r.serial = serial; r.targetLength = targetLength;
        r.life = r.visualDuration + configs[cfg - 1].values[4];
        if (key != null) {
            if (generic) {
                channelByKey["$" + key] = r;
                if (retired != null) delete retiredByKey["$" + key];
            }
            else flameByKey["$" + key] = r;
        }
        return true;
    }
    private static function retireChannel(r:Object):Void {
        var index:Number = retiredCursor;
        var old:Object = retiredChannels[index];
        if (old != null && retiredByKey["$" + old.key] === old) delete retiredByKey["$" + old.key];
        var retired:Object = {key:r.key, keyId:r.keyId, serial:r.serial};
        retiredChannels[index] = retired; retiredByKey["$" + r.key] = retired;
        retiredCursor = (index + 1) % MAX_ARCS;
        delete channelByKey["$" + r.key];
    }
    private static function genericPhase(r:Object, tick:Number):Number {
        var age:Number = tick - r.birthTick;
        if (age < 0) age = 0;
        if (age > r.visualDuration) age = r.visualDuration;
        return r.phaseAtBirth + age;
    }
    private static function canReuseChannel(r:Object, sx:Number, sy:Number, ex:Number, ey:Number):Boolean {
        var dx:Number = ex - sx, dy:Number = ey - sy;
        var oldX:Number = r.endX - r.startX, oldY:Number = r.endY - r.startY;
        var size:Number = dx * dx + dy * dy, oldSize:Number = oldX * oldX + oldY * oldY;
        if (!(size > 1) || !(oldSize > 1)) return false;
        // A moved/turned channel is a new exact segment, never an interpolated fake connection.
        if ((dx * oldX + dy * oldY) / Math.sqrt(size * oldSize) < 0.998629534754574) return false;
        var ox:Number = sx - r.startX, oy:Number = sy - r.startY;
        var tx:Number = ex - r.endX, ty:Number = ey - r.endY;
        return ox * ox + oy * oy <= 1024 && tx * tx + ty * ty <= 4096;
    }
    private static function canReuse(r:Object, sx:Number, sy:Number, ex:Number, ey:Number,
                                      serial:Number, config:TeslaRayConfig):Boolean {
        var dx:Number = ex - sx, dy:Number = ey - sy;
        var oldX:Number = r.endX - r.startX, oldY:Number = r.endY - r.startY;
        var lengthSq:Number = dx * dx + dy * dy, oldLengthSq:Number = oldX * oldX + oldY * oldY;
        if (!(lengthSq > 1) || !(oldLengthSq > 1)) return false;
        if ((dx * oldX + dy * oldY) / Math.sqrt(lengthSq * oldLengthSq) < 0.965925826) return false;
        if (r.serial > 0 && serial > r.serial) return true;
        var maxDist:Number = num(config.flameReuseMaxOriginDist, 32);
        if (!(maxDist > 0)) maxDist = 32;
        var ox:Number = sx - r.startX, oy:Number = sy - r.startY;
        return ox * ox + oy * oy <= maxDist * maxDist;
    }
    public static function stopFlame(key:String, serial:Number):Void {
        var r:Object = flameByKey["$" + key];
        if (!negotiated || r == null || serial < r.serial) return;
        if (!presenting) {
            // 呈现暂停期间不产生差量：直接从存活记录移除，重授予重发时不再出现。
            for (var i:Number = 0; i < records.length; i++)
                if (records[i] === r) { records.splice(i, 1); break; }
            flameByKey["$" + key] = null;
            return;
        }
        if (queue.length >= EVENT_LIMIT) { reportFault("queue_overflow"); return; }
        var wire:String = "x," + r.id + "," + serial;
        queue.push(wire); queuedBytes += length(wire) + 1;
        r.queueIndex = -1;
        flameByKey["$" + key] = null;
    }
    public static function flush():String {
        // 暂停呈现（shadow/断连）时既不发包也不推进视觉时钟，存活记录原样冻结。
        if (!enabled || !presenting) return null;
        var paused:Boolean = _root.暂停 ? true : false;
        if (!paused) gameTick++;
        sequence++;
        var offset:Object = SceneCoordinateManager.effectOffset;
        var ox:Number = num(offset.x, 0), oy:Number = num(offset.y, 0);
        var payload:String = epoch + "|" + sequence + "|" + gameTick + "|" + (paused ? 1 : 0)
            + ";o," + ox + "," + oy;
        for (var q:Number = 0; q < queue.length; q++) payload += ";" + queue[q];
        queue.length = 0; queuedBytes = 0;
        for (var i:Number = records.length - 1; i >= 0; i--) {
            var r:Object = records[i];
            materializeOffset(r, ox, oy);
            if (visualAge(r, gameTick) > r.life) {
                if (r.genericChannel) {
                    if (channelByKey["$" + r.key] === r) retireChannel(r);
                } else if (r.key != null && flameByKey["$" + r.key] === r) flameByKey["$" + r.key] = null;
                records[i] = records[records.length - 1]; records.length--;
            }
        }
        return payload;
    }
    public static function getStats():Object {
        return {enabled:enabled, lighting:lightingEnabled, channelsEnabled:channelsEnabled,
            epoch:epoch, tick:gameTick, active:records.length, queued:queue.length, configs:configs.length,
            channelUpdates:channelUpdates, channelCoalesced:channelCoalesced};
    }
}
