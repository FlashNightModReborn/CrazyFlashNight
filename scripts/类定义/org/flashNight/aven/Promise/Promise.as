/**
 * org.flashNight.aven.Promise.Promise
 * 
 * 一个符合 Promises/A+ 规范的 Promise 类在 ActionScript 2 中的实现示例。
 */
import org.flashNight.aven.Promise.Scheduler;
import org.flashNight.neur.Event.*;

class org.flashNight.aven.Promise.Promise {
    private var _state:String;         // "pending", "fulfilled", or "rejected"
    private var _value:Object;         // fulfill 时的返回值
    private var _reason:Object;        // reject 时的错误原因
    private var _onFulfilledCallbacks:Array; 
    private var _onRejectedCallbacks:Array;

    // _resolve 和 _reject 使用私有方法缓存，以减少闭包开销
    private var _resolve:Function;
    private var _reject:Function;

    /**
     * 构造函数
     * @param executor  执行器函数，形如 (resolve, reject) => {}
     */
    public function Promise(executor:Function) {
        this._state = "pending";
        this._value = null;
        this._reason = null;
        this._onFulfilledCallbacks = [];
        this._onRejectedCallbacks = [];

        var self:Promise = this;

        // --------------------- 内部 resolve 函数 ---------------------
        this._resolve = function(value:Object):Void {
            // 状态只能从 pending 转到 fulfilled
            if (self._state === "pending") {
                // 处理 thenable
                if (value instanceof Promise) {
                    // 若返回值本身是个 Promise，需等待它 resolve/reject
                    value.then(self._resolve, self._reject);
                    return;
                }

                self._state = "fulfilled";
                self._value = value;

                // 异步执行所有 onFulfilled 回调
                var callbacks:Array = self._onFulfilledCallbacks;
                self._onFulfilledCallbacks = null;
                self._onRejectedCallbacks = null;

                for (var i:Number = 0; i < callbacks.length; i++) {
                    (function(cb:Function, val:Object):Void {
                        asyncCall(function():Void {
                            cb(val);
                        });
                    })(callbacks[i], value);
                }
            }
        };

        // --------------------- 内部 reject 函数 ---------------------
        this._reject = function(reason:Object):Void {
            // 状态只能从 pending 转到 rejected
            if (self._state === "pending") {
                self._state = "rejected";
                self._reason = reason;

                // 异步执行所有 onRejected 回调
                var callbacks:Array = self._onRejectedCallbacks;
                self._onFulfilledCallbacks = null;
                self._onRejectedCallbacks = null;

                for (var i:Number = 0; i < callbacks.length; i++) {
                    (function(cb:Function, rsn:Object):Void {
                        asyncCall(function():Void {
                            cb(rsn);
                        });
                    })(callbacks[i], reason);
                }
            }
        };

        // --------------------- 执行传入 executor ---------------------
        try {
            executor(this._resolve, this._reject);
        } catch (e:Object) {
            this._reject(e);
        }
    }

    /**
     * then 方法
     * @param onFulfilled fulfilled 状态的回调
     * @param onRejected  rejected 状态的回调
     * @return 新的 Promise，用于链式调用
     */
    public function then(onFulfilled:Function, onRejected:Function):Promise {
        var self:Promise = this;

        // 创建新的 promise2，用于链式
        var promise2:Promise = new Promise(function(resolve2:Function, reject2:Function):Void {

            /**
             * 包装后的 fulfilled 回调
             */
            function fulfilled(value:Object):Void {
                asyncCall(function():Void {
                    try {
                        if (isFunction(onFulfilled)) {
                            var x:Object = onFulfilled(value);
                            resolvePromise(promise2, x, resolve2, reject2);
                        } else {
                            // 如果 onFulfilled 不是函数，直接将当前 value 传递给下一个
                            resolve2(value);
                        }
                    } catch (e:Object) {
                        reject2(e);
                    }
                });
            }

            /**
             * 包装后的 rejected 回调
             */
            function rejected(reason:Object):Void {
                asyncCall(function():Void {
                    try {
                        if (isFunction(onRejected)) {
                            var x:Object = onRejected(reason);
                            resolvePromise(promise2, x, resolve2, reject2);
                        } else {
                            // 如果 onRejected 不是函数，直接把 reason 往下层 reject
                            reject2(reason);
                        }
                    } catch (e:Object) {
                        reject2(e);
                    }
                });
            }

            // 根据当前 promise 的状态，决定立刻异步调用还是加入回调队列
            if (self._state === "fulfilled") {
                fulfilled(self._value);
            } else if (self._state === "rejected") {
                rejected(self._reason);
            } else {
                // pending 状态，先把回调存起来
                self._onFulfilledCallbacks.push(fulfilled);
                self._onRejectedCallbacks.push(rejected);
            }
        });

        return promise2;
    }

    /**
     * catch 方法（AS2 中 catch 为关键词，改为 onCatch）
     * @param onRejected 当 Promise 失败时调用的函数
     * @return 新的 Promise，用于链式调用
     */
    public function onCatch(onRejected:Function):Promise {
        return this.then(null, onRejected);
    }

