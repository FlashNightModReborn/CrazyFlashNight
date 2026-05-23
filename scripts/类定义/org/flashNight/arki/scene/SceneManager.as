import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.neur.Event.LifecycleEventDispatcher;
import org.flashNight.gesh.depth.DepthManager;

/**
SceneManager.as
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.SceneManager {
    public static var instance:SceneManager; // 单例引用

    public var gameworld:MovieClip; // 当前gameworld
    
    /**
     * 单例获取：返回全局唯一实例
     */
    public static function getInstance():SceneManager {
        return instance || (instance = new SceneManager());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function SceneManager() {
        gameworld = null;
    }

    /*
     * 对新附加的gameworld进行初始化，并附加必要组件。
     */
    public function initGameWorld(_gw:MovieClip):Void{
        gameworld = _gw;

        // ── 钉定 authored 实例深度（必须在 DepthManager 与 地图/子弹区域 等运行时层创建之前）──
        // 把 背景 / deadbody 钉到 gameworld 最底两层，消除对 FLA 摆层规范的依赖：
        // 背景烤图被提升到 deadbody 层后，任何夹在 deadbody 与 背景 之间的
        // authored 图层都会被烤好的不透明背景位图盖住。
        pinAuthoredLayers(gameworld);

        // gameworld地图碰撞箱层已经弃用，为防止错误附加一个空影片剪辑作为地图层
        if(gameworld.地图 == null) gameworld.createEmptyMovieClip("地图", -2);
        // 附加子弹层，层级在所有人物之下
        if(gameworld.子弹区域 == null) gameworld.createEmptyMovieClip("子弹区域", -1);
        // 附加效果层，层级在 DM 管理区和创建暂存区之上
        if(gameworld.效果 == null) gameworld.createEmptyMovieClip("效果", 1048000);

        // 创建事件分发器
        gameworld.dispatcher = new LifecycleEventDispatcher(gameworld);

        // ── 重写 getNextHighestDepth ──
        // 计数器 900000-999999（创建暂存区），避开 Twip 深度范围(0-870655) 和 UnitBullet 域(1000000+)
        // 所有新建 gw 子级在此创建后，同帧被 DM.updateDepth 移到 Twip 深度
        var _gwDC:Number = 900000;
        gameworld.getNextHighestDepth = function():Number {
            var d:Number = _gwDC++;
            if (_gwDC >= 1000000) _gwDC = 900000;
            return d;
        };

        // ── 创建 DepthManager ──
        if (DepthManager.instance) DepthManager.instance.dispose();
        DepthManager.instance = new DepthManager(gameworld, 0, 1048575, 256);
        // 用当前可用边界标定（非战斗场景帧脚本已设 Ymin/Ymax；战斗场景在 StageManager 中精确覆盖）
        var ym:Number = _root.Ymin;
        var yM:Number = _root.Ymax;
        DepthManager.instance.calibrate(
            isNaN(ym) ? 0 : ym,
            isNaN(yM) ? 1200 : yM
        );

        // 将上述属性设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["效果", "子弹区域", "地图", "dispatcher", "getNextHighestDepth"], 1, false);

        // 发布场景切换事件
        _root.帧计时器.eventBus.publish("SceneChanged");
    }

    /**
     * 把 authored 实例 背景 / deadbody 钉到 gameworld 最底两层。
     * 背景严格最底、deadbody 次底，消除对 FLA 摆层规范的依赖。
     *
     * 主路径：以「其余子级最小深度 minOther」与 -2 的较小值为锚点 anchor，
     *         把 deadbody / 背景 重定位到 anchor-1 / anchor-2（在所有内容之下
     *         且空闲，纯重定位、零位移）。锚点封顶到 -2 是为了让 deadbody/背景
     *         同时低于本方法返回后 createEmptyMovieClip 创建的 地图(-2)/
     *         子弹区域(-1) 两个保留层，避免与之深度撞槽。
     * 降级：无其它子级或底部已贴时间轴下限(-16384)时，直接钉到 -16384/-16383
     *       两槽（最底两层，排序必然正确；占用者经 swapDepths 互换自然上移）。
     * 调用时机有两条硬约束，缺一不可：
     *   1) 必须在创建 地图/子弹区域 等运行时层之前——确保 minOther 只统计
     *      FLA authored 子级，不被运行时层干扰。
     *   2) 必须在 DepthManager 创建之前——DM 会劫持子级的 swapDepths 并
     *      重定向到 updateDepth（把入参当 Y 坐标）；若反序调用，本方法的
     *      swapDepths(anchor-1) 会被当成 Y 坐标而非深度，钉定彻底失效。
     */
    private function pinAuthoredLayers(gw:MovieClip):Void {
        var deadbody:MovieClip = gw.deadbody;
        if (deadbody == undefined) return;
        var bg:MovieClip = gw.背景; // 部分无背景室内图为 undefined

        var TIMELINE_FLOOR:Number = -16384;

        // 求其余子级（排除 背景/deadbody 自身）的最小深度
        var minOther:Number = Number.MAX_VALUE;
        var child:MovieClip;
        var d:Number;
        for (var nm in gw) {
            child = gw[nm];
            if (child == deadbody || child == bg) continue;
            if (child.getDepth == undefined) continue; // 过滤非 MovieClip 属性
            d = child.getDepth();
            if (!isNaN(d) && d < minOther) minOther = d;
        }

        // 锚点封顶到 -2：保证 deadbody/背景 同时低于其它 authored 子级，
        // 与本方法返回后创建的 地图(-2)/子弹区域(-1) 保留层。
        // minOther==MAX_VALUE 时 anchor 取 -2，但下方条件不会走主路径。
        var anchor:Number = (minOther < -2) ? minOther : -2;

        if (minOther != Number.MAX_VALUE && (anchor - 2) >= TIMELINE_FLOOR) {
            // 主路径：anchor-1 / anchor-2 在所有内容之下且空闲，纯重定位、零位移
            deadbody.swapDepths(anchor - 1);
            if (bg != undefined) bg.swapDepths(anchor - 2);
        } else {
            // 降级：无其它子级，或底部已贴时间轴下限、无连续空位。
            // 钉到深度下限两槽——-16384/-16383 即最底两层，排序必然正确。
            if (bg != undefined) {
                bg.swapDepths(TIMELINE_FLOOR);
                deadbody.swapDepths(TIMELINE_FLOOR + 1);
            } else {
                deadbody.swapDepths(TIMELINE_FLOOR);
            }
        }
    }

    /*
     * 移除gameworld及其组件
     */
    public function removeGameWorld():Void{
        // 幂等检查
        if (gameworld == null) {
            return;
        }

        // 安全网：清除刘海屏波次计时器（正常路径由 clearStage/failStage 触发，
        // 但手动退出关卡可能跳过它们，导致计时器残留）
        var sm:Object = _root.server;
        if (sm != null && sm.isSocketConnected) {
            sm.sendSocketMessage("W隐藏");
        }

        // 销毁事件分发器
        if (gameworld.dispatcher != null) {
            gameworld.dispatcher.destroy();
            gameworld.dispatcher = null;
        }

        // 释放BitmapData资源
        if (gameworld.deadbody != null && gameworld.deadbody.layers != null) {
            if (gameworld.deadbody.layers[0] != null) {
                gameworld.deadbody.layers[0].dispose();
            }
            if (gameworld.deadbody.layers[1] != null) {
                gameworld.deadbody.layers[1].dispose();
            }
            if (gameworld.deadbody.layers[2] != null) {
                gameworld.deadbody.layers[2].dispose();
            }
            gameworld.deadbody.layers = null;
        }

        // 显式 dispose DepthManager：清空内部数据，解绑 onUnload 回调。
        // 注意：instance = null 必须在 removeMovieClip 之后。
        // 原因：removeMovieClip 会级联触发子级 onUnload → StaticDeinitializer.deInitializeUnit
        // → DepthManager.instance.removeMovieClip(target)。若 instance 已 null 则空引用。
        // dispose 后内部数据已清空，子级的 removeMovieClip 调用会安全 return false。
        if (DepthManager.instance) {
            DepthManager.instance.dispose();
        }

        gameworld.swapDepths(_root.getNextHighestDepth());
        gameworld.removeMovieClip();
        DepthManager.instance = null;
        gameworld = null;
    }

    /**
     * 完整清理方法（幂等）
     * 用于游戏重启时的彻底清理
     */
    public function dispose():Void {
        removeGameWorld();
    }

    /**
     * 重置单例状态（用于游戏重启后重新初始化）
     */
    public function reset():Void {
        dispose();
    }


    public function addBodyLayers(w:Number ,h:Number):Void{
        var deadbody = gameworld.deadbody;
        if(deadbody.layers != null) return;
        // 位图层尺寸钳制：下限保最小可用；上限是防御性护栏，不是设计天花板。
        // 旧值 2880x1024 是 Flash 8 时代 BitmapData 上限的遗留常量，已实测推翻——
        // 本运行时(FP11.2 projector) AVM1 BitmapData 无 2880/8191/16M 硬墙，
        // 真实约束是内存（实测档案见 scripts/优化随笔/AS2-BitmapData-尺寸上限实测.md）。
        // 8192x4096 仅用于挡住 XML 异常尺寸值，正常手作地图远小于此。
        if(w < 1024) w = 1024;
        else if(w >= 8192) w = 8192;
        if(h < 512) h = 512;
        else if(h >= 4096) h = 4096;
        deadbody.layers = new Array(3);
        deadbody.layers[0] = new flash.display.BitmapData(w, h, true, 13421772);
        deadbody.layers[1] = null; // 从未被使用的deadbody1不添加
        deadbody.layers[2] = new flash.display.BitmapData(w, h, true, 13421772);
        // 单一坐标原点不变量：所有 layers BD 的像素 (0,0) 都对应 deadbody 局部 (0,0)
        // = gameworld 原点。BitmapEffectRenderer.renderBloodstain 与 DeathEffectRenderer
        // 都基于此假设直接写 gameworld 局部坐标，背景 bake 必须维持同原点（见 贴背景图）。
        deadbody.attachBitmap(deadbody.layers[0], 0);
        deadbody.attachBitmap(deadbody.layers[2], 2);

        // 将 'deadbody' 设置为不可枚举
        _global.ASSetPropFlags(gameworld, ["deadbody"], 1, false);
    }


    public function addInstance(info:Object, name:String):MovieClip{
        var inst;
        if (info.url != null) {
            // 检测url参数载入外部swf
            inst = gameworld.createEmptyMovieClip(name, gameworld.getNextHighestDepth());
            inst.loadMovie(info.url);
        } else if(info.Identifier != null) {
            // 根据identifier从库中加载元件
            inst = gameworld.attachMovie(info.Identifier, name, gameworld.getNextHighestDepth());
        }else{
            // 否则，创建空元件
            inst = gameworld.createEmptyMovieClip(name, gameworld.getNextHighestDepth());
        }
        inst._x = info.x;
        inst._y = info.y;
        // Y 排序实例走 DepthManager；显式 Depth 配置的固定装饰物保持原样
        if (isNaN(info.Depth)) {
            DepthManager.instance.updateDepth(inst, info.y);
        } else {
            inst.swapDepths(info.Depth);
        }
        if (info.Parameters) ObjectUtil.cloneParameters(inst, info.Parameters);
        return inst;
    }

}