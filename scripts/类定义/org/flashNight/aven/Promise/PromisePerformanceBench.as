import org.flashNight.aven.Promise.Promise;
import org.flashNight.aven.Promise.Scheduler;

/**
 * Promise 基础设施性能基准测试
 *
 * 测量维度:
 *   1. Promise 构造成本（new Promise + executor）
 *   2. Promise.resolve() 静态方法成本
 *   3. then() 链设置成本（同步部分）
 *   4. 链解析吞吐（异步排空）
 *   5. Promise.all 聚合成本
 *   6. Scheduler 原始吞吐（无 Promise 包装）
 *   7. 闭包创建开销对照
 *
 * 用法: TestLoader.as 中调用 PromisePerformanceBench.run()
 */
class org.flashNight.aven.Promise.PromisePerformanceBench {

    private static var _results:Array;
    private static var _benchQueue:Array;
    private static var _currentIndex:Number;

    /** 每项基准的迭代次数 */
    private static var ITERATIONS:Number = 1000;

    // ================================================================
    // 入口
    // ================================================================

    public static function run():Void {
        _results = [];
        _currentIndex = 0;

        trace("========================================");
        trace("  Promise Performance Benchmark");
        trace("  Iterations per bench: " + ITERATIONS);
        trace("========================================");

        // 按顺序排列基准（每个基准异步完成后触发下一个）
        _benchQueue = [
            "bench_schedulerRawThroughput",
            "bench_closureCreation",
            "bench_promiseCreation",
            "bench_promiseResolveStatic",
            "bench_thenChainSetup",
            "bench_thenChainResolve_1",
            "bench_thenChainResolve_3",
            "bench_thenChainResolve_10",
            "bench_promiseAll_10",
            "bench_promiseAll_50",
            "bench_promiseAll_100",
            "bench_promiseAll_500",
            "bench_longChain_50",
            "bench_longChain_100"
        ];

        runNext();
    }

    /** 串行调度器：每个基准完成后调用 runNext 触发下一个 */
    private static function runNext():Void {
        if (_currentIndex >= _benchQueue.length) {
            reportAll();
            return;
        }

        var benchName:String = _benchQueue[_currentIndex];
        _currentIndex++;

        // 等待 2 帧让上一个基准的残留清理干净
        var waiter:MovieClip = _root.createEmptyMovieClip(
            "_benchWaiter" + _currentIndex,
            _root.getNextHighestDepth()
        );
        var framesLeft:Number = 2;
        waiter.onEnterFrame = function():Void {
            framesLeft--;
            if (framesLeft <= 0) {
                delete this.onEnterFrame;
                this.removeMovieClip();
                org.flashNight.aven.Promise.PromisePerformanceBench.dispatch(benchName);
            }
        };
    }

    /** 分派到对应基准方法 */
    private static function dispatch(name:String):Void {
        if (name == "bench_schedulerRawThroughput") bench_schedulerRawThroughput();
        else if (name == "bench_closureCreation") bench_closureCreation();
        else if (name == "bench_promiseCreation") bench_promiseCreation();
        else if (name == "bench_promiseResolveStatic") bench_promiseResolveStatic();
        else if (name == "bench_thenChainSetup") bench_thenChainSetup();
        else if (name == "bench_thenChainResolve_1") bench_thenChainResolve(1);
        else if (name == "bench_thenChainResolve_3") bench_thenChainResolve(3);
        else if (name == "bench_thenChainResolve_10") bench_thenChainResolve(10);
        else if (name == "bench_promiseAll_10") bench_promiseAll(10);
        else if (name == "bench_promiseAll_50") bench_promiseAll(50);
        else if (name == "bench_promiseAll_100") bench_promiseAll(100);
        else if (name == "bench_promiseAll_500") bench_promiseAll(500);
        else if (name == "bench_longChain_50") bench_longChain(50);
        else if (name == "bench_longChain_100") bench_longChain(100);
        else {
            trace("[BENCH] Unknown: " + name);
            runNext();
        }
    }

