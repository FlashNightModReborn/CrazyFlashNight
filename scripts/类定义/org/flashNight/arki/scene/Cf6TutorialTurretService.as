import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.BookRunRules;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.gesh.depth.DepthManager;

/**
 * CF6 原作 A01 两门自动炮塔（sprite1591）的 CF7 房间服务。
 * 原作事实见 tools/cf6-tutorial-turrets/tutorial-turrets.fragment.json：
 * 不可控制、无输入、无进入/离开、无回收；每 18 帧（30fps→0.6s）向右自动射击。
 * 本服务不拥有奖励、存档写入、出口结算与击杀计数权威。
 *
 * 源码边界（尚待真实 AVM1 验证）：
 * - 视觉资产是独立展示 SWF（默认 flashswf/backgrounds/cf6/CF6_A01_Turret.swf），
 *   由本服务用 MovieClipLoader 按 spec.assetUrl 显式载入自己持有的 holder，
 *   不新增全局 linkage，不改 things-new 资产注册表。
 * - 逐弹目标过滤已实接线：BulletQueueProcessor 主命中循环与 injectHit 均消费
 *   子弹侧 仅命中目标标记 / 目标侧 目标标记；能力开关 targetFilterEnabled
 *   断开时带标记子弹 fail-closed 拒绝结算一切目标，本服务同时停射。
 *   过滤仅覆盖主队列普通子弹通道（射线 settleRayHit 批路不读标记），
 *   因此 normalizeSpec 明确拒绝 普通子弹 以外的弹种，换 bulletType 不能绕过过滤。
 * - 生命周期：每实例普通 Object 归属凭据（token）+ 一次性加载票据（ticket）。
 *   gameworld 直属 wrapper 创建时即持归属凭据，loadClip 仅替换其专用 payload 子剪辑；
 *   每实例独占 loader/listener，加载回调先验 wrapper 凭据和一次性票据；
 *   删除只作用于仍持本实例凭据的剪辑，绝不收养无凭据同名剪辑、不抹除他人回调。
 * - 时钟：服务帧回调是唯一时钟。暂停（_root.暂停===true）时整钟冻结——
 *   不推进帧、不开火、元件不进入射击帧故无帧内枪声；恢复后相位不漂移、无双枪声。
 *   开火/枪口/枪声同拍：进入第 fireFrameOffset+1 帧（1 基，默认第 12 帧）的同一 tick
 *   驱动 inner.gotoAndStop 并发射子弹。
 */
class org.flashNight.arki.scene.Cf6TutorialTurretService {
    private static var installed:Boolean = false;
    private static var active:Object;
    private static var sessionCounter:Number = 0;

    /** 过滤能力绑定真实实现类，不再是独立全局开关。 */
    private static function filterWired():Boolean {
        return org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor.targetFilterEnabled === true;
    }

    public static function install():Void {
        if (installed) return;
        installed = true;
        NativeInteractionContext.install();
        NativeInteractionContext.onSceneTeardown(teardown);
    }

    /** 本片段只覆盖原作两门炮塔所在的 A01。 */
    public static function knownMap(mapId:String):Boolean {
        return mapId == "A01";
    }

