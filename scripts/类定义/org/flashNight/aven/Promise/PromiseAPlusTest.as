import org.flashNight.aven.Promise.Promise;

import org.flashNight.aven.Promise.Scheduler;

/**
 * Promises/A+ 规范合规性测试套件
 *
 * 测试覆盖:
 * - 2.1 Promise 状态
 * - 2.2 then 方法
 * - 2.3 Promise 解析过程
 * - 调度器行为（单帧链解析）
 */
class org.flashNight.aven.Promise.PromiseAPlusTest {

    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _total:Number = 0;
    private static var _clip:MovieClip;
    private static var _frameCount:Number = 0;
    private static var _reported:Boolean = false;
    private static var _timerSeq:Number = 0;

    /** 创建断原型 thenable，覆盖 AS2 proto-null 判空陷阱 */
    private static function createProtoNullThenable(
        shouldReject:Boolean, payload:Object
    ):Object {
        var thenable:Object = {};
        thenable.__proto__ = null;
        thenable["then"] = function(resolvePromise:Function, rejectPromise:Function):Void {
            if (shouldReject) {
                rejectPromise(payload);
            } else {
                resolvePromise(payload);
            }
        };
        return thenable;
    }

    /** 断言工具 */
    private static function assert(testName:String, condition:Boolean, detail:String):Void {
        _total++;
        if (condition) {
            _passed++;
            trace("[PASS] " + testName);
        } else {
            _failed++;
            trace("[FAIL] " + testName + (detail != undefined ? " | " + detail : ""));
        }
    }

    /** 若干帧后执行，用于检测“应该 settle 但卡住了”的场景 */
    private static function afterFrames(frames:Number, fn:Function):Void {
        _timerSeq++;

        var waiter:MovieClip = _root.createEmptyMovieClip(
            "_promiseTestWaiter" + _timerSeq,
            _root.getNextHighestDepth()
        );
        waiter.remainingFrames = frames;
        waiter.onEnterFrame = function():Void {
            this.remainingFrames--;
            if (this.remainingFrames <= 0) {
                delete this.onEnterFrame;
                fn();
                this.removeMovieClip();
            }
        };
    }

    /** 入口 */
    public static function main():Void {
        _passed = 0;
        _failed = 0;
        _total = 0;
        _frameCount = 0;
        _reported = false;
        _timerSeq = 0;

        trace("========================================");
        trace("  Promises/A+ Compliance Test Suite");
        trace("========================================");

        runCoreTests();
        runPhase2Tests();
        runPhase3Tests();

        // --- 帧计数器，等待异步测试完成后输出汇总 ---
        _clip = _root.createEmptyMovieClip("_promiseTestTimer", _root.getNextHighestDepth());
        _clip.onEnterFrame = function():Void {
            org.flashNight.aven.Promise.PromiseAPlusTest._frameCount++;
            if (org.flashNight.aven.Promise.PromiseAPlusTest._frameCount >= 45) {
                org.flashNight.aven.Promise.PromiseAPlusTest.reportResults();
            }
        };
    }

    /** Core A+ 规范测试与第一批生产安全测试 */
    private static function runCoreTests():Void {
        test_2_2_7_thenReturnsPromise();

        test_2_1_stateTransitions();
        test_2_2_1_optionalArguments();
        test_2_2_2_onFulfilledCalledWithValue();
        test_2_2_4_asyncExecution();
        test_2_2_5_calledAtMostOnce();
        test_2_2_6_callbackOrder();
        test_2_2_7_1_chainingValues();
        test_2_2_7_2_chainingThrow();
        test_2_2_7_2_rejectionThrow();
        test_2_2_7_3_valuePropagation();
        test_2_2_7_4_reasonPropagation();
        test_2_3_1_cycleDetection();
        test_2_3_2_promiseAdoption();
        test_2_3_3_thenableHandling();
        test_2_3_3_thenCalledWithThis();
        test_2_3_3_thenGetterAccessedOnce();
        test_2_3_3_throwBeforeResolveRejects();
        test_2_3_3_throwAfterResolveIgnored();
        test_2_3_3_throwAfterRejectIgnored();
        test_2_3_3_protoNullThenable();
        test_2_3_4_plainValueResolve();
        test_staticAll();
        test_staticAllRejects();
        test_staticAllEmpty();
        test_staticRace();
        test_staticRaceEmptyPending();
        test_staticAllSettled();
        test_staticAllSettledEmpty();
        test_executorThrowAfterResolveIgnored();
        test_chainResolutionTiming();
        test_resolveWithThenable();
        test_resolveWithProtoNullThenable();
        test_selfResolutionInExecutorRejects();
        test_multipleThensOnSamePromise();
        test_longChain();
        test_errorRecoveryInChain();
        test_schedulerRecoversAfterClipRemoval();
    }

    /** Phase 2: 扩展生产安全测试 */
    private static function runPhase2Tests():Void {
        test_errorPropagationSkipsFulfilled();
        test_reRejectFromCatch();
        test_nonFunctionThenArgs();
        test_lateThenOnSettled();
        test_resolveExistingPromise();
        test_resolveRejectedPromise();
        test_deepThenableInResolve();
        test_asyncThenable();
        test_thenableNeverSettles();
        test_undefinedReturnInChain();
        test_allWithPlainValues();
        test_allFirstRejectionWins();
        test_nestedPromiseAll();
        test_onFinallyFulfilled();
        test_onFinallyRejected();
        test_onFinallyThrowOverrides();
        test_onFinallyAsync();
        test_largeBatchAll();
        test_complexErrorRecovery();
        test_raceImmediateVsDelayed();
        test_resolveNullInChain();
        test_multipleOnRejected();
    }

    /** Phase 3: 生产健壮性强化测试 */
    private static function runPhase3Tests():Void {
        test_catchRecoverWithFulfilledPromise();
        test_onRejectedReturnsUndefined();
        test_handlerReturnsFunction();
        test_allWithThenables();
        test_raceAllSyncValues();
        test_thenNoArgs();
        test_onFinallyNonFunction();
        test_nestedThenInsideThen();
        test_deferredForkTwoChains();
        test_superLongChain100();
        test_resolveNoArg();
        test_rejectInOnFulfilledChain();
        test_catchThenFinally();
        test_allSingleReject();
        test_raceWithThenable();
        test_schedulerTickManualDrain();
        test_schedulerBindToExternalDriven();
        test_schedulerFallbackToClip();
        test_schedulerUnbindPausesThenFallback();
    }

    /** 输出汇总 */
    private static function reportResults():Void {
        if (_reported) return;
        _reported = true;
        delete _clip.onEnterFrame;

        trace("");
        trace("========================================");
        trace("  Test Results: " + _passed + "/" + _total + " passed, " + _failed + " failed");
        if (_failed == 0) {
            trace("  ALL PASSED");
        } else {
            trace("  SOME TESTS FAILED");
        }
        trace("========================================");
    }

    // ================================================================
    // 2.1 Promise States
    // ================================================================

