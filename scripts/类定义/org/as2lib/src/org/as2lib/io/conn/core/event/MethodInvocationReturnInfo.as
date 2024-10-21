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

import org.as2lib.core.BasicClass;

/**
 * {@code MethodInvocationReturnInfo} informs clients that the method invocation
 * returned successfully.
 * 
 * <p>This class is used in conjunction with the {@link MethodInvocationCallback}
 * and {@link MethodInvocationReturnListener} classes.
 *
 * @author Simon Wacker
 */
class org.as2lib.io.conn.core.event.MethodInvocationReturnInfo extends BasicClass {
	
	/** The return value returned by the invoked method. */
	private var returnValue;
	
	/** Url of the service the method was invoked on. */
	private var serviceUrl:String;
	
	/** The name of the method that was invoked. */
	private var methodName:String;
	
	/** The arguments used for the invocation. */
	private var methodArguments:Array;
	
	/**
	 * Constructs a new {@code MethodInvocationReturnInfo} instance.
	 * 
	 * @param serviceUrl the url to the service the method was invoked on
	 * @param methodName the name of the method that was invoked
	 * @param methodArguments the arguments used as parameters for the method invocation
	 * @param returnValue the result of the method invocation
	 */
	public function MethodInvocationReturnInfo(serviceUrl:String, methodName:String, methodArguments:Array, returnValue) {
		this.serviceUrl = serviceUrl;
		this.methodName = methodName;
		this.methodArguments = methodArguments;
		this.returnValue = returnValue;
	}
	
	/**
	 * Returns the url to the service the method was invoked on.
	 *
	 * @return the url to the service the method was invoked on
	 */
	public function getServiceUrl(Void):String {
		return serviceUrl;
	}
	
	/**
	 * Returns the name of the method that was invoked on the service
	 *
	 * @return the name of the method that was invoked on the service
	 */
	public function getMethodName(Void):String {
		return methodName;
	}
	
	/**
	 * Returns the arguments used as parameters for the method invocation.
	 *
	 * @return the arguments used as parameters for the method invocation
	 */
	public function getMethodArguments(Void):Array {
		return methodArguments;
	}
	
	/*
	 * Returns the return value of the method invocation.
	 *
	 * @return the return value of the method invocation
	 */
	public function getReturnValue(Void) {
		return returnValue;
	}
	
}