import org.flashNight.arki.spatial.animation.FragmentConfig;

/**
 * 碎片动画预设配置库
 * 
 * 此类提供了一系列预定义的动画配置，适用于不同类型的破碎效果。
 * 每个预设都经过精心调试，可以直接使用或作为自定义配置的起点。
 * 
 * 预设分类：
 * 1. 材质类型：木制、金属、玻璃、石头、纸张等
 * 2. 破碎强度：轻微、普通、强烈、爆炸等
 * 3. 环境条件：无重力、水下、强风等
 * 4. 特殊效果：慢动作、快进、弹跳等
 * 
 * 使用建议：
 * - 选择最接近需求的预设作为基础
 * - 根据具体场景微调参数
 * - 结合loadFromObject方法应用外部配置
 * - 为项目创建自定义预设并添加到此类
 * 
 * 设计原则：
 * - 真实感：基于现实物理特性
 * - 视觉效果：注重观赏性和流畅度
 * - 性能优化：平衡效果与计算开销
 * - 可扩展性：便于添加新预设
 * 
 */
class org.flashNight.arki.spatial.animation.FragmentPresets {
    
    /**
     * 获取默认配置
     * 
     * 标准的中等强度破碎效果，适用于大多数场景。
     * 平衡了真实感和性能，是一个安全的选择。
     * 
     * 特点：
     * - 中等重力和反弹
     * - 适中的速度分布
     * - 50%的碰撞概率
     * - 向左的主要方向
     * 
     * @return FragmentConfig 默认配置对象
     */
    public static function getDefault():FragmentConfig {
        return new FragmentConfig();
    }
    
    /**
     * 获取木制破碎配置
     * 
     * 模拟木制物品（木箱、木板、树枝等）破碎的效果。
     * 木制品通常重量适中，有一定弹性但不会反弹太多。
     * 
     * 物理特性：
     * - 中等重力：木制品密度适中
     * - 低反弹：木制品吸收冲击能量
     * - 高摩擦：木制品表面粗糙
     * - 中等速度：破碎时不会过于激烈
     * 
     * 适用场景：
     * - 资源箱破碎
     * - 木制建筑破坏
     * - 树木倒塌效果
     * - 家具破损
     * 
     * @return FragmentConfig 木制破碎配置
     */
    public static function getWoodenBreak():FragmentConfig {
        var config:FragmentConfig = new FragmentConfig();
        
        // 物理参数：木制品特性
        config.gravity = 1.2;           // 中等重力
        config.bounce = 0.25;           // 低反弹，木制品吸收能量
        config.friction = 0.9;          // 高摩擦，表面粗糙
        config.groundY = 30;
        
        // 运动参数：中等活跃度
        config.baseVelocityX = 6;       // 中等水平速度
        config.velocityXRange = 4;      // 适度随机变化
        config.velocityYMin = 3;        // 较温和的向上速度
        config.velocityYMax = 8;
        config.rotationRange = 4;       // 中等旋转
        
        // 碰撞参数：部分碰撞
        config.collisionProbability = 0.4;  // 木片不会全部碰撞
        config.energyLoss = 0.6;        // 较大能量损失，快速稳定
        
        // 质量参数：中等密度
        config.massScale = 120;         // 木制品中等密度
        config.minMass = 0.6;
        
        // 其他参数
        config.direction = -1;          // 向左破碎
        
        return config;
    }
    
    /**
     * 获取金属破碎配置
     * 
     * 模拟金属物品（铁箱、装甲、机械部件等）破碎的效果。
     * 金属具有高密度、强反弹性和低摩擦的特点。
     * 
     * 物理特性：
     * - 高重力：金属密度大，下落快
     * - 高反弹：金属硬度高，弹性好
     * - 低摩擦：金属表面光滑
     * - 高速度：破碎时碎片飞散迅速
     * 
     * 适用场景：
     * - 机甲破损
     * - 金属容器爆炸
     * - 工业设备损坏
     * - 武器破碎
     * 
     * @return FragmentConfig 金属破碎配置
     */
    public static function getMetalBreak():FragmentConfig {
        var config:FragmentConfig = new FragmentConfig();
        
        // 物理参数：金属特性
        config.gravity = 1.8;           // 高重力，金属密度大
        config.bounce = 0.6;            // 高反弹，硬质材料
        config.friction = 0.7;          // 低摩擦，表面光滑
        config.groundY = 30;
        
        // 运动参数：高速破碎
        config.baseVelocityX = 12;      // 高水平速度
        config.velocityXRange = 8;      // 大范围随机变化
        config.velocityYMin = 6;        // 较强的向上抛射
        config.velocityYMax = 15;
        config.rotationRange = 8;       // 快速旋转
        
        // 碰撞参数：频繁碰撞
        config.collisionProbability = 0.7;  // 金属碎片经常碰撞
        config.energyLoss = 0.4;        // 较小能量损失，保持活跃
        
        // 质量参数：高密度
        config.massScale = 60;          // 金属高密度
        config.minMass = 1.0;
        
        // 其他参数
        config.direction = -1;
        
        return config;
    }
    
