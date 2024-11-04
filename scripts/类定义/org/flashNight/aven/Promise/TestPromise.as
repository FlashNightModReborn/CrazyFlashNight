import org.flashNight.aven.Promise.*;

class org.flashNight.aven.Promise.TestPromise {
    public static function main():Void {
        // Basic successful Promise
        var promiseSuccess:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            // Simulate asynchronous operation
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

        // Basic failed Promise
        var promiseFailure:Promise = new Promise(function(resolve:Function, reject:Function):Void {
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

        // Promise chaining
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

        // Exception handling
        var errorPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            throw new Error("An exception occurred");
        });

        errorPromise.onCatch(function(reason:Object):Void {
            trace("Exception caught: " + reason.message);
        });

        // Multiple then calls
        var multipleThenPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve("Resolved once");
        });

        multipleThenPromise.then(function(value:Object):Void {
            trace("First then (multiple then test): " + value);
        });

        multipleThenPromise.then(function(value:Object):Void {
            trace("Second then (multiple then test): " + value);
        });

        // Nested Promise
        var nestedPromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(new Promise(function(innerResolve:Function, innerReject:Function):Void {
                innerResolve("Nested promise resolved");
            }));
        });

        nestedPromise.then(function(value:Object):Void {
            trace("Nested promise test: " + value);
        });

        // Null value test
        var nullValuePromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(null);
        });

        nullValuePromise.then(function(value:Object):Void {
            trace("Null value test: " + (value === null ? "null" : "not null"));
        });

        // Undefined value test
        var undefinedValuePromise:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(undefined);
        });

        undefinedValuePromise.then(function(value:Object):Void {
            trace("Undefined value test: " + (value === undefined ? "undefined" : "defined"));
        });

        // Mixed synchronous and asynchronous calls
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

        // Multiple resolve/reject calls
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

        // Promise resolving with another Promise as value
        var promiseWithPromiseValue:Promise = new Promise(function(resolve:Function, reject:Function):Void {
            resolve(new Promise(function(innerResolve:Function, innerReject:Function):Void {
                innerResolve("Inner promise resolved");
            }));
        });

        promiseWithPromiseValue.then(function(value:Object):Void {
            trace("Promise with promise as value: " + value);
        });
    }
}
