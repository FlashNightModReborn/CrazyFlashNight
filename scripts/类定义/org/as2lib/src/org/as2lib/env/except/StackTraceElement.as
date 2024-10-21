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
import org.as2lib.env.except.StackTraceElementStringifier;

/**
 * {@code StackTraceElement} represents an element in the stack trace returned by the
 * {@link Throwable#getStackTrace} method.
 *
 * <p>A stack trace element is simply a data holder. It holds the thrower, the method
 * that threw the throwable and the arguments passed to the method that threw the
 * throwable.
 *
 * <p>This class is also responsible for stringifying itself. This functionality is
 * used by the {@link ThrowableStringifier}. You can set your own stringifier to get a
 * custom string representation of the stack trace element via the static
 * {@code #setStringifier} method.
 *
 * @author Simon Wacker
 * @author Martin Heidegger
 */
class org.as2lib.env.except.StackTraceElement extends BasicClass {
	
	/** Stringifier to stringify stack trace elements. */
	private static var stringifier:Stringifier;
	
	/** The object that declares the method that thew the throwable. */
	private var thrower;
	
	/** The throwing method. */
	private var method:Function;
	
	/** The arguments passed to the throwing method. */
	private var args:Array;
	
	/**
	 * Returns the stringifier to stringify stack trace elements.
	 *
	 * <p>The returned stringifier is either the default
	 * {@link StackTraceElementStringifier} if no custom stringifier was set or if the
	 * stringifier was set to {@code null} or the set stringifier.
	 *
	 * @return the default or the custom stringifier
	 */
	public static function getStringifier(Void):Stringifier {
		if (!stringifier) stringifier = new StackTraceElementStringifier();
		return stringifier;
	}
	
	/**
	 * Sets the stringifier to stringify stack trace elements.
	 *
	 * <p>If {@code stackTraceElementStringifier} is {@code null} the static
	 * {@link #getStringifier} method returns the default stringifier.
	 *
	 * @param stackTraceElementStringifier the stringifier to stringify stack trace
	 * elements
	 */
	public static function setStringifier(stackTraceElementStringifier:Stringifier):Void {
		stringifier = stackTraceElementStringifier;
	}
	
	/**
	 * Constructs a new {@code SimpleStackTraceElement} instance.
	 *
	 * @param thrower the object that declares the method that threw the throwable
	 * @param method the method that threw the throwable
	 * @param args the arguments passed to the throwing method
	 */
	public function StackTraceElement(thrower, method:Function, args:Array) {
		this.thrower = thrower ? thrower : null;
		this.method = method ? method : null;
		this.args = args ? args.concat() : null;
	}
	
	/**
	 * Returns the object that declares the method that threw the throwable.
	 *
	 * @return the object that declares the method that threw the throwable
	 */
	public function getThrower(Void) {
		return thrower;
	}
	
	/**
	 * Returns the method that threw the throwable.
	 *
	 * @return the method that threw the throwable
	 */
	public function getMethod(Void):Function {
		return method;
	}
	
	/**
	 * Returns the arguments that have been passed to the method that threw the
	 * throwable.
	 *
	 * @return the arguments passed to the method that threw the throwable
	 */
	public function getArguments(Void):Array {
		return args.concat();
	}
	
	/**
	 * Returns the string representation of this stack trace element.
	 *
	 * <p>The string representation is obtained via the stringifier returned by the
	 * static {@link #getStringifier} method.
	 *
	 * @return the string representation of this stack trace element
	 */
	public function toString():String {
		return getStringifier().execute(this);
	}
	
}