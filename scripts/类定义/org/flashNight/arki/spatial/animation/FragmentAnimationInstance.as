import org.flashNight.arki.spatial.animation.FragmentConfig;
import org.flashNight.arki.spatial.animation.FragmentSize;
import org.flashNight.arki.spatial.animation.FragmentAnimator;

/**
 * 碎片动画实例类
 * 
 * 此类负责执行单个碎片动画的所有逻辑，包括物理模拟、碰撞检测、
 * 渲染更新等。每个动画实例独立运行，拥有自己的物理状态和生命周期。
 * 
 * 核心功能模块：
 * 1. 碎片管理：自动发现和初始化碎片MovieClip
 * 2. 物理计算：重力、摩擦、反弹等物理效果
 * 3. 碰撞系统：碎片间的弹性碰撞检测和响应
 * 4. 质量系统：基于视觉尺寸计算物理质量
 * 5. 生命周期：自动开始、运行和结束动画
 * 6. 性能优化：智能停止检测和资源清理
 * 
 * 物理模拟特性：
 * - 真实重力：考虑质量差异的重力加速度
 * - 弹性碰撞：基于动量守恒的碰撞计算
 * - 摩擦力：地面摩擦和空气阻力模拟
 * - 能量损耗：系统稳定性和真实感
 * - 旋转动力学：碰撞引起的旋转变化
 * 
 * 性能考虑：
 * - 碰撞优化：只有部分碎片参与碰撞检测
 * - 早期停止：智能检测动画结束条件
 * - 内存管理：及时清理引用，防止内存泄漏
 * - 计算优化：使用高效的数学算法
 * 
 */
class org.flashNight.arki.spatial.animation.FragmentAnimationInstance {
    
    // ======================== 基础属性 ========================
    
    /**
     * 动画实例的唯一标识符
     * 
     * 由FragmentAnimator分配的唯一ID，用于识别和管理动画实例。
     * 当动画自然结束时，会使用此ID从全局管理器中移除自己。
     */
    private var _animationId:Number;
    
    /**
     * 动画作用域容器
     * 
     * 承载所有碎片MovieClip的容器对象。碎片的位置、旋转等变换
     * 都是相对于此容器的坐标系进行的。
     */
    private var _scope:MovieClip;
    
    /**
     * 碎片命名前缀
     * 
     * 用于查找碎片MovieClip的名称前缀。实际查找的碎片名称格式为：
     * 前缀 + 数字（从1开始），例如："碎片1", "碎片2", "碎片3"...
     */
    private var _fragmentPrefix:String;
    
    /**
     * 动画配置对象
     * 
     * 包含所有物理参数、运动设置、碰撞参数等配置信息。
     * 此对象在动画过程中不会被修改，确保行为的一致性。
     */
    private var _config:FragmentConfig;
    
    // ======================== 碎片数据数组 ========================
    
    /**
     * 碎片MovieClip引用数组
     * 
     * 存储所有碎片MovieClip的引用。数组索引对应碎片编号-1，
     * 例如：_fragments[0]对应"前缀1"，_fragments[1]对应"前缀2"
     * 
     * 如果某个碎片不存在，对应位置存储null，但仍保留位置
     * 以保持索引的一致性。
     */
    private var _fragments:Array;
    
    /**
     * X轴速度数组（像素/帧）
     * 
     * 存储每个碎片在X轴方向的瞬时速度。正值表示向右移动，
     * 负值表示向左移动。速度会受到摩擦力和碰撞的影响而变化。
     */
    private var _velocityX:Array;
    
    /**
     * Y轴速度数组（像素/帧）
     * 
     * 存储每个碎片在Y轴方向的瞬时速度。负值表示向上移动，
     * 正值表示向下移动。速度会受到重力和碰撞的影响而变化。
     */
    private var _velocityY:Array;
    
    /**
     * 旋转速度数组（度/帧）
     * 
     * 存储每个碎片的瞬时旋转速度。正值表示顺时针旋转，
     * 负值表示逆时针旋转。旋转速度会受到摩擦和碰撞的影响。
     */
    private var _velocityRotation:Array;
    