    /** 规格校验 + 默认值归一（纯函数，供装配期与测试共用）。 */
    public static function normalizeSpec(spec:Object):Object {
        if (spec == null) return null;
        if (typeof spec.assetUrl != "string" || spec.assetUrl.length == 0 || spec.assetUrl.length > 256
                || spec.assetUrl.indexOf("..") >= 0 || !endsWithSwf(spec.assetUrl)) return null;
        var linkage:String = spec.linkage == undefined ? "CF6教学炮塔-A01自动炮" : spec.linkage;
        if (typeof linkage != "string" || linkage.length == 0 || linkage.indexOf("..") >= 0) return null;
        var marker:String = spec.filterMarker == undefined ? "cf6-a01-turret-zombie" : spec.filterMarker;
        if (typeof marker != "string" || marker.length == 0 || marker.length > 64) return null;
        // 逐弹过滤只覆盖主队列普通子弹通道；射线/穿透等未覆盖弹种在此明确拒绝。
        if (spec.bulletType != undefined && spec.bulletType !== "普通子弹") return null;
        var rows:Array = spec.turrets;
        if (rows == null || rows.length < 1 || rows.length > 8) return null;
        var out:Object = {
            assetUrl: spec.assetUrl,
            linkage: linkage,
            filterMarker: marker,
            fireIntervalFrames: num(spec.fireIntervalFrames, 18),
            fireFrameOffset: num(spec.fireFrameOffset, 11),
            scatterDeg: num(spec.scatterDeg, 15),
            power: num(spec.power, 10),
            bulletSpeed: num(spec.bulletSpeed, 20),
            zRange: num(spec.zRange, 300),
            bulletType: "普通子弹",
            sound: spec.sound == undefined ? "无" : String(spec.sound),
            muzzleEffect: spec.muzzleEffect == undefined ? "无" : String(spec.muzzleEffect),
            hitMapEffect: spec.hitMapEffect == undefined ? "无声火花" : String(spec.hitMapEffect),
            turrets: []
        };
        if (out.fireIntervalFrames != Math.floor(out.fireIntervalFrames) || out.fireIntervalFrames < 2 || out.fireIntervalFrames > 120) return null;
        if (out.fireFrameOffset != Math.floor(out.fireFrameOffset) || out.fireFrameOffset < 0 || out.fireFrameOffset >= out.fireIntervalFrames) return null;
        if (!(out.scatterDeg >= 0 && out.scatterDeg <= 45)) return null;
        if (!(out.power > 0 && out.power <= 10000)) return null;
        if (!(out.bulletSpeed > 0 && out.bulletSpeed <= 200)) return null;
        if (!(out.zRange > 0 && out.zRange <= 2000)) return null;
        var needsAdopt:Boolean = false;
        for (var i:Number = 0; i < rows.length; i++) {
            var r:Object = rows[i];
            if (r == null) return null;
            var x:Number = Number(r.x), y:Number = Number(r.y);
            if ((x - x) != 0 || (y - y) != 0 || Math.abs(x) > 5000 || Math.abs(y) > 5000) return null;
            if (r.facing != "right" && r.facing != "left") return null;
            if (r.name != undefined) {
                if (typeof r.name != "string" || r.name.length == 0 || r.name.length > 64) return null;
                needsAdopt = true;
            }
            var footprint:Array=undefined;
            if(r.ownFootprint!==undefined) {
                if(!(r.ownFootprint instanceof Array) || r.ownFootprint.length!=4) return null;
                footprint=r.ownFootprint.concat();
                for(var bi:Number=0;bi<4;bi++) if(typeof footprint[bi]!="number" || (footprint[bi]-footprint[bi])!=0) return null;
                if(!(footprint[2]>footprint[0]) || !(footprint[3]>footprint[1])
                    || footprint[2]-footprint[0]>500 || footprint[3]-footprint[1]>200) return null;
            }
            out.turrets.push({x: x, y: y, facing: r.facing, name: r.name,ownFootprint:footprint});
        }
        // 收养模式必须配归属凭据：凭据由放置方写在实例 __cf6TurretAdoptToken 上。
        if (needsAdopt) {
            if (typeof spec.adoptToken != "string" || spec.adoptToken.length == 0 || spec.adoptToken.length > 64) return null;
            out.adoptToken = spec.adoptToken;
        }
        return out;
    }
    private static function endsWithSwf(url:String):Boolean {
        var tail:String = url.substr(url.length - 4).toLowerCase();
        return url.length >= 4 && tail == ".swf";
    }
    private static function num(v, d:Number):Number {
        var n:Number = Number(v);
        return (n - n) != 0 || v == undefined ? d : n;
    }

