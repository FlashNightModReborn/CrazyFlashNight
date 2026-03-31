import org.flashNight.aven.Promise.PromiseAPlusTest;

var PROMISE_TEST_MODE:String = "all"; // all | a_plus | bench | none

if (PROMISE_TEST_MODE == "all") {
    PromiseAPlusTest.main();

    var _promiseBenchStarter:MovieClip = _root.createEmptyMovieClip(
        "_promiseBenchStarter",
        _root.getNextHighestDepth()
    );
    var _promiseBenchFramesLeft:Number = 70;
    _promiseBenchStarter.onEnterFrame = function():Void {
        _promiseBenchFramesLeft--;
        if (_promiseBenchFramesLeft <= 0) {
            delete this.onEnterFrame;
            this.removeMovieClip();
            trace("");
            trace("=== Promise Bench Start ===");
            PromisePerformanceBench.run();
        }
    };
} else if (PROMISE_TEST_MODE == "a_plus") {
    PromiseAPlusTest.main();
} else if (PROMISE_TEST_MODE == "bench") {
    PromisePerformanceBench.run();
} else {
    trace("[TestLoader] PROMISE_TEST_MODE=none");
}


========================================
  Promises/A+ Compliance Test Suite
========================================
[PASS] 2.2.7-returns-promise
[PASS] resolve-same-instance
[PASS] 2.1-resolve-once
[PASS] 2.1-reject-once
[PASS] 2.2.2-value-arg
[PASS] 2.2.4-async-fulfilled
[PASS] 2.2.4-async-rejected
[PASS] 2.2.5-called-once
[PASS] static-all-empty
[PASS] static-allSettled-empty
[PASS] executor-throw-after-resolve
[PASS] resolve-thenable-unwrap
[PASS] resolve-proto-null-thenable
[PASS] resolve-proto-null-thenable-reject
[PASS] multiple-then-a
[PASS] multiple-then-b
[PASS] multiple-then-c
[PASS] safety-scheduler-recovery-value
[PASS] resolve-existing-value
[PASS] resolve-rejected-passthrough
[PASS] deep-thenable-resolve
[PASS] multi-reject-a
[PASS] multi-reject-b
[PASS] resolve-no-arg
[PASS] 2.2.1-fulfill-passthrough
[PASS] 2.2.1-reject-passthrough
[PASS] 2.2.6-fulfilled-order
[PASS] 2.2.6-rejected-order
[PASS] 2.2.7.2-chain-throw
[PASS] 2.2.7.2-rejection-throw
[PASS] 2.2.7.3-value-propagation
[PASS] 2.2.7.4-reason-propagation
[PASS] 2.3.1-cycle-detection
[PASS] 2.3.3-thenable-resolve
[PASS] 2.3.3-thenable-reject
[PASS] 2.3.3.3.3-first-wins
[PASS] 2.3.3.3.1-recursive-thenable
[PASS] 2.3.3.4-then-not-function
[PASS] 2.3.3.2-then-getter-throws
[PASS] 2.3.3-this-binding
[PASS] 2.3.3-then-getter-once-value
[PASS] 2.3.3-then-getter-once-count
[PASS] 2.3.3-throw-before-settle
[PASS] 2.3.3-throw-after-resolve
[PASS] 2.3.3-throw-after-reject
[PASS] 2.3.3-proto-null-thenable
[PASS] 2.3.3-proto-null-thenable-reject
[PASS] 2.3.4-number
[PASS] 2.3.4-string
[PASS] 2.3.4-boolean
[PASS] 2.3.4-null
[PASS] 2.3.4-undefined
[PASS] static-all-reject
[PASS] static-allSettled-mixed
[PASS] safety-self-resolution
[PASS] non-func-fulfill-passthrough
[PASS] non-func-reject-passthrough
[PASS] undefined-chain
[PASS] all-plain-values
[PASS] finally-throw-overrides
[PASS] large-batch-all
[PASS] race-immediate-wins
[PASS] null-in-chain
[PASS] reject-handler-undefined
[PASS] handler-returns-function
[PASS] all-with-thenables
[PASS] race-all-sync
[PASS] then-no-args-fulfill
[PASS] then-no-args-reject
[PASS] finally-non-func-fulfill
[PASS] all-single-reject
[PASS] race-with-thenable
[PASS] 2.2.7.1-chain-values
[PASS] 2.3.2-adopt-fulfilled
[PASS] 2.3.2-adopt-rejected
[PASS] error-recovery
[PASS] propagation-skips-a
[PASS] propagation-skips-b
[PASS] propagation-reason
[PASS] re-reject-from-catch
[PASS] all-first-reject-wins
[PASS] nested-all
[PASS] catch-recover-fulfilled
[PASS] finally-non-func-reject
[PASS] finally-fulfilled-called
[PASS] finally-fulfilled-value
[PASS] finally-rejected-called
[PASS] finally-rejected-reason
[PASS] complex-recovery
[PASS] nested-then-inside-then
[PASS] reject-skip-fulfill-chain
[PASS] reject-far-catch
[PASS] chain-timing-value
[PASS] chain-timing-frames
[PASS] catch-then-finally-order
[PASS] catch-then-finally-value
[PASS] long-chain-10
[PASS] super-long-chain-100
[PASS] tick-manual-drain
[PASS] bindTo-external-flag
[PASS] bindTo-driveMode
[PASS] bindTo-clip-removed
[PASS] bindTo-no-auto-drain
[PASS] bindTo-tick-drains
[PASS] rebind-unsub-old
[PASS] fallback-unsub
[PASS] fallback-not-external
[PASS] fallback-driveMode
[PASS] unbind-suspended
[PASS] unbind-not-external
[compile] done
[PASS] unbind-no-auto-drain
[PASS] async-thenable
[PASS] static-all-order
[PASS] static-race-first-settled
[PASS] 2.3.2-adopt-pending
[PASS] finally-async-order
[PASS] finally-async-value
[PASS] unbind-tick-recovers
[PASS] unbind-fallback-mode
[PASS] fallback-fires
[PASS] fork-chain-A
[PASS] fork-chain-B
[PASS] safety-scheduler-recovery-fires
[PASS] safety-self-resolution-no-hang
[PASS] static-race-empty-pending
[PASS] unbind-fallback-restored
[PASS] thenable-never-settles
[PASS] late-then-value
[PASS] late-then-fired