    /**
     * 碰撞参与标志数组
     * 
     * 存储每个碎片是否参与碰撞检测的布尔值。设置为false的碎片
     * 不会与其他碎片发生碰撞，但仍会受到重力和地面碰撞的影响。
     * 这种设计可以减少计算量并产生更自然的视觉效果。
     */
    private var _collidable:Array;
    
    /**
     * 碎片质量数组
     * 
     * 存储每个碎片的物理质量值。质量根据碎片的视觉尺寸计算得出，
     * 影响重力效果、碰撞响应、摩擦力等物理行为。质量大的碎片：
     * - 受空气阻力影响较小
     * - 反弹衰减较快
     * - 在碰撞中占据优势
     * - 更容易停止运动
     */
    private var _mass:Array;
    
    /**
     * 碎片尺寸信息数组
     * 
     * 存储每个碎片的尺寸信息对象，包含宽度、高度、面积等数据。
     * 用于质量计算、碰撞半径计算等用途。
     */
    private var _size:Array;
    
    // ======================== 状态控制 ========================
    
    /**
     * 动画运行状态标志
     * 
     * 指示当前动画是否正在运行。true表示动画正在更新中，
     * false表示动画已停止。只有运行中的动画才会执行物理计算。
     */
    private var _isRunning:Boolean = false;
    
    /**
     * 构造函数
     * 
     * 创建一个新的动画实例，但不立即开始播放。需要调用start()方法
     * 才能开始动画。构造过程包括：
     * 1. 保存传入的参数
     * 2. 初始化碎片引用和属性
     * 3. 计算初始物理参数
     * 4. 准备动画数据结构
     * 
     * @param animationId:Number 动画实例的唯一ID
     * @param scope:MovieClip 动画作用域容器
     * @param fragmentPrefix:String 碎片命名前缀
     * @param config:FragmentConfig 动画配置对象
     * 
     * @example
     * var instance:FragmentAnimationInstance = new FragmentAnimationInstance(
     *     1, container, "碎片", config
     * );
     * instance.start(); // 开始播放动画
     */
    public function FragmentAnimationInstance(animationId:Number, scope:MovieClip, 
                                            fragmentPrefix:String, config:FragmentConfig) {
        _animationId = animationId;
        _scope = scope;
        _fragmentPrefix = fragmentPrefix;
        _config = config;
        
        // 初始化所有数据数组
        initializeFragments();
        initializePhysics();
        
        if (_config.enableDebug) {
            _root.服务器.发布服务器消息("[FragmentAnimationInstance] 实例创建完成, ID: " + _animationId);
        }
    }
    