    public static function beginRoom(world:MovieClip, identity:Object, mapId:String, spec:Object):Boolean {
        install();
        var run:Object = _root._saveExt.bookRun;
        if (run.bookId != "cf6-sting" || run.routeId != "historical" || run.outcome != "active"
                || _root.当前关卡名 !== "书中历险-毒刺行动" || run.slot !== String(_root.savePath)
                || !BookRunRules.sameCf6Run(run, run)
                || !knownMap(mapId)
                || world !== _root.gameworld || identity == null
                || identity !== StageReturnFlow.worldIdentity(world)) return false;
        if (active != null && active.owner === identity && active.mapId === mapId && current(active)) return true;
        teardown();
        var norm:Object = normalizeSpec(spec);
        var s:Object = {mapId: mapId, world: world, owner: identity, slot: String(_root.savePath),
            stageName: String(_root.当前关卡名), spec: norm, turrets: [], failed: false, fired: 0,
            sessionId: ++sessionCounter};
        s.runIdentity = {bookId: run.bookId, routeId: run.routeId, slot: run.slot, seed: run.seed,
            startedAt: run.startedAt, planSeed: run.planSeed};
        active = s;
        world.__cf6TutorialTurrets = s;
        if (norm == null) { fail(s, "炮塔规格无效"); return true; }
        // 原作"只伤 sprite630 专用僵尸"语义：过滤实现类断开时显式拒绝进入射击态。
        if (!filterWired()) { fail(s, "目标过滤已断开，拒绝进入射击态"); return true; }
        for (var i:Number = 0; i < norm.turrets.length; i++) {
            if (!attachOne(s, norm.turrets[i], i)) return true;
        }
        return true;
    }

    /**
     * 每门炮塔一个监听器闭包，参数捕获 (s, t, ticket)：
     * 身份在发起加载前由外部会话捕获并随一次性票据下发，不在迟到回调里补身份。
     */
    private static function attachOne(s:Object, row:Object, index:Number):Boolean {
        var world:MovieClip = s.world;
        var name:String = row.name != undefined ? row.name : "__cf6Turret" + index;
        var holder:MovieClip = world[name];
        var t:Object = {name: name, holder: null, token: {}, inner: undefined, loaded: false,
            facing: row.facing, groundY:row.y, ownFootprint:row.ownFootprint, frame: 0, owned: false, loadTicket: null,
            loader: null, listener: null, retired:false, payload: null, payloadName:"__cf6TurretPayload",
            muzzleLocal: {x: 112.45, y: -70.5}};
        if (holder != undefined) {
            // 收养模式：必须持本会话规格凭据，绝不收养无凭据的同名外部剪辑。
            if (s.spec.adoptToken == undefined || holder._parent !== world
                    || holder.__cf6TurretAdoptToken !== s.spec.adoptToken) {
                fail(s, "炮塔实例归属凭据不符: " + name); return false;
            }
            if (holder.是否为敌人 === true) { fail(s, "炮塔实例阵营不符: " + name); return false; }
            t.holder = holder;
            t.inner = holder;
            t.loaded = true;
            t.previousFrame = holder.onEnterFrame;
            holder.__cf6TurretOwner = t.token;
            s.turrets.push(t);
            bindHolder(s, t, holder);
            return !s.failed;
        }
        // 加载模式：holder 是 gameworld 直接子剪辑（子弹入口按 gameworld[发射者] 解析），
        // 名字携带会话序号，同路径重建时旧 holder 名不会与新会话冲突。
        name = "__cf6TurretAsset" + s.sessionId + "_" + index;
        t.name = name;
        holder = world.createEmptyMovieClip(name, world.getNextHighestDepth());
        if (holder == undefined) { fail(s, "炮塔容器创建失败"); return false; }
        holder.__cf6TurretOwner = t.token;
        holder._x = row.x;
        holder._y = row.y;
        if (row.facing == "left") holder._xscale = -100;
        if (DepthManager.instance != undefined) {
            if (DepthManager.instance.updateDepth(holder, holder._y) !== true) s.depthDegraded = true;
        }
        t.holder = holder;
        t.owned = true;
        holder.onUnload = holderUnloadCallback(s, t);
        var ticket:Object = {};
        t.loadTicket = ticket;
        t.payload = holder.createEmptyMovieClip(t.payloadName, 1);
        s.turrets.push(t);
        if (t.payload == undefined) { fail(s, "炮塔资源容器创建失败"); return false; }
        t.loader = new MovieClipLoader();
        t.listener = loaderListener(s, t, ticket);
        t.loader.addListener(t.listener);
        if (!t.loader.loadClip(s.spec.assetUrl, t.payload)) {
            fail(s, "炮塔资源加载请求失败");
            return false;
        }
        return true;
    }

    private static function loaderListener(s:Object, t:Object, ticket:Object):Object {
        return {
            onLoadInit: function(target:MovieClip):Void {
                org.flashNight.arki.scene.Cf6TutorialTurretService.onAssetInit(s, t, ticket, target);
            },
            onLoadError: function(target:MovieClip, errorCode:String, httpStatus:Number):Void {
                org.flashNight.arki.scene.Cf6TutorialTurretService.onAssetError(s, t, ticket, target, errorCode);
            }
        };
    }

