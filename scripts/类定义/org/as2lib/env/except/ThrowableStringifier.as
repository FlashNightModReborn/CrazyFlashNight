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
import org.as2lib.util.Stringifier;
import org.as2lib.util.StringUtil;
import org.as2lib.env.except.Throwable;
import org.as2lib.env.except.StackTraceElement;
import org.as2lib.env.reflect.ReflectUtil;

/**
 * {@code ThrowableStringifier} stringifies instances of type {@link Throwable}.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.except.ThrowableStringifier extends BasicClass implements Stringifier {
	
	/** Show the stack trace. */
	private var showStackTrace:Boolean;
	
	/** Show the cause. */
	private var showCause:Boolean;
	
	/**
	 * Constructs a new {@code ThrowableStringifier} instance.
	 *
	 * <p>You can switch different parts of the string representation on or off using
	 * the declared arguments.
	 *
	 * <p>The stack trace and the cause are be default shown. That means if you want
	 * them to be contained in the resulting string representation you do not have to
	 * specify any arguments.
	 *
	 * <p>The settings apply only to the throwable to stringify. That means they do
	 * not apply for its cause. The cause is responsible for stringifying itself.
	 *
	 * @param showStackTrace determines whether the string representation contains the
	 * stack trace
	 * @param showCause determines whether the string representation contains the
	 * cause
	 */
	public function ThrowableStringifier(showStackTrace:Boolean, showCause:Boolean) {
		this.showStackTrace = showStackTrace == null ? true : showStackTrace;
		this.showCause = showCause == null ? true : showCause;
	}
	
	/**
	 * Returns a string representation of the passed-in {@link Throwable} instance.
	 *
	 * <p>Depending on the settings you made on instantiation the stack trace and
	 * cause is contained in the resulting string or not.
	 *
	 * <p>Note that the cause is stringified by its own stringifier. That means the
	 * setting show stack trace and show cause settings apply only for this throwable
	 * and not for its causes. The cause is responsible for stringifying itself.
	 *
	 * <p>The throwable elements are also responsible for stringifying themselves.
	 *
	 * <p>The string representation is composed as follows:
	 * <pre>
	 *   theFullQualifiedNameOfTheThrowable: theMessage
	 *     at theStringRepresentationOfTheStackTraceElement
	 *     ..
	 *   Caused by: theStringRepresentationOfTheCause
	 * </pre>
	 *
	 * <p>Here is how a real string representation could look like:
	 * <pre>
	 *   org.as2lib.data.holder.IllegalLengthException: The argument length '-2' is not allowed to be negative.
	 *     at org.as2lib.data.holder.MyDataHolder.setMaximumLength(Number)
	 *   Caused by: org.as2lib.data.math.IllegalNumberException: The argument number '-2' is not allowed in a range from 0 to ∞.
	 *     at org.as2lib.data.math.Range.setNumber(Number)
	 * </pre>
	 *
	 * @param target the {@code Throwable} to stringify
	 * @return the string representation of the passed-in {@code target} throwable
	 * @see #stringifyStackTrace
	 */
	public function execute(target):String {
		var throwable:Throwable = target;
		var result:String = "";
		var typeName:String = ReflectUtil.getTypeNameForInstance(throwable);
		var indent:Number = typeName.length + 2;
		result += typeName + ": " + StringUtil.addSpaceIndent(throwable.getMessage(), indent).substr(indent);
		var stackTrace:Array = throwable.getStackTrace();
		if (stackTrace && stackTrace.length > 0) {
			result += "\n" + stringifyStackTrace(throwable.getStackTrace());
		}
		var cause = throwable.getCause();
		if (cause) {
			result += "\nCaused by: " + cause;
		}
		return result;
	}

	/**
	 * Stringifies the passed-in {@code stackTrace} array that contains
	 * {@link StackTraceElement} instances.
	 *
	 * <p>The individual {@code StackTraceElement} instances are responsible for
	 * stringifying themselves.
	 *
	 * <p>The resulting string representation is composed as follows:
	 * <pre>
	 *     at theStringRepresentationOfTheFirstStackTraceElement
	 *     at theStringRepresentationOfTheSecondStackTraceElement
	 *     ..
	 * </pre>
	 *
	 * <p>A real string representation could look like this:
	 * <pre>
	 *     at org.as2lib.data.math.Range.setNumber(Number)
	 *     at org.as2lib.data.holder.MyDataHolder.setMaximumLength(Number)
	 *     at com.simonwacker.MyApplication.initialize()
	 * </pre>
	 *
	 * @param stackTrace the stack trace to stringify
	 * @return the string representation of the passed-in {@code stackTrace}
	 */
	public function stringifyStackTrace(stackTrace:Array):String {
		var result:String = "";
		for (var i:Number = 0; i < stackTrace.length; i++) {
			var element:StackTraceElement = stackTrace[i];
			result += ("  at " 
					   + element.toString());
			if (i < stackTrace.length-1) {
				result += "\n";
			}
		}
		return result;
	}
	
}