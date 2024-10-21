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

import org.as2lib.env.event.distributor.EventDistributorControl;
import org.as2lib.env.event.distributor.SimpleEventDistributorControl;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.io.conn.core.server.AbstractServerServiceProxy;
import org.as2lib.io.conn.core.server.ServerServiceProxy;
import org.as2lib.io.conn.core.server.ReservedServiceException;
import org.as2lib.io.conn.core.event.MethodInvocationErrorListener;
import org.as2lib.io.conn.core.event.MethodInvocationErrorInfo;
import org.as2lib.io.conn.local.core.EnhancedLocalConnection;

/**
 * {@code LocalServerServiceProxy} handles client requests to a certain service and
 * its responses.
 * 
 * <p>This client requests normally come from a client service proxy because this
 * class is designed to interact with this type of client.
 *
 * <p>You can setup your service proxy as follows to await client requests:
 * <code>
 *   var service:LocalServerServiceProxy = new LocalServerServiceProxy("myService", new MyService());
 *   service.run();
 * </code>
 * 
 * <p>A client may then invoke a method on this service proxy.
 * <code>
 *   var client = new LocalClientServiceProxy("myService");
 *   var callback:MethodInvocationCallback = client.myMethod("firstArgument", "secondArgument");
 * </code>
 * 
 * <p>You may choose to combine multiple services in one server for easier usage.
 * <code>
 *   var server:LocalServer = new LocalServer("local.as2lib.org");
 *   server.addService(new LocalServerServiceProxy("myServiceOne", new MyServiceOne()));
 *   server.addService(new LocalServerServiceProxy("myServiceTwo", new MyServiceTwo()));
 *   server.run();
 * </code>
 *
 * <p>A client must then prefix the service's name with the host of the server.
 * <code>
 *   var client = new LocalClientServiceProxy("local.as2lib.org/myService");
 *   var callback:MethodInvocationCallback = client.myMethod("firstArgument", "secondArgument");
 * </code>
 * 
 * <p>If the client invokes a method with arguments on this service that are not of
 * type {@code Number}, {@code String}, {@code Boolean} or {@code Array} which are
 * converted dynamically to the correct type, Flash just creates a new object of type
 * {@code Object} and populates it with the instance variables of the passed object.
 * To receive an instance of correct type you must thus register the class. Note
 * that the client must register the same class with the same name. This registration
 * must also be done for return values on the client and the server.
 * <code>
 *   Object.registerClass("MyClass", MyClass);
 * </code>
 * 
 * <p>The received object will now be of correct type. But you still have to be aware
 * of some facts.<br>
 * Flash creates a new object in the background and sets the instance variables of
 * the sent instance to the new object. It then registers this object to the appropriate
 * class (if registered previously) and applies the constructor of that class to the
 * new object passing no arguments. This means if the constructor sets instance variables
 * it overwrites the ones set previously by {@code undefined}.
 *
 * @author Simon Wacker
 * @author Christoph Atteneder
 */
class org.as2lib.io.conn.local.server.LocalServerServiceProxy extends AbstractServerServiceProxy implements ServerServiceProxy {
	
	/** The wrapped service object. */
	private var service;
	
	/** The service path. */
	private var path:String;
	
	/** Used to run this service. */
	private var connection:EnhancedLocalConnection;
	
	/** Stores set error listeners and controls the {@code errorDistributor}. */
	private var errorDistributorControl:EventDistributorControl;
	
	/** Distributes to all added error listeners. */
	private var errorDistributor:MethodInvocationErrorListener;
	
	/** This service's status. */
	private var running:Boolean;
	
	/** Stores the current service url. */
	private var currentServiceUrl:String;
	
	/**
	 * Constructs a new {@code LocalServerServiceProxy} instance.
	 * 
	 * @param path the path of this service
	 * @param service object that provides the service's operations
	 * @throws IllegalArgumentException if {@code path} is {@code null}, {@code undefined}
	 * or an empty string or if {@code service} is {@code null} or {@code undefined}
	 */
	public function LocalServerServiceProxy(path:String, service) {
		if (!path || !service) throw new IllegalArgumentException("Neither the path [" + path + "] nor the service [" + service + "] are allowed to be null, undefined or a blank string.", this, arguments);
		this.path = path;
		this.service = service;
		running = false;
		currentServiceUrl = null;
		errorDistributorControl = new SimpleEventDistributorControl(MethodInvocationErrorListener, false);
		errorDistributor = errorDistributorControl.getDistributor();
	}
	
