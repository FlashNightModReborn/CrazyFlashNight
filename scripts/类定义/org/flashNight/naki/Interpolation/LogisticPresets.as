/**
 * LogisticPresets.as - Logistic曲线预设类型和工厂方法
 * 
 * 路径：org.flashNight.naki.Interpolation.LogisticPresets
 * 
 * 功能：
 *  1. 提供常用的Logistic曲线预设（减少配置复杂度）
 *  2. 工厂方法快速创建标准曲线类型
 *  3. 参数验证和自动优化
 *  4. 与SymmetricLogistic的便捷集成接口
 * 
 * 性能优化：
 *  - 预计算：所有预设参数在初始化时计算并缓存，避免重复计算
 *  - 直接求值：使用 evaluateWithParams 跳过拟合过程，仅做指数运算
 *  - 输入验证：范围检查和归一化边界处理，避免异常值
 *  - 状态管理：正确处理重置和自定义预设的状态同步
 * 
 * 设计理念：
 *  - 简化API：用户无需了解数学细节，只需选择合适的预设类型
 *  - 类型安全：枚举式的曲线类型，避免配置错误
 *  - 性能优先：预计算+缓存，确保生产环境高性能
 *  - 健壮性：完善的边界检查和错误处理
 */

import org.flashNight.naki.Interpolation.SymmetricLogistic;

class org.flashNight.naki.Interpolation.LogisticPresets {
    
    // ============ 曲线类型常量（枚举式设计） ============
    
    /** 平缓S型：开始和结束都很平缓，中间过渡平滑 */
    public static var CURVE_GENTLE_S:String = "gentle_s";
    
    /** 陡峭S型：中间过渡区域很窄，快速变化 */
    public static var CURVE_STEEP_S:String = "steep_s";
    
    /** 早期饱和：快速上升后趋于平缓（指数衰减类似） */
    public static var CURVE_EARLY_SATURATION:String = "early_saturation";
    
    /** 延迟启动：开始很平缓，后期快速上升 */
    public static var CURVE_LATE_ACCELERATION:String = "late_acceleration";
    
    /** 中心对称：完美的中心对称S型 */
    public static var CURVE_SYMMETRIC:String = "symmetric";
    
    /** 游戏平衡：专门为游戏数值平衡设计的曲线 */
    public static var CURVE_GAME_BALANCE:String = "game_balance";
    
    /** 用户体验：为UI/UX优化的平滑过渡曲线 */
    public static var CURVE_UX_SMOOTH:String = "ux_smooth";

    // ============ 内部状态管理 ============
    
    /** 预设配置存储（包含预计算参数） */
    private static var presetConfigs:Object;
    
    /** 预设是否已初始化 */
    private static var presetsInitialized:Boolean = false;
    
    /** 数值验证常量 */
    private static var EPSILON:Number = 1e-10;

    // ============ 核心工厂方法 ============

    /**
     * 使用预设曲线类型计算函数值（高性能版本）
     * 
     * @param curveType  曲线类型（使用上面定义的常量）
     * @param x          输入值
     * @param xRange     输入值的范围 {min:Number, max:Number}
     * @param yRange     输出值的范围 {min:Number, max:Number}
     * @return           计算结果
     */
    public static function evaluate(
        curveType:String, 
        x:Number, 
        xRange:Object, 
        yRange:Object
    ):Number {
        // 1. 确保预设已初始化
        _ensurePresetsInitialized();
        
        // 2. 输入验证和健壮性检查
        var validationResult:Object = _validateInputs(x, xRange, yRange);
        if (!validationResult.isValid) {
            trace("LogisticPresets warning: " + validationResult.errorMsg);
            return _getFallbackValue(xRange, yRange);
        }
        
        // 3. 获取预设配置
        var config:Object = presetConfigs[curveType];
        if (!config) {
            trace("Warning: Unknown curve type '" + curveType + "', using symmetric");
            config = presetConfigs[CURVE_SYMMETRIC];
        }
        
        // 4. 参数有效性检查
        if (!config.params || !config.params.isValid) {
            trace("Warning: Invalid preset params for '" + curveType + "', using linear fallback");
            return _linearFallbackByRange(x, xRange, yRange);
        }

        // 5. 输入值归一化（带边界处理）
        var normalizedX:Number = _safeNormalize(x, xRange.min, xRange.max);
        
        // 6. 使用预计算参数直接计算（高性能路径）
        var result:Number = SymmetricLogistic.evaluateWithParams(
            normalizedX,
            config.params,
            0, 1  // 预设都在[0,1]标准区间内计算
        );
        
        // 7. 将结果映射到目标输出范围
        return yRange.min + result * (yRange.max - yRange.min);
    }

