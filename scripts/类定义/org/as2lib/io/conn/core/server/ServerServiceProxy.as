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

import org.as2lib.core.BasicInterface;
import org.as2lib.io.conn.core.event.MethodInvocationErrorListener;

/**
 * {@code ServerServiceProxy} handles client requests to a certain service and its
 * responses.
 * 
 * @author Simon Wacker
 * @author Christoph Atteneder
 */
interface org.as2lib.io.conn.core.server.ServerServiceProxy extends BasicInterface {
	
	/**
	 * Runs the service and listens for requests of clients.
	 *
	 * @param host the host to run this service on
	 */
	public function run(host:String):Void;
	
	/**
	 * Stops this service.
	 */
	public function stop(Void):Void;
	
	/**
	 * @overload #invokeMethodByNameAndArguments
	 * @overload #invokeMethodByNameAndArgumentsAndResponseService
	 */
	public function invokeMethod():Void;
	
	/**
	 * Invokes the service method corresponding to the passed-in {@code methodName} on
	 * the actaul service object, passing the content of {@code args} array as parameters.
	 * 
	 * @param methodName the name of the service method to invoke
	 * @param args arguments to pass-to the method
	 */
	public function invokeMethodByNameAndArguments(methodName:String, args:Array):Void;
	
	/**
	 * Invokes the service method corresponding to the passed-in {@code methodName} on
	 * the actual service object and returns the response to the client using the
	 * passed-in {@code responseServiceUrl}.
	 *
	 * @param methodName name of method to invoke on the service
	 * @param args arguments to pass to the method
	 * @param responseServiceUrl the url of response service to which the result is sent
	 */
	public function invokeMethodByNameAndArgumentsAndResponseService(methodName:String, args:Array, responseServiceUrl:String):Void;
	
	/**
	 * Returns the actual service this proxy wraps.
	 *
	 * @return the wrapped service
	 */
	public function getService(Void);
	
	/**
	 * Returns the path on the host of this service.
	 *
	 * @return the path of this service
	 */
	public function getPath(Void):String;
	
	/**
	 * Indicates whether this service is currently running.
	 *
	 * @return {@code true} if this service runs else {@code false}
	 */
	public function isRunning(Void):Boolean;
	
	/**
	 * Adds a new error listener to listen for errors that may occur when trying to
	 * invoke a method on this service.
	 * 
	 * @param errorListener the error listener to add
	 * @see #removeErrorListener
	 */
	public function addErrorListener(errorListener:MethodInvocationErrorListener):Void;
	
	/**
	 * Removes an added error listener.
	 *
	 * @param errorListener the error listener to remove
	 * @see #addErrorListener
	 */
	public function removeErrorListener(errorListener:MethodInvocationErrorListener):Void;
	
}