    private static function holderUnloadCallback(s:Object, t:Object):Function {
        return function():Void { org.flashNight.arki.scene.Cf6TutorialTurretService.onHolderUnload(s, t); };
    }

    /** 外层被外部卸载时先撤销票据与监听器；不向同路径替换剪辑执行卸载。 */
    public static function onHolderUnload(s:Object, t:Object):Void {
        if (t == null || t.retired === true) return;
        t.retired = true;
        t.loadTicket = null;
        detachLoaderListener(t);
        var holder:MovieClip = s.world[t.name];
        if (ownsHolder(s, t) && t.loader != null && holder[t.payloadName] != undefined)
            t.loader.unloadClip(holder[t.payloadName]);
        t.loaded = false;
        t.loader = null;
    }

    /** wrapper 从不作为 loadClip 目标；其普通 Object 凭据在载入前后保持不变。 */
    private static function ownsHolder(s:Object, t:Object):Boolean {
        var resident:MovieClip = s.world[t.name];
        return t.token != undefined && resident != undefined
            && resident._parent === s.world && resident.__cf6TurretOwner === t.token;
    }

    private static function matchesLoad(s:Object, t:Object, ticket:Object, target:MovieClip):Boolean {
        if (s == null || active !== s || s.failed || !current(s)
                || t == null || t.retired === true || ticket == null || t.loadTicket !== ticket || !ownsHolder(s, t)) return false;
        var holder:MovieClip = s.world[t.name];
        // payload 是自有 wrapper 内的唯一载入槽；只有本服务会创建/销毁该槽。
        return target != undefined && target._parent === holder
            && target._name === t.payloadName && holder[t.payloadName] === target;
    }

    private static function detachLoaderListener(t:Object):Void {
        if (t.loader != null && t.listener != null) t.loader.removeListener(t.listener);
        t.listener = null;
    }

    /**
     * 收养已校验凭据；加载模式 wrapper 凭据在创建时就已固定。
     * 只有已就绪资源安装发射者属性和帧回调，不向迟到目标补写凭据。
     */
    private static function bindHolder(s:Object, t:Object, holder:MovieClip):Void {
        if (!ownsHolder(s, t)) return;
        holder.是否为敌人 = false;
        holder.方向 = t.facing == "left" ? "左" : "右";
        // A01 固定机关发射者合同，沿用现役机关的有限等级/高命中率/零伤害加成；
        // Z轴坐标是世界地面行，不能用“离地高度0”代替，否则主碰撞循环会错层。
        holder.等级 = 35;
        holder.命中率 = 100000;
        holder.伤害加成 = 0;
        holder.Z轴坐标 = holder._y;
        t.groundY = holder._y;
        if (typeof holder.dispatcher.publish != "function") {
            t.dispatcher = new org.flashNight.neur.Event.EventDispatcher();
            holder.dispatcher = t.dispatcher;
        }
        var inner:MovieClip = t.inner;
        if (inner != undefined) {
            // 服务接管元件时钟：真实元件帧数必须恰等于射击周期（1 帧测试 mock 豁免）。
            if (inner._totalframes > 1 && inner._totalframes != s.spec.fireIntervalFrames) {
                fail(s, "炮塔资产帧数与射击周期不符: " + t.name);
                return;
            }
            inner.gotoAndStop(1);
        }
        t.frame = 0;
        t.frameCallback = frameCallback(s, t);
        holder.onEnterFrame = t.frameCallback;
    }

    /** 资源载入完成。一次性票据 + 会话/世界身份同时成立才认领；票据即刻消费。 */
    public static function onAssetInit(s:Object, t:Object, ticket:Object, target:MovieClip):Void {
        if (!matchesLoad(s, t, ticket, target)) return;
        t.loadTicket = null;
        detachLoaderListener(t);
        // 主控预合成资产内已含 turret 子剪辑时直接采用，否则从载入 SWF 的库 attach。
        var inner:MovieClip = target.turret != undefined
            ? target.turret
            : target.attachMovie(s.spec.linkage, "turret", 1);
        if (inner == undefined) { fail(s, "炮塔 linkage 未就绪: " + s.spec.linkage); return; }
        t.inner = inner;
        t.loaded = true;
        bindHolder(s, t, s.world[t.name]);
    }