	/**
	 * Returns the currently used connection.
	 *
	 * <p>This is either the connection set via the {@link #setConnection} method or
	 * the default one which is an instance of class {@link EnhancedLocalConnection}.
	 * 
	 * @return the currently used connection
	 */
	public function getConnection(Void):EnhancedLocalConnection {
		if (!connection) connection = new EnhancedLocalConnection(this);
		return connection;
	}
	
	/**
	 * Sets a new connection.
	 *
	 * <p>If {@code connection} is {@code null} or {@code undefined}, {@link #getConnection}
	 * will return the default connection.
	 * 
	 * @param connection the new connection
	 */
	public function setConnection(connection:EnhancedLocalConnection):Void {
		this.connection = connection;
	}
	
	/**
	 * Runs this service proxy on the passed-in {@code host}.
	 *
	 * <p>This service proxy will be restarted if it is already running. This means it
	 * it first stops itself and starts itself again.
	 * 
	 * <p>Only the path of this service proxy is used to connect if the passed-in {@code host}
	 * is {@code null}, {@code undefined} or an empty string.
	 * 
	 * @param host the host to run the service on
	 * @throws ReservedServiceException if a service on the passed-in {@code host} with
	 * the service's path is already in use
	 */
	public function run(host:String):Void {
		if (isRunning()) this.stop();
		try {
			currentServiceUrl = generateServiceUrl(host, path);
			getConnection().connect(currentServiceUrl);
			running = true;
		} catch(exception:org.as2lib.io.conn.local.core.ReservedConnectionException) {
			// "new ReservedServiceException" without braces is not MTASC compatible
			throw (new ReservedServiceException("Service with url [" + currentServiceUrl + "] is already in use.", this, arguments)).initCause(exception);
		}
	}
	
	/**
	 * Stops this service.
	 */
	public function stop(Void):Void {
		getConnection().close();
		running = false;
		currentServiceUrl = null;
	}
	
	/**
	 * Handles incoming 'remote' method invocations on the service.
	 * 
	 * <p>The method corresponding to the passed-in {@code methodName} is invoked on the
	 * wrapped service.
	 *
	 * <p>The error listeners will be informed of a failure if:
	 * <ul>
	 *   <li>
	 *     A method with the passed-in {@code methodName} does not exist on the wrapped
	 *     service.
	 *   </li>
	 *   <li>The service method threw an exception.</li>
	 * </ul>
	 * 
	 * @param methodName the name of the method to invoke on the service
	 * @param args the arguments to use as parameters when invoking the method
	 */
	public function invokeMethodByNameAndArguments(methodName:String, args:Array):Void {
		try {
			if (service[methodName]) {
				service[methodName].apply(service, args);
			} else {
				errorDistributor.onError(new MethodInvocationErrorInfo(currentServiceUrl, methodName, args, MethodInvocationErrorInfo.UNKNOWN_METHOD_ERROR, null));
			}
		} catch (exception) {
			errorDistributor.onError(new MethodInvocationErrorInfo(currentServiceUrl, methodName, args, MethodInvocationErrorInfo.METHOD_EXCEPTION_ERROR, exception));
		}
	}
	
