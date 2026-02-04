import org.flashNight.neur.Controller.PIDController;
import org.flashNight.neur.PerformanceOptimizer.PerformanceScheduler;

/**
 * PerformanceSchedulerTest - 门面协调器回归测试（mock actuator/viz）
 *
 * 状态所有权：scheduler 内部持有 performanceLevel / actualFPS / pid 等，
 * host 上仅保留 性能等级上限 和 offsetTolerance。
 */
class org.flashNight.neur.PerformanceOptimizer.test.PerformanceSchedulerTest {

    public static function runAllTests():String {
        var out:String = "=== PerformanceSchedulerTest ===\n";
        out += test_twoStepConfirmationLeadsToActuation();
        out += test_onSceneChanged();
        out += test_setPerformanceLevelProtection();
        out += test_presetQualityDynamicSync();
        out += test_loggerHooks();
        out += test_pidDetailAndTag();
        return out + "\n";
    }

    // --- helpers ---

    private static function buildLight():Array {
        var arr:Array = [];
        for (var i:Number = 0; i < 24; i++) {
            arr.push(i % 9);
        }
        return arr;
    }

    private static function makeRoot():Object {
        var canvas:Object = { clear:function(){}, beginFill:function(){}, endFill:function(){}, moveTo:function(){}, lineTo:function(){}, curveTo:function(){}, lineStyle:function(){}, _x:0, _y:0 };
        return {
            _quality: "HIGH",
            lastMsg: null,
            发布消息: function(msg:String):Void { this.lastMsg = msg; },
            天气系统: { 当前时间: 0, 昼夜光照: buildLight() },
            玩家信息界面: { 性能帧率显示器: { 帧率数字: { text: null }, 画布: canvas } },
            显示列表: { 预设任务ID: "TASK", 继续播放:function(){}, 暂停播放:function(){} },
            UI系统: { 经济面板动效: true }
        };
    }

    /** host 仅保留 scheduler 仍需读写的 LIVE 字段 */
    private static function makeHost():Object {
        return {
            帧率: 30,
            性能等级上限: 0,
            offsetTolerance: 0
        };
    }

    /** 纯比例 PID（Kp=1），用于测试中快速触发切档 */
    private static function makePID():PIDController {
        return new PIDController(1, 0, 0, 1000, 0.1);
    }

    private static function makeMockActuator():Object {
        return {
            applied: [],
            presetQuality: "HIGH",
            apply: function(level:Number):Void { this.applied.push(level); },
            setPresetQuality: function(q:String):Void { this.presetQuality = q; },
            getPresetQuality: function():String { return this.presetQuality; }
        };
    }

    private static function makeMockViz():Object {
        return {
            updateData: function(fps:Number):Void {},
            drawCurve: function(c:MovieClip, level:Number):Void {},
            getTotalFPS: function():Number { return 0; },
            getMinFPS: function():Number { return 0; },
            getMaxFPS: function():Number { return 0; }
        };
    }

    private static function line(ok:Boolean, msg:String):String {
        return "  " + (ok ? "✓ " : "✗ ") + msg + "\n";
    }

    // --- test: evaluate 主循环两次确认 ---

    private static function test_twoStepConfirmationLeadsToActuation():String {
        var out:String = "[evaluate]\n";

        var root:Object = makeRoot();
        var host:Object = makeHost();
        var pid:PIDController = makePID();
        var scheduler:PerformanceScheduler = new PerformanceScheduler(host, 30, 26, "HIGH", {root: root}, pid);

        var actuator:Object = makeMockActuator();
        scheduler.setActuator(actuator);
        scheduler.setVisualization(makeMockViz());

        // 模拟60帧，帧间隔50ms（≈20FPS），触发两次评估
        var t:Number = 0;
        for (var i:Number = 0; i < 60; i++) {
            t += 50;
            scheduler.evaluate(t);
        }

        out += line(actuator.applied.length == 1, "两次确认后只执行一次切档");
        out += line(actuator.applied.length == 1 && actuator.applied[0] == 3, "低FPS下切到level3（clamp后）");
        out += line(scheduler.getPerformanceLevel() == 3, "scheduler.performanceLevel更新为3");
        out += line(scheduler.getSampler().getFramesLeft() == 120, "切到level3后采样周期=120帧");

        return out;
    }

