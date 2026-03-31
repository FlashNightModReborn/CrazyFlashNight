/**
 * org.flashNight.aven.Promise.Promise
 *
 * ActionScript 2 实现的 Promises/A+ 规范 Promise。
 *
 * 性能优化记录 (2026-03):
 *   [PERF] 状态从 String("pending"/"fulfilled"/"rejected") 改为 Number(0/1/2)
 *         消除状态检查的字符串比较开销（H08: 跨类型 === 对同类型 Number 仅 ~2ns）
 *   [PERF] _resolve/_reject 中局部化 self 引用的属性访问（H01/H02）
 *   [PERF] then() 中缓存 Scheduler 实例到静态变量，避免每次 getInstance()（S01）
 *   [PERF] resolvePromise 中 isReferenceLike 结果判断后提前返回，减少分支深度
 *   [PERF] _resolve/_reject 回调分发使用 while(i<len) + 局部变量（H01/H16）
 *   [PERF] asyncCall 直接 push 到 Scheduler 队列，省去 getInstance() 方法调用
 *
 * 修复记录 (2026-03):
 *   [FIX] AS2 不支持 IIFE — 移除所有 (function(){})() 模式
 *   [FIX] _resolve/_reject 中的双重 asyncCall — 回调已在 then 内部异步化，
 *         _resolve/_reject 直接同步调用即可
 *   [FIX] _resolve 增加通用 thenable 解包 — 符合 Promises/A+ §2.3.3
 *   [FIX] Promise.all/race/allSettled 中的 IIFE 替换为静态辅助方法
 *   [FIX] Scheduler 改为排空队列模式 — 同一帧内解析整条链
 *
 * A+ 合规性与 try-catch 的权衡:
 *   AS2 性能规范(H18)禁止热路径使用 try-catch，但 Promises/A+ §2.3.3 要求捕获:
 *   (1) thenable 的 then 属性访问异常 (2) thenable.then() 调用异常
 *   (3) executor 执行异常 (4) onFulfilled/onRejected 回调异常
 *   当前保留 A+ 必需的 try-catch 以确保合规；未来若确定业务场景不涉及
 *   外部 thenable，可通过编译开关移除 thenable 路径的 try-catch。
 */
import org.flashNight.aven.Promise.Scheduler;

class org.flashNight.aven.Promise.Promise {

    // 状态常量（Number 比较远快于 String 比较）
    private static var PENDING:Number   = 0;
    private static var FULFILLED:Number = 1;
    private static var REJECTED:Number  = 2;

    private var _state:Number;           // 0=pending, 1=fulfilled, 2=rejected
    private var _value:Object;           // fulfill 时的返回值
    private var _reason:Object;          // reject 时的错误原因
    private var _onFulfilledCallbacks:Array;
    private var _onRejectedCallbacks:Array;

    // _resolve 和 _reject 使用闭包，因为需要传给 executor 和 thenable.then
    private var _resolve:Function;
    private var _reject:Function;

    // 缓存 Scheduler 实例，避免每次 asyncCall 都走 getInstance()
    private static var _scheduler:Scheduler;

