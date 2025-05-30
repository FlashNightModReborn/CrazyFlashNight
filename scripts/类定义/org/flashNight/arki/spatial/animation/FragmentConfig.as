/**
 * 碎片动画配置管理类
 * 
 * 此类封装了碎片动画系统的所有可配置参数，包括物理模拟、运动控制、
 * 碰撞检测、调试选项等各个方面的设置。通过修改这些参数，可以实现
 * 不同风格和效果的破碎动画。
 * 
 * 配置分类：
 * 1. 物理参数：控制重力、反弹、摩擦等基础物理行为
 * 2. 运动参数：控制碎片的初始运动状态和速度分布
 * 3. 碰撞参数：控制碎片间的碰撞检测和响应
 * 4. 质量计算：控制如何根据碎片尺寸计算物理质量
 * 5. 停止条件：控制动画何时自动结束
 * 6. 调试选项：控制调试信息的输出
 * 
 * 使用场景：
 * - 资源箱破碎：重物理感，慢速散落
 * - 玻璃破碎：轻快感，高速飞溅
 * - 岩石破碎：重物理感，中等散落
 * - 纸片破碎：轻飘感，慢速飘落
 * 
 */
class org.flashNight.arki.spatial.animation.FragmentConfig {
    
    // ======================== 物理参数 ========================
    
    /**
     * 重力加速度 (像素/帧²)
     * 
     * 控制碎片向下的加速度。较大的值会让碎片快速下落，
     * 较小的值会产生飘浮效果。
     * 
     * 推荐值：
     * - 重物破碎：1.2 - 2.0
     * - 普通破碎：0.8 - 1.4
     * - 轻物破碎：0.3 - 0.8
     * 
     * @default 1.4
     */
    public var gravity:Number = 1.4;
    
    /**
     * 反弹衰减系数 (0-1)
     * 
     * 控制碎片撞击地面后的反弹强度。值越大反弹越强，
     * 0表示完全不反弹，1表示完全弹性碰撞（不推荐）。
     * 
     * 推荐值：
     * - 金属碎片：0.4 - 0.7
     * - 木制碎片：0.2 - 0.4
     * - 软质碎片：0.1 - 0.3
     * 
     * @default 0.35
     */
    public var bounce:Number = 0.35;
    
    /**
     * 地面摩擦系数 (0-1)
     * 
     * 控制碎片在地面滑动时的摩擦力。值越大摩擦越强，
     * 碎片停止得越快。
     * 
     * 推荐值：
     * - 粗糙地面：0.8 - 0.95
     * - 普通地面：0.7 - 0.85
     * - 光滑地面：0.5 - 0.7
     * 
     * @default 0.85
     */
    public var friction:Number = 0.85;
    
    /**
     * 碎片总数量
     * 
     * 指定要处理的碎片MovieClip数量。系统会查找名为
     * "前缀1", "前缀2", ..., "前缀N"的MovieClip。
     * 
     * 性能考虑：
     * - 1-10个：性能很好
     * - 10-20个：性能良好
     * - 20+个：需要注意性能
     * 
     * @default 10
     */
    public var fragmentCount:Number = 10;
    
    /**
     * 地面高度 (像素)
     * 
     * 相对于容器坐标系的地面Y坐标。碎片落到此高度时
     * 会触发地面碰撞逻辑（反弹、摩擦等）。
     * 
     * @default 30
     */
    public var groundY:Number = 30;
    
    // ======================== 运动参数 ========================
    
    /**
     * 基础水平速度 (像素/帧)
     * 
     * 碎片水平方向的基础飞行速度。实际速度会在此基础上
     * 添加随机变化，并受direction参数影响方向。
     * 
     * 推荐值：
     * - 爆炸效果：10 - 20
     * - 普通破碎：5 - 15
     * - 轻微破碎：2 - 8
     * 
     * @default 8
     */
    public var baseVelocityX:Number = 8;
    
    /**
     * 水平速度随机范围 (像素/帧)
     * 
     * 在基础水平速度基础上增加的随机变化范围。
     * 每个碎片会获得 [baseVelocityX, baseVelocityX + velocityXRange] 的速度。
     * 
     * @default 6
     */
    public var velocityXRange:Number = 6;
    
    /**
     * 最小垂直速度 (像素/帧)
     * 
     * 碎片向上抛射的最小初始速度（负值表示向上）。
     * 配合velocityYMax形成速度区间。
     * 
     * @default 4
     */
    public var velocityYMin:Number = 4;
    