    // --- test: onSceneChanged ---

    private static function test_onSceneChanged():String {
        var out:String = "[onSceneChanged]\n";

        var root:Object = makeRoot();
        var host:Object = makeHost();
        var pid:PIDController = makePID();
        var scheduler:PerformanceScheduler = new PerformanceScheduler(host, 30, 26, "HIGH", {root: root}, pid);

        var actuator:Object = makeMockActuator();
        scheduler.setActuator(actuator);
        scheduler.setVisualization(makeMockViz());

        // 先用前馈设置到 level 2，使 quantizer 进入已确认状态
        scheduler.setPerformanceLevel(2, 5, 1000);
        actuator.applied = []; // 清除前馈产生的 apply 记录

        // 手动让 quantizer 进入半次确认状态
        scheduler.getQuantizer().setAwaitingConfirmation(true);

        scheduler.onSceneChanged();

        // 1) performanceLevel 归零
        out += line(scheduler.getPerformanceLevel() === 0, "performanceLevel重置为0");

        // 2) actuator 收到 apply(0)
        out += line(actuator.applied.length == 1 && actuator.applied[0] == 0, "执行器收到apply(0)");

        // 3) PID 被重置（无异常抛出即可）
        out += line(true, "PID已重置（无异常抛出）");

        // 4) 迟滞状态清除
        out += line(!scheduler.getQuantizer().isAwaitingConfirmation(), "迟滞确认状态已清除");

        // 5) 采样窗口重置
        out += line(scheduler.getSampler().getFramesLeft() == 30, "采样周期重置为30帧（level0）");
        out += line(scheduler.getSampler().getFrameStartTime() > 0, "frameStartTime更新为当前时间（>0）");

        return out;
    }

    // --- test: setPerformanceLevel 保护窗口 ---

    private static function test_setPerformanceLevelProtection():String {
        var out:String = "[setPerformanceLevel]\n";

        var root:Object = makeRoot();
        var host:Object = makeHost();
        var pid:PIDController = makePID();
        var scheduler:PerformanceScheduler = new PerformanceScheduler(host, 30, 26, "HIGH", {root: root}, pid);

        var actuator:Object = makeMockActuator();
        scheduler.setActuator(actuator);
        scheduler.setVisualization(makeMockViz());

        // 手动设置到 level 2，保持5秒
        scheduler.setPerformanceLevel(2, 5, 1000);

        out += line(scheduler.getPerformanceLevel() === 2, "performanceLevel设为2");
        out += line(actuator.applied.length == 1 && actuator.applied[0] == 2, "执行器收到apply(2)");
        out += line(!scheduler.getQuantizer().isAwaitingConfirmation(), "quantizer确认状态已清除");

        // 保护窗口: max(30*5=150, 30*(1+2)=90) = 150
        out += line(scheduler.getSampler().getFramesLeft() == 150, "保护窗口=150帧（max(150,90)）");
        out += line(scheduler.getSampler().getFrameStartTime() == 1000, "frameStartTime更新为传入时间");

        // 估算帧率: 30 - 2*2 = 26
        out += line(scheduler.getActualFPS() == 26, "估算帧率=26（30-2*2）");

        // 相同等级不重复执行
        actuator.applied = [];
        scheduler.setPerformanceLevel(2, 5, 2000);
        out += line(actuator.applied.length == 0, "相同等级不重复执行");

        return out;
    }

    // --- test: presetQuality 动态同步 ---

    private static function test_presetQualityDynamicSync():String {
        var out:String = "[presetQuality动态同步]\n";

        var root:Object = makeRoot();
        var host:Object = makeHost();

        var scheduler:PerformanceScheduler = new PerformanceScheduler(host, 30, 26, "HIGH", {root: root});
        scheduler.setVisualization(makeMockViz());

        // 初始预设画质
        out += line(scheduler.getActuator().getPresetQuality() == "HIGH", "初始presetQuality=HIGH");

        // 运行时修改 presetQuality，并在下一次 apply 前同步
        scheduler.setPresetQuality("LOW");
        scheduler.setPerformanceLevel(1, 5, 1000);

        out += line(scheduler.getActuator().getPresetQuality() == "LOW", "apply前presetQuality同步为LOW");
        out += line(root._quality == "LOW", "L1 在预设为LOW时 quality=LOW（而非MEDIUM）");

        return out;
    }