    /**
     * 快速创建常用的游戏数值映射
     * 
     * @param curveType    曲线类型
     * @param inputValue   输入值
     * @param inputMin     输入最小值
     * @param inputMax     输入最大值  
     * @param outputMin    输出最小值
     * @param outputMax    输出最大值
     * @return             映射结果
     */
    public static function mapValue(
        curveType:String,
        inputValue:Number,
        inputMin:Number, inputMax:Number,
        outputMin:Number, outputMax:Number
    ):Number {
        return evaluate(
            curveType,
            inputValue,
            { min: inputMin, max: inputMax },
            { min: outputMin, max: outputMax }
        );
    }

    /**
     * 创建专用的游戏系统映射器
     */
    public static function createGameMapper(
        curveType:String,
        inputRange:Object,
        outputRange:Object
    ):Function {
        return function(inputValue:Number):Number {
            return evaluate(curveType, inputValue, inputRange, outputRange);
        };
    }

    // ============ 专用应用场景的便捷方法 ============

    /**
     * 相机缩放专用：根据敌人数量计算缩放限制
     */
    public static function cameraZoomByEnemyCount(
        enemyCount:Number,
        minEnemies:Number, maxEnemies:Number,
        minZoom:Number, maxZoom:Number
    ):Number {
        return mapValue(
            CURVE_GAME_BALANCE,
            enemyCount,
            minEnemies, maxEnemies,
            maxZoom, minZoom  // 注意：敌人多时缩放小，所以颠倒
        );
    }

    /**
     * 难度曲线专用：根据玩家等级计算难度系数
     */
    public static function difficultyByLevel(
        playerLevel:Number,
        minLevel:Number, maxLevel:Number,
        minDifficulty:Number, maxDifficulty:Number
    ):Number {
        return mapValue(
            CURVE_EARLY_SATURATION,
            playerLevel,
            minLevel, maxLevel,
            minDifficulty, maxDifficulty
        );
    }

    /**
     * 音频衰减专用：根据距离计算音量
     */
    public static function volumeByDistance(
        distance:Number,
        nearDistance:Number, farDistance:Number,
        maxVolume:Number, minVolume:Number
    ):Number {
        return mapValue(
            CURVE_STEEP_S,
            distance,
            nearDistance, farDistance,
            maxVolume, minVolume  // 距离远时音量小
        );
    }

    /**
     * UI动画专用：缓动函数生成器
     */
    public static function uiEasing(curveType:String, progress:Number):Number {
        return evaluate(
            curveType,
            progress,
            { min: 0, max: 1 },
            { min: 0, max: 1 }
        );
    }

    /**
     * 经济系统专用：成本/收益曲线
     */
    public static function economicCurve(
        investment:Number,
        minInvestment:Number, maxInvestment:Number,
        baseReturn:Number, maxReturn:Number
    ):Number {
        return mapValue(
            CURVE_LATE_ACCELERATION,
            investment,
            minInvestment, maxInvestment,
            baseReturn, maxReturn
        );
    }

    // ============ 配置管理方法 ============

    /**
     * 获取所有可用的曲线类型（动态生成，避免手工维护）
     */
    public static function getAvailableCurves():Array {
        _ensurePresetsInitialized();
        var curves:Array = [];
        for (var name:String in presetConfigs) {
            curves.push(name);
        }
        return curves;
    }

    /**
     * 获取指定曲线类型的描述信息
     */
    public static function getCurveDescription(curveType:String):Object {
        _ensurePresetsInitialized();
        var config:Object = presetConfigs[curveType];
        return config ? {
            name: curveType,
            description: config.description,
            useCase: config.useCase,
            characteristics: config.characteristics,
            params: config.params,
            isValid: config.params ? config.params.isValid : false
        } : null;
    }