    /**
     * 初始化碎片引用和属性
     * 
     * 此方法负责：
     * 1. 在作用域中查找所有碎片MovieClip
     * 2. 计算每个碎片的视觉尺寸（通过getBounds）
     * 3. 基于尺寸计算物理质量
     * 4. 处理缺失的碎片（设置默认值）
     * 5. 输出调试信息（如果启用）
     * 
     * 质量计算逻辑：
     * - 获取碎片的边界矩形
     * - 计算面积 = 宽度 × 高度
     * - 质量 = max(面积 / 质量缩放因子, 最小质量)
     * 
     * 缺失碎片处理：
     * - 如果找不到某个编号的碎片，在数组中存储null
     * - 为其分配默认尺寸和质量，避免计算错误
     * - 输出警告信息（调试模式下）
     */
    private function initializeFragments():Void {
        // 初始化数组
        _fragments = new Array(_config.fragmentCount);
        _mass = new Array(_config.fragmentCount);
        _size = new Array(_config.fragmentCount);
        
        var totalMass:Number = 0;
        var maxMass:Number = 0;
        var minMass:Number = Number.MAX_VALUE;
        var validFragmentCount:Number = 0;
        
        // 遍历所有预期的碎片
        for (var i:Number = 0; i < _config.fragmentCount; i++) {
            // 构造碎片名称：前缀 + (索引+1)
            var fragmentName:String = _fragmentPrefix + (i + 1);
            var mc:MovieClip = _scope[fragmentName];
            
            _fragments[i] = mc;
            
            if (mc) {
                validFragmentCount++;
                
                // 计算碎片的边界矩形
                var bounds:Object = mc.getBounds(_scope);
                var fragmentWidth:Number = bounds.xMax - bounds.xMin;
                var fragmentHeight:Number = bounds.yMax - bounds.yMin;
                
                // 创建尺寸信息对象
                var size:FragmentSize = new FragmentSize(fragmentWidth, fragmentHeight);
                _size[i] = size;
                
                // 基于面积计算质量
                var fragmentMass:Number = Math.max(size.area / _config.massScale, _config.minMass) || 100;
                _mass[i] = fragmentMass;
                
                // 统计信息
                totalMass += fragmentMass;
                maxMass = Math.max(maxMass, fragmentMass);
                minMass = Math.min(minMass, fragmentMass);
                
                if (_config.enableDebug) {
                    _root.服务器.发布服务器消息("[FragmentAnimationInstance] 碎片" + (i + 1) + " (" + fragmentName + ") - " +
                          "尺寸:" + Math.round(fragmentWidth) + "x" + Math.round(fragmentHeight) + 
                          ", 面积:" + Math.round(size.area) + 
                          ", 质量:" + Math.round(fragmentMass * 100) / 100);
                }
            } else {
                // 处理缺失的碎片
                if (_config.enableDebug) {
                    _root.服务器.发布服务器消息("[FragmentAnimationInstance] 警告：找不到碎片 " + fragmentName);
                }
                
                // 设置默认值，避免计算错误
                _size[i] = new FragmentSize(20, 20);
                _mass[i] = _config.minMass;
            }
        }
        
        // 输出统计信息
        if (_config.enableDebug) {
            _root.服务器.发布服务器消息("[FragmentAnimationInstance] 碎片初始化完成:");
            _root.服务器.发布服务器消息("  - 总数: " + _config.fragmentCount + " (有效: " + validFragmentCount + ")");
            _root.服务器.发布服务器消息("  - 质量统计: 总计=" + Math.round(totalMass * 100) / 100 + 
                  ", 最大=" + Math.round(maxMass * 100) / 100 + 
                  ", 最小=" + Math.round(minMass * 100) / 100);
            
            if (validFragmentCount == 0) {
                _root.服务器.发布服务器消息("[FragmentAnimationInstance] 警告：没有找到任何有效的碎片！");
            }
        }
    }
    
    /**
     * 初始化物理运动参数
     * 
     * 此方法为每个碎片生成随机的初始运动状态，包括：
     * 1. 水平速度：基于配置的方向和速度参数
     * 2. 垂直速度：向上的随机抛射速度
     * 3. 旋转速度：随机的旋转方向和速度
     * 4. 碰撞参与：根据概率随机决定是否参与碰撞
     * 
     * 速度生成逻辑：
     * - 水平速度 = 方向 × (基础速度 + 随机范围)
     * - 垂直速度 = -(随机值 在 [最小速度, 最大速度] 范围内)
     * - 旋转速度 = 随机值 在 [-旋转范围, +旋转范围] 范围内
     * 
     * 碰撞参与决策：
     * - 根据碰撞概率随机决定每个碎片是否参与碰撞
     * - 不参与碰撞的碎片可以减少计算量
     * - 同时产生更自然的视觉效果（不是所有碎片都会碰撞）
     */
    private function initializePhysics():Void {
        // 初始化物理数组
        _velocityX = new Array(_config.fragmentCount);
        _velocityY = new Array(_config.fragmentCount);
        _velocityRotation = new Array(_config.fragmentCount);
        _collidable = new Array(_config.fragmentCount);
        
        var collidableCount:Number = 0;
        
        // 为每个碎片生成初始物理参数
        for (var i:Number = 0; i < _config.fragmentCount; i++) {
            // 水平速度：基础方向 + 随机变化
            // direction为-1时向左，为1时向右
            _velocityX[i] = _config.direction * (_config.baseVelocityX + Math.random() * _config.velocityXRange);
            
            // 垂直速度：向上抛射 + 随机变化
            // 负值表示向上，模拟爆炸向上抛射的效果
            var verticalSpeed:Number = Math.random() * (_config.velocityYMax - _config.velocityYMin) + _config.velocityYMin;
            _velocityY[i] = -verticalSpeed;
            
            // 旋转速度：完全随机的方向和大小
            _velocityRotation[i] = (Math.random() * _config.rotationRange * 2 - _config.rotationRange);
            
            // 碰撞参与：根据概率随机决定
            _collidable[i] = (Math.random() < _config.collisionProbability);
            
            if (_collidable[i]) {
                collidableCount++;
            }
            
            if (_config.enableDebug) {
                _root.服务器.发布服务器消息("[FragmentAnimationInstance] 碎片" + (i + 1) + " 初始速度: " +
                      "vx=" + Math.round(_velocityX[i] * 10) / 10 + 
                      ", vy=" + Math.round(_velocityY[i] * 10) / 10 + 
                      ", vr=" + Math.round(_velocityRotation[i] * 10) / 10 + 
                      ", 碰撞=" + (_collidable[i] ? "是" : "否"));
            }
        }
        
        // 输出物理初始化统计信息
        if (_config.enableDebug) {
            _root.服务器.发布服务器消息("[FragmentAnimationInstance] 物理参数初始化完成:");
            _root.服务器.发布服务器消息("  - 参与碰撞的碎片: " + collidableCount + "/" + _config.fragmentCount + 
                  " (" + Math.round(collidableCount / _config.fragmentCount * 100) + "%)");
            _root.服务器.发布服务器消息("  - 主运动方向: " + (_config.direction > 0 ? "向右" : "向左"));
            _root.服务器.发布服务器消息("  - 速度范围: X=[" + Math.round(_config.baseVelocityX * 10) / 10 + 
                  "," + Math.round((_config.baseVelocityX + _config.velocityXRange) * 10) / 10 + 
                  "], Y=[" + _config.velocityYMin + "," + _config.velocityYMax + "]");
        }
    }
    