    /**
     * 最大垂直速度 (像素/帧)
     * 
     * 碎片向上抛射的最大初始速度（负值表示向上）。
     * 每个碎片会获得 [velocityYMin, velocityYMax] 的随机向上速度。
     * 
     * @default 12
     */
    public var velocityYMax:Number = 12;
    
    /**
     * 旋转速度范围 (度/帧)
     * 
     * 控制碎片旋转的速度范围。每个碎片会获得
     * [-rotationRange, +rotationRange] 的随机旋转速度。
     * 
     * 推荐值：
     * - 快速旋转：8 - 15
     * - 普通旋转：3 - 8
     * - 慢速旋转：1 - 5
     * 
     * @default 5
     */
    public var rotationRange:Number = 5;
    
    // ======================== 碰撞参数 ========================
    
    /**
     * 碎片参与碰撞的概率 (0-1)
     * 
     * 控制多少比例的碎片会参与碰撞检测。设置为小于1的值
     * 可以减少计算量，同时产生更自然的碰撞分布。
     * 
     * 推荐值：
     * - 密集碰撞：0.7 - 1.0
     * - 适度碰撞：0.4 - 0.7
     * - 稀疏碰撞：0.1 - 0.4
     * 
     * @default 0.5
     */
    public var collisionProbability:Number = 0.5;
    
    /**
     * 碰撞能量损失系数 (0-1)
     * 
     * 控制碎片间碰撞时的能量损耗。值越小，碰撞后的速度越小，
     * 系统越快稳定。1表示完全弹性碰撞（能量不损失）。
     * 
     * 推荐值：
     * - 软质材料：0.3 - 0.5
     * - 普通材料：0.5 - 0.7
     * - 硬质材料：0.7 - 0.9
     * 
     * @default 0.5
     */
    public var energyLoss:Number = 0.5;
    
    // ======================== 质量计算参数 ========================
    
    /**
     * 面积转质量的缩放因子
     * 
     * 控制如何将碎片的视觉面积转换为物理质量。
     * 质量 = 面积 / massScale，值越大则质量越小。
     * 
     * 推荐值：
     * - 轻质材料：200 - 500
     * - 普通材料：80 - 200
     * - 重质材料：20 - 80
     * 
     * @default 100
     */
    public var massScale:Number = 100;
    
    /**
     * 最小质量限制
     * 
     * 防止极小的碎片质量过小导致物理计算异常。
     * 任何碎片的质量都不会低于此值。
     * 
     * @default 0.5
     */
    public var minMass:Number = 0.5;
    
    // ======================== 停止条件参数 ========================
    
    /**
     * 停止判定阈值基础值 (像素/帧)
     * 
     * 用于计算速度停止阈值的基础值。实际阈值会根据碎片质量
     * 进行调整：threshold = stopThresholdBase / sqrt(mass)
     * 
     * @default 0.5
     */
    public var stopThresholdBase:Number = 0.5;
    
    /**
     * X轴速度停止阈值 (像素/帧)
     * 
     * 当碎片的水平速度绝对值小于此值时，将被设为0。
     * 
     * @default 0.3
     */
    public var stopThresholdX:Number = 0.3;
    
    /**
     * 旋转速度停止阈值 (度/帧)
     * 
     * 当碎片的旋转速度绝对值小于此值时，将被设为0。
     * 
     * @default 0.2
     */
    public var stopThresholdRotation:Number = 0.2;
    
    // ======================== 方向设置 ========================
    
    /**
     * 主运动方向 (-1 或 1)
     * 
     * 控制碎片的主要飞行方向：
     * -1：向左飞行
     *  1：向右飞行
     * 
     * @default -1
     */
    public var direction:Number = -1;
    
    // ======================== 调试选项 ========================
    
    /**
     * 是否启用调试输出
     * 
     * 启用后会在控制台输出详细的运行信息，包括：
     * - 碎片初始化信息
     * - 质量计算结果
     * - 碰撞参与统计
     * - 动画生命周期事件
     * 
     * 注意：调试模式会影响性能，发布版本应该关闭。
     * 
     * @default false
     */
    public var enableDebug:Boolean = false;
    
    /**
     * 构造函数
     * 
     * 创建一个使用默认参数的配置实例。
     * 创建后可以根据需要修改各个参数。
     */
    public function FragmentConfig() {
        // 所有参数已在声明时设置默认值
    }
    
