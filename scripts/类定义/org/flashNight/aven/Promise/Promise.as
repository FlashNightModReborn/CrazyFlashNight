/**
 * Promise 类用于处理异步操作，类似于现代 JavaScript 中的 Promise。
 * 它支持链式调用、错误处理以及嵌套的 Promise 解析。
 */
class org.flashNight.aven.Promise.Promise {
    // 私有属性，用于保存 Promise 的状态和值
    private var _state:String; // "pending"、"fulfilled" 或 "rejected"
    private var _value:Object; // 成功时的值
    private var _reason:Object; // 失败时的原因

    // 数组，用于存储成功和失败的回调函数
    private var _onFulfilledCallbacks:Array;
    private var _onRejectedCallbacks:Array;

    /**
     * Promise 的构造函数
     * @param executor 一个接受 resolve 和 reject 函数的执行器函数
     */
    public function Promise(executor:Function) {
        // 初始化 Promise 的状态为 pending
        this._state = "pending";
        this._value = null;
        this._reason = null;
        this._onFulfilledCallbacks = [];
        this._onRejectedCallbacks = [];

        // 缓存当前对象的引用，供内部函数使用
        var self:Promise = this;

        /**
         * resolve 函数，用于将 Promise 标记为成功并执行所有成功回调
         * @param value 要传递的成功值
         */
        this._resolve = function(value:Object):Void {
            // 只有在 pending 状态下才能改变状态
            if (self._state == "pending") {
                self._state = "fulfilled";
                self._value = value;

                // 获取当前所有成功回调，并清空回调数组以释放内存
                var callbacks:Array = self._onFulfilledCallbacks;
                self._onFulfilledCallbacks = null;
                self._onRejectedCallbacks = null;

                // 逆序遍历并执行所有成功回调
                var i:Number = callbacks.length;
                while (--i >= 0) {
                    (function(callback:Function):Void {
                        // 模拟异步执行
                        callback(self._value);
                    })(callbacks[i]);
                }
            }
        };

        /**
         * reject 函数，用于将 Promise 标记为失败并执行所有失败回调
         * @param reason 要传递的失败原因
         */
        this._reject = function(reason:Object):Void {
            // 只有在 pending 状态下才能改变状态
            if (self._state == "pending") {
                self._state = "rejected";
                self._reason = reason;

                // 获取当前所有失败回调，并清空回调数组以释放内存
                var callbacks:Array = self._onRejectedCallbacks;
                self._onFulfilledCallbacks = null;
                self._onRejectedCallbacks = null;

                // 逆序遍历并执行所有失败回调
                var i:Number = callbacks.length;
                while (--i >= 0) {
                    (function(callback:Function):Void {
                        // 模拟异步执行
                        callback(self._reason);
                    })(callbacks[i]);
                }
            }
        };

        // 尝试执行执行器函数，并传入 resolve 和 reject
        try {
            executor(this._resolve, this._reject);
        } catch (e:Object) {
            // 如果执行器函数抛出异常，调用 reject
            this._reject(e);
        }
    }

    // 将 resolve 和 reject 定义为实例方法，避免闭包带来的性能开销
    private var _resolve:Function;
    private var _reject:Function;

