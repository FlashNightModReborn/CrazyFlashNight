/**
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
import org.as2lib.test.mock.ArgumentsMatcher;
import org.as2lib.test.mock.support.DefaultArgumentsMatcher;

/**
 * {@code MethodCall} stores all information available about a method call.
 * 
 * @author Simon Wacker
 */
class org.as2lib.test.mock.MethodCall extends BasicClass {
	
	/** The name of the called method. */
	private var methodName:String;
	
	/** The arguments passed to the method. */
	private var args:Array;
	
	/** The matcher that compares expected and actual arguments. */
	private var argumentsMatcher:ArgumentsMatcher;
	
	/**
	 * Constructs a new {@code MethodCall} instance.
	 *
	 * <p>If {@code args} is {@code null} an empty array will be used instead.
	 *
	 * @param methodName the name of the called method
	 * @param args the arguments used for the method call
	 */
	public function MethodCall(methodName:String, args:Array) {
		this.methodName = methodName;
		this.args = args ? args : new Array();
	}
	
	/**
	 * Returns the name of the called method.
	 *
	 * @return the name of the called method
	 */
	public function getMethodName(Void):String {
		return methodName;
	}
	
	/**
	 * Returns the arguments used for the method call.
	 *
	 * @return the arguments used for the method call
	 */
	public function getArguments(Void):Array {
		return args;
	}
	
	/**
	 * Returns the currently used arguments matcher.
	 * 
	 * <p>That is either the arguments matcher set via the
	 * {@link #setArgumentsMatcher} method or an instance of the default
	 * {@link DefaultArgumentsMatcher} class.
	 *
	 * @return the currently used arguments matcher
	 */
	public function getArgumentsMatcher(Void):ArgumentsMatcher {
		if (!argumentsMatcher) argumentsMatcher = new DefaultArgumentsMatcher();
		return argumentsMatcher;
	}
	
	/**
	 * Sets the new arguments matcher.
	 * 
	 * <p>If {@code argumentsMatcher} is {@code null} the {@link #getArgumentsMatcher}
	 * method returns the default arguments matcher.
	 *
	 * @param argumentsMatcher the new arguments matcher
	 */
	public function setArgumentsMatcher(argumentsMatcher:ArgumentsMatcher):Void {
		this.argumentsMatcher = argumentsMatcher;
	}
	
	/**
	 * Checks whether this method call matches the passed-in {@code methodCall}.
	 *
	 * <p>{@code false} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code methodCall} is {@code null}.</li>
	 *   <li>The method names do not match.</li>
	 *   <li>The arguments do not match.</li>
	 * </ul>
	 *
	 * @param methodCall the method call to compare with this instance
	 */
	public function matches(methodCall:MethodCall):Boolean {
		if (!methodCall) return false;
		if (methodName != methodCall.getMethodName()) return false;
		return getArgumentsMatcher().matchArguments(args, methodCall.getArguments() ? methodCall.getArguments() : new Array());
	}
	
	/**
	 * Returns the string representation of this method call.
	 *
	 * <p>The returned string is constructed as follows:
	 * <pre>
	 *   theMethodName(theFirstArgument, ..)
	 * </pre>
	 *
	 * @return the string representation of this method call
	 */
	public function toString():String {
		return (methodName + "(" + args + ")");
	}
	
}