/*
 * Copyright the original author or authors.
 * 
 * Licensed under the MOZILLA PUBLIC LICENSE, Version 1.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.mozilla.org/MPL/MPL-1.1.html
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.io.conn.core.client.ClientServiceProxy;
import org.as2lib.io.conn.core.client.AbstractClientServiceProxy;
import org.as2lib.io.conn.core.client.UnknownServiceException;
import org.as2lib.io.conn.core.server.ReservedServiceException;
import org.as2lib.io.conn.core.event.MethodInvocationCallback;
import org.as2lib.io.conn.core.event.MethodInvocationReturnInfo;
import org.as2lib.io.conn.core.event.MethodInvocationErrorInfo;
import org.as2lib.io.conn.core.event.MethodInvocationErrorListener;
import org.as2lib.io.conn.local.core.EnhancedLocalConnection;

/**
 * {@code LocalClientServiceProxy} handles client requests to a certain service
 * and its responses.
 * 
 * <p>Example:
 * <code>
 *   var client:LocalClientServiceProxy = new LocalClientServiceProxy("local.as2lib.org/myService");
 *   var callback:MethodInvocationCallback = client.invoke("myMethod", ["firstArgument", "secondArgument"]);
 *   callback.onReturn = function(returnInfo:MethodInvocationReturnInfo):Void {
 *       trace("myMethod - return value: " + returnInfo.getReturnValue());
 *   }
 *   callback.onError = function(errorInfo:MethodInvocationErrorInfo):Void {
 *       trace("myMethod - error: " + errorInfo.getException());
 *   }
 * </code>
 * 
 * <p>It is also possible to call the method directly on the proxy. But you can't
 * type the proxy then.
 * <code>
 *   var client = new LocalClientServiceProxy("local.as2lib.org/myService");
 *   var callback:MethodInvocationCallback = client.myMethod("firstArgument", "secondArgument");
 * </code>
 *
 * <p>The neatest way is to use {@code LocalClientServiceProxyFactory} to get a proxy
 * for a service interface or class, which enables compiler checks. For more
 * information on this refer to the {@link LocalClientServiceProxyFactory} class.
 * 
 * <p>If the return value is not of type {@code Number}, {@code Boolean}, {@code String}
 * or {@code Array} that are converted directly into the appropriate type you must
 * do the following to receive a value of correct type. Otherwise the return value
 * will be an instance of type Object that is populated with the instance variables
 * of the sent object. Note that this must be done on the client as well as on the
 * server and the 'symbolId' in this case {@code "MyClass"} must be the same.
 * <code>
 *   Object.registerClass("MyClass", MyClass);
 * </code>
 * 
 * <p>The received object will now be of correct type. But you still have to be aware
 * of some facts:<br>
 * Flash creates a new object in the background and sets the instance variables of
 * the sent instance to the new object. It then registers this object with the
 * appropriate class (if registered previously) and applies the constructor of that
 * class to the new object passing no arguments. This means if the constructor sets
 * instance variables it overwrites the ones set previously by {@code undefined}.
 *
 * @author Simon Wacker
 * @author Christoph Atteneder
 * @see org.as2lib.io.conn.local.client.LocalClientServiceProxyFactory
 */
class org.as2lib.io.conn.local.client.LocalClientServiceProxy extends AbstractClientServiceProxy implements ClientServiceProxy {
	
	/**
	 * Generates the response url for a service.
	 * 
	 * <p>The response url is composed as follows:
	 * <pre>theServiceUrl.theMethodName_Return_theIndex</pre>
	 * 
	 * <p>If the passed-in {@code methodName} is {@code null}, {@code undefined} or an
	 * empty string the response url will be composed as follows:
	 * <pre>theServiceUrl_Return_theIndex</pre>
	 *
	 * <p>{@code index} is a number from 0 to infinite depending on how many responses
	 * are pending.
	 * 
	 * @param serviceUrl the url to the service
	 * @param methodName the name of the responsing method
	 * @return the generated response url
	 * @throws IllegalArgumentException if the passed-in {@code serviceUrl} is {@code null},
	 * {@code undefined} or an empty stirng
	 */
	public static function generateResponseServiceUrl(serviceUrl:String, methodName:String):String {
		if (!serviceUrl) throw new IllegalArgumentException("Service url must not be null, undefined or an empty string.", eval("th" + "is"), arguments);
		if (!methodName) {
			var result:String = serviceUrl + "_Return";
			var i:Number = 0;
			while (EnhancedLocalConnection.connectionExists(result + "_" + i)) {
				i++;
			}
			return (result + "_" + i);
		} else {
			var result:String = serviceUrl + "_" + methodName + "_Return";
			var i:Number = 0;
			while (EnhancedLocalConnection.connectionExists(result + "_" + i)) {
				i++;
			}
			return (result + "_" + i);
		}
	}
	
	/** The url of the service. */
	private var url:String;
	
	/** Used EnhancedLocalConnection. */
	private var connection:EnhancedLocalConnection;
	
	/** Stores all currently used response services. */
	private var responseServices:Array;
	
	/**
	 * Constructs a new {@code LocalClientServiceProxy} instance.
	 * 
	 * @param url the url of the service
	 * @throws IllegalArgumentException if {@code url} is {@code null}, {@code undefined}
	 * or an empty string
	 */
	public function LocalClientServiceProxy(url:String) {
		if (!url) throw new IllegalArgumentException("Argument 'url' must not be null, undefined or an empty string.", this, arguments);
		this.url = url;
		connection = new EnhancedLocalConnection();
		responseServices = new Array();
	}
	