	/**
	 * Handles incoming 'remote' method invocations on the service and responses through
	 * the {@code responseServiceUrl}.
	 * 
	 * <p>The method corresponding to the passed-in {@code methodName} is invoked on the
	 * service and the response of this invocation is passed through the
	 * {@code responseServiceUrl} to the client.
	 *
	 * <p>If the response service url is {@code null} or an empty string the 
	 * {@link #invokeMethodByNameAndArguments} method is invoked instead.
	 * 
	 * <p>The response service is supposed to implement two methods with the following
	 * signature:
	 * <ul>
	 *   <li>onReturn(returnValue):Void</li>
	 *   <li>onError(errorCode:Number, exception):Void</li>
	 * </ul>
	 * 
	 * <p>The {@code onReturn} method is invoked on the response service if the method
	 * returned successfully.
	 * 
	 * <p>The {@code onError} method is invoked on the response service if:
	 * <ul>
	 *   <li>The method threw an exception.</li>
	 *   <li>The method does not exist on the service.</li>
	 * </ul>
	 *
	 * <p>The error listeners will be informed of a failure if:
	 * <ul>
	 *   <li>
	 *     A method with the passed-in {@code methodName} does not exist on the wrapped
	 *     service.
	 *   </li>
	 *   <li>The service method threw an exception.</li>
	 *   <li>
	 *     The response server with the given {@code responseServiceUrl} does not exist.
	 *   </li>
	 *   <li>The return value is too big to send over a local connection.</li>
	 *   <li>An unknown failure occured when trying to send the response.</li>
	 * </ul>
	 * 
	 * @param methodName the name of the method to invoke on the service
	 * @param args the arguments to use as parameters when invoking the method
	 * @param responseServiceUrl the url to the service that handles the response
	 */
	public function invokeMethodByNameAndArgumentsAndResponseService(methodName:String, args:Array, responseServiceUrl:String):Void {
		if (!responseServiceUrl) {
			invokeMethodByNameAndArguments(methodName, args);
			return;
		}
		var listener:MethodInvocationErrorListener = getBlankMethodInvocationErrorListener();
		var owner:LocalServerServiceProxy = this;
		listener.onError = function(info:MethodInvocationErrorInfo):Void {
			// "owner.errorDistributor" and "owner.currentServiceUrl" are not MTASC compatible
			owner["errorDistributor"].onError(new MethodInvocationErrorInfo(owner["currentServiceUrl"], methodName, args, MethodInvocationErrorInfo.UNKNOWN_ERROR, null));
		};
		try {
			if (service[methodName]) {
				var returnValue = service[methodName].apply(service, args);
				sendResponse(methodName, args, responseServiceUrl, "onReturn", [returnValue], listener);
			} else {
				sendResponse(methodName, args, responseServiceUrl, "onError", [MethodInvocationErrorInfo.UNKNOWN_METHOD_ERROR, null], listener);
				errorDistributor.onError(new MethodInvocationErrorInfo(currentServiceUrl, methodName, args, MethodInvocationErrorInfo.UNKNOWN_METHOD_ERROR, null));
			}
		} catch (serviceMethodException) {
			sendResponse(methodName, args, responseServiceUrl, "onError", [MethodInvocationErrorInfo.METHOD_EXCEPTION_ERROR, serviceMethodException], listener);
			errorDistributor.onError(new MethodInvocationErrorInfo(currentServiceUrl, methodName, args, MethodInvocationErrorInfo.METHOD_EXCEPTION_ERROR, serviceMethodException));
		}
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
	 * Sends a response to the client.
	 * 
	 * @param methodName the name of the method
	 * @param methodArguments the arguments used for the method invocation
	 * @param responseServiceUrl the url of the response service
	 * @param responseMethod the response method to invoke on the response service
	 * @param responseArguments the arguments to pass to the response method
	 * @param responseListener the listener that listens for failures that may occur when
	 * sending the response
	 */
	private function sendResponse(methodName:String, methodArguments:Array, responseServiceUrl:String, responseMethod:String, responseArguments:Array, responseListener:MethodInvocationErrorListener):Void {
		try {
			getConnection().send(responseServiceUrl, responseMethod, responseArguments, responseListener);
		} catch (uce:org.as2lib.io.conn.local.core.UnknownConnectionException) {
			errorDistributor.onError(new MethodInvocationErrorInfo(currentServiceUrl, methodName, methodArguments, MethodInvocationErrorInfo.UNKNOWN_SERVICE_ERROR, uce));
		} catch (mie:org.as2lib.io.conn.core.client.MethodInvocationException) {
			errorDistributor.onError(new MethodInvocationErrorInfo(currentServiceUrl, methodName, methodArguments, MethodInvocationErrorInfo.OVERSIZED_ARGUMENTS_ERROR, mie));
		}
	}
	
	/**
	 * Returns the wrapped service.
	 *
	 * @return the wrapped service
	 */
	public function getService(Void) {
		return service;
	}
	
	/**
	 * Returns the path of this service.
	 */
	public function getPath(Void):String {
		return path;
	}
	
	/**
	 * Returns whether this service is running or not.
	 *
	 * @return {@code true} if this service is running else {@code false}
	 */
	public function isRunning(Void):Boolean {
		return running;
	}
	
	/**
	 * Adds an error listener.
	 * 
	 * <p>Error listeners are notified when a client tried to invoke a method on this
	 * service and something went wrong.
	 * 
	 * @param errorListener the new error listener to add
	 */
	public function addErrorListener(errorListener:MethodInvocationErrorListener):Void {
		errorDistributorControl.addListener(errorListener);
	}
	
	/**
	 * Removes an error listener.
	 *
	 * <p>Error listeners are notified when a client tried to invoke a method on this
	 * service and something went wrong.
	 *
	 * @param errorListener the error listener to remove
	 */
	public function removeErrorListener(errorListener:MethodInvocationErrorListener):Void {
		errorDistributorControl.removeListener(errorListener);
	}
	
}