    /**
     * 获取玻璃破碎配置
     * 
     * 模拟玻璃物品（窗户、瓶子、水晶等）破碎的效果。
     * 玻璃轻薄脆弱，破碎时产生大量轻快的小碎片。
     * 
     * 物理特性：
     * - 低重力：玻璃碎片相对较轻
     * - 中等反弹：玻璃有一定硬度但易碎
     * - 中等摩擦：玻璃表面平滑但边缘粗糙
     * - 高速度：玻璃破碎时碎片飞溅迅速
     * 
     * 视觉特效：
     * - 大量小碎片：fragmentCount设置较高
     * - 快速旋转：表现玻璃碎片的轻盈感
     * - 活跃碰撞：模拟碎片间的频繁接触
     * 
     * 适用场景：
     * - 窗户破碎
     * - 瓶子摔碎
     * - 水晶破损
     * - 镜子碎裂
     * 
     * @return FragmentConfig 玻璃破碎配置
     */
    public static function getGlassBreak():FragmentConfig {
        var config:FragmentConfig = new FragmentConfig();
        
        // 物理参数：玻璃特性
        config.gravity = 0.8;           // 低重力，轻质材料
        config.bounce = 0.4;            // 中等反弹，硬但脆
        config.friction = 0.75;         // 中等摩擦
        config.groundY = 30;
        config.fragmentCount = 15;      // 更多碎片数量
        
        // 运动参数：快速轻盈
        config.baseVelocityX = 10;      // 高水平速度
        config.velocityXRange = 10;     // 很大的随机变化
        config.velocityYMin = 5;        // 中等向上速度
        config.velocityYMax = 12;
        config.rotationRange = 12;      // 快速随机旋转
        
        // 碰撞参数：活跃碰撞
        config.collisionProbability = 0.8;  // 高碰撞概率
        config.energyLoss = 0.5;        // 中等能量损失
        
        // 质量参数：轻质材料
        config.massScale = 200;         // 玻璃轻质，大缩放因子
        config.minMass = 0.3;           // 很小的最小质量
        
        // 其他参数
        config.direction = -1;
        
        return config;
    }
    
    /**
     * 获取石头破碎配置
     * 
     * 模拟石制物品（岩石、混凝土、砖块等）破碎的效果。
     * 石头重量大、硬度高，破碎时产生大块重质碎片。
     * 
     * 物理特性：
     * - 超高重力：石头密度极大
     * - 低反弹：石头破碎后失去弹性
     * - 超高摩擦：石头表面极其粗糙
     * - 中低速度：重量限制了飞散速度
     * 
     * 适用场景：
     * - 岩石爆破
     * - 建筑倒塌
     * - 地面破裂
     * - 山体滑坡
     * 
     * @return FragmentConfig 石头破碎配置
     */
    public static function getStoneBreak():FragmentConfig {
        var config:FragmentConfig = new FragmentConfig();
        
        // 物理参数：石头特性
        config.gravity = 2.2;           // 超高重力，极重材料
        config.bounce = 0.15;           // 极低反弹，几乎不弹
        config.friction = 0.95;         // 极高摩擦，快速停止
        config.groundY = 30;
        
        // 运动参数：重而缓慢
        config.baseVelocityX = 4;       // 低水平速度
        config.velocityXRange = 3;      // 小范围变化
        config.velocityYMin = 2;        // 低向上速度
        config.velocityYMax = 6;
        config.rotationRange = 2;       // 慢速旋转
        
        // 碰撞参数：稀少碰撞
        config.collisionProbability = 0.3;  // 重物不易改变方向
        config.energyLoss = 0.8;        // 大量能量损失
        
        // 质量参数：超高密度
        config.massScale = 40;          // 石头超高密度
        config.minMass = 1.5;           // 较大的最小质量
        
        // 其他参数
        config.direction = -1;
        
        return config;
    }
    