    /** 记录结果并触发下一个基准 */
    private static function record(name:String, totalMs:Number, ops:Number):Void {
        var perOpUs:Number = Math.round((totalMs / ops) * 1000 * 100) / 100;
        var entry:String = "[BENCH] " + name
            + " | total=" + totalMs + "ms"
            + " | ops=" + ops
            + " | per-op=" + perOpUs + "us";
        trace(entry);
        _results.push(entry);
        runNext();
    }

    /** 汇总报告 */
    private static function reportAll():Void {
        trace("");
        trace("========================================");
        trace("  Benchmark Summary (" + _results.length + " tests)");
        trace("========================================");
        var i:Number = 0;
        while (i < _results.length) {
            trace(_results[i]);
            i++;
        }
        trace("========================================");
        trace("  ALL BENCHMARKS DONE");
        trace("========================================");
    }

    // ================================================================
    // Bench 1: Scheduler 原始吞吐（enqueue + drain）
    // ================================================================

    private static function bench_schedulerRawThroughput():Void {
        var scheduler:Scheduler = Scheduler.getInstance();
        var n:Number = ITERATIONS * 10;
        var counter:Object = {val: 0};

        var t0:Number = getTimer();
        var i:Number = 0;
        while (i < n) {
            scheduler.enqueue(function():Void {
                counter.val++;
            });
            i++;
        }
        var enqueueMs:Number = getTimer() - t0;

        // 追加一个末尾哨兵回调，在 drain 完成时记录
        scheduler.enqueue(function():Void {
            var totalMs:Number = getTimer() - t0;
            var drainMs:Number = totalMs - enqueueMs;
            trace("[BENCH] Scheduler.enqueue (x" + n + ") | enqueue=" + enqueueMs + "ms");
            trace("[BENCH] Scheduler.drain   (x" + n + ") | drain=" + drainMs + "ms"
                + " | verified=" + counter.val + "/" + n);
            org.flashNight.aven.Promise.PromisePerformanceBench.record(
                "Scheduler.enqueue+drain (x" + n + ")",
                totalMs, n
            );
        });
    }

    // ================================================================
    // Bench 2: 闭包创建开销（对照基准）
    // ================================================================

    private static function bench_closureCreation():Void {
        var n:Number = ITERATIONS;
        var arr:Array = [];
        var captured:Number = 42;

        var t0:Number = getTimer();
        var i:Number = 0;
        while (i < n) {
            arr.push(function():Number { return captured; });
            i++;
        }
        var elapsed:Number = getTimer() - t0;
        arr.length = 0;

        record("Closure creation (x" + n + ")", elapsed, n);
    }

    // ================================================================
    // Bench 3: Promise 构造成本
    // ================================================================

    private static function bench_promiseCreation():Void {
        var n:Number = ITERATIONS;

        var t0:Number = getTimer();
        var i:Number = 0;
        while (i < n) {
            new Promise(function(resolve:Function, reject:Function):Void {
                resolve(i);
            });
            i++;
        }
        var elapsed:Number = getTimer() - t0;

        record("new Promise(sync resolve) (x" + n + ")", elapsed, n);
    }

    // ================================================================
    // Bench 4: Promise.resolve() 静态方法
    // ================================================================

    private static function bench_promiseResolveStatic():Void {
        var n:Number = ITERATIONS;

        var t0:Number = getTimer();
        var i:Number = 0;
        while (i < n) {
            Promise.resolve(i);
            i++;
        }
        var elapsed:Number = getTimer() - t0;

        record("Promise.resolve(value) (x" + n + ")", elapsed, n);
    }

    // ================================================================
    // Bench 5: then() 链设置成本（同步部分，不等解析）
    // ================================================================

    private static function bench_thenChainSetup():Void {
        var n:Number = ITERATIONS;
        var handler:Function = function(v:Object):Object { return v; };

        var t0:Number = getTimer();
        var i:Number = 0;
        while (i < n) {
            Promise.resolve(i).then(handler).then(handler).then(handler);
            i++;
        }
        var elapsed:Number = getTimer() - t0;

        record("then() chain setup x3 (x" + n + ")", elapsed, n);
    }