    // --- test: logger hooks ---

    private static function test_loggerHooks():String {
        var out:String = "[logger]\n";

        var root:Object = makeRoot();
        var host:Object = makeHost();
        var pid:PIDController = makePID();
        var scheduler:PerformanceScheduler = new PerformanceScheduler(host, 30, 26, "HIGH", {root: root}, pid);

        // mock actuator/viz
        var actuator:Object = makeMockActuator();
        scheduler.setActuator(actuator);
        scheduler.setVisualization(makeMockViz());

        // mock logger（记录调用次数和参数）
        var calls:Array = [];
        var mockLogger:Object = {
            _tag: null,
            setTag: function(tag:String):Void { this._tag = tag; },
            getTag: function():String { return this._tag; },
            sample: function(t:Number, level:Number, actualFPS:Number, denoisedFPS:Number, pidOutput:Number):Void {
                calls.push({fn:"sample"});
            },
            pidDetail: function(t:Number, pTerm:Number, iTerm:Number, dTerm:Number, pidOutput:Number):Void {
                calls.push({fn:"pidDetail", pTerm:pTerm, iTerm:iTerm, dTerm:dTerm, pidOutput:pidOutput});
            },
            levelChanged: function(t:Number, oldLevel:Number, newLevel:Number, actualFPS:Number, quality:String):Void {
                calls.push({fn:"levelChanged", oldLevel:oldLevel, newLevel:newLevel});
            },
            manualSet: function(t:Number, level:Number, holdSec:Number):Void {
                calls.push({fn:"manualSet", level:level, holdSec:holdSec});
            },
            sceneChanged: function(t:Number, level:Number, actualFPS:Number, targetFPS:Number, quality:String):Void {
                calls.push({fn:"sceneChanged", level:level, actualFPS:actualFPS, targetFPS:targetFPS, quality:quality});
            }
        };
        scheduler.setLogger(mockLogger);

        // 触发两次采样点（60帧）
        var t:Number = 0;
        for (var i:Number = 0; i < 60; i++) {
            t += 50;
            scheduler.evaluate(t);
        }

        out += line(countCalls(calls, "sample") == 2, "采样点日志 sample 调用2次");
        out += line(countCalls(calls, "pidDetail") == 2, "PID分量日志 pidDetail 调用2次（与sample同步）");
        out += line(countCalls(calls, "levelChanged") == 1, "切档日志 levelChanged 调用1次");

        // 前馈调用
        scheduler.setPerformanceLevel(2, 5, 1000);
        out += line(countCalls(calls, "manualSet") == 1, "前馈日志 manualSet 调用1次");

        // 场景切换（此时 level=2, 由前馈设置）
        scheduler.onSceneChanged();
        out += line(countCalls(calls, "sceneChanged") == 1, "场景切换日志 sceneChanged 调用1次");

        // 验证快照捕获了重置前的状态
        var scEntry:Object = findCall(calls, "sceneChanged");
        out += line(scEntry.level == 2, "sceneChanged快照: level=2（重置前）");
        out += line(scEntry.targetFPS == 26, "sceneChanged快照: targetFPS=26");
        out += line(scEntry.quality == "HIGH", "sceneChanged快照: quality=HIGH");

        return out;
    }

    // --- test: PID分量详细日志 + 标签系统 ---