    /**
     * 添加成功和失败的处理函数
     * @param onFulfilled 当 Promise 成功时调用的函数
     * @param onRejected 当 Promise 失败时调用的函数
     * @return 返回一个新的 Promise，用于链式调用
     */
    public function then(onFulfilled:Function, onRejected:Function):Promise {
        var self:Promise = this;

        // 创建并返回一个新的 Promise，用于链式调用
        var promise2:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            /**
             * fulfilled 函数，当当前 Promise 成功时调用
             * @param value 当前 Promise 的成功值
             */
            function fulfilled(value:Object):Void {
                try {
                    // 如果 onFulfilled 是函数，调用并传递值，否则直接传递值
                    var x:Object = isFunction(onFulfilled) ? onFulfilled(value) : value;
                    // 解析返回值并决定如何处理
                    resolvePromise(promise2, x, resolve, reject);
                } catch (e:Object) {
                    // 如果发生错误，拒绝新 Promise
                    reject(e);
                }
            }

            /**
             * rejected 函数，当当前 Promise 失败时调用
             * @param reason 当前 Promise 的失败原因
             */
            function rejected(reason:Object):Void {
                try {
                    if (isFunction(onRejected)) {
                        // 如果 onRejected 是函数，调用并传递原因
                        var x:Object = onRejected(reason);
                        // 解析返回值并决定如何处理
                        resolvePromise(promise2, x, resolve, reject);
                    } else {
                        // 如果 onRejected 不是函数，直接拒绝新 Promise
                        reject(reason);
                    }
                } catch (e:Object) {
                    // 如果发生错误，拒绝新 Promise
                    reject(e);
                }
            }

            // 根据当前 Promise 的状态决定如何处理
            if (self._state == "fulfilled") {
                // 如果当前 Promise 已成功，异步调用 fulfilled
                fulfilled(self._value);
            } else if (self._state == "rejected") {
                // 如果当前 Promise 已失败，异步调用 rejected
                rejected(self._reason);
            } else if (self._state == "pending") {
                // 如果当前 Promise 仍在等待中，将回调函数添加到对应的数组中
                self._onFulfilledCallbacks.push(fulfilled);
                self._onRejectedCallbacks.push(rejected);
            }
        });

        return promise2;
    }

    /**
     * 添加失败的处理函数
     * @param onRejected 当 Promise 失败时调用的函数
     * @return 返回一个新的 Promise，用于链式调用
     */
    public function onCatch(onRejected:Function):Promise {
        // 'catch' 是 AS2 的保留关键字，所以使用 'onCatch' 代替
        return this.then(null, onRejected);
    }

    /**
     * 辅助函数，检查对象是否为函数
     * @param obj 要检查的对象
     * @return 如果对象是函数，返回 true，否则返回 false
     */
    private static function isFunction(obj:Object):Boolean {
        return typeof(obj) == "function";
    }

    /**
     * 内部函数，根据返回的值来解析 Promise
     * @param promise 要解析的 Promise
     * @param x 回调函数返回的值
     * @param resolve Promise 的 resolve 函数
     * @param reject Promise 的 reject 函数
     */
    private static function resolvePromise(promise:Promise, x:Object, resolve:Function, reject:Function):Void {
        var then:Object;
        var called:Boolean = false;

        // 如果 promise 和 x 指向同一对象，抛出类型错误，防止循环引用
        if (promise === x) {
            reject(new Error("TypeError: Chaining cycle detected for promise"));
            return;
        }

        // 如果 x 是对象或函数，可能是一个 Promise
        if (x != null && (typeof(x) == "object" || isFunction(x))) {
            try {
                // 尝试获取 x 的 then 方法
                then = x.then;
                if (isFunction(then)) {
                    // 调用 then 方法，将 x 作为 this，并传入两个回调函数
                    then.call(x, function(y:Object):Void {
                        if (called) return;
                        called = true;
                        // 递归解析 y
                        resolvePromise(promise, y, resolve, reject);
                    }, function(r:Object):Void {
                        if (called) return;
                        called = true;
                        // 拒绝 Promise
                        reject(r);
                    });
                } else {
                    // 如果 then 不是函数，直接成功
                    resolve(x);
                }
            } catch (e:Object) {
                if (called) return;
                called = true;
                // 如果获取 then 方法或调用 then 方法时抛出错误，拒绝 Promise
                reject(e);
            }
        } else {
            // 如果 x 不是对象或函数，直接成功
            resolve(x);
        }
    }

    /**
     * 重写 toString 方法，提供 Promise 的当前状态和值/原因的字符串表示
     * @return Promise 的字符串表示
     */
    public function toString():String {
        var result:String = "[Promise state: " + this._state;

        if (this._state == "fulfilled") {
            // 如果 Promise 成功，显示成功值
            result += ", value: " + this._value;
        } else if (this._state == "rejected") {
            // 如果 Promise 失败，显示失败原因
            result += ", reason: " + this._reason;
        }

        result += "]";
        return result;
    }

    // ---------------------- 静态方法部分 ----------------------

    /**
     * Promise.resolve 静态方法
     * @param value 要解析的值
     * @return 一个以给定值解析后的 Promise
     */
    public static function resolve(value:Object):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            resolve(value);
        });
    }

    /**
     * Promise.reject 静态方法
     * @param reason 要拒绝的原因
     * @return 一个以给定原因拒绝的 Promise
     */
    public static function reject(reason:Object):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            reject(reason);
        });
    }

    /**
     * Promise.all 静态方法
     * @param promises 一个包含多个 Promise 的数组
     * @return 一个新的 Promise，当所有输入的 Promise 都成功时解析为结果数组，若有任意一个失败则拒绝
     */
    public static function all(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            if (promises.length === 0) {
                resolve([]);
                return;
            }

            var results:Array = [];
            var completed:Number = 0;
            var hasRejected:Boolean = false;

            for (var i:Number = 0; i < promises.length; i++) {
                (function(index:Number):Void {
                    var p:Promise = promises[index];
                    Promise.resolve(p).then(function(value:Object):Void {
                        if (hasRejected) return;
                        results[index] = value;
                        completed++;
                        if (completed === promises.length) {
                            resolve(results);
                        }
                    }, function(reason:Object):Void {
                        if (hasRejected) return;
                        hasRejected = true;
                        reject(reason);
                    });
                })(i);
            }
        });
    }

    /**
     * Promise.race 静态方法
     * @param promises 一个包含多个 Promise 的数组
     * @return 一个新的 Promise，当任意一个输入的 Promise 首先完成（成功或失败）时，立即解析或拒绝
     */
    public static function race(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            if (promises.length === 0) {
                // 如果传入的数组为空，则 Promise 永远不会完成
                return;
            }

            for (var i:Number = 0; i < promises.length; i++) {
                (function(p:Promise):Void {
                    Promise.resolve(p).then(function(value:Object):Void {
                        resolve(value);
                    }, function(reason:Object):Void {
                        reject(reason);
                    });
                })(promises[i]);
            }
        });
    }

    /**
     * Promise.allSettled 静态方法
     * @param promises 一个包含多个 Promise 的数组
     * @return 一个新的 Promise，当所有输入的 Promise 都完成（无论成功或失败）时，解析为结果数组
     */
    public static function allSettled(promises:Array):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            if (promises.length === 0) {
                resolve([]);
                return;
            }

            var results:Array = [];
            var completed:Number = 0;

            for (var i:Number = 0; i < promises.length; i++) {
                (function(index:Number):Void {
                    var p:Promise = promises[index];
                    Promise.resolve(p).then(function(value:Object):Void {
                        results[index] = { status: "fulfilled", value: value };
                        completed++;
                        if (completed === promises.length) {
                            resolve(results);
                        }
                    }, function(reason:Object):Void {
                        results[index] = { status: "rejected", reason: reason };
                        completed++;
                        if (completed === promises.length) {
                            resolve(results);
                        }
                    });
                })(i);
            }
        });
    }
}