========================================
  Test Results: 129/129 passed, 0 failed
  ALL PASSED
========================================

=== Promise Bench Start ===
========================================
  Promise Performance Benchmark
  timerQuantum~1ms
  sync repeats=5, async repeats=3
========================================
[BENCH] Closure creation | median=87ms | samples=[121,87,154,77,80] | ops=4000 | per-op=21.75us
[BENCH] new Promise(sync resolve) | median=52ms | samples=[54,52,44,47,61] | ops=1000 | per-op=52us
[BENCH] Promise.resolve(value) | median=54ms | samples=[53,53,62,54,77] | ops=1000 | per-op=54us
[BENCH] Scheduler.enqueue+drain | median=230ms | samples=[148,230,261] | ops=5000 | per-op=46us | r1=verified=5000/5000 ; r2=verified=5000/5000 ; r3=verified=5000/5000
[BENCH] then-chain-resolve(depth=1) | median=1105ms | samples=[726,1105,1363] | ops=1000 | per-op=1105us | r1=setup=630ms, completed=1000/1000, frames=1 ; r2=setup=1022ms, completed=1000/1000, frames=1 ; r3=setup=1279ms, completed=1000/1000, frames=1
[BENCH] then-chain-resolve(depth=3) | median=2866ms | samples=[2581,2866,4466] | ops=1000 | per-op=2866us | r1=setup=2375ms, completed=1000/1000, frames=1 ; r2=setup=2642ms, completed=1000/1000, frames=1 ; r3=setup=4242ms, completed=1000/1000, frames=1
[BENCH] then-chain-resolve(depth=10) | median=6988ms | samples=[5517,6988,9973] | ops=400 | per-op=17470us | r1=setup=5204ms, completed=400/400, frames=1 ; r2=setup=6752ms, completed=400/400, frames=1 ; r3=setup=9742ms, completed=400/400, frames=1
[BENCH] Promise.all(size=10) | median=1874ms | samples=[1519,1874,1920] | ops=150 | per-op=12493.33us | r1=setup=1395ms, completed=150/150, frames=1 ; r2=setup=1846ms, completed=150/150, frames=1 ; r3=setup=1892ms, completed=150/150, frames=1
[BENCH] Promise.all(size=50) | median=1617ms | samples=[1617,1667,1517] | ops=80 | per-op=20212.5us | r1=setup=1510ms, completed=80/80, frames=1 ; r2=setup=1601ms, completed=80/80, frames=1 ; r3=setup=1481ms, completed=80/80, frames=1
[BENCH] Promise.all(size=100) | median=1578ms | samples=[1322,1766,1578] | ops=48 | per-op=32875us | r1=setup=1184ms, completed=48/48, frames=1 ; r2=setup=1727ms, completed=48/48, frames=1 ; r3=setup=1526ms, completed=48/48, frames=1
[BENCH] Promise.all(size=500) | median=2052ms | samples=[2052,1971,2374] | ops=12 | per-op=171000us | r1=setup=1919ms, completed=12/12, frames=1 ; r2=setup=1914ms, completed=12/12, frames=1 ; r3=setup=2296ms, completed=12/12, frames=1
[BENCH] long-chain(depth=50) | median=3725ms | samples=[2681,4829,3725] | ops=80 | per-op=46562.5us | r1=setup=2288ms, completed=80/80, frames=1 ; r2=setup=4479ms, completed=80/80, frames=1 ; r3=setup=3532ms, completed=80/80, frames=1
[BENCH] long-chain(depth=100) | median=3856ms | samples=[3856,4291,2613] | ops=40 | per-op=96400us | r1=setup=3591ms, completed=40/40, frames=1 ; r2=setup=4140ms, completed=40/40, frames=1 ; r3=setup=2441ms, completed=40/40, frames=1

