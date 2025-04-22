/**
 * 提供一组用于导弹/子弹组件的默认回调函数。
 * 这些回调函数实现了基本的初始化、目标搜索（带限帧优化）、追踪和预发射抛物线移动逻辑。
 * 回调函数设计为作为属性添加到导弹实例 (this) 上，并在组件的生命周期中被调用。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.DefaultMissileCallbacks
{
    // 移除原始代码中未使用的类变量，因为回调函数的逻辑状态保存在导弹实例 (this) 上。
    // private var shooter:MovieClip; // 不再需要
    // private var _launchX:Number; // 不再需要
    // private var _launchY:Number; // 不再需要
    // private var _preFrame:Number; // 不再需要
    // private var _preTotal:Number; // 不再需要

    /**
     * 构建并返回一组默认的导弹回调函数对象。
     * 这些回调函数将被赋值给导弹实例的对应属性，并在导弹的生命周期中被调用。
     *
     * @param shooter MovieClip 发射此导弹的 MovieClip 实例。
     * @param velocity Number 导弹的最大速度。
     * @param angleRadians Number 导弹初始的旋转角度（弧度）。
     * @return Object 包含以下回调函数的对象：
     *                 - onInitializeMissile:Function 初始化导弹属性。
     *                 - onSearchForTarget:Function 搜索攻击目标（限帧优化）。
     *                 - onTrackTarget:Function 追踪目标并调整速度和方向。
     *                 - onPreLaunchMove:Function 执行发射前的抛物线蓄力动画。
     */
    public static function build(shooter:MovieClip,
                                 velocity:Number,
                                 angleRadians:Number):Object
    {
        // 每帧搜索目标时处理的最大数量，用于限帧搜索。
        // 根据实际性能需求调整此值。
        var SEARCH_BATCH_SIZE:Number = 8; // 假设每帧处理8个目标

        /**
         * 导弹初始化回调函数。
         * 在导弹被创建时调用一次，用于设置导弹的初始属性。
         * 此函数作为方法被添加到导弹实例 (this) 上。
         */
        function _init():Void
        {
            // 设置初始速度（通常低于最大速度，以便后续加速）
            this.speed = velocity / 2;
            // 存储发射者的名字，以便后续在全局 gameworld 中查找
            this.shooter = shooter._name;
            // 设置初始旋转角度（由 build 方法传入，通常根据发射者朝向计算）
            this.rotationAngle = angleRadians;
            // 设置追踪时的旋转速度（每帧最大旋转角度）
            this._rotationSpeed = 1;
            // 设置最大速度
            this.maxSpeed = velocity;
            // 设置追踪时的加速度
            this.acceleration = 10;

            // 初始化搜索相关的内部状态变量（用于限帧搜索）
            this._searchIndex = 0;          // 当前搜索到的目标索引
            this._searchTargetCache = null; // 存储待搜索的目标缓存数组
            this._bestTargetSoFar = null;   // 当前搜索到的最佳目标
            this._minDistanceSoFar = Infinity; // 当前搜索到的最小距离（平方）
        }

        /**
         * 目标搜索回调函数。
         * 在导弹处于“搜索目标”状态时每帧调用。
         * 实现限帧搜索逻辑：优先检查发射者指定目标，否则进行基于缓存的限帧搜索。
         * 此函数作为方法被添加到导弹实例 (this) 上。
         *
         * @return Boolean 如果本帧成功锁定（找到并设置了）目标，则返回 true；
         *                 如果仍在搜索中或本帧未找到目标，则返回 false。
         */
        function _search():Boolean
        {
            var gw:MovieClip = _root.gameworld;
            // 获取发射者实例
            var currentShooter:MovieClip = gw[this.shooter];

            // 检查发射者是否存在或已死亡
            if (!currentShooter || currentShooter.hp <= 0) {
                 // 发射者无效，清除当前目标并返回 false
                this.target = null;
                this.hasTarget = false;
                // 重置搜索状态
                this._searchTargetCache = null;
                this._searchIndex = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                return false;
            }

            // --- 优先检查发射者的当前攻击目标 ---
            var attackTargetName:String = currentShooter.攻击目标;
            var primaryTarget:MovieClip = gw[attackTargetName];

            // 检查发射者是否有指定目标，且目标有效（存在且未死亡）
            if (attackTargetName != "无" && primaryTarget && primaryTarget.hp > 0) {
                // 发射者有有效的目标，直接锁定此目标
                this.target = primaryTarget;
                this.hasTarget = true;
                // 锁定目标后，重置所有限帧搜索相关的状态
                this._searchTargetCache = null;
                this._searchIndex = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                // 返回 true 表示成功锁定目标
                return true;
            }

            // --- 如果发射者没有有效目标，开始或继续限帧搜索 ---

            // 如果搜索缓存为空，表示需要启动新的搜索或者缓存已处理完毕
            if (this._searchTargetCache == null) {
                 // 从全局缓存获取潜在敌人列表（假设获取的是附近的敌人，30可能代表距离或某种范围）
                this._searchTargetCache = _root.帧计时器.获取敌人缓存(currentShooter, 30);
                this._searchIndex = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;

                // 如果缓存为空，表示附近没有敌人，搜索结束但未找到目标
                if (this._searchTargetCache.length == 0) {
                    this.target = null;
                    this.hasTarget = false;
                    // 保持缓存为 null，下次进入搜索状态会重新获取
                    return false;
                }
            }

            // 计算本次帧搜索需要处理的结束索引
            var endIndex:Number = Math.min(this._searchIndex + SEARCH_BATCH_SIZE, this._searchTargetCache.length);

            // 处理当前帧的搜索批次
            for (var i = this._searchIndex; i < endIndex; i++)
            {
                var potentialTarget:MovieClip = this._searchTargetCache[i];

                // 检查潜在目标是否有效（存在且未死亡）
                if (potentialTarget && potentialTarget.hp > 0) {
                    // 计算当前导弹实例到潜在目标的平方距离
                    var dx:Number = potentialTarget._x - this.targetObject._x;
                    var dy:Number = potentialTarget._y - this.targetObject._y;
                    var dSq:Number = dx * dx + dy * dy; // 使用平方距离避免开方，提高性能

                    // 如果当前目标比之前找到的最佳目标更近
                    if (dSq < this._minDistanceSoFar)
                    {
                        this._minDistanceSoFar = dSq;
                        this._bestTargetSoFar = potentialTarget;
                    }
                }
            }

            // 更新搜索索引
            this._searchIndex = endIndex;

            // 检查是否已处理完所有潜在目标
            if (this._searchIndex >= this._searchTargetCache.length)
            {
                // 所有目标都已处理完毕，搜索结束
                this.target = this._bestTargetSoFar; // 设置最终找到的最佳目标
                this.hasTarget = (this.target != null); // 更新是否有目标的状态
                // 重置搜索状态，以便下次进入搜索状态时重新开始
                this._searchTargetCache = null;
                this._searchIndex = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;

                // 返回是否有目标的状态
                return this.hasTarget;
            } else {
                // 搜索仍在进行中，本帧未锁定最终目标
                return false;
            }
        }

        /**
         * 目标追踪回调函数。
         * 在导弹处于“追踪目标”状态时每帧调用。
         * 根据目标位置调整导弹的方向和速度。
         * 此函数作为方法被添加到导弹实例 (this) 上。
         */
        function _track():Void
        {
            // 如果当前没有有效目标，则切换回搜索状态
            if (!this.target || this.target.hp <= 0) {
                // 假设导弹实例有一个 changeState 方法
                this.changeState("SearchTarget");
                this.target = null; // 清除无效目标引用
                this.hasTarget = false;
                return;
            }

            var targetObject = this.targetObject; // 导弹自身的 MovieClip 实例
            var target = this.target; // 锁定的目标 MovieClip 实例

            // 计算导弹到目标的向量
            var dx:Number = target._x - targetObject._x;
            // 计算Y轴偏移量，模拟瞄准目标的不同高度部位（如头部、身体中心等）
            // 根据目标身高进行缩放，并考虑特殊状态如“倒地”
            var coefficient:Number = target.身高 / 175; // 假设175是基准身高
            var yOffset:Number = target.中心高度 ? target.中心高度 * coefficient :
                                 target.状态 == "倒地"? 35 : 75;
            var dy:Number = target._y - targetObject._y - yOffset;

            // 计算目标相对于导弹的角度（以弧度为单位）
            var targetAngleRadians:Number = Math.atan2(dy, dx);
            // 将弧度转换为角度（0-360）
            var targetAngleDegrees:Number = targetAngleRadians * 180 / Math.PI;

            // 计算当前导弹朝向与目标角度的差值
            var angleDifference:Number = targetAngleDegrees - this.rotationAngle;

            // 确保角度差值在 -180 到 180 范围内，以便正确计算最短旋转方向
            if (angleDifference > 180) {
                angleDifference -= 360;
            } else if (angleDifference < -180) {
                angleDifference += 360;
            }

            // 根据旋转速度限制，缓慢调整当前导弹的旋转角度
            // 只旋转不超过 _rotationSpeed 的角度
            var rotationStep:Number = Math.min(Math.max(angleDifference, -this._rotationSpeed), this._rotationSpeed);
            this.rotationAngle += rotationStep;

            // 将计算出的 Y 轴偏移量存储到导弹实例，可能用于视觉效果或其他用途
            targetObject.yOffset = yOffset;

            // 更新导弹速度，使其逐渐加速到最大速度
            if (this.speed < this.maxSpeed) {
                this.speed += this.acceleration;
            }

            // Debug 输出（可选）
            // _root.服务器.发布服务器消息("Speed: " + this.speed + " MaxSpeed: " + this.maxSpeed + " Accel: " + this.acceleration);
            // _root.服务器.发布服务器消息("TargetAngle: " + targetAngleDegrees + " RotationAngle: " + this.rotationAngle);
        }

        /**
         * 预发射移动回调函数。
         * 在导弹发射前（通常是蓄力或准备阶段）每帧调用。
         * 实现一个带有随机元素的抛物线/振荡蓄力动画。
         * 此函数作为方法被添加到导弹实例 (this) 上。
         *
         * @param flag String 调用的标志，目前只处理 "isComplete" 用于检查动画是否完成。
         * @return Boolean 如果 flag 是 "isComplete"，返回动画是否完成；否则返回 false。
         */
        function _preLaunch(flag:String):Boolean {
            // ---------- 首帧随机化初始化 ----------
            // 检查是否是动画的第一帧，如果是则进行初始化并生成随机参数
            if (this._preFrame == undefined) {
                this._preFrame    = 0;
                 // 随机总帧数，控制动画时长 (例如 10 到 15 帧)
                this._preTotal    = 10 + Math.floor(Math.random() * 6);
                // 记录导弹开始蓄力时的初始位置
                this._launchX     = this.targetObject._x;
                this._launchY     = this.targetObject._y;

                // 随机生成抛物线的峰值高度
                this._peakHeight  = 20 + Math.random() * 40; // 例如 20~60

                // 随机生成横向振荡的最大振幅
                this._horizAmp    = Math.random() * 8; // 例如 0~8

                // 随机生成横向振荡的完整周期数
                this._horizCycles = 1 + Math.random() * 2; // 例如 1~3 个周期
            }

            // ---------- 结束判定 ----------
            // 如果调用时传入 "isComplete" 标志，则返回动画是否已完成
            if (flag == "isComplete") {
                 return this._preFrame >= this._preTotal;
            }

            // ---------- 帧推进 ----------
            // 推进当前帧计数
            this._preFrame++;
            // 计算动画的进度比例 (0 到 1)
            var t:Number = this._preFrame / this._preTotal;

            // ---------- 垂直位移计算（模拟抛物线） ----------
            var y:Number;
            if (t < 0.4) {
                // 前 40% 时间：使用 ease-out cubic 曲线向上移动，模拟快速抬升
                var t1:Number = t / 0.4; // 将当前时间映射到 0-1 范围
                // ease-out cubic 公式: f(t) = 1 - (1 - t)^3
                // 位移是负的，因为 Y 轴向下增加
                y = -this._peakHeight * (1 - Math.pow(1 - t1, 3));
            } else {
                // 后 60% 时间：使用 ease-in cubic 曲线向下回落，模拟受重力影响加速下落
                var t2:Number = (t - 0.4) / 0.6; // 将当前时间映射到 0-1 范围
                 // ease-in cubic 公式: f(t) = t^3
                 // 这里需要计算从峰值回到初始高度的位移
                // 峰值高度是 -_peakHeight，回落到 0
                // 回落部分的位移 = -_peakHeight * (1 - (1 - t2)^3) 错误
                // 应该是从峰值(-_peakHeight)到初始位置(0)的插值，使用ease-in
                // 另一种更直观的思路：整个过程是一个从0到-_peakHeight再到0的曲线
                // 前40%是上升 (0 to -_peakHeight) ease-out cubic
                // 后60%是下降 (-_peakHeight to 0) ease-in cubic
                // 下降部分的进度 t2 (0 to 1) 对应 Y 从 -_peakHeight 到 0
                // Y = -_peakHeight + _peakHeight * Math.pow(t2, 3); // 这是从 -peakHeight 到 0 的 ease-in
                // 但原代码的逻辑似乎是分开计算位移，然后加到启动位置
                // 让我们沿用原代码的计算逻辑，它计算的是相对启动 Y 的位移
                // 前40%向上，后60%向下回到原点。
                // 后60%的位移计算：从最高点 -_peakHeight 回到 0
                // 假设最高点在 t=0.4 时达到
                // 目标 Y = 0 (启动 Y)
                // 当前时间 t2 (0 to 1) 对应 0.4 到 1 的总时间
                // 使用 ease-out quadratic 也许更接近抛物线? 但代码用的是 cubic
                // 沿用代码逻辑：后60%是相对启动位置的位移，从最高点 -_peakHeight 下降到接近0
                // 这个计算方式有点反直觉，因为它没有直接插值。
                // 让我们尝试理解原代码的意图：它计算的是相对启动位置的 *偏移量*。
                // 前40%的位移是从0到最高点 `-_peakHeight * (1 - Math.pow(1 - t1, 3))`
                // 后60%的位移是 `-_peakHeight * (1 - Math.pow(t2, 3))`
                // 当 t2=0 (t=0.4), 位移 = -_peakHeight * (1-1) = 0. 这不对。
                // 当 t2=1 (t=1.0), 位移 = -_peakHeight * (1-0) = -_peakHeight. 这也不对。
                // *重新审视代码*：
                // `y = -this._peakHeight * (1 - Math.pow(1 - t1, 3));` 当 t1=0, y=0; t1=1, y=-_peakHeight. 向上。
                // `y = -this._peakHeight * (1 - Math.pow(t2, 3));` 当 t2=0, y=-_peakHeight; t2=1, y=0. 从最高点回到原点。
                // 这个逻辑是正确的！前40%从0到-_peakHeight，后60%从-_peakHeight到0。
                y = -this._peakHeight * (1 - Math.pow(t2, 3));
            }

            // ---------- 横向振荡（衰减） ----------
            // 计算衰减因子，随着时间 t 从 1 线性衰减到 0
            var decay:Number = 1 - t;
            // 计算横向偏移量：衰减振幅 * 正弦波 (频率由 _horizCycles 控制)
            var x:Number = this._horizAmp * decay *
                        Math.sin(2 * Math.PI * this._horizCycles * t);

            // ---------- 注入细碎抖动（仅峰值附近） ----------
            // 在接近抛物线最高点的时间段内，给导弹角度添加随机小幅抖动
            if (t > 0.35 && t < 0.45) { // 例如在 35% 到 45% 的时间范围内
                this.rotationAngle += (Math.random() - 0.5) * 0.4; // 在 ±0.2 度范围内随机调整角度
            }

            // ---------- 应用位置 ----------
            // 将计算出的偏移量叠加到初始发射位置上，更新导弹的当前位置
            this.targetObject._x = this._launchX + x;
            this.targetObject._y = this._launchY + y;

            // 返回 false 表示动画尚未完成（除非 flag 是 "isComplete"）
            return false;
        }

        // 返回包含所有回调函数的对象
        return {
            onInitializeMissile : _init,        // 初始化函数
            onSearchForTarget   : _search,      // 目标搜索函数 (限帧优化)
            onTrackTarget       : _track,       // 目标追踪函数
            onPreLaunchMove     : _preLaunch    // 预发射动画函数
        };
    }
}
