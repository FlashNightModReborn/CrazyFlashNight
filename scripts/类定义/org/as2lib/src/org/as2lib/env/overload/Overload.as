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
import org.as2lib.env.overload.OverloadHandler;
import org.as2lib.env.overload.SimpleOverloadHandler;
import org.as2lib.env.overload.UnknownOverloadHandlerException;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.overload.SameTypeSignatureException;

/**
 * {@code Overload} provides methods to overload a method.
 *
 * <p>With overloading you have typically two or more methods with the same name. Which
 * method gets actually invoked depends on its type signature, that means its return
 * and arguments' types. Here is an example of what overloading may look if it would be
 * supported by Flash (note that this code does actually not work).
 * 
 * <p>Example:
 * <code>
 *   // MyClass.as
 *   class MyClass {
 *       public function myMethod(number:Number, string:String):Void {
 *           trace("myMethod(Number, String):Void");
 *       }
 *       public function myMethod(number:Number):Void {
 *           trace("myMethod(Number):Void");
 *       }
 *       public function myMethod(string:String):Number {
 *           trace("myMethod(String):Number");
 *           return 1;
 *       }
 *   }
 * </code>
 *
 * <p>Usage:
 * <code>
 *   // test.fla
 *   var myInstance:MyClass = new MyClass();
 *   myInstance.myMethod(1);
 *   myInstance.myMethod(2, "myString");
 *   var number:Number = myInstance.myMethod("myString");
 *   trace(number);
 * </code>
 *
 * <p>Output:
 * <pre>
 *   myMethod(Number):Void
 *   myMethod(Number, String):Void
 *   myMethod(String):Number
 *   1
 * </pre>
 *
 * <p>As you can see, depending on what type the passed-in arguments have a different
 * method is invoked. This is sadly not possible with ActionScript, that is what this
 * class is for. Using the overload mechanism this class offers the overloading looks
 * as follows:
 *
 * <code>
 *   // MyClass.as
 *   class MyClass {
 *       public function myMethod() {
 *           var o:Overload = new Overload(this);
 *           o.addHandler([Number, String], myMethodByNumberAndString);
 *           o.addHandler([Number], myMethodByNumber);
 *           o.addHandler([String], myMethodByString);
 *           return o.forward(arguments);
 *       }
 *       public function myMethodByNumberAndString(number:Number, string:String):Void {
 *           trace("myMethod(Number, String):Void");
 *       }
 *       public function myMethodByNumber(number:Number):Void {
 *           trace("myMethod(Number):Void");
 *       }
 *       public function myMethodByString(string:String):Number {
 *           trace("myMethod(String):Number");
 *           return 1;
 *       }
 *   }
 * </code>
 *
 * <p>Using the above testing code the output looks the same.
 *
 * <p>While this is a good overloading mechanism / overloading alternative it still has
 * some disadvantages.
 * <ul>
 *   <li>
 *     If not all methods the overloaded method forwards to returns a value of the
 *     same type, return type type-checking is lost.
 *   </li>
 *   <li>
 *     The type checking of the arguments is also lost at compile time. At run-time the
 *     {@code Overload} class throws an {@code UnknownOverloadHandlerException} if the
 *     real arguments match no added overload handler.
 *   </li>
 *   <li>The overloading slows the method execution a little bit down.</li>
 * </ul>
 *
 * <p>But if you declare the methods to overload to as public, as in the example, you
 * can still invoke them directly. Doing so, all the above problems do not hold true
 * anymore. The overloaded methods then acts more as a convenient method that is easy
 * to use if appropriate.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.overload.Overload extends BasicClass {
	
	/** All registered handlers. */
	private var handlers:Array;
	
	/** Handler to use if no handler matches. */
	private var defaultHandler:OverloadHandler;
	
	/** The target object to invoke the method on. */
	private var target;
	
	/**
	 * Constructs a new {@code Overload} instance.
	 * 
	 * <p>The passed-in {@code target} is normally the object on which the overloading
	 * takes place. This means it is the object that declares all methods that take
	 * part at the overloading.
	 *
	 * @param target the target to invoke the overloaded method on
	 */
	public function Overload(target) {
		this.handlers = new Array();
		this.target = target;
	}
	
	/**
	 * Sets the default handler.
	 *
	 * <p>This handler will be used if no other handler matches to a list of arguments.
	 * All real arguments used for the overloading are passed as parameters to the
	 * method of this default handler.
	 *
	 * <p>The method is invoked on the same scope as the other handlers. That is the
	 * target passed-in on construction.
	 * 
	 * <code>
	 *   var overload:Overload = new Overload(this);
	 *   overload.addHandler([String], methodWithStringArgument);
	 *   overload.addHandler([Number], methodWithNumberArgument);
	 *   overload.setDefaultHandler(function() {
	 *       trace(arguments.length + " arguments were used.");
	 *   });
	 *   return overload.forward(arguments);
	 * </code>
	 *
	 * <p>If the passed-in {@code method} is {@code null}, {@code undefined} or not of
	 * type {@code "function"} the default handler gets removed.
	 *
	 * @param method the method of the handler to invoke if no added handler matches
	 * the overload arguments
	 * @see #removeDefaultHandler
	 */
	public function setDefaultHandler(method:Function):Void {
		if (typeof(method) == "function") {
			defaultHandler = new SimpleOverloadHandler(null, method);
		} else {
			removeDefaultHandler();
		}
	}
	
	/**
	 * Removes the default handler.
	 *
	 * <p>This handler is used if no other handler matches to a list of arguments.
	 *
	 * @see #setDefaultHandler
	 */
	public function removeDefaultHandler(Void):Void {
		defaultHandler = null;
	}
	
	/**
	 * @overload #addHandlerByHandler
	 * @overload #addHandlerByValue
	 */
	public function addHandler() {
		var l:Number = arguments.length;
		if (l == 1) {
			var handler:OverloadHandler = arguments[0];
			if (handler == null || handler instanceof OverloadHandler) {
				addHandlerByHandler(handler);
				return;
			}
		}
		if (l == 2) {
			var args:Array = arguments[0];
			var method:Function = arguments[1];
			if ((args == null || args instanceof Array) && (method == null || method instanceof Function)) {
				return addHandlerByValue(args, method);
			}
		}
		throw new IllegalArgumentException("The types and count of the passed-in arguments [" + arguments + "] must match one of the available choices.", this, arguments);
	}
	
	/**
	 * Adds the passed-in {@code handler}.
	 *
	 * <p>Overload handlers are used to determine the method to forward to. This is
	 * done using the methods {@link OverloadHandler#matches} and
	 * {@link OverloadHandler#isMoreExplicit}. If both conditions hold true the method
	 * invocation is forwarded to the method of the handler, that gets returned by the
	 * {@link OverloadHandler#getMethod} method.
	 * 
	 * <p>If the passed-in {@code handler} is {@code null} or {@code undefined} no
	 * actions will take place.
	 *
	 * @param handler the new overload handler to add
	 */
	public function addHandlerByHandler(handler:OverloadHandler):Void {
		if (handler) {
			handlers.push(handler);
		}
	}
	
	/**
	 * Adds a new {@link SimpleOverloadHandler} instance, that gets configured with the
	 * passed-in {@code argumentsTypes} and {@code method}.
	 *
	 * <p>Overload handlers are used to determine the method to forward to. This is
	 * done using the methods {@link OverloadHandler#matches} and
	 * {@link OverloadHandler#isMoreExplicit}. If both conditions hold true the method
	 * invocation is forwarded to the method of the handler, that gets returned by the
	 * {@link OverloadHandler#getMethod} method.
	 *
	 * <p>The passed-in {@code argumentsTypes} are the types of arguments the method
	 * expects from the real arguments to have. The {@code SimpleOverloadHandler} does
	 * its matches and explicity checks upon these arguments' types.
	 *
	 * <p>The passed-in {@code method} is the method to invoke if the added handler
	 * matches the real arguments and if it is the most explicit handler among all 
	 * matching ones.
	 *
	 * @param argumentsTypes the arguments' types of the overload handler
	 * @param method the method corresponding to the passed-in {@code argumentsTypes}
	 * @return the newly created overload handler
	 * @see SimpleOverloadHandler#SimpleOverloadHandler
	 */
	public function addHandlerByValue(argumentsTypes:Array, method:Function):OverloadHandler {
		var handler:OverloadHandler = new SimpleOverloadHandler(argumentsTypes, method);
		handlers.push(handler);
		return handler;
	}
	
	/**
	 * Removes the passed-in {@code handler}.
	 *
	 * <p>All occurrences of the passed-in {@code handler} are removed.
	 *
	 * @param handler the overload handler to remove
	 */
	public function removeHandler(handler:OverloadHandler):Void {
		if (handler) {
			var i:Number = handlers.length;
			while (--i-(-1)) {
				if (handlers[i] == handler) {
					handlers.splice(i, 1);
				}
			}
		}
	}
	
	/**
	 * Forwards to the appropriate overload handler depending on the passed-in
	 * {@code args}.
	 *
	 * <p>This is not done by using the {@link OverloadHandler#execute} method but
	 * manually by using {@code apply} on the method returned by the
	 * {@link OverloadHandler#getMethod} method. Invoking the method this way
	 * increases the number of possible recurions with overlaoded methods.
	 *
	 * <p>If the {@code args} array is {@code null} or {@code undefined} an empty array
	 * is used instead.
	 *
	 * <p>If no overload handler matches, the default overload handler will be used if
	 * it has been set.
	 *
	 * <p>Overload handlers are supposed to have the same type signature if the
	 * {@link OverloadHandler#isMoreExplicit} method returns {@code null}.
	 *
	 * @return the return value of the invoked method
	 * @throws org.as2lib.env.overload.UnknownOverloadHandlerException if no adequate
	 * overload handler could be found
	 * @throws org.as2lib.env.overload.SameTypeSignatureException if there exist at
	 * least two overload handlers with the same type siganture, that means their
	 * arguments' types are the same
	 */
	public function forward(args:Array) {
		return doGetMatchingHandler(arguments.caller, args).getMethod().apply(target, args);
	}
	
	/**
	 * Returns the most explicit overload handler from the array of matching handlers.
	 *
	 * <p>If the {@code args} array is {@code null} or {@code undefined} an empty array
	 * is used instead.
	 *
	 * <p>If no handler matches the default handler gets returned if it has been set.
	 *
	 * <p>Overload handlers are supposed to have the same type signature if the
	 * {@link OverloadHandler#isMoreExplicit} method returns {@code null}.
	 *
	 * @param args the arguments that shall match to a specific overload handler
	 * @return the most explicit overload handler
	 * @throws org.as2lib.env.overload.UnknownOverloadHandlerException if no adequate
	 * overload handler could be found
	 * @throws org.as2lib.env.overload.SameTypeSignatureException if there exist at
	 * least two overload handlers with the same type siganture, that means their
	 * arguments' types are the same
	 */
	public function getMatchingHandler(args:Array):OverloadHandler {
		return doGetMatchingHandler(arguments.caller, args);
	}
	
	/**
	 * Returns the most explicit overload handler out of the array of matching overload
	 * handlers.
	 *
	 * <p>If the passed-in {@code args} array is {@code null} or {@code undefined} an
	 * empty array is used instead.
	 *
	 * <p>If no handler matches the default handler gets returned if it has been set.
	 *
	 * <p>Overload handlers are supposed to have the same type signature if the
	 * {@link OverloadHandler#isMoreExplicit} method returns {@code null}.
	 *
	 * @param overloadedMethod the overloaded method on the target
	 * @param overloadArguments the arguments for which the overload shall be performed
	 * @return the most explicit overload handler
	 * @throws org.as2lib.env.overload.UnknownOverloadHandlerException if no adequate
	 * overload handler could be found
	 * @throws org.as2lib.env.overload.SameTypeSignatureException if there exist at
	 * least two overload handlers with the same type siganture, that means their
	 * arguments' types are the same
	 */
	private function doGetMatchingHandler(overloadedMethod:Function, overloadArguments:Array):OverloadHandler {
		if (!overloadArguments) overloadArguments = [];
		var matchingHandlers:Array = getMatchingHandlers(overloadArguments);
		var i:Number = matchingHandlers.length;
		if (i == 0) {
			if (defaultHandler) {
				return defaultHandler;
			}
			throw new UnknownOverloadHandlerException("No appropriate OverloadHandler found.",
									 			  	  this,
									 			  	  arguments,
													  target,
													  overloadedMethod,
													  overloadArguments,
													  handlers);
		}
		var result:OverloadHandler = matchingHandlers[--i];
		while (--i-(-1)) {
			var moreExplicit:Boolean = result.isMoreExplicit(matchingHandlers[i]);
			if (moreExplicit == null) {
				throw new SameTypeSignatureException("Two OverloadHandlers have the same type signature.",
													 this,
													 arguments,
													 target,
													 overloadedMethod,
													 overloadArguments,
													 [result, matchingHandlers[i]]);
			}
			if (!moreExplicit) result = matchingHandlers[i];
		}
		return result;
	}
	
	/**
	 * Returns {@link OverlaodHandler} instances that match the passed-in {@code args}.
	 *
	 * <p>The match is performed using the {@link OverlaodHandler#matches} method.
	 * 
	 * @param args the arguments that shall match to overload handlers
	 * @return an array containing the matching {@code OverloadHandler} instances
	 */
	private function getMatchingHandlers(args:Array):Array {
		var result:Array = new Array();
		var i:Number = handlers.length;
		while (--i-(-1)) {
			var handler:OverloadHandler = handlers[i];
			if (handler.matches(args)) result.push(handler);
		}
		return result;
	}
	
}