    /**
     * 构造函数
     * @param executor  执行器函数，形如 function(resolve, reject) {}
     */
    public function Promise(executor:Function) {
        this._state = 0; // PENDING
        this._value = null;
        this._reason = null;
        this._onFulfilledCallbacks = [];
        this._onRejectedCallbacks = [];

        var self:Promise = this;

        // --------------------- 内部 resolve 函数 ---------------------
        this._resolve = function(value:Object):Void {
            // 状态只能从 pending 转换
            if (self._state !== 0) return;

            // 禁止 promise 解析为其自身
            if (value === self) {
                self._reject(new Error("TypeError: Promise cannot resolve itself"));
                return;
            }

            // 处理 thenable（包括 Promise 实例和含 then 方法的普通对象）
            if (Promise.isReferenceLike(value)) {
                var thenProp:Object = undefined;
                try {
                    thenProp = value["then"];
                } catch (e:Object) {
                    // getter 抛出异常，直接 reject (A+ §2.3.3.2)
                    self._reject(e);
                    return;
                }
                if (typeof(thenProp) == "function") {
                    // 是 thenable，递归解析 (A+ §2.3.3.3)
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

            // 普通值：直接 fulfill
            self._state = 1; // FULFILLED
            self._value = value;

            // 同步分发所有 onFulfilled 回调
            var callbacks:Array = self._onFulfilledCallbacks;
            self._onFulfilledCallbacks = null;
            self._onRejectedCallbacks = null;

            var i:Number = 0;
            var len:Number = callbacks.length;
            while (i < len) {
                callbacks[i](value);
                i++;
            }
        };

        // --------------------- 内部 reject 函数 ---------------------
        this._reject = function(reason:Object):Void {
            if (self._state !== 0) return;

            self._state = 2; // REJECTED
            self._reason = reason;

            var callbacks:Array = self._onRejectedCallbacks;
            self._onFulfilledCallbacks = null;
            self._onRejectedCallbacks = null;

            var i:Number = 0;
            var len:Number = callbacks.length;
            while (i < len) {
                callbacks[i](reason);
                i++;
            }
        };

        // --------------------- 执行传入 executor ---------------------
        // A+ 要求捕获 executor 异常
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
        var selfState:Number = self._state; // H01: 局部化状态

        var promise2:Promise = new Promise(function(resolve2:Function, reject2:Function):Void {

            /**
             * 包装后的 fulfilled 回调
             */
            function fulfilled(value:Object):Void {
                Promise.asyncCall(function():Void {
                    try {
                        if (typeof(onFulfilled) == "function") {
                            var x:Object = onFulfilled(value);
                            Promise.resolvePromise(promise2, x, resolve2, reject2);
                        } else {
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
                Promise.asyncCall(function():Void {
                    try {
                        if (typeof(onRejected) == "function") {
                            var x:Object = onRejected(reason);
                            Promise.resolvePromise(promise2, x, resolve2, reject2);
                        } else {
                            reject2(reason);
                        }
                    } catch (e:Object) {
                        reject2(e);
                    }
                });
            }

            // 根据当前 promise 的状态，决定立刻异步调用还是加入回调队列
            if (selfState === 1) { // FULFILLED
                fulfilled(self._value);
            } else if (selfState === 2) { // REJECTED
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

    /**
     * AS2 中 proto-null 对象对 `!= null` 的 loose equality 会退化，
     * 这里显式筛掉原始值，只要还能承载属性访问，就允许参与 thenable 检测。
     */
    private static function isReferenceLike(value:Object):Boolean {
        if (value === null) return false;
        var t:String = typeof(value);
        // 排除原始类型（undefined/number/string/boolean），剩余均为引用类型
        return (t == "object" || t == "function" || t == "movieclip");
    }

    /**
     * 核心函数：根据 x 的类型和值，解析返回的新 Promise 状态 (A+ §2.3)
     */
    private static function resolvePromise(promise2:Promise, x:Object,
                                          resolve2:Function, reject2:Function):Void {
        // 防止循环引用 (A+ §2.3.1)
        if (promise2 === x) {
            reject2(new Error("TypeError: Chaining cycle detected for promise"));
            return;
        }

        // 非引用类型直接 fulfill (A+ §2.3.4)
        if (!Promise.isReferenceLike(x)) {
            resolve2(x);
            return;
        }

        // 引用类型：可能是 thenable (A+ §2.3.3)
        var called:Boolean = false;
        try {
            var thenProp:Object = x["then"];
            if (typeof(thenProp) == "function") {
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
                resolve2(x);
            }
        } catch (e:Object) {
            if (!called) {
                called = true;
                reject2(e);
            }
        }
    }

    /**
     * 覆盖 toString 以便查看调试
     */
    public function toString():String {
        var stateStr:String;
        if (this._state === 1) {
            stateStr = "fulfilled, value: " + this._value;
        } else if (this._state === 2) {
            stateStr = "rejected, reason: " + this._reason;
        } else {
            stateStr = "pending";
        }
        return "[Promise state: " + stateStr + "]";
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
     */
    public static function all(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            var total:Number = promises.length;
            if (total === 0) {
                resolve([]);
                return;
            }

            var state:Object = {completed: 0, rejected: false};
            var results:Array = [];

            var i:Number = 0;
            while (i < total) {
                Promise._allHelper(promises[i], i, results, resolve, reject, total, state);
                i++;
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
            var len:Number = promises.length;
            if (len === 0) return; // 空数组永远 pending

            var i:Number = 0;
            while (i < len) {
                Promise.resolve(promises[i]).then(
                    function(value:Object):Void { resolve(value); },
                    function(reason:Object):Void { reject(reason); }
                );
                i++;
            }
        });
    }

    /**
     * Promise.allSettled
     */
    public static function allSettled(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            var total:Number = promises.length;
            if (total === 0) {
                resolve([]);
                return;
            }

            var state:Object = {completed: 0};
            var results:Array = [];

            var i:Number = 0;
            while (i < total) {
                Promise._allSettledHelper(promises[i], i, results, resolve, total, state);
                i++;
            }
        });
    }

    /** Promise.allSettled 的循环辅助 */
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

    /* ================== 异步调度 ================== */

    /**
     * 在下一次 Scheduler 排空时调用给定函数
     * 缓存 Scheduler 实例避免每次 getInstance() 的方法调用开销
     */
    private static function asyncCall(fn:Function):Void {
        var s:Scheduler = _scheduler;
        if (s == undefined) {
            s = Scheduler.getInstance();
            _scheduler = s;
        }
        s.enqueue(fn);
    }
}