    /** 资源载入失败：一次性票据 + 会话/世界身份同时成立才置失败态。 */
    public static function onAssetError(s:Object, t:Object, ticket:Object, target:MovieClip, errorCode:String):Void {
        if (!matchesLoad(s, t, ticket, target)) return;
        t.loadTicket = null;
        fail(s, "炮塔资源加载失败: " + errorCode);
    }

    /** 参数捕获工厂：避免 AS2 局部寄存器复用影响迟到回调（机制层同款教训）。 */
    private static function frameCallback(s:Object, t:Object):Function {
        return function():Void { org.flashNight.arki.scene.Cf6TutorialTurretService.frame(s, t); };
    }

    public static function frame(s:Object, t:Object):Void {
        if (!current(s) || s.failed || !t.loaded) return;
        // 暂停冻结整钟：不推进帧、不开火；元件不进入射击帧，故无帧内枪声。
        if (_root.暂停) return;
        var holder:MovieClip = s.world[t.name];
        if (holder == undefined || t.token == undefined || holder.__cf6TurretOwner !== t.token) return;
        // 必须在进入可能发声的时间轴帧之前确认能力；拒射不能先播枪声。
        if (!filterWired() || typeof _root.子弹区域shoot传递 != "function") {
            fail(s, "炮塔发射能力已断开"); return;
        }
        t.frame++;
        // 0 基偏移 → 1 基时间轴帧：fireFrameOffset=11 即第 12 帧（原作帧12 射击）。
        var f:Number = (t.frame % s.spec.fireIntervalFrames) + 1;
        if (t.inner != undefined) t.inner.gotoAndStop(f);
        if (f == s.spec.fireFrameOffset + 1) fire(s, t, holder);
    }

    private static function fire(s:Object, t:Object, holder:MovieClip):Void {
        if (!current(s) || s.failed || t.retired === true || !ownsHolder(s, t)) return;
        if (!filterWired()) { fail(s, "目标过滤已断开，停止射击"); return; }
        // CF7 兼容：使用原枪口焰的视觉锚点；原 marker/manifest 仍保留其原始坐标。
        // 通过展示元件的实际变换，包含嵌套位移/倍率/朝向，不以屏幕坐标加偏移代替。
        var origin:MovieClip = t.inner != undefined ? t.inner : holder;
        var p:Object = {x: t.muzzleLocal.x, y: t.muzzleLocal.y};
        origin.localToGlobal(p);
        s.world.globalToLocal(p);
        if ((p.x - p.x) != 0 || (p.y - p.y) != 0) return;
        var bullet:Object = makeBullet(s, t, p.x, p.y);
        if(!placeEmission(s,t,bullet)) return;
        applyCrossRowAim(s, t, bullet);
        // 目标搜索不持久保存 MC；发射提交前再验普通对象世界身份及本 wrapper 凭据。
        if (!current(s) || s.failed || t.retired === true || !ownsHolder(s, t) || !filterWired()) return;
        if (typeof _root.子弹区域shoot传递 != "function") { fail(s, "子弹发射入口缺失"); return; }
        var projectile:Object=_root.子弹区域shoot传递(bullet);
        if(projectile!=undefined && bullet.速度Z!==undefined) bindFlight(s.world,s.owner,projectile,bullet);
        s.fired++;
    }

