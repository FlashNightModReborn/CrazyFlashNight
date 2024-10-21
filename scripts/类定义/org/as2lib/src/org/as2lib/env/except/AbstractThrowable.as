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

import org.as2lib.env.except.Throwable;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.except.IllegalStateException;
import org.as2lib.env.except.StackTraceElement;
import org.as2lib.env.except.ThrowableStringifier;
import org.as2lib.util.Stringifier;
import org.as2lib.env.log.Logger;
import org.as2lib.env.log.LogManager;

/**
 * {@code AbstractThrowable} is an abstract class that contains sourced out
 * functionalities used by the classes {@link Exception} and
 * {@link FatalException}.
 * 
 * <p>It is thought to be an abstract implementation of the {@link Throwable}
 * interface. Because of that sub-classes must implement the {@code Throwable}
 * interface if they are themselves not abstract.
 *
 * <p>This class extends the {@code Error} class. Thus you can use sub-classes of
 * it as throwable type in catch-blocks in Flex.
 *
 * @author Simon Wacker
 * @see org.as2lib.env.except.Throwable
 */
class org.as2lib.env.except.AbstractThrowable extends Error {
	
	/** Stringifier used to stringify throwables. */
	private static var stringifier:Stringifier;
	
	/** Logger used to output throwables. */
	private static var logger:Logger;
	
	/**
	 * Returns the stringifier to stringify throwables.
	 *
	 * <p>The returned stringifier is either the default
	 * {@link ThrowableStringifier} if no custom stringifier was set or if the
	 * stringifier was set to {@code null}.
	 *
	 * @return the current stringifier
	 */
	public static function getStringifier(Void):Stringifier {
		if (!stringifier) stringifier = new ThrowableStringifier();
		return stringifier;
	}
	
	/**
	 * Sets the stringifier to stringify throwables.
	 *
	 * <p>If {@code throwableStringifier} is {@code null} the static
	 * {@link #getStringifier} method will return the default stringifier.
	 *
	 * @param throwableStringifier the stringifier to stringify throwables
	 */
	public static function setStringifier(throwableStringifier:Stringifier):Void {
		stringifier = throwableStringifier;
	}
	
	/**
	 * Returns the logger used to log throwables.
	 * 
	 * @return the logger used to log throwables
	 */
	private static function getLogger(Void):Logger {
		if (!logger) {
			logger = LogManager.getLogger("org.as2lib.env.except.Throwable");
		}
		return logger;
	}
	
	/** The saved stack of method calls. */
	private var stackTrace:Array;
	
	/** The throwable that caused this throwable to be thrown. */
	private var cause;
	
	/** The message describing what went wrong. */
	private var message:String;
	
	/** The error code to obtain localized client messages. */
	private var errorCode:String;
	
	/**
	 * Constructs a new {@code AbstractThrowable} instance.
	 *
	 * <p>All arguments are allowed to be {@code null} or {@code undefined}. But
	 * if one is, the string representation returned by the {@code toString}
	 * method will not be complete.
	 *
	 * <p>The {@code args} array should be the internal arguments array of the
	 * method that throws the throwable. The internal arguments array exists in
	 * every method and contains its parameters, the callee method and the caller
	 * method. You can refernce it in every method using the name
	 * {@code "arguments"}.
	 *
	 * @param message the message that describes the problem in detail
	 * @param thrower the object that declares the method that throws this
	 * throwable
	 * @param args the arguments of the throwing method
	 */
	private function AbstractThrowable(message:String, thrower, args:Array) {
		this.message = message;
		stackTrace = new Array();
		addStackTraceElement(thrower, args.callee, args);
		// TODO: Implement findMethod to display the next line correctly.
		// addStackTraceElement(undefined, args.caller, new Array());
	}
	
	/**
	 * Adds a stack trace element to the stack trace.
	 *
	 * <p>The new stack trace element is added to the end of the stack trace.
	 *
	 * <p>At some parts in your application you may want to add stack trace elements
	 * manually. This can help you to get a clearer image of what went where wrong and
	 * why. You can use this method to do so.
	 *
	 * @param thrower the object that threw, rethrew or forwarded (let pass) the
	 * throwable
	 * @param method the method that threw, rethrew or forwarded (let pass) the
	 * throwable
	 * @param args the arguments the method was invoked with when throwing, rethrowing
	 * or forwarding (leting pass) the throwable
	 */
	public function addStackTraceElement(thrower, method:Function, args:Array):Void {
		stackTrace.push(new StackTraceElement(thrower, method, args));
	}
	