    /**
     * 添加自定义预设
     */
    public static function addCustomPreset(
        name:String,
        x1:Number, y1:Number, x2:Number, y2:Number,
        description:String, useCase:String
    ):Void {
        _ensurePresetsInitialized();
        
        // 创建配置对象
        var config:Object = {
            x1: x1, y1: y1, x2: x2, y2: y2,
            description: description,
            useCase: useCase,
            characteristics: "Custom preset"
        };
        
        // 立即预计算参数
        config.params = SymmetricLogistic.fitFromTwoPoints(x1, y1, x2, y2, 0, 1);
        
        // 存储配置
        presetConfigs[name] = config;
        
        trace("Added custom preset '" + name + "' (valid: " + config.params.isValid + ")");
    }

    /**
     * 重置所有预设为默认配置
     */
    public static function resetToDefaults():Void {
        presetConfigs = null;
        presetsInitialized = false;  // 重要：重置初始化标志
        SymmetricLogistic.clearCache(); // 清除SymmetricLogistic的缓存
        trace("LogisticPresets reset to defaults");
    }

    /**
     * 强制重新初始化预设（用于调试或配置更新后）
     */
    public static function forceReinitialize():Void {
        presetsInitialized = false;
        _ensurePresetsInitialized();
    }

    // ============ 测试和调试方法 ============

    /**
     * 生成曲线测试数据（用于可视化和调试）
     */
    public static function generateTestData(
        curveType:String,
        sampleCount:Number,
        xRange:Object,
        yRange:Object
    ):Array {
        var data:Array = [];
        var stepSize:Number = (xRange.max - xRange.min) / (sampleCount - 1);
        
        for (var i:Number = 0; i < sampleCount; i++) {
            var x:Number = xRange.min + i * stepSize;
            var y:Number = evaluate(curveType, x, xRange, yRange);
            data.push({ x: x, y: y });
        }
        
        return data;
    }

    /**
     * 比较多种曲线类型在相同输入下的表现
     */
    public static function compareCurves(
        testValue:Number,
        xRange:Object,
        yRange:Object
    ):Object {
        var results:Object = {};
        var curves:Array = getAvailableCurves();
        
        for (var i:Number = 0; i < curves.length; i++) {
            var curveType:String = curves[i];
            results[curveType] = evaluate(curveType, testValue, xRange, yRange);
        }
        
        return results;
    }

    /**
     * 性能基准测试
     */
    public static function benchmarkPerformance(iterations:Number):Object {
        _ensurePresetsInitialized();
        
        var startTime:Number = getTimer();
        var testRange:Object = { min: 0, max: 10 };
        var outputRange:Object = { min: 0, max: 1 };
        
        for (var i:Number = 0; i < iterations; i++) {
            var testValue:Number = Math.random() * 10;
            evaluate(CURVE_SYMMETRIC, testValue, testRange, outputRange);
        }
        
        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;
        
        return {
            iterations: iterations,
            duration: duration,
            avgTimePerCall: duration / iterations,
            callsPerSecond: iterations / (duration / 1000)
        };
    }

    // ============ 私有辅助方法 ============

    /**
     * 确保预设已初始化（含预计算优化）
     */
    private static function _ensurePresetsInitialized():Void {
        if (!presetsInitialized) {
            trace("Initializing LogisticPresets with parameter pre-computation...");
            
            // 1. 创建基础配置
            presetConfigs = _createBaseConfigs();
            
            // 2. 预计算所有预设的参数
            _precomputeAllParams();
            
            // 3. 标记为已初始化
            presetsInitialized = true;
            
            trace("LogisticPresets initialized. Available curves: " + getAvailableCurves().length);
        }
    }

