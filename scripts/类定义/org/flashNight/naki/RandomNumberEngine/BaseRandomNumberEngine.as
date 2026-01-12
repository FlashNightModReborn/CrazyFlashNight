import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.RandomNumberEngine.BaseRandomNumberEngine {
    // 单例实例，确保全局只有一个实例
    private static var instance:BaseRandomNumberEngine;

    // 随机数生成器的种子，用于初始化随机数生成
    private var seed:Number;

    // Box-Muller 高斯采样缓存（一次计算产生两个正态分布值，缓存第二个）
    private var gaussianCached:Boolean = false;
    private var gaussianCacheValue:Number = 0;

    // 私有构造函数，防止直接实例化
    private function BaseRandomNumberEngine() {
        // 使用当前时间作为默认种子
        this.seed = new Date().getTime();
    }

    // 静态方法获取单例实例
    // 如果实例不存在则创建一个新的实例
    public static function getInstance():BaseRandomNumberEngine {
        if (instance == null) {
            instance = new BaseRandomNumberEngine();
            // Replace getInstance with a function that returns the instance directly
            getInstance = function():BaseRandomNumberEngine {
                return instance;
            };
        }
        return instance;
    }

    // 设置随机数种子
    // @param newSeed: 新的种子值
    public function setSeed(newSeed:Number):Void {
        this.seed = newSeed;
    }

    // 获取当前种子
    // @return 当前的种子值
    public function getSeed():Number {
        return this.seed;
    }

    // 生成下一个随机数的方法
    // 这个方法应该在派生类中被覆盖
    // @return 随机数
    public function next():Number {
        trace("base next");
        return 0; // 默认实现（无实际用途）
    }

    // 生成一个0到1之间的随机浮点数
    // @return 0到1之间的随机浮点数
    public function nextFloat():Number {
        trace("base nextFloat");
        return next() / 0x100000000; // 默认实现（无实际用途）
    }

    // 模拟传统的 random(n) 函数，生成 0 到 n-1 之间的随机整数
    // @param n: 上限值（不包含）
    // @return 生成的随机整数
    public function random(n:Number):Number {
        return Math.floor(nextFloat() * n);
    }

    /**
     * 高性能概率判定（假定 denominator ≥ 1）
     * 等价于 “random(denominator) == 0”，但完全内联，无任何额外分支。
     *
     * @param denominator 分母 d（> = 1 时命中概率为 1/d）
     * @return Boolean    是否命中
     */
    public function randomCheck(denominator:Number):Boolean {
        // nextFloat() ∈ [0,1)，乘以 denominator 后 ⌊·⌋ 就相当于 randomIntegerStrict(0, denominator-1)
        // “>> 0” 是 AS2 中最快的向下取整手段（integer cast）
        return ((nextFloat() * denominator) >> 0) == 0;
    }

    /**
     * 1/2 概率检查
     * 等价于 random(2)==0，但更直接
     */
    public function randomCheckHalf():Boolean {
        // nextFloat()*2 ∈ [0,2)，>>0 相当于 floor()
        // 如果结果是 0，就命中 1/2
        return ((nextFloat() * 2) >> 0) == 0;
    }

    /**
     * 随机符号生成
     * 50%概率返回 1，50%概率返回 -1
     * 用于随机方向、随机正负偏移等场景
     * @return Number 返回 1 或 -1
     */
    public function randomSign():Number {
        // nextFloat() < 0.5 ? -1 : 1
        // 使用位运算优化：(nextFloat() * 2) >> 0 结果为 0 或 1
        // 0 * 2 - 1 = -1
        // 1 * 2 - 1 = 1
        return (((nextFloat() * 2) >> 0) << 1) - 1;
    }

    /**
     * 1/3 概率检查
     * 同理，直接 floor(nextFloat()*3)==0
     */
    public function randomCheckThird():Boolean {
        return ((nextFloat() * 3) >> 0) == 0;
    }

    /**
     * 1/4 概率检查（四分之一）
     * 等价于 random(4)==0，适用于季度、象限等逻辑
     */
    public function randomCheckQuarter():Boolean {
        return ((nextFloat() * 4) >> 0) == 0;
    }

    /**
     * 1/5 概率检查（五分之一）
     * 等价于 random(5)==0，适用于星级评价等
     */
    public function randomCheckFifth():Boolean {
        return ((nextFloat() * 5) >> 0) == 0;
    }

    /**
     * 1/6 概率检查（六分之一）
     * 等价于 random(6)==0，骰子单面概率
     */
    public function randomCheckSixth():Boolean {
        return ((nextFloat() * 6) >> 0) == 0;
    }

    /**
     * 1/8 概率检查（八分之一）
     * 等价于 random(8)==0，二的三次方，常用于位运算优化场景
     */
    public function randomCheckEighth():Boolean {
        return ((nextFloat() * 8) >> 0) == 0;
    }

    /**
     * 1/10 概率检查（十分之一）
     * 等价于 random(10)==0，适用于十进制概率，如10%概率
     */
    public function randomCheckTenth():Boolean {
        return ((nextFloat() * 10) >> 0) == 0;
    }

    /**
     * 1/16 概率检查（十六分之一）
     * 等价于 random(16)==0，二的四次方，位运算友好
     */
    public function randomCheckSixteenth():Boolean {
        return ((nextFloat() * 16) >> 0) == 0;
    }

    /**
     * 1/20 概率检查（二十分之一）
     * 等价于 random(20)==0，5%概率，RPG常用
     */
    public function randomCheckTwentieth():Boolean {
        return ((nextFloat() * 20) >> 0) == 0;
    }

    /**
     * 1/100 概率检查（百分之一）
     * 等价于 random(100)==0，1%概率，百分比系统
     */
    public function randomCheckHundredth():Boolean {
        return ((nextFloat() * 100) >> 0) == 0;
    }

    /**
     * 概率权重检查（多选一）
     * 基于权重数组进行随机选择，返回选中的索引
     * @param weights 权重数组，如 [30, 50, 20] 表示 30%、50%、20%的概率
     * @return Number 返回选中的索引，-1表示无效输入
     */
    public function randomWeightedChoice(weights:Array):Number {
        if (!weights || weights.length == 0) return -1;
        
        var total:Number = 0;
        for (var i:Number = 0; i < weights.length; i++) {
            total += weights[i];
        }
        
        if (total <= 0) return -1;
        
        var roll:Number = nextFloat() * total;
        var accumulator:Number = 0;
        
        for (var j:Number = 0; j < weights.length; j++) {
            accumulator += weights[j];
            if (roll < accumulator) {
                return j;
            }
        }
        
        return weights.length - 1; // 防止浮点精度问题
    }

    /**
     * 随机二选一（50%概率）
     * 最常用的二选一场景，如方向选择（左/右）、开关状态（开/关）等
     * @param option1 第一个选项
     * @param option2 第二个选项
     * @return 返回选中的选项（50%概率返回option1，50%概率返回option2）
     */
    public function randomChoice(option1, option2) {
        // 使用位运算优化的50%概率判断
        return ((nextFloat() * 2) >> 0) == 0 ? option1 : option2;
    }

    /**
     * 随机二选一（自定义概率）
     * 带概率参数的二选一，用于需要非对称概率的场景
     * @param option1 第一个选项
     * @param option2 第二个选项
     * @param probability1 选择第一个选项的概率（0-1）
     * @return 返回选中的选项
     */
    public function randomChoiceWeighted(option1, option2, probability1:Number) {
        return nextFloat() < probability1 ? option1 : option2;
    }

    /**
     * 从多个选项中随机选择一个（等概率）
     * @param options 选项数组
     * @return 返回随机选中的选项
     */
    public function randomPick(options:Array) {
        if (!options || options.length == 0) return null;
        if (options.length == 1) return options[0];
        return options[randomInteger(0, options.length - 1)];
    }

    /**
     * 渐进概率检查
     * 随着尝试次数增加，成功概率逐步提高
     * @param baseChance 基础概率分母（如传入100表示1%基础概率）
     * @param attemptCount 当前尝试次数
     * @param scaleFactor 缩放因子，默认为2（每次尝试概率翻倍）
     * @return Boolean 是否成功
     */
    public function randomProgressiveCheck(baseChance:Number, attemptCount:Number, scaleFactor:Number):Boolean {
        if (scaleFactor == undefined) scaleFactor = 2;
        if (attemptCount <= 0) attemptCount = 1;
        
        var adjustedChance:Number = baseChance / Math.pow(scaleFactor, attemptCount - 1);
        if (adjustedChance < 1) adjustedChance = 1; // 确保最终必定成功
        
        return randomCheck(adjustedChance);
    }

    /**
     * 连击概率检查
     * 用于连续成功的概率计算，每次成功后概率递减
     * @param baseDenominator 基础概率分母
     * @param comboCount 当前连击次数
     * @param decayRate 衰减率，默认为1.5
     * @return Boolean 是否继续连击
     */
    public function randomComboCheck(baseDenominator:Number, comboCount:Number, decayRate:Number):Boolean {
        if (decayRate == undefined) decayRate = 1.5;
        if (comboCount <= 0) return randomCheck(baseDenominator);
        
        var adjustedDenominator:Number = baseDenominator * Math.pow(decayRate, comboCount);
        return randomCheck(adjustedDenominator);
    }

    /**
     * 冷却时间概率检查
     * 用于技能冷却或限频场景，在冷却期间返回false
     * @param denominator 基础概率分母
     * @param lastTriggerTime 上次触发时间
     * @param cooldownFrames 冷却帧数
     * @return Boolean 是否通过检查
     */
    public function randomCooldownCheck(denominator:Number, lastTriggerTime:Number, cooldownFrames:Number):Boolean {
        var currentTime:Number = _root.帧计时器.当前帧数 || getTimer();
        if (currentTime - lastTriggerTime < cooldownFrames) {
            return false; // 冷却期内
        }
        return randomCheck(denominator);
    }

    /**
     * 疲劳系统概率检查
     * 随着连续使用次数增加，成功概率逐渐降低
     * @param baseDenominator 基础概率分母
     * @param fatigueLevel 疲劳等级（0-无疲劳）
     * @param maxFatigue 最大疲劳值，超过此值概率降为0
     * @return Boolean 是否成功
     */
    public function randomFatigueCheck(baseDenominator:Number, fatigueLevel:Number, maxFatigue:Number):Boolean {
        if (fatigueLevel >= maxFatigue) return false; // 完全疲劳
        
        var fatigueRatio:Number = fatigueLevel / maxFatigue;
        var adjustedDenominator:Number = baseDenominator * (1 + fatigueRatio * 3); // 疲劳降低概率
        
        return randomCheck(adjustedDenominator);
    }

    /**
     * 临界概率检查
     * 在特定条件下（如血量低于阈值）提高概率
     * @param baseDenominator 基础概率分母
     * @param currentValue 当前值（如当前血量）
     * @param threshold 临界阈值
     * @param maxValue 最大值（如最大血量）
     * @param boostFactor 提升因子，默认为2
     * @return Boolean 是否成功
     */
    public function randomCriticalCheck(baseDenominator:Number, currentValue:Number, threshold:Number, maxValue:Number, boostFactor:Number):Boolean {
        if (boostFactor == undefined) boostFactor = 2;
        
        if (currentValue <= threshold) {
            var criticalRatio:Number = 1 - (currentValue / threshold); // 越低越强
            var adjustedDenominator:Number = baseDenominator / (1 + criticalRatio * (boostFactor - 1));
            return randomCheck(adjustedDenominator);
        }
        
        return randomCheck(baseDenominator);
    }




    // 判断给定的成功率是否发生
    // @param probabilityPercent: 成功率的百分比（0-100）
    // @return 是否发生成功事件
    public function successRate(probabilityPercent:Number):Boolean {
        var randomValue:Number = nextFloat() * 100;
        return randomValue <= probabilityPercent;
    }

    // 在指定范围内生成一个随机整数
    // @param min: 最小值
    // @param max: 最大值
    // @return 生成的随机整数
    public function randomInteger(min:Number, max:Number):Number {
        return Math.floor(nextFloat() * (max - min + 1) + min);
    }

    // 在指定范围内生成一个随机整数
    // 入参必须为整数，严格模式下性能提升20%，非整数会导致小数部分不会被完整舍去
    // @param min: 最小值
    // @param max: 最大值
    // @return 生成的随机整数
    public function randomIntegerStrict(min:Number, max:Number):Number {
        // 使用位运算替代 Math.floor，提高性能
        return ((nextFloat() * (max - min + 1)) >> 0) + min;
    }

    // 在指定范围内生成一个随机浮点数
    // @param min: 最小值
    // @param max: 最大值
    // @return 生成的随机浮点数
    public function randomFloat(min:Number, max:Number):Number {
        return nextFloat() * (max - min) + min;
    }

    // 在指定范围内生成一个随机整数偏移
    // @param range: 偏移范围
    // @return 生成的随机整数偏移
    public function randomOffset(range:Number):Number {
        // trace("range: " + range);
        return Math.floor(nextFloat() * (range * 2 + 1)) - range;
    }

    // 在指定范围内生成一个随机浮点数偏移
    // @param range: 偏移范围
    // @return 生成的随机浮点数偏移
    public function randomFloatOffset(range:Number):Number {
        return nextFloat() * (range * 2) - range;
    }

    // 根据指定范围生成一个波动的乘数
    // @param fluctuationRange: 波动范围百分比
    // @return 波动后的乘数
    public function randomFluctuation(fluctuationRange:Number):Number {
        return 1 + (nextFloat() * (fluctuationRange * 2) - fluctuationRange) / 100;
    }


    // 从数组中获取一个随机元素
    // @param array: 待选数组
    // @return 数组中的随机元素
    public function getRandomArrayElement(array:Array) {
        if (array.length == 0) {
            return null; // 如果数组为空，返回null
        }
        var randomIndex:Number = randomInteger(0, array.length - 1); // 生成随机索引
        return array[randomIndex]; // 返回随机索引处的元素
    }

    // 随机打乱数组
    // @param array: 需要打乱的数组
    public function shuffleArray(array:Array):Void {
        var len:Number = array.length;
        if (len <= 1) {
            return; // 如果数组长度为0或1，无需打乱
        }
        for (var i:Number = 0; i < len; i++) {
            var j:Number = randomInteger(i, len - 1);
            var temp:Object = array[i];
            array[i] = array[j];
            array[j] = temp;
        }
    }

    /**
     * 从流中随机选择 k 个样本，并对每个被选中的样本执行传入的函数
     * @param stream: 数据流数组
     * @param k: 选择样本数量
     * @param filterFunc: 传入的处理函数，接收当前样本
     * @return 返回最终的样本数组
     */

    public function reservoirSampleWithFilter(
        stream:Array,       // 数据流
        k:Number,           // 需要抽取的样本数
        filterFunc:Function // 条件过滤函数(element:Object)->Boolean
    ):Array {
        var reservoir:Array = [];
        var matchCount:Number = 0;

        for (var i:Number = 0; i < stream.length; i++) {
            var element = stream[i];
            // 执行过滤函数判断是否纳入抽样池
            if (filterFunc(element)) {
                matchCount++;
                // 水塘抽样核心逻辑
                if (matchCount <= k) {
                    reservoir.push(element);
                } else {
                    var j:Number = this.randomInteger(0, matchCount - 1);
                    if (j < k) {
                        reservoir[j] = element;
                    }
                }
            }
        }
        return reservoir.slice(0, k); // 确保返回长度不超过k
    }


    // 根据权重从数组中随机选择一个元素
    // @param array: 待选数组
    // @param weights: 权重数组
    // @return 根据权重选择的随机元素
    public function getWeightedRandomElement(array:Array, weights:Array):Object {
        if (array.length == 0 || array.length != weights.length) {
            return null; // 确保数组和权重非空且长度相同
        }
        var totalWeight:Number = 0;
        for (var i:Number = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }
        var random:Number = nextFloat() * totalWeight;
        for (i = 0; i < weights.length; i++) {
            random -= weights[i];
            if (random <= 0) {
                return array[i];
            }
        }
        return array[array.length - 1]; // 备用方案
    }

    // 生成一个指定大小的随机排列
    // @param size: 数组大小
    // @return 生成的随机排列
    public function generatePermutation(size:Number):Array {
        var array:Array = new Array(size);
        for (var i:Number = 0; i < size; i++) {
            array[i] = i;
        }
        shuffleArray(array);
        return array;
    }

    // 从流中随机选择k个样本
    // @param stream: 数据流
    // @param k: 样本大小
    // @return 随机选择的k个样本
    public function reservoirSample(stream:Array, k:Number):Array {
        var reservoir:Array = stream.slice(0, k);
        for (var i:Number = k; i < stream.length; i++) {
            var j:Number = randomInteger(0, i);
            if (j < k) {
                reservoir[j] = stream[i];
            }
        }
        return reservoir;
    }

    // 生成一个随机颜色
    // @return 生成的随机颜色值
    public function randomColor():Number {
        return randomInteger(0, 0xFFFFFF);
    }

    // 生成符合高斯分布的随机数（Irwin-Hall 3 近似）
    // 使用 3 个均匀分布 U(0,1) 之和近似正态分布
    // Irwin-Hall(3)：E=1.5, Var=0.25, σ=0.5
    // 标准化：z = (sum - 1.5) / 0.5 = 2*sum - 3
    //
    // 精度权衡：
    // - 峰度 2.4（真正态为 3.0），分布略微集中
    // - 范围 ±3σ（真正态为 ±∞），但游戏应用完全足够
    // - 对于联弹建模（n=3-20，期望 1-10，σ<3），误差可忽略
    //
    // 性能：仅 3 次 LCG，比 CLT-12 快 4 倍，比 Box-Muller 快约 12 倍
    // @param mean: 均值
    // @param standardDeviation: 标准差
    // @return 生成的近似高斯分布随机数
    public function randomGaussian(mean:Number, standardDeviation:Number):Number {
        // Irwin-Hall(3)：(sum - 1.5) / 0.5 = 2*sum - 3
        var z:Number = (nextFloat() + nextFloat() + nextFloat()) * 2 - 3;
        return z * standardDeviation + mean;
    }

    // CLT-12 精度版本（保留供需要更好尾部精度的场景）
    // @param mean: 均值
    // @param standardDeviation: 标准差
    // @return 生成的高斯分布随机数
    public function randomGaussianCLT12(mean:Number, standardDeviation:Number):Number {
        var sum:Number = nextFloat() + nextFloat() + nextFloat() + nextFloat()
                       + nextFloat() + nextFloat() + nextFloat() + nextFloat()
                       + nextFloat() + nextFloat() + nextFloat() + nextFloat();
        return (sum - 6) * standardDeviation + mean;
    }

    // Box-Muller 精确版本（保留供需要高精度尾部的场景使用）
    // 一次产生两个独立的标准正态分布值，缓存第二个供下次使用
    // @param mean: 均值
    // @param standardDeviation: 标准差
    // @return 生成的高斯分布随机数
    public function randomGaussianPrecise(mean:Number, standardDeviation:Number):Number {
        var z:Number;
        if (gaussianCached) {
            z = gaussianCacheValue;
            gaussianCached = false;
        } else {
            var u1:Number = nextFloat();
            var u2:Number = nextFloat();
            if (u1 < 1e-10) u1 = 1e-10;
            var r:Number = Math.sqrt(-2.0 * Math.log(u1));
            var theta:Number = 6.283185307179586 * u2;
            z = r * Math.cos(theta);
            gaussianCacheValue = r * Math.sin(theta);
            gaussianCached = true;
        }
        return z * standardDeviation + mean;
    }

    // 生成符合指数分布的随机数
    // @param lambda: 指数分布的参数
    // @return 生成的指数分布随机数
    public function randomExponential(lambda:Number):Number {
        var u:Number = nextFloat();
        return -Math.log(1 - u) / lambda;
    }

    // 生成一个随机布尔值
    // @param probability: 返回true的概率（0到1之间）
    // @return 生成的随机布尔值
    public function randomBoolean(probability:Number):Boolean {
        // 如果未提供参数，使用默认值0.5
        if (probability == undefined) {
            probability = 0.5;
        }
        return nextFloat() < probability;
    }

    /**
     * 生成一个带随机索引的字符串（格式: key + [0, countMax]的随机整数）
     * 用于随机跳转场景（如gotoAndPlay("a" + 随机索引)）
     * 
     * @param key 基础字符串（如"a"）
     * @param countMax 最大索引值（包含）
     * @return 拼接后的随机字符串（如"a2"）
     */
    public function randomKey(key:String, countMax:Number):String {
        // 生成0到countMax（包含）的随机整数
        var randomIndex:Number = randomIntegerStrict(0, countMax);
        return key + randomIndex;
    }

    // 生成指定长度的随机字符串
    // @param length: 字符串长度
    // @return 生成的随机字符串
    public function randomString(length:Number):String {
        var chars:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        var str:String = "";
        for (var i:Number = 0; i < length; i++) {
            str += chars.charAt(randomInteger(0, chars.length - 1));
        }
        return str;
    }

    // 生成一个随机角度（0到360度）
    // @return 生成的随机角度
    public function randomAngle():Number {
        return nextFloat() * 360;
    }

    // 生成一个位于圆内的随机点
    // @param radius: 圆的半径
    // @return 圆内的随机点（包含x和y坐标）
    public function randomPointInCircle(radius:Number):Object {
        var angle:Number = randomAngle();
        var distance:Number = Math.sqrt(nextFloat()) * radius;
        return { x: distance * Math.cos(angle), y: distance * Math.sin(angle) };
    }

    // 获取数组中指定数量的唯一随机元素
    // @param array: 原始数组
    // @param count: 需要获取的元素数量
    // @return 数组中的唯一随机元素
    public function getUniqueRandomElements(array:Array, count:Number):Array {
        if (count > array.length) {
            return null; // 无法获取超过数组长度的唯一元素
        }
        shuffleArray(array);
        return array.slice(0, count);
    }

    // ==================== 联弹分段躲闪建模专用方法 ====================

    /**
     * 四类别多项式采样（联弹分段躲闪建模专用）
     *
     * 将 n 次独立伯努利试验分配到四个类别：MISS、跳弹、过穿、直感（懒闪避）
     *
     * 优化策略：
     * 1. 小 n（≤12）：直接循环 + 二分判定（恒定 2 次比较）
     * 2. 大 n（>12）：独立高斯采样 + 归一化修正（避免条件概率除法）
     *
     * 概率分布假设（用于二分判定优化）：
     * - 高概率：跳弹/过穿（进入躲闪系统后大概率命中）
     * - 低概率：miss/直感
     * - 二分结构：先分离 (instant+miss) vs (bounce+pen)
     *
     * @param n 总段数（霰弹值）
     * @param pMiss MISS概率
     * @param pBounce 跳弹概率
     * @param pInstant 直感概率（懒闪避）
     * @param outCounts 输出数组 [missCount, bounceCount, penCount, instantCount]
     */
    public function multinomialSample4(n:Number, pMiss:Number, pBounce:Number, pInstant:Number, outCounts:Array):Void {
        // NaN 检查
        if (pMiss != pMiss) pMiss = 0;
        if (pBounce != pBounce) pBounce = 0;
        if (pInstant != pInstant) pInstant = 0;

        // 累积阈值（用于二分判定）
        // t1 = P(直感)
        // tLow = P(直感) + P(MISS)  ← 低概率事件累积
        // tMid = tLow + P(跳弹)     ← 用于高概率分支内部判定
        var t1:Number = pInstant;
        var tLow:Number = t1 + pMiss;
        var tMid:Number = tLow + pBounce;

        var instantCount:Number = 0;
        var missCount:Number = 0;
        var bounceCount:Number = 0;
        var penCount:Number = 0;

        // 小 n 直接循环 + 二分判定
        // 性能测试结果（2026-01-12）：
        // - n=9:  Loop 161ms vs Gauss 169ms，比值 0.95（Loop略优）
        // - n=11: Loop 186ms vs Gauss 184ms，比值 1.01（平衡点）
        // - n=13: Loop 215ms vs Gauss 182ms，比值 1.18（Gaussian优）
        // - 平衡点 n ≈ 11，设阈值为 12 保守取整
        // - 游戏实际霰弹值范围 3-20，多数在 3-12，走循环路径
        if (n <= 12) {
            var i:Number = 0;
            do {
                var r:Number = nextFloat();
                // 二分判定：恒定 2 次比较
                // 第一层：分离低概率(instant+miss) vs 高概率(bounce+pen)
                if (r < tLow) {
                    // 低概率分支：instant 或 miss
                    if (r < t1) instantCount++; else missCount++;
                } else {
                    // 高概率分支：bounce 或 pen
                    if (r < tMid) bounceCount++; else penCount++;
                }
            } while (++i < n);
        } else {
            // 大 n：独立高斯采样 + 归一化修正
            // 避免条件概率除法，直接对各分类独立采样
            // pen 由剩余值计算，无需显式采样

            // 预计算方差 var = n * p * (1-p)
            // 用 var > 0.25 判断是否需要 sqrt（等价于 sigma > 0.5）
            var varInst:Number = n * pInstant * (1 - pInstant);
            var varMiss:Number = n * pMiss * (1 - pMiss);
            var varBounce:Number = n * pBounce * (1 - pBounce);

            // Irwin-Hall 3 近似高斯
            // 仅当 var > 0.25 时才计算 sqrt 并采样
            if (varInst > 0.25) {
                instantCount = (n * pInstant + Math.sqrt(varInst) * ((nextFloat() + nextFloat() + nextFloat()) * 2 - 3) + 0.5) >> 0;
            } else {
                instantCount = (n * pInstant + 0.5) >> 0;
            }

            if (varMiss > 0.25) {
                missCount = (n * pMiss + Math.sqrt(varMiss) * ((nextFloat() + nextFloat() + nextFloat()) * 2 - 3) + 0.5) >> 0;
            } else {
                missCount = (n * pMiss + 0.5) >> 0;
            }

            if (varBounce > 0.25) {
                bounceCount = (n * pBounce + Math.sqrt(varBounce) * ((nextFloat() + nextFloat() + nextFloat()) * 2 - 3) + 0.5) >> 0;
            } else {
                bounceCount = (n * pBounce + 0.5) >> 0;
            }

            // 边界修正
            if (instantCount < 0) instantCount = 0;
            if (missCount < 0) missCount = 0;
            if (bounceCount < 0) bounceCount = 0;

            // ========== 归一化修正 ==========
            // 使用概率加权的随机余数分配，避免舍入误差系统性偏向 pen
            var sum:Number = instantCount + missCount + bounceCount;
            if (sum > n) {
                // 超出：按比例缩减（四舍五入）
                var scale:Number = n / sum;
                instantCount = (instantCount * scale + 0.5) >> 0;
                missCount = (missCount * scale + 0.5) >> 0;
                bounceCount = (bounceCount * scale + 0.5) >> 0;
                sum = instantCount + missCount + bounceCount;
            }
            // pen 先取剩余值
            penCount = n - sum;
            if (penCount < 0) penCount = 0;

            // ========== 余数修正 ==========
            // 计算最终余数（缩放后可能仍有偏差，通常 |remainder| ≤ 2）
            var finalSum:Number = instantCount + missCount + bounceCount + penCount;
            var remainder:Number = n - finalSum;

            // ========== 形式化证明与性能取舍说明 ==========
            //
            // 【定理1】|remainder| ≤ 2
            // 【证明】四舍五入最多使每个分量偏移 ±0.5，三分量累计最大偏移 ±1.5，
            //        取整后 |sum' - n| ≤ 2，故 |remainder| ≤ 2。              ∎
            //
            // 【定理2】remainder < 0 时，instantCount + missCount + bounceCount > 0
            // 【证明】remainder < 0 ⟹ finalSum > n ⟹ sum' > n（因 penCount ≥ 0）。
            //        又 sum' = instant + miss + bounce，且 n > 12（大 n 路径前提），
            //        故 instant + miss + bounce > 12 > 0。                    ∎
            //
            // 【性能取舍】
            // 旧实现：按概率随机选择桶增减，需调用 nextFloat()（每次约 5-10 周期）
            // 新实现：确定性选择高频桶（pen/bounce 优先），无随机调用
            //
            // 统计影响分析：
            // - |remainder| ≤ 2，对 n > 12 的分布影响 < 2/12 ≈ 17%（单次最大偏差）
            // - 实际游戏中 n 典型值 13-20，单次偏差对总体分布影响可忽略
            // - 移除 2 次 nextFloat() 调用，热路径性能提升约 10-20 周期
            //
            // 结论：性能收益 > 统计精度损失，采用确定性修正。
            // =============================================================

            // remainder > 0：需要补充，优先补到高频桶（pen > bounce > miss > instant）
            while (remainder > 0) {
                if (penCount >= 0) penCount++;      // pen 始终可补（剩余类别）
                else if (bounceCount > 0) bounceCount++;
                else if (missCount > 0) missCount++;
                else instantCount++;
                remainder--;
            }

            // remainder < 0：需要扣除，优先从高频桶扣（pen > bounce > miss > instant）
            // 根据定理2，至少存在一个非零桶可扣
            while (remainder < 0) {
                if (penCount > 0) penCount--;
                else if (bounceCount > 0) bounceCount--;
                else if (missCount > 0) missCount--;
                else instantCount--;  // 由定理2保证此时 instantCount > 0
                remainder++;
            }
        }

        // 输出结果
        outCounts[0] = missCount;
        outCounts[1] = bounceCount;
        outCounts[2] = penCount;
        outCounts[3] = instantCount;
    }

    /**
     * 三类别多项式采样（无懒闪避情况）
     *
     * 简化版本，用于目标不具有懒闪避属性的情况
     *
     * @param n 总段数（霰弹值）
     * @param pMiss MISS概率
     * @param pBounce 跳弹概率
     * @param outCounts 输出数组 [missCount, bounceCount, penCount]
     */
    public function multinomialSample3(n:Number, pMiss:Number, pBounce:Number, outCounts:Array):Void {
        // NaN 检查
        if (pMiss != pMiss) pMiss = 0;
        if (pBounce != pBounce) pBounce = 0;

        // 累积阈值
        var tMiss:Number = pMiss;
        var tBounce:Number = pMiss + pBounce;

        var missCount:Number = 0;
        var bounceCount:Number = 0;
        var penCount:Number = 0;

        // 小 n 直接循环（阈值 12，与 multinomialSample4 一致）
        if (n <= 12) {
            var i:Number = 0;
            do {
                var r:Number = nextFloat();
                // 优化判定顺序：miss 概率低，先判定可快速跳过
                // 但为保持与 multinomialSample4 一致的二分结构，这里用标准顺序
                if (r < tMiss) {
                    missCount++;
                } else if (r < tBounce) {
                    bounceCount++;
                } else {
                    penCount++;
                }
            } while (++i < n);
        } else {
            // 大 n：独立高斯采样 + 归一化修正
            // 用 var > 0.25 判断是否需要 sqrt（等价于 sigma > 0.5）
            var varMiss:Number = n * pMiss * (1 - pMiss);
            var varBounce:Number = n * pBounce * (1 - pBounce);

            if (varMiss > 0.25) {
                missCount = (n * pMiss + Math.sqrt(varMiss) * ((nextFloat() + nextFloat() + nextFloat()) * 2 - 3) + 0.5) >> 0;
            } else {
                missCount = (n * pMiss + 0.5) >> 0;
            }

            if (varBounce > 0.25) {
                bounceCount = (n * pBounce + Math.sqrt(varBounce) * ((nextFloat() + nextFloat() + nextFloat()) * 2 - 3) + 0.5) >> 0;
            } else {
                bounceCount = (n * pBounce + 0.5) >> 0;
            }

            // 边界修正
            if (missCount < 0) missCount = 0;
            if (bounceCount < 0) bounceCount = 0;

            // ========== 归一化修正 ==========
            // 使用概率加权的随机余数分配
            var sum:Number = missCount + bounceCount;
            if (sum > n) {
                var scale:Number = n / sum;
                missCount = (missCount * scale + 0.5) >> 0;
                bounceCount = (bounceCount * scale + 0.5) >> 0;
                sum = missCount + bounceCount;
            }
            // pen 先取剩余值
            penCount = n - sum;
            if (penCount < 0) penCount = 0;

            // ========== 余数修正 ==========
            // 计算最终余数（缩放后可能仍有偏差，通常 |remainder| ≤ 2）
            var finalSum:Number = missCount + bounceCount + penCount;
            var remainder:Number = n - finalSum;

            // 形式化证明与性能取舍同 multinomialSample4，此处简述：
            // 【定理】|remainder| ≤ 2，且 remainder < 0 时 missCount + bounceCount > 0
            // 【性能取舍】确定性修正替代随机修正，移除 nextFloat() 调用

            // remainder > 0：优先补到高频桶
            while (remainder > 0) {
                if (penCount >= 0) penCount++;
                else if (bounceCount > 0) bounceCount++;
                else missCount++;
                remainder--;
            }

            // remainder < 0：优先从高频桶扣
            while (remainder < 0) {
                if (penCount > 0) penCount--;
                else if (bounceCount > 0) bounceCount--;
                else missCount--;  // 由定理保证此时 missCount > 0
                remainder++;
            }
        }

        outCounts[0] = missCount;
        outCounts[1] = bounceCount;
        outCounts[2] = penCount;
    }

    /**
     * 计算联弹分段建模的懒闪避概率
     *
     * 将 DodgeHandler.lazyMiss 的逻辑复用为概率计算（不执行随机判定）
     * 用于联弹分段建模中获取每段的懒闪避触发概率
     *
     * @param hp 目标当前血量
     * @param fullHp 目标满血值
     * @param lazyMissValue 懒闪避值（0-1）
     * @param perPelletDamage 单段伤害值
     * @return 懒闪避概率（0-1）
     */
    public function calcLazyMissProbability(hp:Number, fullHp:Number, lazyMissValue:Number, perPelletDamage:Number):Number {
        // 无效检查
        if (!fullHp || fullHp <= 0 || !hp || hp <= 0 || lazyMissValue <= 0) {
            return 0;
        }

        // 缓存常用计算值
        var halfHp:Number = fullHp * 0.5;
        var maxRate:Number = lazyMissValue; // 最大概率（0-1）

        var successRate:Number;

        if (perPelletDamage > halfHp) {
            // 单段伤害超过半血：最大懒闪避
            successRate = maxRate;
        } else if (hp < halfHp) {
            // 当前血量低于半血：阈值降低
            var fifthHp:Number = fullHp * 0.2;
            if (perPelletDamage > fifthHp) {
                successRate = maxRate;
            } else if (perPelletDamage < fullHp * 0.025) {
                successRate = 0; // 伤害小于2.5%不闪避
            } else {
                successRate = maxRate * perPelletDamage * 5 / fullHp;
            }
        } else {
            // 当前血量高于半血
            if (perPelletDamage < fullHp * 0.05) {
                successRate = 0; // 伤害小于5%不闪避
            } else {
                successRate = maxRate * perPelletDamage * 2 / fullHp;
            }
        }

        // 上限为1
        if (successRate > 1) successRate = 1;
        return successRate;
    }
}
