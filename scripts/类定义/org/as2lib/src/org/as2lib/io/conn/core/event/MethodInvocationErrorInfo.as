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
 * {@code MethodInvocationErrorInfo} informs the client of an error that occured on
 * a method invocation.
 * 
 * <p>It defines constants, that can be used to identify what kind of error occured.
 *
 * <p>This class is used in conjunction with the {@link MethodInvocationCallback}
 * and {@link MethodInvocationErrorListener} classes.
 * 
 * @author Simon Wacker
 */
class org.as2lib.io.conn.core.event.MethodInvocationErrorInfo extends BasicClass {
	
	/** Indicates an error of unknown origin. */
	public static var UNKNOWN_ERROR:Number = 0;
	
	/** Indicates an error caused because of a not existing service. */
	public static var UNKNOWN_SERVICE_ERROR:Number = 1;
	
	/** Indicates that the method to invoke does not exist. */
	public static var UNKNOWN_METHOD_ERROR:Number = 2;
	
	/** Indicates an error caused by arguments that are out of size. */
	public static var OVERSIZED_ARGUMENTS_ERROR:Number = 3;
	
	/** Indicates that the service method to invoke threw an exception. */
	public static var METHOD_EXCEPTION_ERROR:Number = 4;
	
	/** Url of the service the method should have been invoked on. */
	private var serviceUrl:String;
	
	/** The name of the method to be executed. */
	private var methodName:String;
	
	/** The arguments used for the invocation. */
	private var methodArguments:Array;
	
	/** A number indicating the type of the error. */
	private var errorCode:Number;
	
	/** The exception that caused the error. */
	private var exception;
	
	/**
	 * Constructs a new {@code MethodInvocationErrorInfo} instance.
	 *
	 * <p>If {@code errorCode} is {@code null} or {@code undefined}, {@link #UNKNOWN_ERROR}
	 * is used.
	 * 
	 * @param serviceUrl the url to the service the method should be or was invoked on
	 * @param methodName the name of the method that should be or was invoked on the service
	 * @param methodArguments the arguments used as parameters for the method invocation
	 * @param error a number indicating the type of the error
	 * @param exception the exception that caused the error
	 */
	public function MethodInvocationErrorInfo(serviceUrl:String, methodName:String, methodArguments:Array, errorCode:Number, exception) {
		this.serviceUrl = serviceUrl;
		this.methodName = methodName;
		this.methodArguments = methodArguments;
		this.errorCode = errorCode == null ? UNKNOWN_ERROR : errorCode;
		this.exception = exception == null ? null : exception;
	}
	
	/**
	 * Returns the url to the service the method should be or was invoked on.
	 * 
	 * @return the url to the service the method should be or was invoked on
	 */
	public function getServiceUrl(Void):String {
		return serviceUrl;
	}
	
	/**
	 * Returns the name of the method that caused this error.
	 * 
	 * @return the name of the method that should be or was invoked on the service
	 */
	public function getMethodName(Void):String {
		return methodName;
	}
	
	/**
	 * Returns the arguments used as parameters for the method invocaton
	 * that caused this error.
	 *
	 * @return the arguments used as parameters for the method invocation
	 */
	public function getMethodArguments(Void):Array {
		return methodArguments;
	}
	
	/**
	 * Returns the error code that describes this error.
	 *
	 * <p>The error code matches one of the declared error constants.
	 * 
	 * @return the error code that describes the type of this error
	 */
	public function getErrorCode(Void):Number {
		return errorCode;
	}
	
	/**
	 * Returns the exception that caused this error.
	 *
	 * <p>Note that this error is not always caused by an exception. This method may
	 * does also return {@code null}.
	 * 
	 * @return the exception that caused this error or {@code null}
	 */
	public function getException(Void) {
		return exception;
	}
	
}