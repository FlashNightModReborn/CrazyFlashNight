import org.flashNight.aven.Promise.*;
import org.flashNight.neur.Event.*;

/**
 * org.flashNight.aven.Promise.TestPromise
 * 
 * 一个用于测试 org.flashNight.aven.Promise.Promise 类的更全面的测试套件。
 * 包含多种测试用例，确保 Promise 实现更好地符合 Promises/A+ 规范。
 */
class org.flashNight.aven.Promise.TestPromise {
    public static function main():Void {
        
        // ============【 1. 基本功能测试 】====================================
        
        // 1.1 基本成功的 Promise 测试
        var promiseSuccess:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var timerID:Number = setInterval(function():Void {
                clearInterval(timerID);
                resolve("Operation successful");
            }, 1000);
        });

        promiseSuccess.then(
            function(value:Object):Void {
                trace("[promiseSuccess] Success: " + value);
            },
            function(reason:Object):Void {
                trace("[promiseSuccess] Failure: " + reason);
            }
        );

        // 1.2 基本失败的 Promise 测试
        var promiseFailure:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var timerID:Number = setInterval(function():Void {
                clearInterval(timerID);
                reject("Operation failed");
            }, 1000);
        });

        promiseFailure
            .then(function(value:Object):Void {
                trace("[promiseFailure] Success: " + value);
            })
            .onCatch(function(reason:Object):Void {
                trace("[promiseFailure] Caught Error: " + reason);
            });

        // 1.3 Promise 链式调用测试
        var chainedPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(1);
        });

        chainedPromise
            .then(function(value:Object):Object {
                trace("[chainedPromise] First then: " + value);
                return value + 1;
            })
            .then(function(value:Object):Object {
                trace("[chainedPromise] Second then: " + value);
                return value + 1;
            })
            .then(function(value:Object):Void {
                trace("[chainedPromise] Third then: " + value);
            });

        // 1.4 异常捕获测试
        var errorPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            throw new Error("An exception occurred");
        });

        errorPromise.onCatch(function(reason:Object):Void {
            trace("[errorPromise] Exception caught: " + reason.message);
        });

        // 1.5 多次 then 调用测试 (同一 Promise)
        var multipleThenPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve("Resolved once");
        });

        multipleThenPromise.then(function(value:Object):Void {
            trace("[multipleThenPromise] First then: " + value);
        });

        multipleThenPromise.then(function(value:Object):Void {
            trace("[multipleThenPromise] Second then: " + value);
        });

        // 1.6 嵌套 Promise 测试
        var nestedPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(
                new Promise(function(innerResolve:Function, innerReject:Function):Void {
                    innerResolve("Nested promise resolved");
                })
            );
        });

        nestedPromise.then(function(value:Object):Void {
            trace("[nestedPromise] " + value);
        });

        // 1.7 传递 null 值测试
        var nullValuePromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(null);
        });

        nullValuePromise.then(function(value:Object):Void {
            trace("[nullValuePromise] value === null ? " + (value === null));
        });

        // 1.8 传递 undefined 值测试
        var undefinedValuePromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(undefined);
        });

        undefinedValuePromise.then(function(value:Object):Void {
            // AS2 下无法直接比较 undefined，需要 typeof 判断
            var isUndefined:Boolean = (typeof(value) == "undefined");
            trace("[undefinedValuePromise] value === undefined ? " + isUndefined);
        });

        // 1.9 同步和异步混合调用测试
        var mixedPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(5);
        });

        mixedPromise
            .then(function(value:Object):Object {
                trace("[mixedPromise] First then: " + value);
                return new Promise(function(innerResolve:Function, innerReject:Function):Void {
                    var timerID:Number = setInterval(function():Void {
                        clearInterval(timerID);
                        innerResolve(value + 5); // 5 + 5 = 10
                    }, 500);
                });
            })
            .then(function(value:Object):Void {
                trace("[mixedPromise] Second then: " + value);
            });

        // 1.10 多次调用 resolve 和 reject 测试
        var multipleResolveRejectPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve("First resolve");
            reject("Should not affect");
            resolve("Should not affect");
        });

        multipleResolveRejectPromise
            .then(function(value:Object):Void {
                trace("[multipleResolveRejectPromise] " + value);
            })
            .onCatch(function(reason:Object):Void {
                trace("[multipleResolveRejectPromise] Error: " + reason);
            });

        // 1.11 Promise 以另一个 Promise 作为 resolve 值测试
        var promiseWithPromiseValue:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(new Promise(function(innerResolve:Function, innerReject:Function):Void {
                innerResolve("Inner promise resolved");
            }));
        });

        promiseWithPromiseValue.then(function(value:Object):Void {
            trace("[promiseWithPromiseValue] " + value);
        });


        // ============【 2. 静态方法测试 】====================================
        
        // 2.1 Promise.resolve 测试
        var resolvedPromise:Promise = Promise.resolve("Immediate value");
        resolvedPromise.then(function(value:Object):Void {
            trace("[resolvedPromise] " + value);
        });

        // 2.2 Promise.reject 测试
        var rejectedPromise:Promise = Promise.reject("Immediate error");
        rejectedPromise.onCatch(function(reason:Object):Void {
            trace("[rejectedPromise] " + reason);
        });

        // 2.3 Promise.all 成功测试
        var promiseAll1:Promise = Promise.resolve("All 1");
        var promiseAll2:Promise = Promise.resolve("All 2");
        var promiseAll3:Promise = Promise.resolve("All 3");
        Promise.all([promiseAll1, promiseAll2, promiseAll3])
            .then(function(values:Array):Void {
                trace("[promiseAll success] " + values);
            })
            .onCatch(function(reason:Object):Void {
                trace("[promiseAll failure] " + reason);
            });

        // 2.4 Promise.all 失败测试
        var promiseAllFail1:Promise = Promise.resolve("AllFail 1");
        var promiseAllFail2:Promise = Promise.reject("AllFail 2");
        var promiseAllFail3:Promise = Promise.resolve("AllFail 3");
        Promise.all([promiseAllFail1, promiseAllFail2, promiseAllFail3])
            .then(function(values:Array):Void {
                trace("[promiseAll should not resolve]");
            })
            .onCatch(function(reason:Object):Void {
                trace("[promiseAll rejected] " + reason);
            });

        // 2.5 Promise.all 空数组测试
        Promise.all([])
            .then(function(values:Array):Void {
                if (values.length === 0) {
                    trace("[promiseAll empty] Test passed with empty array.");
                } else {
                    trace("[promiseAll empty] Unexpected values: " + values);
                }
            })
            .onCatch(function(reason:Object):Void {
                trace("[promiseAll empty failure] " + reason);
            });

        // 2.6 Promise.race 成功测试
        var promiseRace1:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var timerID:Number = setInterval(function():Void {
                clearInterval(timerID);
                resolve("Race 1 resolved first");
            }, 300);
        });
        var promiseRace2:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var timerID:Number = setInterval(function():Void {
                clearInterval(timerID);
                resolve("Race 2 resolved second");
            }, 500);
        });
        Promise.race([promiseRace1, promiseRace2])
            .then(function(value:Object):Void {
                trace("[promiseRace success] " + value);
            })
            .onCatch(function(reason:Object):Void {
                trace("[promiseRace failure] " + reason);
            });

        // 2.7 Promise.race 失败测试
        var promiseRaceFail1:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var timerID:Number = setInterval(function():Void {
                clearInterval(timerID);
                reject("Race Fail 1 rejected first");
            }, 200);
        });
        var promiseRaceFail2:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var timerID:Number = setInterval(function():Void {
                clearInterval(timerID);
                resolve("Race Fail 2 resolved second");
            }, 400);
        });
        Promise.race([promiseRaceFail1, promiseRaceFail2])
            .then(function(value:Object):Void {
                trace("[promiseRace fail test should not resolve] " + value);
            })
            .onCatch(function(reason:Object):Void {
                trace("[promiseRace fail test rejected] " + reason);
            });

        // 2.8 Promise.race 空数组测试
        Promise.race([])
            .then(function(value:Object):Void {
                trace("[promiseRace empty should not resolve]");
            })
            .onCatch(function(reason:Object):Void {
                trace("[promiseRace empty reject] " + reason);
            });

        // 2.9 Promise.allSettled 测试: 混合成功和失败
        var promiseAllSettled1:Promise = Promise.resolve("AllSettled 1");
        var promiseAllSettled2:Promise = Promise.reject("AllSettled 2");
        var promiseAllSettled3:Promise = Promise.resolve("AllSettled 3");
        Promise.allSettled([promiseAllSettled1, promiseAllSettled2, promiseAllSettled3])
            .then(function(results:Array):Void {
                trace("[promiseAllSettled mix] Results:");
                for (var i:Number = 0; i < results.length; i++) {
                    trace("  -> " + i + " status: " + results[i].status);
                    if (results[i].status == "fulfilled") {
                        trace("  -> value: " + results[i].value);
                    } else {
                        trace("  -> reason: " + results[i].reason);
                    }
                }
            });

        // 2.10 Promise.allSettled 空数组测试
        Promise.allSettled([])
            .then(function(results:Array):Void {
                if (results.length === 0) {
                    trace("[promiseAllSettled empty] Test passed with empty array.");
                } else {
                    trace("[promiseAllSettled empty] Unexpected results: " + results);
                }
            });

        // 2.11 Promise.allSettled 全部成功测试
        var promiseAllSettledAll1:Promise = Promise.resolve("AllSettled All 1");
        var promiseAllSettledAll2:Promise = Promise.resolve("AllSettled All 2");
        Promise.allSettled([promiseAllSettledAll1, promiseAllSettledAll2])
            .then(function(results:Array):Void {
                trace("[promiseAllSettled all success] Results:");
                for (var i:Number = 0; i < results.length; i++) {
                    trace("  -> " + i + " status: " + results[i].status);
                    if (results[i].status == "fulfilled") {
                        trace("  -> value: " + results[i].value);
                    } else {
                        trace("  -> reason: " + results[i].reason);
                    }
                }
            });


        // ============【 3. 进一步的 A+ 规范测试 】============================
        
        // 3.1 没有 onFulfilled 的 then 测试（可选参数）
        var noOnFulfilled:Promise = Promise.resolve(10);
        noOnFulfilled.then(null).then(function(value:Object):Void {
            trace("[noOnFulfilled] value = " + value);
        });

        // 3.2 没有 onRejected 的 then 测试（可选参数）
        var noOnRejected:Promise = Promise.reject("No onRejected error");
        noOnRejected.then(null).onCatch(function(reason:Object):Void {
            trace("[noOnRejected] reason = " + reason);
        });

        // 3.3 Thenable 对象测试（非 Promise 但含 then 方法）
        var thenable:Object = {
            then: function(resolveFn:Function, rejectFn:Function):Void {
                resolveFn("Thenable resolved value");
            }
        };
        var thenableTest:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(thenable);
        });
        thenableTest.then(function(value:Object):Void {
            trace("[thenableTest] " + value);
        });

        // 3.4 Chaining cycle (循环引用) 测试
        // 让 promise2 返回自己，应该触发 TypeError
        var circularPromise:Promise = Promise.resolve("circular start");
        var p2:Promise;
        p2 = circularPromise.then(function():Promise {
            trace("[circularPromise] Attempting to return self to create a cycle.");
            return p2; // 返回自己，触发循环引用
        });
        p2.onCatch(function(reason:Object):Void {
            trace("[circularPromise] " + reason);
        });

        // 3.5 立即 resolve/reject 测试：验证 then 回调是否异步执行
        var immediatePromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve("Immediate resolved");
        });

        var asyncCheck:Boolean = false;
        immediatePromise.then(function(value:Object):Void {
            // 若 Promise A+ 正确实现，应在当前事件循环结束后才执行
            trace("[immediatePromise] asyncCheck = " + asyncCheck + ", value = " + value);
        });
        asyncCheck = true;

        // 3.6 强制抛出异常后再次 resolve 测试
        var forcedExceptionPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            throw new Error("Forced exception");
        });
        forcedExceptionPromise.then(function(value:Object):Void {
            trace("[forcedExceptionPromise] should not fulfill: " + value);
        }).onCatch(function(reason:Object):Void {
            trace("[forcedExceptionPromise] caught: " + reason.message);
        });

        // 3.7 大量异步操作测试（简单演示，验证状态是否正常）
        var bigBatch:Array = [];
        for (var i:Number = 0; i < 5; i++) {
            (function(index:Number):Void {
                bigBatch.push(
                    new Promise(function(resolve:Function, reject:Function):Void {
                        var r:Number = Math.floor(Math.random() * 100);
                        var timerID:Number = setInterval(function():Void {
                            clearInterval(timerID);
                            if (r < 90) {
                                resolve("Batch " + index + " resolved with r=" + r);
                            } else {
                                reject("Batch " + index + " rejected with r=" + r);
                            }
                        }, r + 100); // 随机延迟
                    })
                );
            })(i);
        }
        Promise.all(bigBatch).then(function(values:Array):Void {
            trace("[bigBatch] all resolved: " + values);
        }).onCatch(function(reason:Object):Void {
            trace("[bigBatch] one rejected: " + reason);
        });

        // 3.8 测试返回普通对象（非 Thenable）
        var normalObjectPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            var obj:Object = { data: "testObject" };
            resolve(obj);
        });
        normalObjectPromise.then(function(value:Object):Void {
            trace("[normalObjectPromise] data = " + value.data);
        });

        // ============【 测试入口结束 】========================================

    }
}
