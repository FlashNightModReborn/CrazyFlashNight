import org.flashNight.arki.component.Effect.*;  // EffectSystem.Effect 用到

// ============================================================================
// 消除子弹（合批版，事件驱动 / frameUpdate）
// ----------------------------------------------------------------------------
// 用法：
//   1) var p = _root.消弹属性初始化(某个消弹区域MC);
//   2) _root.消除子弹(p);   // 本帧只入队
//   3) 每帧由 frameUpdate 事件统一批处理并清空队列
// ----------------------------------------------------------------------------
// 设计要点：
// - 队列与缓存挂在 _root.gameworld.__消弹 之下（跨场景更稳）
// - 每帧仅构建一次“子弹 key 列表”，避免多次 for..in
// - 冲突安全：队列在帧末清空，新入队请求自动延迟到下一帧处理
// - 碰撞采用：区域定位area.getRect(_root.gameworld) + 子弹注册点落点检测
// ============================================================================


// 地图变动时，重新初始化子弹池（见文末 SceneChanged 订阅）


// ===============================
// 提交接口：仅入队（不立即执行）+ 惰性初始化
// ===============================
_root.消除子弹 = function(obj:Object):Void {
    if (_root.暂停) return;

    var gw:MovieClip = _root.gameworld;

    // 最小校验：需要区域定位area
    if (obj && obj.区域定位area) {
        gw.__消弹.队列.push(obj);
    }
};


// ===============================
// 帧内批处理（由 frameUpdate 事件驱动调用）
// ===============================
_root.__处理消弹队列 = function():Void {
    if (_root.暂停) return;

    var gw:MovieClip = _root.gameworld;
    if (!gw || gw.__消弹 == undefined) return; // ★ 防护

    var 队列:Array = gw.__消弹.队列;
    var 子弹容器:Object = gw.子弹区域;
    if (!子弹容器 || 队列.length == 0) return;

    // —— 宏：标志位（局部常量，零索引成本）——
    #include "../macros/FLAG_MELEE.as"
    #include "../macros/FLAG_PIERCE.as"

    // —— 每帧仅构建一次子弹 key 列表 —— 
    var keys:Array = gw.__消弹.子弹键缓存;
    var ki:Number = 0;
    for (var k in 子弹容器) { keys[ki++] = k; }  // 快速枚举
    keys.length = ki; // 截断到本帧长度

    // —— 逐请求处理（合批）——
    var qlen:Number = 队列.length;
    for (var qi:Number = 0; qi < qlen; qi++) {
        var req:Object = 队列[qi];

        // 局部缓存参数
        var 消弹敌我属性:Boolean = req.消弹敌我属性;
        var 消弹方向 = req.消弹方向;          // "左"/"右"/null
        var shootZ:Number = req.shootZ;
        var Z轴攻击范围:Number = req.Z轴攻击范围;
        var 区域定位area:MovieClip = req.区域定位area;

        // 若区域已被移除或无 getRect，则跳过该请求
        if (!区域定位area || 区域定位area.getRect == undefined) continue;

        // 使用“最终位置”求矩形（gameworld 坐标系）：{xMin,xMax,yMin,yMax}
        var R:Object = 区域定位area.getRect(gw);

        // —— 扫描子弹（用缓存 keys）——
        for (var i:Number = 0; i < ki; i++) {
            var b:MovieClip = 子弹容器[keys[i]];
            if (!b) continue;

            // 早退：Z轴范围 / 近战 / 静止
            var zOff:Number = b.Z轴坐标 - shootZ;
            if ((zOff > Z轴攻击范围 || zOff < -Z轴攻击范围) || (b.flags & FLAG_MELEE) || b.xmov == 0) continue;

            // 方向过滤（可选）
            var bdir:String = (b.xmov > 0) ? "右" : "左";
            if (消弹方向 && 消弹方向 != bdir) continue;

            // 只处理“敌对子弹”（同侧跳过）
            if (消弹敌我属性 == b.是否为敌人) continue;

            // 注册点 -> gameworld 坐标
            var pt:Object = {x:0, y:0};
            b.localToGlobal(pt);
            gw.globalToLocal(pt);

            // 点 ∈ 矩形（轴对齐）
            if (pt.x < R.xMin || pt.x > R.xMax || pt.y < R.yMin || pt.y > R.yMax) continue;

            // —— 命中处理 ——
			if (req.反弹) {
				b.发射者名 = req.shooter;

				// 当前方向（弧度）与速度
				var rad:Number   = Math.atan2(b.ymov, b.xmov);
				var speed:Number = Math.sqrt(b.xmov * b.xmov + b.ymov * b.ymov);

				// 随机偏移（±30° = π/6；若要 ±15° 用 π/12）
				var offsetRad:Number = (Math.random() - 0.5) * (Math.PI / 3); // ±30°： 
				// 反弹 = 方向 + π，再加一点随机扰动
				var newRad:Number = rad + Math.PI + offsetRad;

				// 更新速度向量与朝向
				b.xmov = Math.cos(newRad) * speed;
				b.ymov = Math.sin(newRad) * speed;
				b._rotation = newRad * 180 / Math.PI; // 显示角度是度制
			} else {
				b.击中地图 = true;
				EffectSystem.Effect(b.击中地图效果, b._x, b._y);
				b.gotoAndPlay("消失");
				if (req.强力 && (b.flags & FLAG_PIERCE)) {
					b.removeMovieClip();
				}
			}

        }
    }

    // 清空队列（复用数组对象，零分配）
    队列.length = 0;
};


// ===============================
// 消弹属性初始化（便捷构造参数对象）
// ===============================
_root.消弹属性初始化 = function(消弹区域:MovieClip):Object {
    var 消弹属性 = {
		shooter: 消弹区域._parent._parent._name, // 发射者
        shootZ: 消弹区域._parent._parent.Z轴坐标,
        消弹敌我属性: 消弹区域._parent._parent.是否为敌人,
        消弹方向: null,          // 无方向限制；可传 "左" 或 "右"
        Z轴攻击范围: 10,
        区域定位area: 消弹区域
    };
    return 消弹属性;
};


// ===============================
// 事件接入（放在“播放列表”之前”）
// ===============================
_root.帧计时器.eventBus.subscribe("frameUpdate", function() {
    _root.__处理消弹队列();
}, _root.帧计时器);


// ===============================
// 场景切换时，重置队列（防止引用旧对象）
// ===============================
_root.帧计时器.eventBus.subscribe("SceneChanged", function() {
    if (!_root.gameworld) return;
    _root.gameworld.__消弹 = {
        队列: [],
        子弹键缓存: []
    };
}, _root.帧计时器);