    /**
     * 创建基础配置（无预计算参数）
     */
    private static function _createBaseConfigs():Object {
        return {
            // 平缓S型：20%和80%处的过渡点较为平缓
            gentle_s: {
                x1: 0.3, y1: 0.2, x2: 0.7, y2: 0.8,
                description: "Gentle S-curve with smooth transitions",
                useCase: "UI animations, user-friendly transitions",
                characteristics: "Smooth start and end, gradual middle transition"
            },
            
            // 陡峭S型：40%和60%处快速过渡
            steep_s: {
                x1: 0.4, y1: 0.1, x2: 0.6, y2: 0.9,
                description: "Steep S-curve with rapid middle transition",
                useCase: "Audio volume control, sharp cutoffs",
                characteristics: "Sharp transition in middle, stable at extremes"
            },
            
            // 早期饱和：快速上升后平缓
            early_saturation: {
                x1: 0.2, y1: 0.6, x2: 0.5, y2: 0.85,
                description: "Early saturation curve, quick rise then plateau",
                useCase: "Difficulty scaling, diminishing returns",
                characteristics: "Rapid initial growth, levels off quickly"
            },
            
            // 延迟启动：开始平缓，后期加速
            late_acceleration: {
                x1: 0.5, y1: 0.15, x2: 0.8, y2: 0.4,
                description: "Late acceleration curve, slow start then rapid growth",
                useCase: "Economic systems, compound growth",
                characteristics: "Slow initial growth, accelerates later"
            },
            
            // 中心对称：完美的50%中心对称
            symmetric: {
                x1: 0.3, y1: 0.3, x2: 0.7, y2: 0.7,
                description: "Perfectly symmetric S-curve",
                useCase: "General purpose, balanced transitions",
                characteristics: "Perfect symmetry around center point"
            },
            
            // 游戏平衡：专为游戏设计的平衡曲线
            game_balance: {
                x1: 0.25, y1: 0.35, x2: 0.75, y2: 0.75,
                description: "Optimized for game balance and player experience",
                useCase: "Game mechanics, player progression",
                characteristics: "Balanced growth, player-friendly pacing"
            },
            
            // UX平滑：为用户体验优化
            ux_smooth: {
                x1: 0.35, y1: 0.25, x2: 0.65, y2: 0.75,
                description: "Smooth curve optimized for user experience",
                useCase: "UI/UX animations, visual transitions",
                characteristics: "Extra smooth, visually pleasing"
            }
        };
    }

    /**
     * 预计算所有预设的Logistic参数（性能优化核心）
     */
    private static function _precomputeAllParams():Void {
        var computedCount:Number = 0;
        var validCount:Number = 0;
        
        for (var name:String in presetConfigs) {
            var config:Object = presetConfigs[name];
            
            // 调用SymmetricLogistic计算参数
            config.params = SymmetricLogistic.fitFromTwoPoints(
                config.x1, config.y1,
                config.x2, config.y2,
                0, 1  // 所有预设都在[0,1]标准区间
            );
            
            computedCount++;
            if (config.params.isValid) {
                validCount++;
            } else {
                trace("Warning: Failed to compute params for preset '" + name + "': " + config.params.errorMsg);
            }
        }
        
        trace("Pre-computed " + computedCount + " presets, " + validCount + " valid");
    }

    /**
     * 输入验证和健壮性检查
     */
    private static function _validateInputs(x:Number, xRange:Object, yRange:Object):Object {
        // 检查NaN
        if (isNaN(x) || isNaN(xRange.min) || isNaN(xRange.max) || 
            isNaN(yRange.min) || isNaN(yRange.max)) {
            return { isValid: false, errorMsg: "Contains NaN values" };
        }
        
        // 检查范围有效性
        if (Math.abs(xRange.max - xRange.min) < EPSILON) {
            return { isValid: false, errorMsg: "xRange.max and xRange.min are too close" };
        }
        
        if (Math.abs(yRange.max - yRange.min) < EPSILON) {
            return { isValid: false, errorMsg: "yRange.max and yRange.min are too close" };
        }
        
        return { isValid: true, errorMsg: null };
    }

    /**
     * 安全的归一化（带边界处理）
     */
    private static function _safeNormalize(x:Number, min:Number, max:Number):Number {
        var normalized:Number = (x - min) / (max - min);
        // 约束到[0,1]范围，避免曲线外推
        return Math.max(0, Math.min(1, normalized));
    }

    /**
     * 获取后备值（当验证失败时）
     */
    private static function _getFallbackValue(xRange:Object, yRange:Object):Number {
        return (yRange.min + yRange.max) / 2; // 返回输出范围的中值
    }

    /**
     * 线性后备方案（当Logistic计算失败时）
     */
    private static function _linearFallbackByRange(x:Number, xRange:Object, yRange:Object):Number {
        var normalizedX:Number = _safeNormalize(x, xRange.min, xRange.max);
        return yRange.min + normalizedX * (yRange.max - yRange.min);
    }
}