    /**
     * 启动动画
     * 
     * 开始动画的主更新循环。此方法会：
     * 1. 设置运行状态标志
     * 2. 启动逐帧更新循环（onEnterFrame）
     * 3. 输出调试信息
     * 
     * 如果动画已经在运行中，重复调用此方法不会产生副作用。
     * 
     * @example
     * var instance:FragmentAnimationInstance = new FragmentAnimationInstance(...);
     * instance.start(); // 开始动画
     */
    public function start():Void {
        if (!_isRunning) {
            _isRunning = true;
            
            // 设置逐帧更新回调
            // 注意：需要保存this引用，因为onEnterFrame中的this会发生变化
            var self:FragmentAnimationInstance = this;
            _scope.onEnterFrame = function():Void {
                self.onEnterFrame();
            };
            
            if (_config.enableDebug) {
                _root.服务器.发布服务器消息("[FragmentAnimationInstance] 动画已启动, ID: " + _animationId);
            }
        }
    }
    
    /**
     * 停止动画
     * 
     * 立即停止动画的更新循环并清理资源。此方法会：
     * 1. 清除运行状态标志
     * 2. 移除逐帧更新回调
     * 3. 输出调试信息
     * 
     * 停止后的动画无法恢复，如需重新播放必须创建新实例。
     * 
     * @example
     * instance.stop(); // 停止动画
     */
    public function stop():Void {
        if (_isRunning) {
            _isRunning = false;
            
            // 清除逐帧更新回调
            delete _scope.onEnterFrame;
            
            if (_config.enableDebug) {
                _root.服务器.发布服务器消息("[FragmentAnimationInstance] 动画已停止, ID: " + _animationId);
            }
        }
    }
    
    /**
     * 逐帧更新回调函数
     * 
     * 这是动画的核心更新循环，每帧都会被调用。更新顺序：
     * 1. 物理运动更新（位置、旋转、重力）
     * 2. 地面碰撞检测和响应
     * 3. 碎片间碰撞检测和响应
     * 4. 停止条件检测
     * 5. 自动清理（如果需要）
     * 
     * 如果检测到所有碎片都已停止运动，会自动停止动画并
     * 从全局管理器中移除自己。
     */
    private function onEnterFrame():Void {
        // 1. 更新所有碎片的物理运动
        updatePhysics();
        
        // 2. 处理碎片间的碰撞
        updateCollisions();
        
        // 3. 检查是否应该停止动画
        if (checkAllStopped()) {
            // 停止当前动画
            stop();
            
            // 从全局管理器中移除自己
            FragmentAnimator._removeAnimationInstance(_animationId);
            
            if (_config.enableDebug) {
                _root.服务器.发布服务器消息("[FragmentAnimationInstance] 动画自然结束, ID: " + _animationId);
            }
        }
    }
    