	/**
	 * Returns the url of the service this proxy invokes methods on.
	 * 
	 * <p>The returned url is never {@code null}, {@code undefined} or an empty string.
	 *
	 * @return the url of the service this proxy invokes methods on
	 */
	public function getUrl(Void):String {
		return url;
	}
	
	/**
	 * Invokes the method with passed-in {@code methodName} on the 'remote' service,
	 * passing the elements of the passed-in {@code args} as parameters and invokes
	 * the appropriate method on the passed-in {@code callback} on response.
	 * 
	 * <p>The response of the method invocation is delegated to the appropriate method
	 * on the passed-in {@code callback}. This is either the {@code onReturn} when no
	 * error occured, or the {@code onError} method in case something went wrong.
	 *
	 * <p>If the passed-in {@code callback} is {@code null} a new {@code MethodInvocationCallback}
	 * instance will be created and returned. It is possible to still set the callback
	 * methods there, after invoking this method.
	 * 
	 * @param methodName the name of the method to invoke on the 'remote' service
	 * @param args the arguments that are passed to the method as parameters
	 * @param callback the callback that handles the response
	 * @return either the passed-in callback or a new callback if {@code null}
	 * @throws IllegalArgumentException if the passed-in {@code methodName} is {@code null},
	 * {@code undefined} or an empty string
	 */
	public function invokeByNameAndArgumentsAndCallback(methodName:String, args:Array, callback:MethodInvocationCallback):MethodInvocationCallback {
		if (!methodName) throw new IllegalArgumentException("Argument 'methodName' must not be null, undefined or an empty string.", this, arguments);
		if (!args) args = new Array();
		if (!callback) callback = getBlankMethodInvocationCallback();
		
		var responseUrl:String = generateResponseServiceUrl(url, methodName);
		
		var responseService:EnhancedLocalConnection = new EnhancedLocalConnection();
		var index:Number = responseServices.push(responseService) - 1;
		var owner:LocalClientServiceProxy = this;
		responseService["onReturn"] = function(returnValue):Void {
			// "owner.responseServices" is not MTASC compatible because "responseServices" is private
			owner["responseServices"].splice(index, 1);
			// "owner.url" is not MTASC compatible because "url" is private
			callback.onReturn(new MethodInvocationReturnInfo(owner["url"], methodName, args, returnValue));
			this.close();
		};
		responseService["onError"] = function(errorCode:Number, exception):Void {
			// "owner.responseServices" is not MTASC compatible because "responseServices" is private
			owner["responseServices"].splice(index, 1);
			// "owner.url" is not MTASC compatible because "url" is private
			callback.onError(new MethodInvocationErrorInfo(owner["url"], methodName, args, errorCode, exception));
			this.close();
		};
		try {
			responseService.connect(responseUrl);
		} catch (exception:org.as2lib.io.conn.local.core.ReservedConnectionException) {
			// "new ReservedServiceException" without braces is not MTASC compatible
			throw (new ReservedServiceException("Response service with url [" + responseUrl + "] does already exist.", this, arguments)).initCause(exception);
		}
		
		var errorListener:MethodInvocationErrorListener = getBlankMethodInvocationErrorListener();
		errorListener.onError = function(info:MethodInvocationErrorInfo) {
			callback.onError(info);
		};
		
		try {
			connection.send(url, "invokeMethod", [methodName, args, responseUrl], errorListener);
		} catch (exception:org.as2lib.io.conn.local.core.UnknownConnectionException) {
			// "new UnknownServiceException" without braces is not MTASC compatible
			throw (new UnknownServiceException("Service with url [" + url + "] does not exist.", this, arguments)).initCause(exception);
		}
		
		return callback;
	}
	
	/**
	 * Returns a blank method invocation error listener. This is an error listern with
	 * no implemented methods.
	 * 
	 * @return a blank method invocation error listener
	 */
	private function getBlankMethodInvocationErrorListener(Void):MethodInvocationErrorListener {
		var result = new Object();
		result.__proto__ = MethodInvocationErrorListener["prototype"];
		result.__constructor__ = MethodInvocationErrorListener;
		return result;
	}
	
	/**
	 * Returns a blank method invocation callback. This is a callback with no implemented
	 * methods.
	 * 
	 * @return a blank method invocation callback
	 */
	private function getBlankMethodInvocationCallback(Void):MethodInvocationCallback {
		var result = new Object();
		result.__proto__ = MethodInvocationCallback["prototype"];
		result.__constructor__ = MethodInvocationCallback;
		return result;
	}
	
	/**
	 * Enables you to invoke the method to be invoked on the 'remote' service directly
	 * on this proxy.
	 * 
	 * <p>The usage is mostly the same.
	 * <code>myProxy.myMethod("myArg1");</code>
	 * <code>myProxy.myMethod("myArg1", myCallback);</code>
	 * <code>var callback:MethodInvocationCallback = myProxy.myMethod("myArg1");</code>
	 * 
	 * @param methodName the name of the method to invoke on the 'remote' service
	 * @return the function to execute as the actual method passing the actual arguments
	 */
	private function __resolve(methodName:String):Function {
		var owner:ClientServiceProxy = this;
		return (function():MethodInvocationCallback {
			if (arguments[arguments.length] instanceof MethodInvocationCallback) {
				return owner.invokeByNameAndArgumentsAndCallback(methodName, arguments, MethodInvocationCallback(arguments.pop()));
			} else {
				return owner.invokeByNameAndArgumentsAndCallback(methodName, arguments, null);
			}
		});
	}

}