    /**
     * 获取纸张破碎配置
     * 
     * 模拟纸制物品（纸张、卡片、薄片等）飘散的效果。
     * 纸张极轻，在空中飘浮时间长，受空气阻力影响明显。
     * 
     * 物理特性：
     * - 极低重力：纸张重量微不足道
     * - 几乎不反弹：纸张软质材料
     * - 高摩擦：纸张表面粗糙且受空气阻力大
     * - 飘浮效果：长时间在空中飘荡
     * 
     * 视觉特效：
     * - 慢速下落：重力极小
     * - 大量旋转：模拟纸片翻飞
     * - 轻柔运动：速度和力度都很小
     * 
     * 适用场景：
     * - 纸张撕碎
     * - 树叶飘落
     * - 布料碎裂
     * - 羽毛飞舞
     * 
     * @return FragmentConfig 纸张破碎配置
     */
    public static function getPaperBreak():FragmentConfig {
        var config:FragmentConfig = new FragmentConfig();
        
        // 物理参数：纸张特性
        config.gravity = 0.3;           // 极低重力，几乎飘浮
        config.bounce = 0.05;           // 几乎不反弹
        config.friction = 0.95;         // 极高空气阻力
        config.groundY = 30;
        config.fragmentCount = 12;      // 适量碎片
        
        // 运动参数：轻柔飘逸
        config.baseVelocityX = 3;       // 低水平速度
        config.velocityXRange = 4;      // 中等随机变化
        config.velocityYMin = 1;        // 极低向上速度
        config.velocityYMax = 4;
        config.rotationRange = 15;      // 大幅旋转，模拟翻飞
        
        // 碰撞参数：几乎不碰撞
        config.collisionProbability = 0.1;  // 纸片很少碰撞
        config.energyLoss = 0.9;        // 极大能量损失
        
        // 质量参数：极轻材料
        config.massScale = 500;         // 纸张极轻
        config.minMass = 0.1;           // 极小质量
        
        // 停止条件：更宽松，允许长时间飘动
        config.stopThresholdBase = 0.2;
        config.stopThresholdX = 0.1;
        
        // 其他参数
        config.direction = -1;
        
        return config;
    }
    
    /**
     * 获取爆炸破碎配置
     * 
     * 模拟爆炸性破碎效果（炸弹、爆炸箱、能量爆发等）。
     * 特点是初始速度极高，碎片向四面八方飞散。
     * 
     * 视觉特效：
     * - 极高初始速度：模拟爆炸冲击
     * - 强烈旋转：表现爆炸的混乱性
     * - 频繁碰撞：高能量环境下的激烈互动
     * - 快速稳定：爆炸后迅速平静
     * 
     * 适用场景：
     * - 炸弹爆炸
     * - 能量释放
     * - 魔法爆发
     * - 超级破坏
     * 
     * @return FragmentConfig 爆炸破碎配置
     */
    public static function getExplosiveBreak():FragmentConfig {
        var config:FragmentConfig = new FragmentConfig();
        
        // 物理参数：爆炸环境
        config.gravity = 1.6;           // 较高重力，快速下落
        config.bounce = 0.5;            // 中等反弹
        config.friction = 0.8;          // 中等摩擦
        config.groundY = 30;
        config.fragmentCount = 15;      // 更多碎片
        
        // 运动参数：爆炸性
        config.baseVelocityX = 18;      // 极高水平速度
        config.velocityXRange = 12;     // 巨大随机变化
        config.velocityYMin = 10;       // 强力向上抛射
        config.velocityYMax = 20;
        config.rotationRange = 20;      // 极快旋转
        
        // 碰撞参数：激烈碰撞
        config.collisionProbability = 0.9;  // 几乎所有碎片都碰撞
        config.energyLoss = 0.4;        // 较小能量损失，保持激烈
        
        // 质量参数：中等
        config.massScale = 100;
        config.minMass = 0.5;
        
        // 其他参数
        config.direction = -1;
        
        return config;
    }
    
