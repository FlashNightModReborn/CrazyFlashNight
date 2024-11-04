import org.flashNight.aven.Promise.*;

class org.flashNight.aven.Promise.TestPromise {
    public static function main():Void {
        // ---------------------- 现有测试用例 ----------------------
        
        // 基本成功的 Promise 测试
        var promiseSuccess:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            // 模拟异步操作，1秒后调用 resolve
            var timerID:Number = setInterval(function():Void {
                clearInterval(timerID);
                resolve("Operation successful");
            }, 1000);
        });

        promiseSuccess.then(function(value:Object):Void {
            trace("Success: " + value);
        }, function(reason:Object):Void {
            trace("Failure: " + reason);
        });

        // 基本失败的 Promise 测试
        var promiseFailure:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            // 模拟异步操作，1秒后调用 reject
            var timerID:Number = setInterval(function():Void {
                clearInterval(timerID);
                reject("Operation failed");
            }, 1000);
        });

        promiseFailure.then(function(value:Object):Void {
            trace("Success: " + value);
        }).onCatch(function(reason:Object):Void {
            trace("Caught Error: " + reason);
        });

        // Promise 链式调用测试
        var chainedPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(1);
        });

        chainedPromise.then(function(value:Object):Object {
            trace("First then: " + value);
            return value + 1;
        }).then(function(value:Object):Object {
            trace("Second then: " + value);
            return value + 1;
        }).then(function(value:Object):Void {
            trace("Third then: " + value);
        });

        // 异常捕获测试
        var errorPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            throw new Error("An exception occurred");
        });

        errorPromise.onCatch(function(reason:Object):Void {
            trace("Exception caught: " + reason.message);
        });

        // 多次 then 调用测试
        var multipleThenPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve("Resolved once");
        });

        multipleThenPromise.then(function(value:Object):Void {
            trace("First then (multiple then test): " + value);
        });

        multipleThenPromise.then(function(value:Object):Void {
            trace("Second then (multiple then test): " + value);
        });

        // 嵌套 Promise 测试
        var nestedPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(new Promise(function(innerResolve:Function, innerReject:Function):Void {
                innerResolve("Nested promise resolved");
            }));
        });

        nestedPromise.then(function(value:Object):Void {
            trace("Nested promise test: " + value);
        });

        // 传递 null 值测试
        var nullValuePromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(null);
        });

        nullValuePromise.then(function(value:Object):Void {
            trace("Null value test: " + (value === null ? "null" : "not null"));
        });

        // 传递 undefined 值测试
        var undefinedValuePromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(undefined);
        });

        undefinedValuePromise.then(function(value:Object):Void {
            trace("Undefined value test: " + (value === undefined ? "undefined" : "defined"));
        });

        // 同步和异步混合调用测试
        var mixedPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(5);
        });

        mixedPromise.then(function(value:Object):Object {
            trace("Mixed promise first then: " + value);
            return new Promise(function(innerResolve:Function, innerReject:Function):Void {
                var timerID:Number = setInterval(function():Void {
                    clearInterval(timerID);
                    innerResolve(value + 5);
                }, 500);
            });
        }).then(function(value:Object):Void {
            trace("Mixed promise second then: " + value);
        });

        // 多次调用 resolve 和 reject 测试
        var multipleResolveRejectPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve("First resolve");
            reject("Should not affect");
            resolve("Should not affect");
        });

        multipleResolveRejectPromise.then(function(value:Object):Void {
            trace("Multiple resolve/reject test: " + value);
        }).onCatch(function(reason:Object):Void {
            trace("Error in multiple resolve/reject test: " + reason);
        });

        // Promise 以另一个 Promise 作为 resolve 值测试
        var promiseWithPromiseValue:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(new Promise(function(innerResolve:Function, innerReject:Function):Void {
                innerResolve("Inner promise resolved");
            }));
        });

        promiseWithPromiseValue.then(function(value:Object):Void {
            trace("Promise with promise as value: " + value);
        });

        // ---------------------- 新增测试用例 ----------------------

        // 使用 Promise.resolve 测试
        var resolvedPromise:Promise = Promise.resolve("Immediate value");
        resolvedPromise.then(function(value:Object):Void {
            trace("Promise.resolve test: " + value);
        });

        // 使用 Promise.reject 测试
        var rejectedPromise:Promise = Promise.reject("Immediate error");
        rejectedPromise.onCatch(function(reason:Object):Void {
            trace("Promise.reject test: " + reason);
        });

        // 使用 Promise.all 测试所有 Promise 都成功
        var promiseAll1:Promise = Promise.resolve("All 1");
        var promiseAll2:Promise = Promise.resolve("All 2");
        var promiseAll3:Promise = Promise.resolve("All 3");

        Promise.all([promiseAll1, promiseAll2, promiseAll3]).then(function(values:Array):Void {
            trace("Promise.all success test: " + values);
        }).onCatch(function(reason:Object):Void {
            trace("Promise.all failure test: " + reason);
        });

        // 使用 Promise.all 测试其中一个 Promise 失败
        var promiseAllFail1:Promise = Promise.resolve("AllFail 1");
        var promiseAllFail2:Promise = Promise.reject("AllFail 2");
        var promiseAllFail3:Promise = Promise.resolve("AllFail 3");

        Promise.all([promiseAllFail1, promiseAllFail2, promiseAllFail3]).then(function(values:Array):Void {
            trace("Promise.all success test (should not be called)");
        }).onCatch(function(reason:Object):Void {
            trace("Promise.all failure test (one rejected): " + reason);
        });

        // 使用 Promise.all 测试空数组
        Promise.all([]).then(function(values:Array):Void {
            trace("Promise.all empty array test: " + values);
        }).onCatch(function(reason:Object):Void {
            trace("Promise.all empty array failure (should not be called)");
        });

        // 使用 Promise.race 测试第一个 Promise 成功
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

        Promise.race([promiseRace1, promiseRace2]).then(function(value:Object):Void {
            trace("Promise.race success test: " + value);
        }).onCatch(function(reason:Object):Void {
            trace("Promise.race failure test: " + reason);
        });

        // 使用 Promise.race 测试第一个 Promise 失败
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

        Promise.race([promiseRaceFail1, promiseRaceFail2]).then(function(value:Object):Void {
            trace("Promise.race success test (should not be called)");
        }).onCatch(function(reason:Object):Void {
            trace("Promise.race failure test: " + reason);
        });

        // 使用 Promise.race 测试空数组
        Promise.race([]).then(function(value:Object):Void {
            trace("Promise.race empty array success (should not be called)");
        }).onCatch(function(reason:Object):Void {
            trace("Promise.race empty array failure (should not be called)");
        });

        // 使用 Promise.allSettled 测试所有 Promise 完成
        var promiseAllSettled1:Promise = Promise.resolve("AllSettled 1");
        var promiseAllSettled2:Promise = Promise.reject("AllSettled 2");
        var promiseAllSettled3:Promise = Promise.resolve("AllSettled 3");

        Promise.allSettled([promiseAllSettled1, promiseAllSettled2, promiseAllSettled3]).then(function(results:Array):Void {
            trace("Promise.allSettled test:");
            for (var i:Number = 0; i < results.length; i++) {
                trace("Promise " + i + " status: " + results[i].status);
                if (results[i].status == "fulfilled") {
                    trace("Value: " + results[i].value);
                } else {
                    trace("Reason: " + results[i].reason);
                }
            }
        });

        // 使用 Promise.allSettled 测试空数组
        Promise.allSettled([]).then(function(results:Array):Void {
            trace("Promise.allSettled empty array test: " + results);
        });

        // 使用 Promise.allSettled 测试所有 Promise 都成功
        var promiseAllSettledAll1:Promise = Promise.resolve("AllSettled All 1");
        var promiseAllSettledAll2:Promise = Promise.resolve("AllSettled All 2");

        Promise.allSettled([promiseAllSettledAll1, promiseAllSettledAll2]).then(function(results:Array):Void {
            trace("Promise.allSettled all fulfilled test:");
            for (var i:Number = 0; i < results.length; i++) {
                trace("Promise " + i + " status: " + results[i].status);
                if (results[i].status == "fulfilled") {
                    trace("Value: " + results[i].value);
                } else {
                    trace("Reason: " + results[i].reason);
                }
            }
        });
    }
}