    /**
     * 更新物理运动
     * 
     * 此方法处理每个碎片的基础物理运动，包括：
     * 1. 重力加速度（考虑质量差异）
     * 2. 位置更新（基于当前速度）
     * 3. 旋转更新（基于旋转速度）
     * 4. 地面碰撞检测和响应
     * 5. 摩擦力和能量损耗
     * 6. 停止阈值检测
     * 
     * 质量影响的物理效果：
     * - 重力：质量大的物体受空气阻力影响相对较小
     * - 反弹：质量大的物体反弹衰减更快
     * - 摩擦：质量大的物体摩擦相对较小
     * - 停止：质量大的物体更容易停止
     */
    private function updatePhysics():Void {
        for (var i:Number = 0; i < _config.fragmentCount; i++) {
            var fragment:MovieClip = _fragments[i];
            if (!fragment) continue; // 跳过不存在的碎片
            
            // === 重力加速度计算 ===
            // 质量大的物体受空气阻力影响相对较小，所以重力效果更明显
            var gravityEffect:Number = _config.gravity * (0.8 + 0.4 / Math.sqrt(_mass[i]));
            _velocityY[i] += gravityEffect;
            
            // === 位置和旋转更新 ===
            fragment._x += _velocityX[i];
            fragment._y += _velocityY[i];
            fragment._rotation += _velocityRotation[i];
            
            // === 地面碰撞检测（使用容差解决浮点数精度问题）===
            if (fragment._y >= _config.groundY - 0.5) {
                // 将碎片限制在地面上
                fragment._y = _config.groundY;
                
                // === 反弹计算 ===
                // 质量大的物体反弹衰减更快（更快稳定）
                var massBounceFactor:Number = _config.bounce * (2 / (1 + _mass[i] / 3));
                _velocityY[i] *= -massBounceFactor;
                
                // === 摩擦力计算 ===
                // 质量大的物体摩擦力相对较小（惯性更强）
                var massFrictionFactor:Number = _config.friction * (0.7 + 0.5 / Math.sqrt(_mass[i]));
                _velocityX[i] *= massFrictionFactor;
                _velocityRotation[i] *= 0.6; // 旋转也受摩擦影响
                
                // === 停止阈值检测 ===
                // 质量大的物体更容易停下来（基于现实物理）
                var stopThreshold:Number = _config.stopThresholdBase / Math.sqrt(_mass[i]);
                
                if (Math.abs(_velocityY[i]) < stopThreshold) {
                    _velocityY[i] = 0;
                }
                if (Math.abs(_velocityX[i]) < _config.stopThresholdX) {
                    _velocityX[i] = 0;
                }
                if (Math.abs(_velocityRotation[i]) < _config.stopThresholdRotation) {
                    _velocityRotation[i] = 0;
                }
            }
        }
    }
    