    /** Only escape the explicitly authored own-footprint; never skip an unrelated wall. */
    public static function placeEmission(s:Object,t:Object,bullet:Object):Boolean {
        var layer:Object=_root.collisionLayer;
        if(typeof layer.hitTest!="function" || !layer.hitTest(bullet.shootX,bullet.shootZ,true)) return true;
        var box:Array=t.ownFootprint;
        if(box==undefined || !(bullet.shootX>box[0] && bullet.shootX<box[2]
            && bullet.shootZ>box[1] && bullet.shootZ<box[3]
            && t.holder._x>box[0] && t.holder._x<box[2] && t.groundY>box[1] && t.groundY<box[3])) return true;
        var exitX:Number=t.facing=="left" ? box[0]-1 : box[2]+1;
        var distance:Number=Math.abs(exitX-bullet.shootX);
        if(!(distance>0) || distance>32 || layer.hitTest(exitX,bullet.shootZ,true)) return false;
        bullet.shootX=exitX;
        return true;
    }
    /** Bind only this factory-produced projectile. Shared bullet movement/lifecycle stay unchanged. */
    public static function bindFlight(world:MovieClip,identity:Object,projectile:Object,shot:Object):Boolean {
        var vx:Number=shot.速度X,vy:Number=shot.速度Y,vz:Number=shot.速度Z;
        if(world!==_root.gameworld || identity==null || world.__stageReturnWorldIdentity!==identity || projectile==undefined
            || ((vx-vx)+(vy-vy)+(vz-vz))!=0 || ((shot.shootX-shot.shootX)+(shot.shootY-shot.shootY)+(shot.shootZ-shot.shootZ))!=0
            || projectile.__cf6TurretFlight!==undefined) return false;
        var flight:Object={world:world,identity:identity,token:{},x:shot.shootX,y:shot.shootY,z:shot.shootZ,
            vx:vx,vy:vy,vz:vz,ticks:0};
        projectile.__cf6TurretFlight=flight;projectile.updateMovement=flightCallback(flight);
        projectile.xmov=vx;projectile.ymov=vy;
        return true;
    }
    private static function flightCallback(flight:Object):Function {
        return function(projectile:Object):Void {
            if(projectile.__cf6TurretFlight!==flight || flight.world!==_root.gameworld
                || flight.identity!==_root.gameworld.__stageReturnWorldIdentity) return;
            flight.ticks++;
            projectile._x=flight.x+flight.vx*flight.ticks;
            projectile._y=flight.y+flight.vy*flight.ticks;
            projectile.Z轴坐标=flight.z+flight.vz*flight.ticks;
        };
    }

    /**
     * CF7 普通子弹兼容，非 CF6 原作自瞄事实。只在开火 tick 选择当前世界前方900px内的
     * 活敌方630标记目标；无合法目标时保留原18帧节奏/15度水平散射，不改全局弹种或碰撞。
     * 三个运动字段对应 WeaponFireCore.applyAimingLogic / LinearBulletMovement 的真实合同。
     */
    private static function applyCrossRowAim(s:Object, t:Object, bullet:Object):Void {
        if (!current(s)) return;
        var bestName:String;
        var bestDistance:Number = 810001;
        var world:MovieClip = s.world;
        for (var name:String in world) {
            var aim:Object = targetAim(s, t, bullet, world[name]);
            if (aim != null && aim.distanceSq < bestDistance) {
                bestName = name;
                bestDistance = aim.distanceSq;
            }
        }
        if (bestName == undefined || !current(s)) return;
        // 按名字从当前世界重新解析与验资格，不沿用跨回调/跨房间的 MC 引用。
        var finalAim:Object = targetAim(s, t, bullet, world[bestName]);
        if (finalAim == null || !current(s)) return;
        bullet.速度X = finalAim.speedX;
        bullet.速度Y = finalAim.speedY;
        bullet.ZY比例 = finalAim.zyRatio;
        bullet.速度Z = finalAim.speedZ;
    }

    private static function targetAim(s:Object, t:Object, bullet:Object, target):Object {
        if (typeof target != "movieclip" || target._parent !== s.world
                || target.是否为敌人 !== true || target.目标标记 !== s.spec.filterMarker
                || !(target.hp > 0) || (target.hp - target.hp) != 0
                || target.防止无限飞 == true) return null;
        var targetX:Number = Number(target._x);
        var targetZ:Number = Number(target.Z轴坐标);
        var centerY:Number = Number(target._y)
            - org.flashNight.arki.unit.UnitUtil.calculateCenterOffset(target);
        var dx:Number = targetX - bullet.shootX;
        var dz:Number = targetZ - bullet.shootZ;
        var dy:Number = centerY - bullet.shootY;
        if ((dx - dx) != 0 || (dz - dz) != 0 || (dy - dy) != 0
                || (centerY - centerY) != 0 || Math.abs(centerY) < 0.001
                || Math.abs(dx) < 0.001
                || (t.facing == "left" ? dx >= 0 : dx <= 0)) return null;
        var distanceSq:Number = dx * dx + dz * dz;
        if (!(distanceSq > 0) || distanceSq > 810000) return null;
        var speed:Number = s.spec.bulletSpeed;
        var speedX:Number = dx > 0 ? speed : -speed;
        var speedY:Number = speedX * dy / dx;
        if (speedY > speed || speedY < -speed) {
            speedY = speedY > 0 ? speed : -speed;
            speedX = speedY * dx / dy;
        }
        var zyRatio:Number = targetZ / centerY;
        if ((speedX - speedX) != 0 || (speedY - speedY) != 0 || (zyRatio - zyRatio) != 0) return null;
        return {speedX: speedX, speedY: speedY, speedZ:speedX*dz/dx, zyRatio: zyRatio, distanceSq: distanceSq};
    }

