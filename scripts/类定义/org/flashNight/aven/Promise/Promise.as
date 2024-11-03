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
        // 初始化 Promise 的状态
        this._state = "pending";
        this._value = null;
        this._reason = null;
        this._onFulfilledCallbacks = [];
        this._onRejectedCallbacks = [];

        // 缓存当前对象的引用，供内部函数使用
        var self:Promise = this;

        /**
         * resolve 函数，用于将 Promise 标记为成功
         * @param value 要传递的成功值
         */
        function resolve(value:Object):Void {
            // 只有在 pending 状态下才能改变状态
            if (self._state == "pending") {
                self._state = "fulfilled";
                self._value = value;

                // 执行所有成功的回调函数
                var callbacksLength:Number = self._onFulfilledCallbacks.length;
                for (var i:Number = 0; i < callbacksLength; i++) {
                    // 调用每个回调函数，传递成功值
                    self._onFulfilledCallbacks[i](self._value);
                }

                // 清空回调数组，释放内存
                self._onFulfilledCallbacks = null;
                self._onRejectedCallbacks = null;
            }
        }

        /**
         * reject 函数，用于将 Promise 标记为失败
         * @param reason 要传递的失败原因
         */
        function reject(reason:Object):Void {
            // 只有在 pending 状态下才能改变状态
            if (self._state == "pending") {
                self._state = "rejected";
                self._reason = reason;

                // 执行所有失败的回调函数
                var callbacksLength:Number = self._onRejectedCallbacks.length;
                for (var i:Number = 0; i < callbacksLength; i++) {
                    // 调用每个回调函数，传递失败原因
                    self._onRejectedCallbacks[i](self._reason);
                }

                // 清空回调数组，释放内存
                self._onFulfilledCallbacks = null;
                self._onRejectedCallbacks = null;
            }
        }

        // 尝试执行执行器函数，传入 resolve 和 reject
        try {
            executor(resolve, reject);
        } catch (e:Object) {
            // 如果发生错误，调用 reject
            reject(e);
        }
    }

    /**
     * 添加成功和失败的处理函数
     * @param onFulfilled 当 Promise 成功时调用的函数
     * @param onRejected 当 Promise 失败时调用的函数
     * @return 返回一个新的 Promise，用于链式调用
     */
    public function then(onFulfilled:Function, onRejected:Function):Promise {
        var self:Promise = this;

        // 创建并返回一个新的 Promise
        var promise2:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            // 如果当前 Promise 已成功
            if (self._state == "fulfilled") {
                // 为了模拟异步行为，可以使用 setTimeout 包裹
                // setTimeout(function() {
                    try {
                        // 如果 onFulfilled 是函数，调用并传递值
                        if (isFunction(onFulfilled)) {
                            var x:Object = onFulfilled(self._value);
                            resolvePromise(promise2, x, resolve, reject);
                        } else {
                            // 如果 onFulfilled 不是函数，直接传递值
                            resolve(self._value);
                        }
                    } catch (e:Object) {
                        // 如果发生错误，拒绝 Promise
                        reject(e);
                    }
                // }, 0);
            }
            // 如果当前 Promise 已失败
            else if (self._state == "rejected") {
                // 异步模拟在低版本js中使用 setTimeout 包裹，考虑到as2的环境姑且不使用
                // setTimeout(function() {
                    try {
                        // 如果 onRejected 是函数，调用并传递原因
                        if (isFunction(onRejected)) {
                            var x:Object = onRejected(self._reason);
                            resolvePromise(promise2, x, resolve, reject);
                        } else {
                            // 如果 onRejected 不是函数，直接传递原因
                            reject(self._reason);
                        }
                    } catch (e:Object) {
                        // 如果发生错误，拒绝 Promise
                        reject(e);
                    }
                // }, 0);
            }
            // 如果当前 Promise 仍在等待中
            else if (self._state == "pending") {
                // 将成功回调添加到数组中
                self._onFulfilledCallbacks.push(function(value:Object):Void {
                    try {
                        if (isFunction(onFulfilled)) {
                            var x:Object = onFulfilled(value);
                            resolvePromise(promise2, x, resolve, reject);
                        } else {
                            resolve(value);
                        }
                    } catch (e:Object) {
                        reject(e);
                    }
                });

                // 将失败回调添加到数组中
                self._onRejectedCallbacks.push(function(reason:Object):Void {
                    try {
                        if (isFunction(onRejected)) {
                            var x:Object = onRejected(reason);
                            resolvePromise(promise2, x, resolve, reject);
                        } else {
                            reject(reason);
                        }
                    } catch (e:Object) {
                        reject(e);
                    }
                });
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

    // 辅助函数，检查对象是否为函数
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

        // 如果 x 是对象或函数
        if (x != null && (typeof(x) == "object" || isFunction(x))) {
            try {
                // 尝试获取 x 的 then 方法
                then = x.then;

                if (isFunction(then)) {
                    // 调用 then 方法，将 x 作为 this
                    then.call(x, function(y:Object):Void {
                        if (called) return;
                        called = true;
                        resolvePromise(promise, y, resolve, reject);
                    }, function(r:Object):Void {
                        if (called) return;
                        called = true;
                        reject(r);
                    });
                } else {
                    // 如果 then 不是函数，直接成功
                    resolve(x);
                }
            } catch (e:Object) {
                if (called) return;
                called = true;
                reject(e);
            }
        } else {
            // 如果 x 不是对象或函数，直接成功
            resolve(x);
        }
    }
}