    /**
     * 更新碎片间碰撞
     * 
     * 此方法处理所有参与碰撞的碎片之间的相互作用：
     * 1. 双重循环检测所有碎片对
     * 2. 计算动态碰撞半径（基于碎片尺寸）
     * 3. 执行圆形碰撞检测
     * 4. 处理碰撞响应（分离和速度调整）
     * 5. 应用能量损耗
     * 
     * 碰撞响应包括：
     * - 重叠分离：将相交的碎片推开
     * - 弹性碰撞：基于动量守恒计算新速度
     * - 旋转影响：碰撞会影响碎片的旋转
     * - 质量效应：质量大的碎片在碰撞中占优势
     * 
     * 性能优化：
     * - 只检测标记为可碰撞的碎片
     * - 使用圆形碰撞检测（比矩形更高效）
     * - 避免重复检测（i与j的配对只检测一次）
     */
    private function updateCollisions():Void {
        // 双重循环检测所有碎片对的碰撞
        for (var i:Number = 0; i < _config.fragmentCount - 1; i++) {
            // 跳过不参与碰撞或不存在的碎片
            if (!_collidable[i] || !_fragments[i]) continue;
            
            for (var j:Number = i + 1; j < _config.fragmentCount; j++) {
                // 跳过不参与碰撞或不存在的碎片
                if (!_collidable[j] || !_fragments[j]) continue;
                
                // === 计算碰撞半径 ===
                // 基于碎片面积计算等效圆形半径
                var radiusI:Number = _size[i].getCollisionRadius();
                var radiusJ:Number = _size[j].getCollisionRadius();
                var minDist:Number = radiusI + radiusJ;
                
                // === 距离检测 ===
                var dx:Number = _fragments[j]._x - _fragments[i]._x;
                var dy:Number = _fragments[j]._y - _fragments[i]._y;
                var dist2:Number = dx * dx + dy * dy; // 距离的平方（避免开方运算）
                
                // 检查是否发生碰撞
                if (dist2 < minDist * minDist && dist2 > 0) {
                    // 发生碰撞，处理碰撞响应
                    var dist:Number = Math.sqrt(dist2);
                    handleCollision(i, j, dx, dy, dist, minDist);
                }
            }
        }
    }
    
    /**
     * 处理两个碎片的碰撞响应
     * 
     * 当检测到两个碎片发生碰撞时，此方法负责计算和应用碰撞响应：
     * 
     * 1. 重叠分离：
     *    - 计算重叠深度
     *    - 根据质量比例分离碎片
     *    - 确保碎片不再相交
     * 
     * 2. 弹性碰撞计算：
     *    - 使用动量守恒定律
     *    - 考虑两个碎片的质量差异
     *    - 计算碰撞后的新速度
     * 
     * 3. 能量损耗：
     *    - 应用配置的能量损失系数
     *    - 模拟非完全弹性碰撞
     *    - 增强系统稳定性
     * 
     * 4. 旋转响应：
     *    - 碰撞会产生随机的旋转变化
     *    - 质量小的碎片旋转变化更大
     * 
     * @param i:Number 第一个碎片的索引
     * @param j:Number 第二个碎片的索引
     * @param dx:Number X轴距离差
     * @param dy:Number Y轴距离差
     * @param dist:Number 两碎片中心的实际距离
     * @param minDist:Number 最小允许距离（两半径之和）
     */
    private function handleCollision(i:Number, j:Number, dx:Number, dy:Number, 
                                   dist:Number, minDist:Number):Void {
        
        // === 重叠分离处理 ===
        var overlap:Number = minDist - dist;
        
        // 根据质量比例计算分离量
        // 质量大的碎片移动得少，质量小的碎片移动得多
        var totalMass:Number = _mass[i] + _mass[j];
        var separationRatioI:Number = _mass[j] / totalMass; // 碎片i的分离比例
        var separationRatioJ:Number = _mass[i] / totalMass; // 碎片j的分离比例
        
        // 计算分离向量
        var separateX:Number = (dx / dist) * overlap;
        var separateY:Number = (dy / dist) * overlap;
        
        // 应用分离，推开重叠的碎片
        _fragments[i]._x -= separateX * separationRatioI;
        _fragments[i]._y -= separateY * separationRatioI;
        _fragments[j]._x += separateX * separationRatioJ;
        _fragments[j]._y += separateY * separationRatioJ;
        
        // === 弹性碰撞速度计算 ===
        var m1:Number = _mass[i];
        var m2:Number = _mass[j];
        
        // 保存碰撞前的速度
        var v1x:Number = _velocityX[i];
        var v1y:Number = _velocityY[i];
        var v2x:Number = _velocityX[j];
        var v2y:Number = _velocityY[j];
        
        // 使用弹性碰撞公式计算新速度
        // 公式基于动量守恒和能量守恒（考虑能量损失）
        _velocityX[i] = ((m1 - m2) * v1x + 2 * m2 * v2x) / (m1 + m2) * _config.energyLoss;
        _velocityY[i] = ((m1 - m2) * v1y + 2 * m2 * v2y) / (m1 + m2) * _config.energyLoss;
        _velocityX[j] = ((m2 - m1) * v2x + 2 * m1 * v1x) / (m1 + m2) * _config.energyLoss;
        _velocityY[j] = ((m2 - m1) * v2y + 2 * m1 * v1y) / (m1 + m2) * _config.energyLoss;
        
        // === 旋转响应 ===
        // 碰撞会产生随机的旋转变化，质量小的碎片变化更大
        _velocityRotation[i] += (Math.random() - 0.5) * 2 / _mass[i];
        _velocityRotation[j] += (Math.random() - 0.5) * 2 / _mass[j];
        
        // 调试信息输出
        if (_config.enableDebug) {
            _root.服务器.发布服务器消息("[FragmentAnimationInstance] 碰撞: 碎片" + (i + 1) + " vs 碎片" + (j + 1) + 
                  ", 重叠=" + Math.round(overlap * 10) / 10 + 
                  ", 质量比=" + Math.round((m1 / m2) * 10) / 10);
        }
    }
    