    /**
     * 从外部对象读取配置参数
     * 
     * 此方法允许从外部Object（如JSON数据、XML解析结果、资源文件等）
     * 批量设置配置参数。只有在外部对象中存在的属性才会被设置，
     * 不存在的属性将保持当前值（默认值或之前设置的值）。
     * 
     * 支持的参数名称必须与类的公共属性名称完全一致。
     * 
     * @param source:Object 包含配置数据的外部对象
     * @return Boolean 返回true表示至少有一个参数被成功设置，false表示没有有效参数
     * 
     * @example
     * // 从JSON风格的对象读取配置
     * var configData:Object = {
     *     gravity: 2.0,
     *     fragmentCount: 15,
     *     baseVelocityX: 12,
     *     enableDebug: true
     * };
     * 
     * var config:FragmentConfig = new FragmentConfig();
     * config.loadFromObject(configData);
     * 
     * @example
     * // 从资源文件读取配置
     * var resourceConfig:Object = ResourceManager.getFragmentConfig("explosion");
     * var config:FragmentConfig = new FragmentConfig();
     * config.loadFromObject(resourceConfig);
     */
    public function loadFromObject(source:Object):Boolean {
        if (!source) {
            if (enableDebug) {
                trace("[FragmentConfig] 警告：source对象为null，无法加载配置");
            }
            return false;
        }
        
        var loadedCount:Number = 0;
        
        // 物理参数
        if (source.gravity != undefined) {
            gravity = Number(source.gravity);
            loadedCount++;
        }
        if (source.bounce != undefined) {
            bounce = Number(source.bounce);
            loadedCount++;
        }
        if (source.friction != undefined) {
            friction = Number(source.friction);
            loadedCount++;
        }
        if (source.fragmentCount != undefined) {
            fragmentCount = Number(source.fragmentCount);
            loadedCount++;
        }
        if (source.groundY != undefined) {
            groundY = Number(source.groundY);
            loadedCount++;
        }
        
        // 运动参数
        if (source.baseVelocityX != undefined) {
            baseVelocityX = Number(source.baseVelocityX);
            loadedCount++;
        }
        if (source.velocityXRange != undefined) {
            velocityXRange = Number(source.velocityXRange);
            loadedCount++;
        }
        if (source.velocityYMin != undefined) {
            velocityYMin = Number(source.velocityYMin);
            loadedCount++;
        }
        if (source.velocityYMax != undefined) {
            velocityYMax = Number(source.velocityYMax);
            loadedCount++;
        }
        if (source.rotationRange != undefined) {
            rotationRange = Number(source.rotationRange);
            loadedCount++;
        }
        
        // 碰撞参数
        if (source.collisionProbability != undefined) {
            collisionProbability = Number(source.collisionProbability);
            loadedCount++;
        }
        if (source.energyLoss != undefined) {
            energyLoss = Number(source.energyLoss);
            loadedCount++;
        }
        
        // 质量计算参数
        if (source.massScale != undefined) {
            massScale = Number(source.massScale);
            loadedCount++;
        }
        if (source.minMass != undefined) {
            minMass = Number(source.minMass);
            loadedCount++;
        }
        
        // 停止条件参数
        if (source.stopThresholdBase != undefined) {
            stopThresholdBase = Number(source.stopThresholdBase);
            loadedCount++;
        }
        if (source.stopThresholdX != undefined) {
            stopThresholdX = Number(source.stopThresholdX);
            loadedCount++;
        }
        if (source.stopThresholdRotation != undefined) {
            stopThresholdRotation = Number(source.stopThresholdRotation);
            loadedCount++;
        }
        
        // 方向设置
        if (source.direction != undefined) {
            direction = Number(source.direction);
            loadedCount++;
        }
        
        // 调试选项
        if (source.enableDebug != undefined) {
            enableDebug = Boolean(source.enableDebug);
            loadedCount++;
        }
        
        // 输出加载结果
        if (enableDebug) {
            trace("[FragmentConfig] 从外部对象加载了 " + loadedCount + " 个配置参数");
        }
        
        return loadedCount > 0;
    }
    