	/**
	 * Returns an array that contains {@link StackTraceElement} instances of the
	 * methods invoked before this throwable was thrown.
	 *
	 * <p>The last element is always the one that contains the actual method that
	 * threw the throwable.
	 *
	 * <p>The stack trace helps you a lot because it says you where the throwing of
	 * the throwable took place and also what arguments caused the throwing.
	 *
	 * <p>The returned stack trace is never {@code null} or {@code undefined}. If
	 * no stack trace element has been set an empty array is returned.
	 *
	 * @return a stack containing the invoked methods until the throwable was thrown
	 */
	public function getStackTrace(Void):Array {
		return stackTrace;
	}
	
	/**
	 * Returns the initialized cause.
	 *
	 * <p>The cause is the throwable that caused this throwable to be thrown.
	 *
	 * @return the initialized cause
	 * @see #initCause
	 */
	public function getCause(Void) {
		return cause;
	}
	
	/**
	 * Initializes the cause of this throwable.
	 *
	 * <p>The cause can only be initialized once. You normally initialize a cause
	 * if you throw a throwable due to the throwing of another throwable. Thereby
	 * you do not lose the information the cause offers.
	 * 
	 * <p>This method returns this throwable to have an easy way to initialize the
	 * cause. Following is how you could use the cause mechanism.
	 *
	 * <code>
	 *   try {
	 *       myInstance.invokeMethodThatThrowsAThrowable();
	 *   } catch (e:org.as2lib.env.except.Throwable) {
	 *       throw new MyThrowable("myMessage", this, arguments).initCause(e);
	 *   }
	 * </code>
	 * 
	 * @param cause the throwable that caused the throwing of this throwable
	 * @return this throwable itself
	 * @throws org.as2lib.env.except.IllegalArgumentException if the passed-in
	 * {@code newCause} is {@code null} or {@code undefined}
	 * @throws org.as2lib.env.except.IllegalStateException if the cause has
	 * already been initialized
	 * @see #getCause
	 */
	public function initCause(newCause):Throwable {
		if (!newCause) throw new IllegalArgumentException("Cause must not be null or undefined.", this, arguments);
		if (cause) throw new IllegalStateException("The cause [" + cause + "] has already been initialized.", this, arguments);
		cause = newCause;
		return Throwable(this);
	}
	
	/**
	 * Returns the message that describes in detail what went wrong.
	 *
	 * <p>The message should be understandable, even for non-programmers. It should
	 * contain detailed information about what went wrong. And maybe also how the user
	 * that sees this message can solve the problem.
	 *
	 * <p>If the throwable was thrown for example because of a wrong collaborator or
	 * an illegal string or something similar, provide the string representation of it
	 * in the error message. It is recommended to put these between []-characters.
	 *
	 * @return the message that describes the problem in detail
	 */
	public function getMessage(Void):String {
		return message;
	}
	
	/**
	 * Initializes the error code for this throwable.
	 * 
	 * <p>The initialization works only once. Any further initialization results in an
	 * exception.
	 * 
	 * <p>Take a look at {@link #getErrorCode} to see what error codes are good for.
	 * 
	 * @param errorCode the error code to get localized client messages by
	 * @return this throwable
	 * @see #getErrorCode
	 */
	public function initErrorCode(errorCode:String):Throwable {
		this.errorCode = errorCode;
		return Throwable(this);
	}
	
	/**
	 * Returns the initialized error code.
	 * 
	 * <p>Error codes can be used to obtain localized messages appropriate for users;
	 * while the {@link #getMessage} method returns messages inteded for developers to
	 * get hands on the exception and fix bugs more easily.
	 * The localized messages can for example be obtained through a global message
	 * source and property files.
	 * 
	 * @return the error code to obtain an error message for users
	 */
	public function getErrorCode(Void):String {
		return errorCode;
	}
	
	/**
	 * Returns the string representation of this throwable.
	 *
	 * <p>The string representation is obtained via the stringifier returned by
	 * the static {@link #getStringifier} method.
	 *
	 * <p>If you want to change the string representation either set a new
	 * stringifier via the static {@link #setStringifier} method or if you want
	 * the string representation only change for one throwable and its
	 * sub-classes overwrite this method.
	 *
	 * @return the string representation of this throwable
	 */
	private function doToString(Void):String {
		return getStringifier().execute(this);
	}
	
}