    /**
     * 检查所有碎片是否都已停止运动
     * 
     * 此方法遍历所有有效的碎片，检查其运动状态：
     * 1. 检查X和Y方向的速度是否都足够小
     * 2. 忽略旋转速度（旋转不影响停止判定）
     * 3. 只要有一个碎片还在明显运动就返回false
     * 4. 所有碎片都静止时返回true
     * 
     * 停止阈值设置为0.1像素/帧，这个值：
     * - 足够小，避免过早停止动画
     * - 足够大，避免无限运行（浮点数精度问题）
     * - 在视觉上基本无法察觉
     * 
     * @return Boolean true表示所有碎片都已停止，false表示还有碎片在运动
     */
    private function checkAllStopped():Boolean {
        for (var i:Number = 0; i < _config.fragmentCount; i++) {
            var fragment:MovieClip = _fragments[i];
            if (fragment) {
                // 检查X和Y速度是否都小于停止阈值
                if (Math.abs(_velocityX[i]) > 0.1 || Math.abs(_velocityY[i]) > 0.1) {
                    return false; // 发现还在运动的碎片
                }
            }
        }
        
        // 所有碎片都已停止
        return true;
    }
    
    // ======================== 公共访问方法 ========================
    
    /**
     * 获取动画实例ID
     * 
     * @return Number 当前动画实例的唯一标识符
     */
    public function getAnimationId():Number {
        return _animationId;
    }
    
    /**
     * 检查动画是否正在运行
     * 
     * @return Boolean true表示动画正在运行，false表示已停止
     */
    public function isRunning():Boolean {
        return _isRunning;
    }
    
    /**
     * 获取碎片总数
     * 
     * @return Number 配置的碎片总数（包括不存在的碎片）
     */
    public function getFragmentCount():Number {
        return _config.fragmentCount;
    }
    
    /**
     * 获取有效碎片数量
     * 
     * @return Number 实际找到的有效碎片数量
     */
    public function getValidFragmentCount():Number {
        var count:Number = 0;
        for (var i:Number = 0; i < _config.fragmentCount; i++) {
            if (_fragments[i]) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * 获取参与碰撞的碎片数量
     * 
     * @return Number 标记为可碰撞的碎片数量
     */
    public function getCollidableFragmentCount():Number {
        var count:Number = 0;
        for (var i:Number = 0; i < _config.fragmentCount; i++) {
            if (_collidable[i] && _fragments[i]) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * 获取指定碎片的当前速度
     * 
     * @param index:Number 碎片索引（0开始）
     * @return Object 包含vx、vy、vr属性的速度对象，如果索引无效返回null
     */
    public function getFragmentVelocity(index:Number):Object {
        if (index < 0 || index >= _config.fragmentCount || !_fragments[index]) {
            return null;
        }
        
        return {
            vx: _velocityX[index],
            vy: _velocityY[index],
            vr: _velocityRotation[index]
        };
    }
    
    /**
     * 强制停止指定碎片的运动
     * 
     * @param index:Number 碎片索引（0开始）
     * @return Boolean 操作是否成功
     */
    public function stopFragment(index:Number):Boolean {
        if (index < 0 || index >= _config.fragmentCount || !_fragments[index]) {
            return false;
        }
        
        _velocityX[index] = 0;
        _velocityY[index] = 0;
        _velocityRotation[index] = 0;
        
        return true;
    }
}