    /**
     * 获取无重力破碎配置
     * 
     * 模拟零重力环境下的破碎效果（太空、魔法环境等）。
     * 碎片在空中漂浮，只受到初始冲击和相互碰撞的影响。
     * 
     * 特殊效果：
     * - 无重力：碎片不会下落
     * - 持续运动：没有重力拖拽，运动持续更久
     * - 三维感：碎片在空中自由旋转
     * - 优雅飘逸：缓慢而连续的运动
     * 
     * 适用场景：
     * - 太空场景
     * - 魔法效果
     * - 梦境场景
     * - 特殊环境
     * 
     * @return FragmentConfig 无重力破碎配置
     */
    public static function getZeroGravityBreak():FragmentConfig {
        var config:FragmentConfig = new FragmentConfig();
        
        // 物理参数：无重力环境
        config.gravity = 0;             // 无重力！
        config.bounce = 0.8;            // 高反弹，能量保持
        config.friction = 0.98;         // 极低摩擦，持续运动
        config.groundY = 1000;          // 地面设在很远处
        
        // 运动参数：飘逸运动
        config.baseVelocityX = 8;       // 中等初始速度
        config.velocityXRange = 6;      // 适度变化
        config.velocityYMin = 4;        // 中等向上速度
        config.velocityYMax = 10;
        config.rotationRange = 6;       // 优雅旋转
        
        // 碰撞参数：活跃互动
        config.collisionProbability = 0.6;  // 较高碰撞概率
        config.energyLoss = 0.2;        // 很小能量损失，长期运动
        
        // 质量参数：
        config.massScale = 100;
        config.minMass = 0.5;
        
        // 停止条件：更严格，因为没有重力帮助停止
        config.stopThresholdBase = 0.1;
        config.stopThresholdX = 0.05;
        
        // 其他参数
        config.direction = -1;
        
        return config;
    }
    
    /**
     * 获取慢动作破碎配置
     * 
     * 模拟电影级慢动作破碎效果，适用于特殊的视觉表现。
     * 所有动作都被放慢，让观众能够清楚看到每个细节。
     * 
     * 视觉特效：
     * - 缓慢运动：所有速度都被大幅降低
     * - 优雅旋转：慢速旋转增强观赏性
     * - 细致碰撞：碰撞过程清晰可见
     * - 戏剧效果：适合关键时刻的表现
     * 
     * 适用场景：
     * - 关键道具破碎
     * - 戏剧性时刻
     * - 教学演示
     * - 艺术表现
     * 
     * @return FragmentConfig 慢动作破碎配置
     */
    public static function getSlowMotionBreak():FragmentConfig {
        var config:FragmentConfig = new FragmentConfig();
        
        // 物理参数：慢动作调整
        config.gravity = 0.5;           // 降低重力
        config.bounce = 0.4;            // 中等反弹
        config.friction = 0.92;         // 较高摩擦，慢速停止
        config.groundY = 30;
        
        // 运动参数：全面放慢
        config.baseVelocityX = 3;       // 大幅降低水平速度
        config.velocityXRange = 2;      // 小范围变化
        config.velocityYMin = 1;        // 慢速向上
        config.velocityYMax = 4;
        config.rotationRange = 2;       // 慢速旋转
        
        // 碰撞参数：清晰可见
        config.collisionProbability = 0.7;  // 较高碰撞概率
        config.energyLoss = 0.6;        // 中等能量损失
        
        // 质量参数：
        config.massScale = 100;
        config.minMass = 0.5;
        
        // 停止条件：更宽松，允许更长展示时间
        config.stopThresholdBase = 0.2;
        config.stopThresholdX = 0.1;
        config.stopThresholdRotation = 0.1;
        
        // 其他参数
        config.direction = -1;
        
        return config;
    }
    
