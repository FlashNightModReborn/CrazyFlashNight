/**
 * org.flashNight.aven.Promise.Promise
 *
 * ActionScript 2 实现的 Promises/A+ 规范 Promise。
 *
 * 修复记录 (2026-03):
 *   [FIX] AS2 不支持 IIFE — 移除所有 (function(){})() 模式
 *   [FIX] _resolve/_reject 中的双重 asyncCall — 回调已在 then 内部异步化，
 *         _resolve/_reject 直接同步调用即可
 *   [FIX] _resolve 增加通用 thenable 解包 — 符合 Promises/A+ §2.3.3
 *   [FIX] Promise.all/race/allSettled 中的 IIFE 替换为静态辅助方法
 *   [PERF] Scheduler 改为排空队列模式 — 同一帧内解析整条链
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
     * @param executor  执行器函数，形如 function(resolve, reject) {}
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
            if (self._state !== "pending") return;

            // 生产安全：禁止 promise 解析为其自身，否则会永久 pending
            if (value === self) {
                self._reject(new Error("TypeError: Promise cannot resolve itself"));
                return;
            }

            // 处理 thenable（包括 Promise 实例和含 then 方法的普通对象）
            if (value != null && (typeof(value) == "object" || typeof(value) == "function")) {
                // 注意：不能用 instanceof Promise 排除，因为需要处理通用 thenable
                var thenProp:Object = undefined;
                try {
                    thenProp = value["then"];
                } catch (e:Object) {
                    // getter 抛出异常，直接 reject
                    self._reject(e);
                    return;
                }
                if (typeof(thenProp) == "function") {
                    // 是 thenable，递归解析
                    var called:Boolean = false;
                    try {
                        thenProp.call(
                            value,
                            function(y:Object):Void {
                                if (called) return;
                                called = true;
                                self._resolve(y);
                            },
                            function(r:Object):Void {
                                if (called) return;
                                called = true;
                                self._reject(r);
                            }
                        );
                    } catch (e2:Object) {
                        if (!called) {
                            called = true;
                            self._reject(e2);
                        }
                    }
                    return;
                }
            }

            self._state = "fulfilled";
            self._value = value;

            // 直接同步调用所有 onFulfilled 回调
            // （回调是 then() 中的 fulfilled 包装器，内部已有 asyncCall 保证异步）
            var callbacks:Array = self._onFulfilledCallbacks;
            self._onFulfilledCallbacks = null;
            self._onRejectedCallbacks = null;

            for (var i:Number = 0; i < callbacks.length; i++) {
                callbacks[i](value);
            }
        };

        // --------------------- 内部 reject 函数 ---------------------
        this._reject = function(reason:Object):Void {
            // 状态只能从 pending 转到 rejected
            if (self._state !== "pending") return;

            self._state = "rejected";
            self._reason = reason;

            // 直接同步调用所有 onRejected 回调
            var callbacks:Array = self._onRejectedCallbacks;
            self._onFulfilledCallbacks = null;
            self._onRejectedCallbacks = null;

            for (var i:Number = 0; i < callbacks.length; i++) {
                callbacks[i](reason);
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

    /**
     * finally 方法（AS2 中 finally 为关键词，改为 onFinally）
     *
     * 无论 fulfilled 或 rejected 均调用 callback。
     * callback 不接收任何参数，其返回值被忽略（除非抛出异常或返回 rejected Promise，
     * 此时新的异常/拒因将覆盖原结果）。原始 value/reason 透传给下游。
     *
     * @param callback 无参回调
     * @return 新的 Promise
     */
    public function onFinally(callback:Function):Promise {
        var isFunc:Boolean = (typeof(callback) == "function");
        return this.then(
            function(value:Object):Object {
                if (isFunc) {
                    return Promise.resolve(callback()).then(function():Object {
                        return value;
                    });
                }
                return value;
            },
            function(reason:Object):Object {
                if (isFunc) {
                    return Promise.resolve(callback()).then(function():Object {
                        return Promise.reject(reason);
                    });
                }
                return Promise.reject(reason);
            }
        );
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
                var thenProp:Object = x["then"];
                if (isFunction(thenProp)) {
                    // 如果是 Thenable，对其进行递归解析
                    thenProp.call(
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
     * 若 value 已是 Promise 实例，直接返回（避免多余包装与解包开销）
     */
    public static function resolve(value:Object):Promise {
        if (value instanceof Promise) {
            return Promise(value);
        }
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
     * 使用静态辅助方法替代 IIFE 来捕获循环变量
     */
    public static function all(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            if (promises.length == 0) {
                resolve([]);
                return;
            }

            var total:Number = promises.length;
            // 用对象包装可变状态，闭包间共享
            var state:Object = {completed: 0, rejected: false};
            var results:Array = [];

            for (var i:Number = 0; i < total; i++) {
                Promise._allHelper(promises[i], i, results, resolve, reject,
                                   total, state);
            }
        });
    }

    /** Promise.all 的循环辅助（替代 IIFE，捕获 index） */
    private static function _allHelper(
        promise:Object, index:Number, results:Array,
        resolve:Function, reject:Function,
        total:Number, state:Object
    ):Void {
        Promise.resolve(promise).then(
            function(value:Object):Void {
                if (state.rejected) return;
                results[index] = value;
                state.completed++;
                if (state.completed === total) {
                    resolve(results);
                }
            },
            function(reason:Object):Void {
                if (state.rejected) return;
                state.rejected = true;
                reject(reason);
            }
        );
    }

    /**
     * Promise.race
     */
    public static function race(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            if (promises.length == 0) {
                // 根据规范，空数组的 race 永远 pending
                return;
            }
            for (var i:Number = 0; i < promises.length; i++) {
                // 不需要 IIFE，因为闭包只捕获 resolve/reject（不依赖 i）
                Promise.resolve(promises[i]).then(
                    function(value:Object):Void {
                        resolve(value);
                    },
                    function(reason:Object):Void {
                        reject(reason);
                    }
                );
            }
        });
    }

    /**
     * Promise.allSettled
     * 使用静态辅助方法替代 IIFE
     */
    public static function allSettled(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            if (promises.length == 0) {
                resolve([]);
                return;
            }

            var total:Number = promises.length;
            var state:Object = {completed: 0};
            var results:Array = [];

            for (var i:Number = 0; i < total; i++) {
                Promise._allSettledHelper(promises[i], i, results, resolve,
                                          total, state);
            }
        });
    }

    /** Promise.allSettled 的循环辅助（替代 IIFE，捕获 index） */
    private static function _allSettledHelper(
        promise:Object, index:Number, results:Array,
        resolve:Function, total:Number, state:Object
    ):Void {
        Promise.resolve(promise).then(
            function(value:Object):Void {
                results[index] = { status: "fulfilled", value: value };
                state.completed++;
                if (state.completed === total) {
                    resolve(results);
                }
            },
            function(reason:Object):Void {
                results[index] = { status: "rejected", reason: reason };
                state.completed++;
                if (state.completed === total) {
                    resolve(results);
                }
            }
        );
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