========================================
  Benchmark Summary (13 tests)
========================================
[BENCH] Closure creation | median=87ms | samples=[121,87,154,77,80] | ops=4000 | per-op=21.75us
[BENCH] new Promise(sync resolve) | median=52ms | samples=[54,52,44,47,61] | ops=1000 | per-op=52us
[BENCH] Promise.resolve(value) | median=54ms | samples=[53,53,62,54,77] | ops=1000 | per-op=54us
[BENCH] Scheduler.enqueue+drain | median=230ms | samples=[148,230,261] | ops=5000 | per-op=46us | r1=verified=5000/5000 ; r2=verified=5000/5000 ; r3=verified=5000/5000
[BENCH] then-chain-resolve(depth=1) | median=1105ms | samples=[726,1105,1363] | ops=1000 | per-op=1105us | r1=setup=630ms, completed=1000/1000, frames=1 ; r2=setup=1022ms, completed=1000/1000, frames=1 ; r3=setup=1279ms, completed=1000/1000, frames=1
[BENCH] then-chain-resolve(depth=3) | median=2866ms | samples=[2581,2866,4466] | ops=1000 | per-op=2866us | r1=setup=2375ms, completed=1000/1000, frames=1 ; r2=setup=2642ms, completed=1000/1000, frames=1 ; r3=setup=4242ms, completed=1000/1000, frames=1
[BENCH] then-chain-resolve(depth=10) | median=6988ms | samples=[5517,6988,9973] | ops=400 | per-op=17470us | r1=setup=5204ms, completed=400/400, frames=1 ; r2=setup=6752ms, completed=400/400, frames=1 ; r3=setup=9742ms, completed=400/400, frames=1
[BENCH] Promise.all(size=10) | median=1874ms | samples=[1519,1874,1920] | ops=150 | per-op=12493.33us | r1=setup=1395ms, completed=150/150, frames=1 ; r2=setup=1846ms, completed=150/150, frames=1 ; r3=setup=1892ms, completed=150/150, frames=1
[BENCH] Promise.all(size=50) | median=1617ms | samples=[1617,1667,1517] | ops=80 | per-op=20212.5us | r1=setup=1510ms, completed=80/80, frames=1 ; r2=setup=1601ms, completed=80/80, frames=1 ; r3=setup=1481ms, completed=80/80, frames=1
[BENCH] Promise.all(size=100) | median=1578ms | samples=[1322,1766,1578] | ops=48 | per-op=32875us | r1=setup=1184ms, completed=48/48, frames=1 ; r2=setup=1727ms, completed=48/48, frames=1 ; r3=setup=1526ms, completed=48/48, frames=1
[BENCH] Promise.all(size=500) | median=2052ms | samples=[2052,1971,2374] | ops=12 | per-op=171000us | r1=setup=1919ms, completed=12/12, frames=1 ; r2=setup=1914ms, completed=12/12, frames=1 ; r3=setup=2296ms, completed=12/12, frames=1
[BENCH] long-chain(depth=50) | median=3725ms | samples=[2681,4829,3725] | ops=80 | per-op=46562.5us | r1=setup=2288ms, completed=80/80, frames=1 ; r2=setup=4479ms, completed=80/80, frames=1 ; r3=setup=3532ms, completed=80/80, frames=1
[BENCH] long-chain(depth=100) | median=3856ms | samples=[3856,4291,2613] | ops=40 | per-op=96400us | r1=setup=3591ms, completed=40/40, frames=1 ; r2=setup=4140ms, completed=40/40, frames=1 ; r3=setup=2441ms, completed=40/40, frames=1
========================================
  ALL BENCHMARKS DONE
========================================