    /** 2.1: 状态只能从 pending 变为 fulfilled 或 rejected，且不可逆 */
    private static function test_2_1_stateTransitions():Void {
        // 多次 resolve 只取第一个值
        var p1:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve("first");
            resolve("second");
            reject("should-not");
        });
        p1.then(function(v:Object):Void {
            assert("2.1-resolve-once", v == "first", "got: " + v);
        });

        // 多次 reject 只取第一个
        var p2:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            reject("firstErr");
            reject("secondErr");
            resolve("should-not");
        });
        p2.then(null, function(r:Object):Void {
            assert("2.1-reject-once", r == "firstErr", "got: " + r);
        });
    }

    // ================================================================
    // 2.2 The then Method
    // ================================================================

    /** 2.2.1: onFulfilled/onRejected 是可选参数 */
    private static function test_2_2_1_optionalArguments():Void {
        // 没有 onFulfilled 时 value 应该穿透
        Promise.resolve(42).then(null).then(function(v:Object):Void {
            assert("2.2.1-fulfill-passthrough", v == 42, "got: " + v);
        });

        // 没有 onRejected 时 reason 应该穿透
        Promise.reject("err42").then(null).then(null, function(r:Object):Void {
            assert("2.2.1-reject-passthrough", r == "err42", "got: " + r);
        });
    }

    /** 2.2.2: onFulfilled 必须以 promise 的 value 为参数调用 */
    private static function test_2_2_2_onFulfilledCalledWithValue():Void {
        Promise.resolve("hello").then(function(v:Object):Void {
            assert("2.2.2-value-arg", v == "hello", "got: " + v);
        });
    }

    /** 2.2.4: onFulfilled/onRejected 必须异步执行 */
    private static function test_2_2_4_asyncExecution():Void {
        var marker:Object = {val: false};

        // 测试 fulfilled 路径的异步性
        Promise.resolve("async").then(function(v:Object):Void {
            assert("2.2.4-async-fulfilled", marker.val == true,
                "callback ran synchronously, marker.val=" + marker.val);
        });
        marker.val = true;

        // 测试 rejected 路径的异步性
        var marker2:Object = {val: false};
        Promise.reject("asyncErr").then(null, function(r:Object):Void {
            assert("2.2.4-async-rejected", marker2.val == true,
                "callback ran synchronously, marker2.val=" + marker2.val);
        });
        marker2.val = true;
    }

    /** 2.2.5: onFulfilled/onRejected 最多被调用一次 */
    private static function test_2_2_5_calledAtMostOnce():Void {
        var callCount:Object = {n: 0};
        var p:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve("once");
            resolve("twice"); // should be ignored
        });
        p.then(function(v:Object):Void {
            callCount.n++;
        });

        // 用 Promise 链延迟检查（不依赖 setInterval）
        Promise.resolve(null).then(function(v:Object):Void {
            assert("2.2.5-called-once", callCount.n == 1, "called " + callCount.n + " times");
        });
    }

    /** 2.2.6: 多次 then 的回调必须按注册顺序执行 */
    private static function test_2_2_6_callbackOrder():Void {
        var deferred:Object = {};
        var order:Object = {fulfilled: "", rejected: ""};

        var p1:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            deferred.fulfill = resolve;
        });
        p1.then(function(v:Object):Void { order.fulfilled += "A"; });
        p1.then(function(v:Object):Void { order.fulfilled += "B"; });
        p1.then(function(v:Object):Void {
            order.fulfilled += "C";
            assert("2.2.6-fulfilled-order", order.fulfilled == "ABC", "got: " + order.fulfilled);
        });

        var p2:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            deferred.reject = reject;
        });
        p2.then(null, function(r:Object):Void { order.rejected += "X"; });
        p2.then(null, function(r:Object):Void { order.rejected += "Y"; });
        p2.then(null, function(r:Object):Void {
            order.rejected += "Z";
            assert("2.2.6-rejected-order", order.rejected == "XYZ", "got: " + order.rejected);
        });

        Promise.resolve(null).then(function(v:Object):Void {
            deferred.fulfill("done");
            deferred.reject("fail");
        });
    }

    /** 2.2.7: then 必须返回一个 promise */
    private static function test_2_2_7_thenReturnsPromise():Void {
        var p:Promise = Promise.resolve(1);
        var p2:Object = p.then(null);
        assert("2.2.7-returns-promise", p2 instanceof Promise, "typeof: " + typeof(p2));
    }

    /** 2.2.7.1: onFulfilled 返回值 x 用于 resolve promise2 */
    private static function test_2_2_7_1_chainingValues():Void {
        Promise.resolve(1)
            .then(function(v:Object):Object { return Number(v) + 10; })
            .then(function(v:Object):Object { return Number(v) * 2; })
            .then(function(v:Object):Void {
                assert("2.2.7.1-chain-values", v == 22, "got: " + v);
            });
    }

    /** 2.2.7.2: onFulfilled 抛出异常 e，promise2 以 e 为 reason reject */
    private static function test_2_2_7_2_chainingThrow():Void {
        Promise.resolve(1)
            .then(function(v:Object):Object {
                throw new Error("chain-error");
                return null; // unreachable
            })
            .then(
                function(v:Object):Void {
                    assert("2.2.7.2-chain-throw", false, "should not fulfill");
                },
                function(r:Object):Void {
                    assert("2.2.7.2-chain-throw", r.message == "chain-error", "got: " + r);
                }
            );
    }

    /** 2.2.7.2: onRejected 抛出异常时，promise2 必须以该异常 reject */
    private static function test_2_2_7_2_rejectionThrow():Void {
        Promise.reject("initial-reason")
            .then(null, function(r:Object):Object {
                throw new Error("reject-handler-error");
                return null;
            })
            .then(
                function(v:Object):Void {
                    assert("2.2.7.2-rejection-throw", false, "should not fulfill");
                },
                function(r:Object):Void {
                    assert("2.2.7.2-rejection-throw",
                        r.message == "reject-handler-error",
                        "got: " + r);
                }
            );
    }

    /** 2.2.7.3: onFulfilled 非函数时，promise2 以 promise1 的 value fulfill */
    private static function test_2_2_7_3_valuePropagation():Void {
        Promise.resolve(99)
            .then(null) // no onFulfilled
            .then(function(v:Object):Void {
                assert("2.2.7.3-value-propagation", v == 99, "got: " + v);
            });
    }

    /** 2.2.7.4: onRejected 非函数时，promise2 以 promise1 的 reason reject */
    private static function test_2_2_7_4_reasonPropagation():Void {
        Promise.reject("propagate-reason")
            .then(function(v:Object):Void {
                assert("2.2.7.4-reason-propagation", false, "should not fulfill");
            })
            .then(null, function(r:Object):Void {
                assert("2.2.7.4-reason-propagation", r == "propagate-reason", "got: " + r);
            });
    }

    // ================================================================
    // 2.3 The Promise Resolution Procedure
    // ================================================================

    /** 2.3.1: promise2 === x 时 reject TypeError */
    private static function test_2_3_1_cycleDetection():Void {
        var p2:Promise;
        p2 = Promise.resolve("start").then(function(v:Object):Object {
            return p2; // cycle!
        });
        p2.then(
            function(v:Object):Void {
                assert("2.3.1-cycle-detection", false, "should not fulfill");
            },
            function(r:Object):Void {
                var msg:String = (r instanceof Error) ? r.message : String(r);
                assert("2.3.1-cycle-detection", msg.indexOf("cycle") >= 0, "got: " + msg);
            }
        );
    }

    /** 2.3.2: x 是 Promise 时，采纳其状态 */
    private static function test_2_3_2_promiseAdoption():Void {
        // onFulfilled 返回一个 fulfilled Promise
        Promise.resolve(1).then(function(v:Object):Object {
            return Promise.resolve("adopted-value");
        }).then(function(v:Object):Void {
            assert("2.3.2-adopt-fulfilled", v == "adopted-value", "got: " + v);
        });

        // onFulfilled 返回一个 rejected Promise
        Promise.resolve(1).then(function(v:Object):Object {
            return Promise.reject("adopted-reason");
        }).then(
            function(v:Object):Void {
                assert("2.3.2-adopt-rejected", false, "should not fulfill");
            },
            function(r:Object):Void {
                assert("2.3.2-adopt-rejected", r == "adopted-reason", "got: " + r);
            }
        );

        // onFulfilled 返回一个 pending Promise（异步 resolve）
        Promise.resolve(1).then(function(v:Object):Object {
            return new Promise(function(resolve:Function, reject:Function):Void {
                var tid:Number = setInterval(function():Void {
                    clearInterval(tid);
                    resolve("async-adopted");
                }, 200);
            });
        }).then(function(v:Object):Void {
            assert("2.3.2-adopt-pending", v == "async-adopted", "got: " + v);
        });
    }

    /** 2.3.3: x 是含 then 方法的对象（thenable） */
    private static function test_2_3_3_thenableHandling():Void {
        // 2.3.3.3: then 是函数，以 x 为 this 调用
        Promise.resolve(1).then(function(v:Object):Object {
            return {
                then: function(resolvePromise:Function, rejectPromise:Function):Void {
                    resolvePromise("thenable-resolved");
                }
            };
        }).then(function(v:Object):Void {
            assert("2.3.3-thenable-resolve", v == "thenable-resolved", "got: " + v);
        });

        // 2.3.3.3.2: thenable 的 then 调用 rejectPromise
        Promise.resolve(1).then(function(v:Object):Object {
            return {
                then: function(resolvePromise:Function, rejectPromise:Function):Void {
                    rejectPromise("thenable-rejected");
                }
            };
        }).then(null, function(r:Object):Void {
            assert("2.3.3-thenable-reject", r == "thenable-rejected", "got: " + r);
        });

        // 2.3.3.3.3: 多次调用 resolvePromise，只取第一个
        Promise.resolve(1).then(function(v:Object):Object {
            return {
                then: function(resolvePromise:Function, rejectPromise:Function):Void {
                    resolvePromise("first-call");
                    resolvePromise("second-call");
                    rejectPromise("should-ignore");
                }
            };
        }).then(function(v:Object):Void {
            assert("2.3.3.3.3-first-wins", v == "first-call", "got: " + v);
        });

        // 2.3.3.3.1: resolvePromise 传入 thenable y，递归解析
        Promise.resolve(1).then(function(v:Object):Object {
            return {
                then: function(resolvePromise:Function, rejectPromise:Function):Void {
                    // 返回另一个 thenable
                    resolvePromise({
                        then: function(res2:Function, rej2:Function):Void {
                            res2("nested-thenable-value");
                        }
                    });
                }
            };
        }).then(function(v:Object):Void {
            assert("2.3.3.3.1-recursive-thenable", v == "nested-thenable-value", "got: " + v);
        });

        // 2.3.3.4: then 不是函数，直接 fulfill
        Promise.resolve(1).then(function(v:Object):Object {
            return { then: 42 }; // then is not a function
        }).then(function(v:Object):Void {
            assert("2.3.3.4-then-not-function", v.then == 42, "got: " + v);
        });

        // 2.3.3.2: 获取 then 时抛出异常
        Promise.resolve(1).then(function(v:Object):Object {
            var obj:Object = {};
            obj.addProperty("then", function():Object {
                throw new Error("then-getter-throws");
                return undefined;
            }, null);
            return obj;
        }).then(
            function(v:Object):Void {
                assert("2.3.3.2-then-getter-throws", false, "should not fulfill");
            },
            function(r:Object):Void {
                assert("2.3.3.2-then-getter-throws",
                    r instanceof Error,
                    "got: " + r);
            }
        );
    }

    /** 2.3.3.3: then 应以 x 作为 this 调用 */
    private static function test_2_3_3_thenCalledWithThis():Void {
        var thenable:Object = {
            marker: "self",
            then: function(resolvePromise:Function, rejectPromise:Function):Void {
                resolvePromise(this.marker);
            }
        };

        Promise.resolve("seed").then(function(v:Object):Object {
            return thenable;
        }).then(function(v:Object):Void {
            assert("2.3.3-this-binding", v == "self", "got: " + v);
        });
    }

    /** 2.3.3.1/2.3.3.2: then 属性应只读取一次 */
    private static function test_2_3_3_thenGetterAccessedOnce():Void {
        var getterState:Object = {count: 0};

        Promise.resolve("seed").then(function(v:Object):Object {
            var thenable:Object = {};
            thenable.addProperty("then", function():Object {
                getterState.count++;
                return function(resolvePromise:Function, rejectPromise:Function):Void {
                    resolvePromise("getter-once");
                };
            }, null);
            return thenable;
        }).then(function(v:Object):Void {
            assert("2.3.3-then-getter-once-value", v == "getter-once", "got: " + v);
            assert("2.3.3-then-getter-once-count", getterState.count == 1,
                "getter invoked " + getterState.count + " times");
        });
    }

    /** 2.3.3.3.4: then 在 settle 前抛异常，应以该异常 reject */
    private static function test_2_3_3_throwBeforeResolveRejects():Void {
        Promise.resolve("seed").then(function(v:Object):Object {
            return {
                then: function(resolvePromise:Function, rejectPromise:Function):Void {
                    throw new Error("throw-before-settle");
                }
            };
        }).then(
            function(v:Object):Void {
                assert("2.3.3-throw-before-settle", false, "should not fulfill");
            },
            function(r:Object):Void {
                assert("2.3.3-throw-before-settle",
                    r.message == "throw-before-settle", "got: " + r);
            }
        );
    }

    /** 2.3.3.3.3: resolvePromise 已调用后，再抛异常必须被忽略 */
    private static function test_2_3_3_throwAfterResolveIgnored():Void {
        Promise.resolve("seed").then(function(v:Object):Object {
            return {
                then: function(resolvePromise:Function, rejectPromise:Function):Void {
                    resolvePromise("resolved-before-throw");
                    throw new Error("late-then-throw");
                }
            };
        }).then(
            function(v:Object):Void {
                assert("2.3.3-throw-after-resolve", v == "resolved-before-throw", "got: " + v);
            },
            function(r:Object):Void {
                assert("2.3.3-throw-after-resolve", false, "should ignore late throw: " + r);
            }
        );
    }

    /** 2.3.3.3.3: rejectPromise 已调用后，再抛异常必须被忽略 */
    private static function test_2_3_3_throwAfterRejectIgnored():Void {
        Promise.resolve("seed").then(function(v:Object):Object {
            return {
                then: function(resolvePromise:Function, rejectPromise:Function):Void {
                    rejectPromise("rejected-before-throw");
                    throw new Error("late-throw-after-reject");
                }
            };
        }).then(
            function(v:Object):Void {
                assert("2.3.3-throw-after-reject", false, "should not fulfill");
            },
            function(r:Object):Void {
                assert("2.3.3-throw-after-reject",
                    r == "rejected-before-throw", "got: " + r);
            }
        );
    }

    /** 2.3.3: proto-null thenable 也必须被识别并解包 */
    private static function test_2_3_3_protoNullThenable():Void {
        Promise.resolve("seed").then(function(v:Object):Object {
            return createProtoNullThenable(false, "proto-null-fulfilled");
        }).then(function(v:Object):Void {
            assert("2.3.3-proto-null-thenable", v == "proto-null-fulfilled", "got: " + v);
        });

        Promise.resolve("seed").then(function(v:Object):Object {
            return createProtoNullThenable(true, "proto-null-rejected");
        }).then(
            function(v:Object):Void {
                assert("2.3.3-proto-null-thenable-reject", false, "should not fulfill");
            },
            function(r:Object):Void {
                assert("2.3.3-proto-null-thenable-reject",
                    r == "proto-null-rejected", "got: " + r);
            }
        );
    }

    /** 2.3.4: x 不是对象也不是函数，直接 fulfill */
    private static function test_2_3_4_plainValueResolve():Void {
        // Number
        Promise.resolve(1).then(function(v:Object):Object {
            return 42;
        }).then(function(v:Object):Void {
            assert("2.3.4-number", v == 42, "got: " + v);
        });

        // String
        Promise.resolve(1).then(function(v:Object):Object {
            return "hello";
        }).then(function(v:Object):Void {
            assert("2.3.4-string", v == "hello", "got: " + v);
        });

        // Boolean
        Promise.resolve(1).then(function(v:Object):Object {
            return true;
        }).then(function(v:Object):Void {
            assert("2.3.4-boolean", v == true, "got: " + v);
        });

        // null
        Promise.resolve(1).then(function(v:Object):Object {
            return null;
        }).then(function(v:Object):Void {
            assert("2.3.4-null", v == null && v !== undefined, "got: " + v);
        });

        // undefined
        Promise.resolve(1).then(function(v:Object):Void {
            // implicit return undefined
        }).then(function(v:Object):Void {
            assert("2.3.4-undefined", typeof(v) == "undefined", "got: " + v);
        });
    }

    // ================================================================
    // 非 A+ 但库已公开的静态组合器
    // ================================================================

    private static function test_staticAll():Void {
        var slow:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var tid:Number = setInterval(function():Void {
                clearInterval(tid);
                resolve("A");
            }, 40);
        });

        Promise.all([slow, Promise.resolve("B"), "C"]).then(
            function(values:Array):Void {
                var ok:Boolean = values.length == 3
                    && values[0] == "A"
                    && values[1] == "B"
                    && values[2] == "C";
                assert("static-all-order", ok, "got: " + values);
            },
            function(reason:Object):Void {
                assert("static-all-order", false, "should not reject: " + reason);
            }
        );
    }

    private static function test_staticAllRejects():Void {
        Promise.all([Promise.resolve("ok"), Promise.reject("boom"), Promise.resolve("later")]).then(
            function(values:Array):Void {
                assert("static-all-reject", false, "should not fulfill");
            },
            function(reason:Object):Void {
                assert("static-all-reject", reason == "boom", "got: " + reason);
            }
        );
    }

    private static function test_staticAllEmpty():Void {
        Promise.all([]).then(function(values:Array):Void {
            assert("static-all-empty", values.length == 0, "got length=" + values.length);
        });
    }

    private static function test_staticRace():Void {
        var fastReject:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var tid:Number = setInterval(function():Void {
                clearInterval(tid);
                reject("race-boom");
            }, 20);
        });
        var slowResolve:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var tid:Number = setInterval(function():Void {
                clearInterval(tid);
                resolve("race-late");
            }, 60);
        });

        Promise.race([slowResolve, fastReject]).then(
            function(value:Object):Void {
                assert("static-race-first-settled", false, "should reject first, got: " + value);
            },
            function(reason:Object):Void {
                assert("static-race-first-settled", reason == "race-boom", "got: " + reason);
            }
        );
    }

    private static function test_staticRaceEmptyPending():Void {
        var settled:Object = {value: false};

        Promise.race([]).then(
            function(value:Object):Void {
                settled.value = true;
            },
            function(reason:Object):Void {
                settled.value = true;
            }
        );

        afterFrames(4, function():Void {
            assert("static-race-empty-pending", settled.value == false,
                "empty race should stay pending");
        });
    }

    private static function test_staticAllSettled():Void {
        Promise.allSettled([Promise.resolve("ok"), Promise.reject("no")]).then(function(results:Array):Void {
            var ok:Boolean = results.length == 2
                && results[0].status == "fulfilled"
                && results[0].value == "ok"
                && results[1].status == "rejected"
                && results[1].reason == "no";
            assert("static-allSettled-mixed", ok, "got: " + results);
        });
    }

    private static function test_staticAllSettledEmpty():Void {
        Promise.allSettled([]).then(function(results:Array):Void {
            assert("static-allSettled-empty", results.length == 0, "got length=" + results.length);
        });
    }

    /** executor 在 resolve 后再抛异常，不得覆盖既有结果 */
    private static function test_executorThrowAfterResolveIgnored():Void {
        new Promise(function(resolve:Function, reject:Function):Void {
            resolve("settled-first");
            throw new Error("late-executor-throw");
        }).then(
            function(v:Object):Void {
                assert("executor-throw-after-resolve", v == "settled-first", "got: " + v);
            },
            function(r:Object):Void {
                assert("executor-throw-after-resolve", false, "should ignore late throw: " + r);
            }
        );
    }

    // ================================================================
    // 调度器行为测试
    // ================================================================

    /**
     * 链解析时序测试：验证 Promise 链是否在合理帧数内完成
     * 一个 5 步链应该在几帧内完成，而不是 10+ 帧
     */
    private static function test_chainResolutionTiming():Void {
        var startFrame:Object = {val: org.flashNight.aven.Promise.PromiseAPlusTest._frameCount};

        Promise.resolve(0)
            .then(function(v:Object):Object { return Number(v) + 1; })
            .then(function(v:Object):Object { return Number(v) + 1; })
            .then(function(v:Object):Object { return Number(v) + 1; })
            .then(function(v:Object):Object { return Number(v) + 1; })
            .then(function(v:Object):Object { return Number(v) + 1; })
            .then(function(v:Object):Void {
                var elapsed:Number = org.flashNight.aven.Promise.PromiseAPlusTest._frameCount - startFrame.val;
                assert("chain-timing-value", v == 5, "got: " + v);
                assert("chain-timing-frames", elapsed <= 3,
                    "5-step chain took " + elapsed + " frames (expected <=3)");
            });
    }

    /**
     * resolve(thenable) 测试：构造函数中 resolve 传入 thenable 对象
     * Promises/A+ 要求 resolve 也应解包 thenable
     */
    private static function test_resolveWithThenable():Void {
        // resolve 传入普通 thenable（非 Promise）
        var p:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve({
                then: function(res:Function, rej:Function):Void {
                    res("thenable-in-resolve");
                }
            });
        });
        p.then(function(v:Object):Void {
            // 规范要求解包 thenable，value 应为 "thenable-in-resolve"
            // 如果未解包，v 将是一个含 then 方法的对象
            var isUnwrapped:Boolean = (v == "thenable-in-resolve");
            assert("resolve-thenable-unwrap", isUnwrapped,
                isUnwrapped ? "" : "thenable not unwrapped, got object with then");
        });
    }

    /** 生产入口也必须解包 proto-null thenable */
    private static function test_resolveWithProtoNullThenable():Void {
        Promise.resolve(createProtoNullThenable(false, "proto-null-in-resolve"))
            .then(function(v:Object):Void {
                assert("resolve-proto-null-thenable",
                    v == "proto-null-in-resolve", "got: " + v);
            });

        new Promise(function(resolve:Function, reject:Function):Void {
            resolve(createProtoNullThenable(true, "proto-null-reason"));
        }).then(
            function(v:Object):Void {
                assert("resolve-proto-null-thenable-reject", false, "should not fulfill");
            },
            function(r:Object):Void {
                assert("resolve-proto-null-thenable-reject",
                    r == "proto-null-reason", "got: " + r);
            }
        );
    }

    /** 生产安全：executor 暴露的 resolve 若收到自身 promise，不应永久 pending */
    private static function test_selfResolutionInExecutorRejects():Void {
        var deferred:Object = {};
        var outcome:Object = {state: "pending", detail: null};

        var p:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            deferred.resolve = resolve;
        });

        p.then(
            function(v:Object):Void {
                outcome.state = "fulfilled";
                outcome.detail = v;
                assert("safety-self-resolution", false, "should not fulfill");
            },
            function(r:Object):Void {
                outcome.state = "rejected";
                outcome.detail = r;

                var msg:String = (r instanceof Error) ? r.message : String(r);
                assert("safety-self-resolution",
                    msg.indexOf("self") >= 0 || msg.indexOf("cycle") >= 0,
                    "got: " + msg);
            }
        );

        Promise.resolve(null).then(function(v:Object):Void {
            deferred.resolve(p);
        });

        afterFrames(4, function():Void {
            assert("safety-self-resolution-no-hang", outcome.state == "rejected",
                "state after self resolve: " + outcome.state);
        });
    }

    /** 同一 Promise 多次 then */
    private static function test_multipleThensOnSamePromise():Void {
        var p:Promise = Promise.resolve("shared");
        var results:Object = {a: null, b: null, c: null};

        p.then(function(v:Object):Void { results.a = v; });
        p.then(function(v:Object):Void { results.b = v; });
        p.then(function(v:Object):Void {
            results.c = v;
            // 在最后一个回调中检查所有结果
            assert("multiple-then-a", results.a == "shared", "a=" + results.a);
            assert("multiple-then-b", results.b == "shared", "b=" + results.b);
            assert("multiple-then-c", results.c == "shared", "c=" + results.c);
        });
    }

    /** 长链测试（10 步） */
    private static function test_longChain():Void {
        var p:Promise = Promise.resolve(0);
        var steps:Number = 10;
        for (var i:Number = 0; i < steps; i++) {
            p = p.then(function(v:Object):Object {
                return Number(v) + 1;
            });
        }
        p.then(function(v:Object):Void {
            assert("long-chain-10", v == 10, "got: " + v);
        });
    }

    /** 错误恢复链测试 */
    private static function test_errorRecoveryInChain():Void {
        Promise.resolve(1)
            .then(function(v:Object):Object {
                throw new Error("deliberate");
                return null;
            })
            .then(
                function(v:Object):Void {
                    // should not be called
                },
                function(r:Object):Object {
                    // recover from error
                    return "recovered";
                }
            )
            .then(function(v:Object):Void {
                assert("error-recovery", v == "recovered", "got: " + v);
            });
    }

    /** 生产安全：调度 clip 被删除后，Scheduler 应能自愈 */
    private static function test_schedulerRecoversAfterClipRemoval():Void {
        Scheduler.getInstance();

        if (_root._promiseScheduler != undefined) {
            _root._promiseScheduler.removeMovieClip();
        }

        var fired:Object = {done: false, value: null};
        Promise.resolve("scheduler-recovered").then(function(v:Object):Void {
            fired.done = true;
            fired.value = v;
            assert("safety-scheduler-recovery-value", v == "scheduler-recovered", "got: " + v);
        });

        afterFrames(4, function():Void {
            assert("safety-scheduler-recovery-fires", fired.done == true,
                "callback stalled after scheduler clip removal");
        });
    }

    // ================================================================
    // Phase 2: 扩展生产安全测试
    // ================================================================

    /** P1: reject 穿越多个无 onRejected 的 then，跳过所有 onFulfilled */
    private static function test_errorPropagationSkipsFulfilled():Void {
        var calls:Object = {a: false, b: false};
        Promise.reject("err-propagate")
            .then(function(v:Object):Void { calls.a = true; })
            .then(function(v:Object):Void { calls.b = true; })
            .then(null, function(r:Object):Void {
                assert("propagation-skips-a", calls.a == false, "handler A was called");
                assert("propagation-skips-b", calls.b == false, "handler B was called");
                assert("propagation-reason", r == "err-propagate", "got: " + r);
            });
    }

    /** P2: catch handler 返回 rejected Promise 继续传播 rejection */
    private static function test_reRejectFromCatch():Void {
        Promise.reject("original")
            .then(null, function(r:Object):Object {
                return Promise.reject("re-rejected");
            })
            .then(
                function(v:Object):Void {
                    assert("re-reject-from-catch", false, "should not fulfill");
                },
                function(r:Object):Void {
                    assert("re-reject-from-catch", r == "re-rejected", "got: " + r);
                }
            );
    }

    /** P3: then() 接收非函数参数时应透传 value/reason */
    private static function test_nonFunctionThenArgs():Void {
        // 传入 number 作为 onFulfilled — 用 Function 变量绕过编译器类型检查
        var notAFunc:Function = Function(42);
        Promise.resolve("pass-through").then(notAFunc).then(function(v:Object):Void {
            assert("non-func-fulfill-passthrough", v == "pass-through", "got: " + v);
        });

        // 传入 string 作为 onRejected
        var notAFunc2:Function = Function("not a function");
        Promise.reject("pass-err").then(null, notAFunc2).then(null, function(r:Object):Void {
            assert("non-func-reject-passthrough", r == "pass-err", "got: " + r);
        });
    }

    /** P4: 已 settled 的 promise，多帧后调用 then 仍能正确触发 */
    private static function test_lateThenOnSettled():Void {
        var p:Promise = Promise.resolve("late-value");
        var result:Object = {called: false};

        afterFrames(8, function():Void {
            p.then(function(v:Object):Void {
                result.called = true;
                assert("late-then-value", v == "late-value", "got: " + v);
            });
        });

        afterFrames(15, function():Void {
            assert("late-then-fired", result.called == true, "callback never fired");
        });
    }

    /** P5: Promise.resolve(existingPromise) 返回同一实例或等价结果 */
    private static function test_resolveExistingPromise():Void {
        var original:Promise = Promise.resolve("existing");
        var wrapped:Promise = Promise.resolve(original);
        // 优化后应返回同一实例
        assert("resolve-same-instance", wrapped === original,
            "Promise.resolve should return same instance");
        wrapped.then(function(v:Object):Void {
            assert("resolve-existing-value", v == "existing", "got: " + v);
        });
    }

    /** P6: Promise.resolve(rejectedPromise) 应保持 rejected 状态 */
    private static function test_resolveRejectedPromise():Void {
        var rejected:Promise = Promise.reject("kept-error");
        var wrapped:Promise = Promise.resolve(rejected);
        wrapped.then(
            function(v:Object):Void {
                assert("resolve-rejected-passthrough", false, "should not fulfill");
            },
            function(r:Object):Void {
                assert("resolve-rejected-passthrough", r == "kept-error", "got: " + r);
            }
        );
    }

    /** P7: 构造函数中 resolve(thenable(thenable(value)))，3 层解包 */
    private static function test_deepThenableInResolve():Void {
        var p:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve({
                then: function(res:Function, rej:Function):Void {
                    res({
                        then: function(res2:Function, rej2:Function):Void {
                            res2("deep-three-levels");
                        }
                    });
                }
            });
        });
        p.then(function(v:Object):Void {
            assert("deep-thenable-resolve", v == "deep-three-levels", "got: " + v);
        });
    }

    /** P8: thenable 异步调用 resolvePromise */
    private static function test_asyncThenable():Void {
        Promise.resolve("seed").then(function(v:Object):Object {
            return {
                then: function(resolvePromise:Function, rejectPromise:Function):Void {
                    var tid:Number = setInterval(function():Void {
                        clearInterval(tid);
                        resolvePromise("async-thenable-value");
                    }, 50);
                }
            };
        }).then(function(v:Object):Void {
            assert("async-thenable", v == "async-thenable-value", "got: " + v);
        });
    }

    /** P9: thenable 永不 settle → 下游 promise 保持 pending */
    private static function test_thenableNeverSettles():Void {
        var settled:Object = {value: false};

        Promise.resolve("seed").then(function(v:Object):Object {
            return {
                then: function(resolvePromise:Function, rejectPromise:Function):Void {
                    // 永不调用 resolvePromise 或 rejectPromise
                }
            };
        }).then(
            function(v:Object):Void { settled.value = true; },
            function(r:Object):Void { settled.value = true; }
        );

        afterFrames(6, function():Void {
            assert("thenable-never-settles", settled.value == false,
                "should stay pending when thenable never resolves");
        });
    }

    /** P10: 链中 handler 返回 undefined（无 return 语句） */
    private static function test_undefinedReturnInChain():Void {
        Promise.resolve("start")
            .then(function(v:Object):Void {
                // 无 return，AS2 返回 undefined
            })
            .then(function(v:Object):Void {
                assert("undefined-chain", typeof(v) == "undefined",
                    "expected undefined, got: " + typeof(v) + " " + v);
            });
    }

    /** P11: Promise.all 接受纯值（非 Promise） */
    private static function test_allWithPlainValues():Void {
        Promise.all(["hello", 42, true]).then(function(values:Array):Void {
            var ok:Boolean = values.length == 3
                && values[0] == "hello"
                && values[1] == 42
                && values[2] == true;
            assert("all-plain-values", ok, "got: " + values);
        });
    }

    /** P12: Promise.all 多个 reject 只取第一个 */
    private static function test_allFirstRejectionWins():Void {
        var d1:Object = {};
        var d2:Object = {};

        var p1:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            d1.reject = reject;
        });
        var p2:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            d2.reject = reject;
        });

        Promise.all([p1, p2]).then(
            function(v:Object):Void {
                assert("all-first-reject-wins", false, "should not fulfill");
            },
            function(r:Object):Void {
                assert("all-first-reject-wins", r == "first-rejection", "got: " + r);
            }
        );

        Promise.resolve(null).then(function(v:Object):Void {
            d1.reject("first-rejection");
            d2.reject("second-rejection");
        });
    }

    /** P13: 嵌套 Promise.all */
    private static function test_nestedPromiseAll():Void {
        var inner:Promise = Promise.all([Promise.resolve("a"), Promise.resolve("b")]);
        var outer:Promise = Promise.all([inner, Promise.resolve("c")]);

        outer.then(function(values:Array):Void {
            var innerValues:Array = values[0];
            var ok:Boolean = innerValues.length == 2
                && innerValues[0] == "a"
                && innerValues[1] == "b"
                && values[1] == "c";
            assert("nested-all", ok,
                "inner=[" + innerValues + "] outer[1]=" + values[1]);
        });
    }

    /** P14: onFinally 在 fulfilled 时调用，value 透传 */
    private static function test_onFinallyFulfilled():Void {
        var finallyCalled:Object = {value: false};

        Promise.resolve("fin-value")
            .onFinally(function():Void {
                finallyCalled.value = true;
            })
            .then(function(v:Object):Void {
                assert("finally-fulfilled-called", finallyCalled.value == true,
                    "finally not called");
                assert("finally-fulfilled-value", v == "fin-value", "got: " + v);
            });
    }

    /** P15: onFinally 在 rejected 时调用，reason 透传 */
    private static function test_onFinallyRejected():Void {
        var finallyCalled:Object = {value: false};

        Promise.reject("fin-error")
            .onFinally(function():Void {
                finallyCalled.value = true;
            })
            .then(null, function(r:Object):Void {
                assert("finally-rejected-called", finallyCalled.value == true,
                    "finally not called");
                assert("finally-rejected-reason", r == "fin-error", "got: " + r);
            });
    }

    /** P16: onFinally 中 throw 覆盖原始结果 */
    private static function test_onFinallyThrowOverrides():Void {
        Promise.resolve("original")
            .onFinally(function():Void {
                throw new Error("finally-error");
            })
            .then(
                function(v:Object):Void {
                    assert("finally-throw-overrides", false, "should not fulfill");
                },
                function(r:Object):Void {
                    assert("finally-throw-overrides",
                        r.message == "finally-error", "got: " + r);
                }
            );
    }

    /** P17: onFinally 返回 async Promise，等待后再透传值 */
    private static function test_onFinallyAsync():Void {
        var order:Object = {log: ""};

        Promise.resolve("val")
            .onFinally(function():Object {
                order.log += "F";
                return new Promise(function(resolve:Function, reject:Function):Void {
                    var tid:Number = setInterval(function():Void {
                        clearInterval(tid);
                        order.log += "A";
                        resolve(null);
                    }, 50);
                });
            })
            .then(function(v:Object):Void {
                order.log += "T";
                assert("finally-async-order", order.log == "FAT",
                    "got: " + order.log);
                assert("finally-async-value", v == "val", "got: " + v);
            });
    }

    /** P18: 大批量 Promise.all（50 项） */
    private static function test_largeBatchAll():Void {

        var batch:Array = [];
        for (var i:Number = 0; i < 50; i++) {
            batch.push(Promise.resolve(i));
        }
        Promise.all(batch).then(function(values:Array):Void {
            var ok:Boolean = values.length == 50
                && values[0] == 0
                && values[49] == 49;
            assert("large-batch-all", ok,
                "length=" + values.length + " [0]=" + values[0] + " [49]=" + values[49]);
        });
    }

    /** P19: 复杂 throw → 跳过 → catch 恢复 → 继续链 */
    private static function test_complexErrorRecovery():Void {
        Promise.resolve(1)
            .then(function(v:Object):Object {
                throw new Error("step1-error");
                return null;
            })
            .then(function(v:Object):Object {
                return "should-not-reach";
            })
            .onCatch(function(r:Object):Object {
                return "recovered-from-" + r.message;
            })
            .then(function(v:Object):Object {
                return v + "-continued";
            })
            .then(function(v:Object):Void {
                assert("complex-recovery",
                    v == "recovered-from-step1-error-continued", "got: " + v);
            });
    }

    /** P20: race 中 immediate resolve 胜过 delayed reject */
    private static function test_raceImmediateVsDelayed():Void {
        var delayed:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var tid:Number = setInterval(function():Void {
                clearInterval(tid);
                reject("delayed-rejection");
            }, 100);
        });

        Promise.race([Promise.resolve("immediate"), delayed]).then(
            function(v:Object):Void {
                assert("race-immediate-wins", v == "immediate", "got: " + v);
            },
            function(r:Object):Void {
                assert("race-immediate-wins", false, "should not reject: " + r);
            }
        );
    }

    /** P21: 链中返回 null 正确传递 */
    private static function test_resolveNullInChain():Void {

        Promise.resolve("start")
            .then(function(v:Object):Object {

                return null;
            })
            .then(function(v:Object):Void {

                assert("null-in-chain", v === null, "got: " + v + " typeof: " + typeof(v));
            });
    }

    /** P22: 同一 rejected Promise 多次 then(null, handler) */
    private static function test_multipleOnRejected():Void {
        var p:Promise = Promise.reject("shared-err");
        var results:Object = {a: null, b: null};

        p.then(null, function(r:Object):Void { results.a = r; });
        p.then(null, function(r:Object):Void {
            results.b = r;
            assert("multi-reject-a", results.a == "shared-err", "a=" + results.a);
            assert("multi-reject-b", results.b == "shared-err", "b=" + results.b);
        });
    }

    // ================================================================
    // Phase 3: 生产健壮性强化测试
    // ================================================================

    /** P3-1: onRejected 返回 fulfilled Promise → 下游应 fulfill（不是继续 reject） */
    private static function test_catchRecoverWithFulfilledPromise():Void {
        Promise.reject("original-err")
            .then(null, function(r:Object):Object {
                return Promise.resolve("catch-recovered");
            })
            .then(
                function(v:Object):Void {
                    assert("catch-recover-fulfilled", v == "catch-recovered", "got: " + v);
                },
                function(r:Object):Void {
                    assert("catch-recover-fulfilled", false, "should fulfill, not reject: " + r);
                }
            );
    }

    /** P3-2: onRejected 返回 undefined（无 return）→ 下游应 fulfill with undefined */
    private static function test_onRejectedReturnsUndefined():Void {
        Promise.reject("some-err")
            .then(null, function(r:Object):Void {
                // 不 return 任何值
            })
            .then(
                function(v:Object):Void {
                    assert("reject-handler-undefined",
                        typeof(v) == "undefined", "got: " + typeof(v) + " " + v);
                },
                function(r:Object):Void {
                    assert("reject-handler-undefined", false,
                        "should fulfill with undefined, not reject: " + r);
                }
            );
    }

    /** P3-3: handler 返回 Function 对象（typeof "function"，过 isReferenceLike）→ 应直接传递 */
    private static function test_handlerReturnsFunction():Void {
        var myFunc:Function = function():String { return "hello"; };
        Promise.resolve(1).then(function(v:Object):Object {
            return myFunc;
        }).then(function(v:Object):Void {
            assert("handler-returns-function",
                typeof(v) == "function" && v === myFunc,
                "got typeof: " + typeof(v));
        });
    }

    /** P3-4: Promise.all 接收 thenable（非 Promise 实例）*/
    private static function test_allWithThenables():Void {
        var thenable1:Object = {
            then: function(res:Function, rej:Function):Void { res("t1"); }
        };
        var thenable2:Object = {
            then: function(res:Function, rej:Function):Void { res("t2"); }
        };

        Promise.all([thenable1, Promise.resolve("p1"), thenable2]).then(
            function(values:Array):Void {
                var ok:Boolean = values.length == 3
                    && values[0] == "t1"
                    && values[1] == "p1"
                    && values[2] == "t2";
                assert("all-with-thenables", ok,
                    "[0]=" + values[0] + " [1]=" + values[1] + " [2]=" + values[2]);
            },
            function(r:Object):Void {
                assert("all-with-thenables", false, "should not reject: " + r);
            }
        );
    }

    /** P3-5: Promise.race 全同步立即值 */
    private static function test_raceAllSyncValues():Void {
        Promise.race([Promise.resolve("first"), Promise.resolve("second"), Promise.resolve("third")])
            .then(function(v:Object):Void {
                assert("race-all-sync", v == "first", "got: " + v);
            });
    }

    /** P3-6: then() 无参数调用 → value/reason 应穿透 */
    private static function test_thenNoArgs():Void {
        Promise.resolve("no-arg-val").then().then(function(v:Object):Void {
            assert("then-no-args-fulfill", v == "no-arg-val", "got: " + v);
        });

        Promise.reject("no-arg-err").then().then(null, function(r:Object):Void {
            assert("then-no-args-reject", r == "no-arg-err", "got: " + r);
        });
    }

    /** P3-7: onFinally 传入非函数参数 → value 应透传 */
    private static function test_onFinallyNonFunction():Void {
        Promise.resolve("fin-passthrough")
            .onFinally(Function(42))
            .then(function(v:Object):Void {
                assert("finally-non-func-fulfill", v == "fin-passthrough", "got: " + v);
            });

        Promise.reject("fin-err-passthrough")
            .onFinally(Function(null))
            .then(null, function(r:Object):Void {
                assert("finally-non-func-reject", r == "fin-err-passthrough", "got: " + r);
            });
    }

    /** P3-8: 嵌套 then — handler 内部创建新 Promise 链并返回 */
    private static function test_nestedThenInsideThen():Void {
        Promise.resolve("outer")
            .then(function(v:Object):Object {
                return Promise.resolve("inner-start")
                    .then(function(iv:Object):Object {
                        return iv + "-step1";
                    })
                    .then(function(iv:Object):Object {
                        return iv + "-step2";
                    });
            })
            .then(function(v:Object):Void {
                assert("nested-then-inside-then",
                    v == "inner-start-step1-step2", "got: " + v);
            });
    }

    /** P3-9: deferred promise 分叉出两条独立链，各自独立解析 */
    private static function test_deferredForkTwoChains():Void {
        var deferred:Object = {};
        var p:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            deferred.resolve = resolve;
        });

        var results:Object = {chainA: null, chainB: null};

        // Chain A: 加工
        p.then(function(v:Object):Object {
            return String(v) + "-A";
        }).then(function(v:Object):Void {
            results.chainA = v;
        });

        // Chain B: 不同加工
        p.then(function(v:Object):Object {
            return String(v) + "-B";
        }).then(function(v:Object):Void {
            results.chainB = v;
        });

        // 稍后 resolve
        Promise.resolve(null).then(function(v:Object):Void {
            deferred.resolve("root");
        });

        afterFrames(4, function():Void {
            assert("fork-chain-A", results.chainA == "root-A", "A=" + results.chainA);
            assert("fork-chain-B", results.chainB == "root-B", "B=" + results.chainB);
        });
    }

    /** P3-10: 100 步超长链压力测试 */
    private static function test_superLongChain100():Void {
        var p:Promise = Promise.resolve(0);
        for (var i:Number = 0; i < 100; i++) {
            p = p.then(function(v:Object):Object {
                return Number(v) + 1;
            });
        }
        p.then(function(v:Object):Void {
            assert("super-long-chain-100", v == 100, "got: " + v);
        });
    }

    /** P3-11: Promise.resolve() 无参数 → fulfill with undefined */
    private static function test_resolveNoArg():Void {
        Promise.resolve().then(function(v:Object):Void {
            assert("resolve-no-arg",
                typeof(v) == "undefined", "got: " + typeof(v) + " " + v);
        });
    }

    /** P3-12: onFulfilled 中 throw → 跳过后续 onFulfilled → 被远处 onCatch 捕获 */
    private static function test_rejectInOnFulfilledChain():Void {
        var skipped:Object = {value: false};

        Promise.resolve("start")
            .then(function(v:Object):Object {
                throw new Error("mid-chain-error");
                return null;
            })
            .then(function(v:Object):Object {
                skipped.value = true;
                return "should-not-reach";
            })
            .then(function(v:Object):Object {
                skipped.value = true;
                return "also-should-not-reach";
            })
            .onCatch(function(r:Object):Object {
                return "caught-" + r.message;
            })
            .then(function(v:Object):Void {
                assert("reject-skip-fulfill-chain", skipped.value == false,
                    "intermediate handlers were called");
                assert("reject-far-catch", v == "caught-mid-chain-error", "got: " + v);
            });
    }

    /** P3-13: catch → then → finally 完整生产链 */
    private static function test_catchThenFinally():Void {
        var log:Object = {entries: ""};

        Promise.reject("init-err")
            .onCatch(function(r:Object):Object {
                log.entries += "C";
                return "recovered";
            })
            .then(function(v:Object):Object {
                log.entries += "T";
                return v + "-processed";
            })
            .onFinally(function():Void {
                log.entries += "F";
            })
            .then(function(v:Object):Void {
                assert("catch-then-finally-order", log.entries == "CTF",
                    "got: " + log.entries);
                assert("catch-then-finally-value",
                    v == "recovered-processed", "got: " + v);
            });
    }

    /** P3-14: Promise.all 单个 rejected → 应 reject */
    private static function test_allSingleReject():Void {
        Promise.all([Promise.reject("solo-fail")]).then(
            function(v:Object):Void {
                assert("all-single-reject", false, "should not fulfill");
            },
            function(r:Object):Void {
                assert("all-single-reject", r == "solo-fail", "got: " + r);
            }
        );
    }

    // ================================================================
    // Scheduler 驱动模式测试
    // ================================================================

    /** tick() 手动排空：clip 模式下立即排空，不等帧 */
    private static function test_schedulerTickManualDrain():Void {
        var result:Object = {value: null};
        Promise.resolve("tick-val").then(function(v:Object):Void {
            result.value = v;
        });

        // 不等帧，直接 tick
        Scheduler.getInstance().tick();
        assert("tick-manual-drain", result.value == "tick-val", "got: " + result.value);
    }

    /** bindTo 切换到外部驱动：clip 应被移除，isExternalDriven 应为 true */
    private static function test_schedulerBindToExternalDriven():Void {
        var scheduler:Scheduler = Scheduler.getInstance();
        var unsubCalls:Object = {count: 0};
        var mockBus:Object = {
            subscribe: function(name:String, fn:Function, scope:Object):Void {},
            unsubscribe: function(name:String, fn:Function, scope:Object):Void {
                unsubCalls.count++;
            }
        };

        // 绑定
        scheduler.bindTo(mockBus, "testEvent");
        assert("bindTo-external-flag", scheduler.isExternalDriven() === true, "not external");
        assert("bindTo-driveMode", scheduler.getDriveMode() === 1, "mode=" + scheduler.getDriveMode());
        assert("bindTo-clip-removed", _root._promiseScheduler == undefined
            || _root._promiseScheduler._parent == undefined, "clip still alive");

        // 外部驱动下 Promise 排空需要手动 tick
        var result:Object = {value: null};
        Promise.resolve("external-val").then(function(v:Object):Void {
            result.value = v;
        });
        assert("bindTo-no-auto-drain", result.value == null, "drained without tick");
        scheduler.tick();
        assert("bindTo-tick-drains", result.value == "external-val", "got: " + result.value);

        // rebind 到同一个 bus 的新事件：应先自动退订旧源
        scheduler.bindTo(mockBus, "testEvent2");
        assert("rebind-unsub-old", unsubCalls.count >= 1, "old source not unsubscribed");

        // 还原到 clip 模式
        scheduler.fallbackToClip();
        assert("fallback-unsub", unsubCalls.count >= 2, "external not unsubscribed on fallback");
    }

    /** fallbackToClip 恢复 clip 驱动 */
    private static function test_schedulerFallbackToClip():Void {
        var scheduler:Scheduler = Scheduler.getInstance();
        assert("fallback-not-external", scheduler.isExternalDriven() === false, "still external");
        assert("fallback-driveMode", scheduler.getDriveMode() === 0, "mode=" + scheduler.getDriveMode());

        // 验证 clip 恢复后 Promise 能自然排空
        var fired:Object = {done: false};
        Promise.resolve("fallback-val").then(function(v:Object):Void {
            fired.done = true;
        });

        afterFrames(3, function():Void {
            assert("fallback-fires", fired.done === true, "callback never fired after fallback");
        });
    }

    /** unbind 进入 SUSPENDED：队列累积但不自动排空，等帧验证 */
    private static function test_schedulerUnbindPausesThenFallback():Void {
        var scheduler:Scheduler = Scheduler.getInstance();
        var mockBus:Object = {
            subscribe: function(name:String, fn:Function, scope:Object):Void {},
            unsubscribe: function(name:String, fn:Function, scope:Object):Void {}
        };

        // bind + unbind → SUSPENDED
        scheduler.bindTo(mockBus, "evt");
        scheduler.unbind();
        assert("unbind-suspended", scheduler.getDriveMode() === 2, "mode=" + scheduler.getDriveMode());
        assert("unbind-not-external", scheduler.isExternalDriven() === false, "still external");

        // SUSPENDED 态下入队，不会自动排空
        var result:Object = {value: null};
        Promise.resolve("paused-val").then(function(v:Object):Void {
            result.value = v;
        });

        // 等 3 帧确认不会自动排空（核心：验证 enqueue 不会触发 clip 自愈）
        afterFrames(3, function():Void {
            assert("unbind-no-auto-drain", result.value == null,
                "auto-drained in SUSPENDED: " + result.value);

            // 手动 tick 验证队列数据没丢
            scheduler.tick();
            assert("unbind-tick-recovers", result.value == "paused-val", "got: " + result.value);

            // fallbackToClip 恢复
            scheduler.fallbackToClip();
            assert("unbind-fallback-mode", scheduler.getDriveMode() === 0,
                "mode=" + scheduler.getDriveMode());

            // 验证 clip 驱动恢复
            var fired2:Object = {done: false};
            Promise.resolve("restored").then(function(v:Object):Void {
                fired2.done = true;
            });
            afterFrames(3, function():Void {
                assert("unbind-fallback-restored", fired2.done === true, "clip not restored");
            });
        });
    }

    /** P3-15: Promise.race 含 thenable */
    private static function test_raceWithThenable():Void {
        var slowThenable:Object = {
            then: function(res:Function, rej:Function):Void {
                var tid:Number = setInterval(function():Void {
                    clearInterval(tid);
                    res("slow-thenable");
                }, 200);
            }
        };

        Promise.race([slowThenable, Promise.resolve("fast-promise")]).then(
            function(v:Object):Void {
                assert("race-with-thenable", v == "fast-promise", "got: " + v);
            },
            function(r:Object):Void {
                assert("race-with-thenable", false, "should not reject: " + r);
            }
        );
    }
}
