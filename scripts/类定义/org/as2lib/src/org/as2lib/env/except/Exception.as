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
import org.as2lib.env.except.AbstractThrowable;

/**
 * {@code Exception} is a default implementation of the {@code Throwable}
 * interface.
 *
 * <p>It differs from the {@link FatalException} class in that it marks the
 * throwable as not-fatal. That means it differs from a {@code FatalException} in
 * its fatality.
 *
 * <p>It also uses the {@code Logger.error} method to log itself, while the
 * {@code FatalException} class uses the {@code Logger.fatal} method.
 *
 * <p>Example:
 * <code>
 *   throw new Exception("This is a detailed message that explains the problem.", this, arguments);
 * <code>
 *
 * <p>The above example is supposed to be in a method, that has been declared on a
 * class.
 *
 * <p>Note that you normally do not throw instances of this class directly. It is
 * better to sub-class it, that means to create a custom exception, that explains
 * its purpose more closely by its name, and throw this exception instead.
 *
 * <p>If you are building a framework that shall be reused it is also helpful to
 * built a exception inheritance hierarchy, where you have one base class. You can
 * then categorize different exceptions by their inheritance hierarchy. This
 * enables you to catch all exceptions from your whole framework or only from
 * specific parts of your framework.
 *
 * <p>For a detailed explanation on how to use throwables, what this exception
 * framework offers you and how to work appropriately with throwables take a look
 * at the class documentation of the {@code Throwable} interface.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.except.Exception extends AbstractThrowable implements Throwable {
	
	/**
	 * Constructs a new {@code Exception} instance.
	 *
	 * <p>All arguments are allowed to be {@code null} or {@code undefined}. But if one
	 * is, the string representation returned by the {@code toString} method will not
	 * be complete.
	 *
	 * <p>The {@code args} array should be the internal arguments array of the method
	 * that throws the throwable. The internal arguments array exists in every method
	 * and contains its parameters, the callee method and the caller method. You can
	 * refernce it in every method using the name {@code "arguments"}.
	 *
	 * @param message the message that describes the problem in detail
	 * @param thrower the object that declares the method that throws this exception
	 * @param args the arguments of the throwing method
	 */
	public function Exception(message:String, thrower, args:Array) {
		super (message, thrower, args);
	}
	
	/**
	 * Returns the string representation of this exception.
	 *
	 * <p>If you do not call this method out of another method, it also executes
	 * the {@code error} method on the logger returned by the
	 * {@link AbstractThrowable#getLogger} method passing {@code this} because it
	 * thinks that the virtual machine called this method.
	 * 
	 * <p>The string representation is obtained via the invocation of the
	 * {@link AbstractThrowable#doToString} method that uses the stringifier returned
	 * by the static {@link AbstractThrowable#getStringifier} method.
	 *
	 * <p>If you want to change the appearance of all exceptions set a new stringifier
	 * via the static {@link AbstractThrowable#setStringifier} method.
	 *
	 * <p>If you only want to change the string representation of one exception and
	 * its sub-classes overwrite the {@code doToString} method in your custom
	 * exception.
	 *
	 * <p>Do not overwrite this method because you will lose the functionality that
	 * invokes the logger when the exception has not been caught and has now reached
	 * the final 'level', the virtual machine, that invokes this method.
	 *
	 * @return the string representation of this fatal exception
	 */
	public function toString():String {
		if (!arguments.caller) {
			if (getLogger().isErrorEnabled()) {
				getLogger().error(this);
			}
		}
		return doToString();
	}
	
}