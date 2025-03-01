import org.flashNight.neur.Controller.PIDController;

class org.flashNight.neur.Optimizer.PIDOptimizer {
    // ===== 配置常量 =====
    private static var MAX_ITERATIONS:Number = 50;       // 最大优化迭代次数
    private static var CONVERGENCE_THRESHOLD:Number = 0.1; // 误差改善阈值
    private static var INITIAL_STEP_SIZE:Number = 1;     // 初始搜索步长
    private static var STEP_DECAY:Number = 0.7;          // 步长衰减系数
    
    // ===== 实例变量 =====
    private var simulationFunction:Function;   // 仿真评估函数
    private var paramHistory:Array;            // 参数优化历史记录
    private var bestParams:Object;             // 当前最佳参数
    private var currentStep:Number;            // 当前搜索步长
    private var searchDirections:Array;        // 参数搜索方向
    
    // ===== 构造函数 =====
    function PIDOptimizer(simulationFunc:Function) {
        this.simulationFunction = simulationFunc;
        this.paramHistory = [];
        this.currentStep = INITIAL_STEP_SIZE;
        this.searchDirections = [
            {Kp:1, Ki:0, Kd:0},  // 沿Kp方向搜索
            {Kp:0, Ki:1, Kd:0},  // 沿Ki方向搜索
            {Kp:0, Ki:0, Kd:1}   // 沿Kd方向搜索
        ];
    }

    // ===== 智能参数搜索 =====
    private function patternSearch(initialParams:Object):Object {
        var params:Object = initialParams;
        var bestError:Number = Number.MAX_VALUE;
        
        for (var i:Number = 0; i < MAX_ITERATIONS; i++) {
            var improved:Boolean = false;
            
            // 在三个正交方向进行搜索
            for each (var dir:Object in this.searchDirections) {
                var newParams:Object = this.exploreDirection(params, dir);
                var newError:Number = this.simulationFunction(newParams);
                
                if (newError < bestError) {
                    bestError = newError;
                    params = this.cloneParams(newParams);
                    improved = true;
                    this.recordParameters(params, bestError);
                }
            }
            
            // 动态调整步长
            if (!improved) {
                this.currentStep *= STEP_DECAY;
                if (this.currentStep < 0.01) break; // 退出条件
            }
        }
        
        return params;
    }

    // ===== 方向探索 =====
    private function exploreDirection(baseParams:Object, direction:Object):Object {
        var positiveParams:Object = this.adjustParams(baseParams, direction, this.currentStep);
        var negativeParams:Object = this.adjustParams(baseParams, direction, -this.currentStep);
        
        var posError:Number = this.simulationFunction(positiveParams);
        var negError:Number = this.simulationFunction(negativeParams);
        
        return (posError < negError) ? positiveParams : negativeParams;
    }

    // ===== 参数调整 =====
    private function adjustParams(params:Object, direction:Object, step:Number):Object {
        return {
            Kp: this.clamp(params.Kp + direction.Kp * step, 0, 100),
            Ki: this.clamp(params.Ki + direction.Ki * step, 0, 10),
            Kd: this.clamp(params.Kd + direction.Kd * step, 0, 10),
            integralMax: params.integralMax,
            derivativeFilter: params.derivativeFilter
        };
    }

    // ===== 辅助方法 =====
    private function cloneParams(params:Object):Object {
        return {
            Kp: params.Kp,
            Ki: params.Ki,
            Kd: params.Kd,
            integralMax: params.integralMax,
            derivativeFilter: params.derivativeFilter
        };
    }

    private function clamp(value:Number, min:Number, max:Number):Number {
        return Math.max(min, Math.min(max, value));
    }

    private function recordParameters(params:Object, error:Number):Void {
        this.paramHistory.push({
            Kp: params.Kp,
            Ki: params.Ki,
            Kd: params.Kd,
            error: error,
            timestamp: getTimer()
        });
    }

    // ===== 自动整定入口 =====
    public function autoTune(initialParams:Object):Object {
        this.bestParams = initialParams;
        var startError:Number = this.simulationFunction(initialParams);
        this.recordParameters(initialParams, startError);
        
        // 执行模式搜索
        var optimized:Object = this.patternSearch(initialParams);
        
        // 最终验证
        var finalError:Number = this.simulationFunction(optimized);
        trace("Optimization complete. Final error: " + finalError);
        return optimized;
    }

    // ===== 可视化调试支持 =====
    public function generateConvergenceChart():Void {
        // 此处可集成图表绘制逻辑
		// 专门的调试页面？
        trace("Parameter convergence history:");
        for (var i:Number = 0; i < this.paramHistory.length; i++) {
            var entry:Object = this.paramHistory[i];
            trace("[" + entry.timestamp + "ms] Kp:" + entry.Kp.toFixed(2) + 
                  " Ki:" + entry.Ki.toFixed(2) + 
                  " Kd:" + entry.Kd.toFixed(2) + 
                  " Error:" + entry.error.toFixed(4));
        }
    }

    // ===== 静态工具方法 =====
    public static function createDefaultParams():Object {
        return {
            Kp: 1.0,
            Ki: 0.05,
            Kd: 0.1,
            integralMax: 1000,
            derivativeFilter: 0.1
        };
    }
}