    /* ------------------- 工具与静态方法 ------------------- */

    private static function isFunction(obj:Object):Boolean {
        return (typeof(obj) == "function");
    }

    /**
     * 核心函数：根据 x 的类型和值，解析返回的新 Promise 状态
     * @param promise2 then 返回的新 Promise
     * @param x        onFulfilled 或 onRejected 的返回值
     * @param resolve2 promise2 的 resolve
     * @param reject2  promise2 的 reject
     */
    private static function resolvePromise(promise2:Promise, x:Object, 
                                          resolve2:Function, reject2:Function):Void {
        // 防止循环引用
        if (promise2 === x) {
            reject2(new Error("TypeError: Chaining cycle detected for promise"));
            return;
        }

        // 如果 x 是对象或函数，可能是一个 Thenable
        if (x != null && (typeof(x) == "object" || isFunction(x))) {
            var called:Boolean = false;
            try {
                var then:Object = x["then"];
                if (isFunction(then)) {
                    // 如果是 Thenable，对其进行递归解析
                    then.call(
                        x, 
                        function(y:Object):Void {
                            if (called) return;
                            called = true;
                            resolvePromise(promise2, y, resolve2, reject2);
                        }, 
                        function(r:Object):Void {
                            if (called) return;
                            called = true;
                            reject2(r);
                        }
                    );
                } else {
                    // then 不是函数，则直接成功
                    resolve2(x);
                }
            } catch (e:Object) {
                if (!called) {
                    called = true;
                    reject2(e);
                }
            }
        } else {
            // 如果 x 是普通值，则直接 fulfill
            resolve2(x);
        }
    }

    /**
     * 覆盖 toString 以便查看调试
     */
    public function toString():String {
        var result:String = "[Promise state: " + this._state;
        if (this._state == "fulfilled") {
            result += ", value: " + this._value;
        } else if (this._state == "rejected") {
            result += ", reason: " + this._reason;
        }
        result += "]";
        return result;
    }

    /* ================== 静态方法 ================== */

    /**
     * Promise.resolve
     */
    public static function resolve(value:Object):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            resolve(value);
        });
    }

    /**
     * Promise.reject
     */
    public static function reject(reason:Object):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            reject(reason);
        });
    }

    /**
     * Promise.all
     */
    public static function all(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            if (promises.length == 0) {
                trace("[Promise.all] 空数组，立即返回 []");
                resolve([]);
                return;
            }

            var results:Array = [];
            var completed:Number = 0;
            var hasRejected:Boolean = false;

            for (var i:Number = 0; i < promises.length; i++) {
                (function(index:Number):Void {
                    // 保证每个元素都能被当成 Promise 处理
                    Promise.resolve(promises[index]).then(
                        function(value:Object):Void {
                            if (hasRejected) return;
                            results[index] = value;
                            completed++;
                            if (completed === promises.length) {
                                resolve(results);
                            }
                        },
                        function(reason:Object):Void {
                            if (hasRejected) return;
                            hasRejected = true;
                            reject(reason);
                        }
                    );
                })(i);
            }
        });
    }

    /**
     * Promise.race
     */
    public static function race(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            if (promises.length == 0) {
                trace("[Promise.race] 空数组，不会触发 resolve 或 reject");
                // 根据 Promises/A+ 规范，空数组的 race 不会触发任何状态改变
                return;
            }
            for (var i:Number = 0; i < promises.length; i++) {
                (function(p:Promise):Void {
                    Promise.resolve(p).then(
                        function(value:Object):Void {
                            resolve(value);
                        },
                        function(reason:Object):Void {
                            reject(reason);
                        }
                    );
                })(promises[i]);
            }
        });
    }

    /**
     * Promise.allSettled
     */
    public static function allSettled(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            if (promises.length == 0) {
                trace("[Promise.allSettled] 空数组，立即返回 []");
                resolve([]);
                return;
            }

            var results:Array = [];
            var completed:Number = 0;
            for (var i:Number = 0; i < promises.length; i++) {
                (function(index:Number):Void {
                    Promise.resolve(promises[index]).then(
                        function(value:Object):Void {
                            results[index] = { status: "fulfilled", value: value };
                            completed++;
                            if (completed === promises.length) {
                                resolve(results);
                            }
                        },
                        function(reason:Object):Void {
                            results[index] = { status: "rejected", reason: reason };
                            completed++;
                            if (completed === promises.length) {
                                resolve(results);
                            }
                        }
                    );
                })(i);
            }
        });
    }

    /* ================== 模拟异步函数 ================== */
    /**
     * 在下一帧/事件循环时调用给定函数
     * 使用 Scheduler 类的队列，模拟微任务调度
     * @param fn 要异步执行的函数
     */
    private static function asyncCall(fn:Function):Void {
        Scheduler.getInstance().enqueue(fn);
    }
}