    private static function test_pidDetailAndTag():String {
        var out:String = "[pidDetail+tag]\n";

        var root:Object = makeRoot();
        var host:Object = makeHost();
        var pid:PIDController = makePID(); // Kp=1, Ki=0, Kd=0
        var scheduler:PerformanceScheduler = new PerformanceScheduler(host, 30, 26, "HIGH", {root: root}, pid);

        var actuator:Object = makeMockActuator();
        scheduler.setActuator(actuator);
        scheduler.setVisualization(makeMockViz());

        // mock logger with tag support
        var calls:Array = [];
        var mockLogger:Object = {
            _tag: null,
            setTag: function(tag:String):Void { this._tag = tag; },
            getTag: function():String { return this._tag; },
            sample: function(t:Number, level:Number, actualFPS:Number, denoisedFPS:Number, pidOutput:Number):Void {
                calls.push({fn:"sample", tag:this._tag});
            },
            pidDetail: function(t:Number, pTerm:Number, iTerm:Number, dTerm:Number, pidOutput:Number):Void {
                calls.push({fn:"pidDetail", pTerm:pTerm, iTerm:iTerm, dTerm:dTerm, pidOutput:pidOutput});
            },
            levelChanged: function(t:Number, oldLevel:Number, newLevel:Number, actualFPS:Number, quality:String):Void {
                calls.push({fn:"levelChanged"});
            },
            manualSet: function(t:Number, level:Number, holdSec:Number):Void {
                calls.push({fn:"manualSet"});
            },
            sceneChanged: function(t:Number, level:Number, actualFPS:Number, targetFPS:Number, quality:String):Void {
                calls.push({fn:"sceneChanged"});
            }
        };
        scheduler.setLogger(mockLogger);

        // 1) 设置标签后采样
        scheduler.setLoggerTag("OL:test");
        out += line(scheduler.getLoggerTag() == "OL:test", "setLoggerTag设置标签");

        var t:Number = 0;
        for (var i:Number = 0; i < 30; i++) {
            t += 50;
            scheduler.evaluate(t);
        }

        // 第一个采样点应带有标签
        var firstSample:Object = findCall(calls, "sample");
        out += line(firstSample != null && firstSample.tag == "OL:test", "sample携带tag='OL:test'");

        // 验证 pidDetail 数据完整性（Kp=1, Ki=0, Kd=0 → P分量=error, I=0, D=0）
        var firstPD:Object = findCall(calls, "pidDetail");
        out += line(firstPD != null, "pidDetail被调用");
        if (firstPD != null) {
            // 纯比例控制器：P分量 = pidOutput, I=0, D=0
            out += line(firstPD.iTerm == 0, "纯比例PID: iTerm=0");
            out += line(firstPD.dTerm == 0, "纯比例PID: dTerm=0");
            // P+I+D 应等于 pidOutput（冗余校验）
            var sum:Number = firstPD.pTerm + firstPD.iTerm + firstPD.dTerm;
            var diff:Number = Math.abs(sum - firstPD.pidOutput);
            out += line(diff < 0.001, "P+I+D=pidOutput（冗余校验通过）");
        }

        // 2) 清除标签
        scheduler.setLoggerTag(null);
        out += line(scheduler.getLoggerTag() == null, "setLoggerTag(null)清除标签");

        // 3) 无logger时 setLoggerTag 不抛异常
        scheduler.setLogger(null);
        scheduler.setLoggerTag("should_not_throw");
        out += line(scheduler.getLoggerTag() == null, "无logger时getLoggerTag返回null");

        // 4) PID组件 getLastP/I/D 验证
        out += line(pid.getLastP() != undefined, "PIDController.getLastP()可用");
        out += line(pid.getLastI() != undefined, "PIDController.getLastI()可用");
        out += line(pid.getLastD() != undefined, "PIDController.getLastD()可用");

        // reset后分量归零
        pid.reset();
        out += line(pid.getLastP() == 0, "reset后getLastP()=0");
        out += line(pid.getLastI() == 0, "reset后getLastI()=0");
        out += line(pid.getLastD() == 0, "reset后getLastD()=0");

        return out;
    }

    private static function countCalls(calls:Array, name:String):Number {
        var n:Number = 0;
        for (var i:Number = 0; i < calls.length; i++) {
            if (calls[i].fn == name) n++;
        }
        return n;
    }

    private static function findCall(calls:Array, name:String):Object {
        for (var i:Number = calls.length - 1; i >= 0; i--) {
            if (calls[i].fn == name) return calls[i];
        }
        return null;
    }
}