    // ================================================================
    // Bench 6: then() 链完整解析（含异步 drain）
    // ================================================================

    private static function bench_thenChainResolve(depth:Number):Void {
        var n:Number = ITERATIONS;
        var completed:Object = {val: 0};
        var handler:Function = function(v:Object):Object { return v; };

        var t0:Number = getTimer();
        var i:Number = 0;
        while (i < n) {
            var p:Promise = Promise.resolve(i);
            var d:Number = 0;
            while (d < depth) {
                p = p.then(handler);
                d++;
            }
            p.then(function(v:Object):Void {
                completed.val++;
            });
            i++;
        }
        var setupMs:Number = getTimer() - t0;

        // 等足够帧数让 drain 完成
        var waitClip:MovieClip = _root.createEmptyMovieClip(
            "_benchResolveWait_" + depth, _root.getNextHighestDepth()
        );
        var framesLeft:Number = 3;
        waitClip.onEnterFrame = function():Void {
            framesLeft--;
            if (framesLeft <= 0) {
                delete this.onEnterFrame;
                this.removeMovieClip();
                var totalMs:Number = getTimer() - t0;
                trace("[BENCH] then-resolve(depth=" + depth
                    + ") setup=" + setupMs + "ms"
                    + " total=" + totalMs + "ms"
                    + " completed=" + completed.val + "/" + n);
                org.flashNight.aven.Promise.PromisePerformanceBench.record(
                    "then-chain-resolve(depth=" + depth + ") (x" + n + ")",
                    totalMs, n
                );
            }
        };
    }

    // ================================================================
    // Bench 7: Promise.all
    // ================================================================

    private static function bench_promiseAll(size:Number):Void {
        var n:Number = 100;
        if (size >= 500) n = 20;
        var completed:Object = {val: 0};

        var t0:Number = getTimer();
        var iter:Number = 0;
        while (iter < n) {
            var arr:Array = [];
            var j:Number = 0;
            while (j < size) {
                arr.push(Promise.resolve(j));
                j++;
            }
            Promise.all(arr).then(function(values:Object):Void {
                completed.val++;
            });
            iter++;
        }
        var setupMs:Number = getTimer() - t0;

        var waitClip:MovieClip = _root.createEmptyMovieClip(
            "_benchAllWait_" + size, _root.getNextHighestDepth()
        );
        var framesLeft:Number = 5;
        waitClip.onEnterFrame = function():Void {
            framesLeft--;
            if (framesLeft <= 0) {
                delete this.onEnterFrame;
                this.removeMovieClip();
                var totalMs:Number = getTimer() - t0;
                trace("[BENCH] Promise.all(size=" + size
                    + ") setup=" + setupMs + "ms"
                    + " total=" + totalMs + "ms"
                    + " completed=" + completed.val + "/" + n);
                org.flashNight.aven.Promise.PromisePerformanceBench.record(
                    "Promise.all(size=" + size + ") (x" + n + ")",
                    totalMs, n
                );
            }
        };
    }

    // ================================================================
    // Bench 8: 长链（单条深链的构建+解析）
    // ================================================================

    private static function bench_longChain(depth:Number):Void {
        var handler:Function = function(v:Object):Object { return v; };

        var t0:Number = getTimer();
        var p:Promise = Promise.resolve(0);
        var i:Number = 0;
        while (i < depth) {
            p = p.then(handler);
            i++;
        }
        var setupMs:Number = getTimer() - t0;

        p.then(function(v:Object):Void {
            var totalMs:Number = getTimer() - t0;
            trace("[BENCH] longChain(depth=" + depth
                + ") setup=" + setupMs + "ms"
                + " total=" + totalMs + "ms");
            org.flashNight.aven.Promise.PromisePerformanceBench.record(
                "longChain(depth=" + depth + ")",
                totalMs, depth
            );
        });
    }
}