    /**
     * 克隆当前配置对象
     * 
     * 创建一个当前配置的完整副本，包含所有参数的当前值。
     * 克隆的对象完全独立，修改其中一个不会影响另一个。
     * 
     * @return FragmentConfig 当前配置的完整副本
     * 
     * @example
     * var originalConfig:FragmentConfig = new FragmentConfig();
     * originalConfig.gravity = 2.0;
     * 
     * var clonedConfig:FragmentConfig = originalConfig.clone();
     * clonedConfig.gravity = 1.0; // 不会影响originalConfig
     */
    public function clone():FragmentConfig {
        var config:FragmentConfig = new FragmentConfig();
        
        // 复制所有物理参数
        config.gravity = this.gravity;
        config.bounce = this.bounce;
        config.friction = this.friction;
        config.fragmentCount = this.fragmentCount;
        config.groundY = this.groundY;
        
        // 复制所有运动参数
        config.baseVelocityX = this.baseVelocityX;
        config.velocityXRange = this.velocityXRange;
        config.velocityYMin = this.velocityYMin;
        config.velocityYMax = this.velocityYMax;
        config.rotationRange = this.rotationRange;
        
        // 复制所有碰撞参数
        config.collisionProbability = this.collisionProbability;
        config.energyLoss = this.energyLoss;
        
        // 复制所有质量计算参数
        config.massScale = this.massScale;
        config.minMass = this.minMass;
        
        // 复制所有停止条件参数
        config.stopThresholdBase = this.stopThresholdBase;
        config.stopThresholdX = this.stopThresholdX;
        config.stopThresholdRotation = this.stopThresholdRotation;
        
        // 复制方向设置
        config.direction = this.direction;
        
        // 复制调试选项
        config.enableDebug = this.enableDebug;
        
        return config;
    }
    
    /**
     * 验证配置参数的有效性
     * 
     * 检查所有参数是否在合理的范围内，并自动修正不合理的值。
     * 
     * @return Boolean 返回true表示所有参数都有效，false表示存在不合理的参数并已修正
     */
    public function validate():Boolean {
        var hasIssues:Boolean = false;
        
        // 验证数值范围
        if (gravity < 0) {
            gravity = 0;
            hasIssues = true;
            if (enableDebug) trace("[FragmentConfig] 修正：gravity不能为负数");
        }
        
        if (bounce < 0 || bounce > 1) {
            bounce = Math.max(0, Math.min(1, bounce));
            hasIssues = true;
            if (enableDebug) trace("[FragmentConfig] 修正：bounce应在0-1范围内");
        }
        
        if (friction < 0 || friction > 1) {
            friction = Math.max(0, Math.min(1, friction));
            hasIssues = true;
            if (enableDebug) trace("[FragmentConfig] 修正：friction应在0-1范围内");
        }
        
        if (fragmentCount < 1) {
            fragmentCount = 1;
            hasIssues = true;
            if (enableDebug) trace("[FragmentConfig] 修正：fragmentCount不能小于1");
        }
        
        if (collisionProbability < 0 || collisionProbability > 1) {
            collisionProbability = Math.max(0, Math.min(1, collisionProbability));
            hasIssues = true;
            if (enableDebug) trace("[FragmentConfig] 修正：collisionProbability应在0-1范围内");
        }
        
        if (energyLoss < 0 || energyLoss > 1) {
            energyLoss = Math.max(0, Math.min(1, energyLoss));
            hasIssues = true;
            if (enableDebug) trace("[FragmentConfig] 修正：energyLoss应在0-1范围内");
        }
        
        if (minMass <= 0) {
            minMass = 0.1;
            hasIssues = true;
            if (enableDebug) trace("[FragmentConfig] 修正：minMass必须大于0");
        }
        
        if (direction != -1 && direction != 1) {
            direction = (direction > 0) ? 1 : -1;
            hasIssues = true;
            if (enableDebug) trace("[FragmentConfig] 修正：direction只能是-1或1");
        }
        
        return !hasIssues;
    }
    
    /**
     * 输出配置摘要信息
     * 
     * 在控制台输出当前配置的主要参数，便于调试和确认。
     */
    public function printSummary():Void {
        trace("[FragmentConfig] 配置摘要：");
        trace("  物理: gravity=" + gravity + ", bounce=" + bounce + ", friction=" + friction);
        trace("  碎片: count=" + fragmentCount + ", direction=" + direction);
        trace("  速度: baseX=" + baseVelocityX + ", rangeX=" + velocityXRange + 
              ", Y=(" + velocityYMin + "-" + velocityYMax + ")");
        trace("  碰撞: probability=" + collisionProbability + ", energyLoss=" + energyLoss);
        trace("  调试: " + (enableDebug ? "启用" : "禁用"));
    }
}