import org.flashNight.aven.Promise.Promise;
import org.flashNight.aven.Promise.Scheduler;

/**
 * Promise 基础设施性能基准测试
 *
 * 设计目标：
 *   1. 不再用“固定等 N 帧”当完成判据，改为等待真实完成或明确超时
 *   2. 同步基准至少跑到最小计时窗口，再取多次采样中位数
 *   3. 异步基准重复多轮，输出样本，避免单次 getTimer() 量化噪声误导
 *
 * 用法: TestLoader.as 中调用 PromisePerformanceBench.run()
 */
class org.flashNight.aven.Promise.PromisePerformanceBench {

    private static var _results:Array;
    private static var _benchQueue:Array;
    private static var _currentIndex:Number;
    private static var _timerSeq:Number;

    private static var SYNC_REPEATS:Number = 5;
    private static var ASYNC_REPEATS:Number = 3;
    private static var MIN_SYNC_WINDOW_MS:Number = 60;
    private static var MAX_SYNC_OPS:Number = 200000;

    // ================================================================
    // 入口
    // ================================================================

    public static function run():Void {
        _results = [];
        _currentIndex = 0;
        _timerSeq = 0;

        warmup();

        trace("========================================");
        trace("  Promise Performance Benchmark");
        trace("  timerQuantum~" + measureTimerQuantum(8) + "ms");
        trace("  sync repeats=" + SYNC_REPEATS + ", async repeats=" + ASYNC_REPEATS);
        trace("========================================");

        _benchQueue = [
            "bench_closureCreation",
            "bench_promiseCreation",
            "bench_promiseResolveStatic",
            "bench_schedulerRawThroughput",
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

        waitFrames(3, function():Void {
            org.flashNight.aven.Promise.PromisePerformanceBench.runNext();
        });
    }

    /** 预热类加载、Scheduler clip 初始化和 Promise 常见路径 */
    private static function warmup():Void {
        var i:Number = 0;
        while (i < 16) {
            Promise.resolve(i).then(function(v:Object):Object { return v; });
            i++;
        }
        Promise.all([Promise.resolve(1), Promise.resolve(2)]).then(function(values:Object):Void {});
        Scheduler.getInstance().enqueue(function():Void {});
    }

    /** 串行调度器：每个基准完成后触发下一个 */
    private static function runNext():Void {
        if (_currentIndex >= _benchQueue.length) {
            reportAll();
            return;
        }

        var benchName:String = _benchQueue[_currentIndex];
        _currentIndex++;

        waitFrames(2, function():Void {
            org.flashNight.aven.Promise.PromisePerformanceBench.dispatch(benchName);
        });
    }

    /** 分派到对应基准方法 */
    private static function dispatch(name:String):Void {
        if (name == "bench_closureCreation") bench_closureCreation();
        else if (name == "bench_promiseCreation") bench_promiseCreation();
        else if (name == "bench_promiseResolveStatic") bench_promiseResolveStatic();
        else if (name == "bench_schedulerRawThroughput") bench_schedulerRawThroughput();
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

    // ================================================================
    // 通用辅助
    // ================================================================

    /** 延迟若干帧后执行 */
    private static function waitFrames(frames:Number, fn:Function):Void {
        _timerSeq++;
        var waiter:MovieClip = _root.createEmptyMovieClip(
            "_promiseBenchWaiter" + _timerSeq,
            _root.getNextHighestDepth()
        );
        waiter.remainingFrames = frames;
        waiter.onEnterFrame = function():Void {
            this.remainingFrames--;
            if (this.remainingFrames <= 0) {
                delete this.onEnterFrame;
                this.removeMovieClip();
                fn();
            }
        };
    }

    /** 按帧轮询直到 predicate 为真或超时 */
    private static function pollUntil(maxFrames:Number, predicate:Function, callback:Function):Void {
        _timerSeq++;
        var waiter:MovieClip = _root.createEmptyMovieClip(
            "_promiseBenchPoller" + _timerSeq,
            _root.getNextHighestDepth()
        );
        waiter.frameCount = 0;
        waiter.onEnterFrame = function():Void {
            this.frameCount++;
            if (predicate()) {
                delete this.onEnterFrame;
                var doneFrames:Number = this.frameCount;
                this.removeMovieClip();
                callback(true, doneFrames);
            } else if (this.frameCount >= maxFrames) {
                delete this.onEnterFrame;
                var timeoutFrames:Number = this.frameCount;
                this.removeMovieClip();
                callback(false, timeoutFrames);
            }
        };
    }

    private static function cloneArray(src:Array):Array {
        var out:Array = [];
        var i:Number = 0;
        while (i < src.length) {
            out[i] = src[i];
            i++;
        }
        return out;
    }

    private static function sortNumbers(a:Array):Void {
        var i:Number = 1;
        while (i < a.length) {
            var v:Number = a[i];
            var j:Number = i - 1;
            while (j >= 0 && a[j] > v) {
                a[j + 1] = a[j];
                j--;
            }
            a[j + 1] = v;
            i++;
        }
    }

    private static function median(src:Array):Number {
        var a:Array = cloneArray(src);
        sortNumbers(a);
        var n:Number = a.length;
        if ((n & 1) == 1) {
            return a[n >> 1];
        }
        return (a[(n >> 1) - 1] + a[n >> 1]) * 0.5;
    }

    private static function samplesToString(samples:Array):String {
        var out:String = "";
        var i:Number = 0;
        while (i < samples.length) {
            if (i > 0) out += ",";
            out += samples[i];
            i++;
        }
        return out;
    }

    private static function notesToString(notes:Array):String {
        if (notes == null || notes.length == 0) return "";
        var out:String = "";
        var i:Number = 0;
        while (i < notes.length) {
            if (i > 0) out += " ; ";
            out += notes[i];
            i++;
        }
        return out;
    }

    /** 采样 getTimer 量化粒度 */
    private static function measureTimerQuantum(samples:Number):Number {
        var diffs:Array = [];
        var i:Number = 0;
        while (i < samples) {
            var t0:Number = getTimer();
            var t1:Number = t0;
            while (t1 == t0) {
                t1 = getTimer();
            }
            diffs.push(t1 - t0);
            i++;
        }
        return median(diffs);
    }

    /** 同步基准：先把工作量推到最小计时窗口，再做多次采样 */
    private static function measureSyncAdaptive(initialOps:Number, runner:Function):Object {
        var ops:Number = initialOps;
        var elapsed:Number = Number(runner(ops));
        while (elapsed < MIN_SYNC_WINDOW_MS && ops < MAX_SYNC_OPS) {
            ops = ops * 2;
            elapsed = Number(runner(ops));
        }

        var samples:Array = [];
        var i:Number = 0;
        while (i < SYNC_REPEATS) {
            samples.push(Number(runner(ops)));
            i++;
        }

        return {ops: ops, samples: samples};
    }

    /** 记录同步基准结果 */
    private static function recordSync(name:String, result:Object, note:String):Void {
        recordSamples(name, result.samples, result.ops, note);
    }

    /** 异步基准：串行跑多轮样本，最后用中位数汇总 */
    private static function runAsyncSamples(
        name:String,
        fallbackOps:Number,
        launch:Function
    ):Void {
        var samples:Array = [];
        var notes:Array = [];
        var repeatIndex:Number = 0;

        function runOne():Void {
            launch(function(totalMs:Number, note:String, opsOverride:Number):Void {
                samples.push(totalMs);
                if (note != undefined) {
                    notes.push("r" + (repeatIndex + 1) + "=" + note);
                }

                repeatIndex++;
                if (repeatIndex < ASYNC_REPEATS) {
                    org.flashNight.aven.Promise.PromisePerformanceBench.waitFrames(2, runOne);
                } else {
                    var finalOps:Number = fallbackOps;
                    if (typeof(opsOverride) == "number") {
                        finalOps = opsOverride;
                    }
                    org.flashNight.aven.Promise.PromisePerformanceBench.recordSamples(
                        name, samples, finalOps, notesToString(notes)
                    );
                }
            });
        }

        runOne();
    }

    /** 统一输出格式并触发下一个基准 */
    private static function recordSamples(name:String, samples:Array, ops:Number, note:String):Void {
        var medMs:Number = median(samples);
        var perOpUs:Number = Math.round((medMs / ops) * 1000 * 100) / 100;
        var entry:String = "[BENCH] " + name
            + " | median=" + medMs + "ms"
            + " | samples=[" + samplesToString(samples) + "]"
            + " | ops=" + ops
            + " | per-op=" + perOpUs + "us";
        if (note != undefined && note.length > 0) {
            entry += " | " + note;
        }
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
    // Sync Bench 1: 闭包创建开销
    // ================================================================

    private static function bench_closureCreation():Void {
        var result:Object = measureSyncAdaptive(2000, function(ops:Number):Number {
            var arr:Array = [];
            var captured:Number = 42;

            var t0:Number = getTimer();
            var i:Number = 0;
            while (i < ops) {
                arr.push(function():Number { return captured; });
                i++;
            }
            var elapsed:Number = getTimer() - t0;
            arr.length = 0;
            return elapsed;
        });

        recordSync("Closure creation", result, "");
    }

    // ================================================================
    // Sync Bench 2: Promise 构造成本
    // ================================================================

    private static function bench_promiseCreation():Void {
        var result:Object = measureSyncAdaptive(500, function(ops:Number):Number {
            var t0:Number = getTimer();
            var i:Number = 0;
            while (i < ops) {
                new Promise(function(resolve:Function, reject:Function):Void {
                    resolve(i);
                });
                i++;
            }
            return getTimer() - t0;
        });

        recordSync("new Promise(sync resolve)", result, "");
    }

    // ================================================================
    // Sync Bench 3: Promise.resolve() 静态方法
    // ================================================================

    private static function bench_promiseResolveStatic():Void {
        var result:Object = measureSyncAdaptive(1000, function(ops:Number):Number {
            var t0:Number = getTimer();
            var i:Number = 0;
            while (i < ops) {
                Promise.resolve(i);
                i++;
            }
            return getTimer() - t0;
        });

        recordSync("Promise.resolve(value)", result, "");
    }

    // ================================================================
    // Async Bench 4: Scheduler 原始吞吐（enqueue + drain）
    // ================================================================

    private static function bench_schedulerRawThroughput():Void {
        var n:Number = 5000;
        runAsyncSamples("Scheduler.enqueue+drain", n, function(done:Function):Void {
            var scheduler:Scheduler = Scheduler.getInstance();
            var counter:Object = {val: 0};

            var t0:Number = getTimer();
            var i:Number = 0;
            while (i < n) {
                scheduler.enqueue(function():Void {
                    counter.val++;
                });
                i++;
            }

            scheduler.enqueue(function():Void {
                done(getTimer() - t0, "verified=" + counter.val + "/" + n, n);
            });
        });
    }

    // ================================================================
    // Async Bench 5: then() 链完整解析
    // ================================================================

    private static function bench_thenChainResolve(depth:Number):Void {
        var n:Number = 1000;
        if (depth >= 10) n = 400;

        runAsyncSamples("then-chain-resolve(depth=" + depth + ")", n, function(done:Function):Void {
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

            org.flashNight.aven.Promise.PromisePerformanceBench.pollUntil(
                180,
                function():Boolean {
                    return completed.val == n;
                },
                function(ok:Boolean, frames:Number):Void {
                    var totalMs:Number = getTimer() - t0;
                    done(
                        totalMs,
                        "setup=" + setupMs + "ms, completed=" + completed.val + "/" + n
                            + ", frames=" + frames + (ok ? "" : ", TIMEOUT"),
                        n
                    );
                }
            );
        });
    }

    // ================================================================
    // Async Bench 6: Promise.all
    // ================================================================

    private static function bench_promiseAll(size:Number):Void {
        var n:Number = 150;
        if (size >= 50) n = 80;
        if (size >= 100) n = 48;
        if (size >= 500) n = 12;

        runAsyncSamples("Promise.all(size=" + size + ")", n, function(done:Function):Void {
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

            org.flashNight.aven.Promise.PromisePerformanceBench.pollUntil(
                240,
                function():Boolean {
                    return completed.val == n;
                },
                function(ok:Boolean, frames:Number):Void {
                    var totalMs:Number = getTimer() - t0;
                    done(
                        totalMs,
                        "setup=" + setupMs + "ms, completed=" + completed.val + "/" + n
                            + ", frames=" + frames + (ok ? "" : ", TIMEOUT"),
                        n
                    );
                }
            );
        });
    }

    // ================================================================
    // Async Bench 7: 多条长链（单条太短会落在计时量化边界）
    // ================================================================

    private static function bench_longChain(depth:Number):Void {
        var chains:Number = 80;
        if (depth >= 100) chains = 40;

        runAsyncSamples("long-chain(depth=" + depth + ")", chains, function(done:Function):Void {
            var handler:Function = function(v:Object):Object { return v; };
            var completed:Object = {val: 0};

            var t0:Number = getTimer();
            var c:Number = 0;
            while (c < chains) {
                var p:Promise = Promise.resolve(c);
                var i:Number = 0;
                while (i < depth) {
                    p = p.then(handler);
                    i++;
                }
                p.then(function(v:Object):Void {
                    completed.val++;
                });
                c++;
            }
            var setupMs:Number = getTimer() - t0;

            org.flashNight.aven.Promise.PromisePerformanceBench.pollUntil(
                240,
                function():Boolean {
                    return completed.val == chains;
                },
                function(ok:Boolean, frames:Number):Void {
                    var totalMs:Number = getTimer() - t0;
                    done(
                        totalMs,
                        "setup=" + setupMs + "ms, completed=" + completed.val + "/" + chains
                            + ", frames=" + frames + (ok ? "" : ", TIMEOUT"),
                        chains
                    );
                }
            );
        });
    }
}