    /**
     * 子弹配置（纯函数）。友方阵营由发射者 holder.是否为敌人=false 经子弹初始化继承；
     * 仅命中目标标记 由 BulletQueueProcessor 主命中循环/injectHit 的逐弹过滤消费，
     * 过滤断开时本函数不可能被调用（fire 前置复检 + fail-closed 守卫双保险）。
     */
    public static function makeBullet(s:Object, t:Object, sx:Number, sy:Number):Object {
        return {
            声音: s.spec.sound,
            霰弹值: 1,
            子弹散射度: s.spec.scatterDeg,
            发射效果: s.spec.muzzleEffect,
            子弹种类: s.spec.bulletType,
            子弹威力: s.spec.power,
            子弹速度: s.spec.bulletSpeed,
            Z轴攻击范围: s.spec.zRange,
            击中地图效果: s.spec.hitMapEffect,
            发射者: t.name,
            仅命中目标标记: s.spec.filterMarker,
            shootX: sx,
            shootY: sy,
            shootZ: t.groundY
        };
    }

    private static function current(s:Object):Boolean {
        return active === s && s != null && BookRunRules.sameCf6Run(s.runIdentity, _root._saveExt.bookRun)
            && s.slot === String(_root.savePath) && s.owner != undefined
            && s.stageName === _root.当前关卡名
            && s.owner === StageReturnFlow.worldIdentity(_root.gameworld);
    }

    private static function fail(s:Object, message:String):Void {
        if (s != null) s.failed = true;
        removeOwned(s);
        _root.发布消息("CF6教学炮塔已停用: " + message);
        trace("[Cf6TutorialTurret] disabled: " + message);
    }

    private static function removeOwned(s:Object):Void {
        if (s == null) return;
        for (var i:Number = 0; i < s.turrets.length; i++) {
            var t:Object = s.turrets[i];
            t.retired = true;
            t.loadTicket = null;
            detachLoaderListener(t);
            var holder:MovieClip = s.world[t.name];
            // 先捕获一次归属，再清理；不能先删凭据再用凭据决定是否删除。
            var owned:Boolean = ownsHolder(s, t);
            if (owned) {
                if (holder.onEnterFrame === t.frameCallback) {
                    if (t.previousFrame == undefined) delete holder.onEnterFrame;
                    else holder.onEnterFrame = t.previousFrame;
                }
                if (t.dispatcher != null && holder.dispatcher === t.dispatcher) delete holder.dispatcher;
                if (t.owned === true) {
                    // listener/ticket 已失效；仅卸载仍在本 wrapper 内的专用资源。
                    if (t.loader != null && holder[t.payloadName] != undefined)
                        t.loader.unloadClip(holder[t.payloadName]);
                    holder.removeMovieClip();
                } else delete holder.__cf6TurretOwner;
            }
            if (t.dispatcher != null) t.dispatcher.destroy();
            t.dispatcher = null;
            t.holder = undefined;
            t.payload = undefined;
            t.loader = null;
            t.inner = undefined;
            t.token = undefined;
        }
        s.turrets = [];
    }

    public static function teardown():Void {
        var s:Object = active;
        if (s == null) return;
        removeOwned(s);
        if (s.world != undefined && s.world.__cf6TutorialTurrets === s) delete s.world.__cf6TutorialTurrets;
        active = null;
    }

    /** 测试探视口：只读，不暴露可写句柄。 */
    public static function debugState():Object {
        var s:Object = active;
        if (s == null) return null;
        var loaded:Number = 0;
        for (var i:Number = 0; i < s.turrets.length; i++) if (s.turrets[i].loaded === true) loaded++;
        return {mapId: s.mapId, failed: s.failed, fired: s.fired, count: s.turrets.length,
            loaded: loaded, sessionId: s.sessionId,
            depthDegraded: s.depthDegraded === true};
    }
}