    /**
     * 根据预设名称获取配置
     * 
     * 提供字符串接口来获取预设配置，便于外部系统调用。
     * 支持的预设名称（不区分大小写）：
     * - "default", "normal" - 默认配置
     * - "wood", "wooden" - 木制破碎
     * - "metal", "metallic" - 金属破碎
     * - "glass", "crystal" - 玻璃破碎
     * - "stone", "rock" - 石头破碎
     * - "paper", "light" - 纸张破碎
     * - "explosion", "explosive" - 爆炸破碎
     * - "zerogravity", "space" - 无重力破碎
     * - "slowmotion", "slow" - 慢动作破碎
     * 
     * @param presetName:String 预设名称（不区分大小写）
     * @return FragmentConfig 对应的配置对象，如果名称无效则返回默认配置
     * 
     * @example
     * var config:FragmentConfig = FragmentPresets.getPreset("glass");
     * var animId:Number = FragmentAnimator.startAnimation(container, "碎片", config);
     */
    public static function getPreset(presetName:String):FragmentConfig {
        if (!presetName) {
            return getDefault();
        }
        
        // 转换为小写并移除空格
        var name:String = presetName.toLowerCase().split(" ").join("");
        
        switch (name) {
            case "default":
            case "normal":
                return getDefault();
                
            case "wood":
            case "wooden":
                return getWoodenBreak();
                
            case "metal":
            case "metallic":
                return getMetalBreak();
                
            case "glass":
            case "crystal":
                return getGlassBreak();
                
            case "stone":
            case "rock":
                return getStoneBreak();
                
            case "paper":
            case "light":
                return getPaperBreak();
                
            case "explosion":
            case "explosive":
                return getExplosiveBreak();
                
            case "zerogravity":
            case "space":
                return getZeroGravityBreak();
                
            case "slowmotion":
            case "slow":
                return getSlowMotionBreak();
                
            default:
                trace("[FragmentPresets] 警告：未知的预设名称 '" + presetName + "'，使用默认配置");
                return getDefault();
        }
    }
    
    /**
     * 获取所有可用的预设名称列表
     * 
     * @return Array 包含所有预设名称的数组
     */
    public static function getAvailablePresets():Array {
        return [
            "default", "wood", "metal", "glass", "stone", 
            "paper", "explosion", "zerogravity", "slowmotion"
        ];
    }
    
    /**
     * 创建混合配置
     * 
     * 将两个配置按指定比例混合，创建新的配置。
     * 可用于创建介于两种预设之间的效果。
     * 
     * @param config1:FragmentConfig 第一个配置
     * @param config2:FragmentConfig 第二个配置
     * @param ratio:Number 混合比例（0.0-1.0），0表示完全使用config1，1表示完全使用config2
     * @return FragmentConfig 混合后的新配置
     * 
     * @example
     * var wood:FragmentConfig = FragmentPresets.getWoodenBreak();
     * var metal:FragmentConfig = FragmentPresets.getMetalBreak();
     * var hybrid:FragmentConfig = FragmentPresets.blendConfigs(wood, metal, 0.3);
     * // 得到70%木制+30%金属特性的配置
     */
    public static function blendConfigs(config1:FragmentConfig, config2:FragmentConfig, ratio:Number):FragmentConfig {
        if (!config1 || !config2) {
            return config1 || config2 || getDefault();
        }
        
        // 限制比例范围
        ratio = Math.max(0, Math.min(1, ratio));
        var invRatio:Number = 1 - ratio;
        
        var blended:FragmentConfig = new FragmentConfig();
        
        // 混合所有数值参数
        blended.gravity = config1.gravity * invRatio + config2.gravity * ratio;
        blended.bounce = config1.bounce * invRatio + config2.bounce * ratio;
        blended.friction = config1.friction * invRatio + config2.friction * ratio;
        blended.fragmentCount = Math.round(config1.fragmentCount * invRatio + config2.fragmentCount * ratio);
        blended.groundY = config1.groundY * invRatio + config2.groundY * ratio;
        
        blended.baseVelocityX = config1.baseVelocityX * invRatio + config2.baseVelocityX * ratio;
        blended.velocityXRange = config1.velocityXRange * invRatio + config2.velocityXRange * ratio;
        blended.velocityYMin = config1.velocityYMin * invRatio + config2.velocityYMin * ratio;
        blended.velocityYMax = config1.velocityYMax * invRatio + config2.velocityYMax * ratio;
        blended.rotationRange = config1.rotationRange * invRatio + config2.rotationRange * ratio;
        
        blended.collisionProbability = config1.collisionProbability * invRatio + config2.collisionProbability * ratio;
        blended.energyLoss = config1.energyLoss * invRatio + config2.energyLoss * ratio;
        
        blended.massScale = config1.massScale * invRatio + config2.massScale * ratio;
        blended.minMass = config1.minMass * invRatio + config2.minMass * ratio;
        
        blended.stopThresholdBase = config1.stopThresholdBase * invRatio + config2.stopThresholdBase * ratio;
        blended.stopThresholdX = config1.stopThresholdX * invRatio + config2.stopThresholdX * ratio;
        blended.stopThresholdRotation = config1.stopThresholdRotation * invRatio + config2.stopThresholdRotation * ratio;
        
        // 非数值参数使用第一个配置的值
        blended.direction = config1.direction;
        blended.enableDebug = config1.enableDebug;
        
        return blended;
    }
}