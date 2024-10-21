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
import org.as2lib.util.ObjectUtil;
import org.as2lib.env.overload.OverloadHandler;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ReflectUtil;

/**
 * {@code SimpleOverloadHandler} offers basic overloading functionalities.
 *
 * <p>Overload handlers are used by the {@code Overload} class to identify the
 * corresponding method for a specific list of arguments. Whereby the overload handler
 * holds the method and the expected arguments' types of this method.
 *
 * <p>It also offers functionalities to match real arguments against the expected
 * arguments' types, {@link #matches}, and to determine which overload handler or
 * rather which arguments' types of two handlers are more explicit,
 * {@link #isMoreExplicit}.
 *
 * <p>It also offers the ability to invoke/execute the target method on a target scope
 * passing-in a list of real arguments.
 *
 * <p>This class is normally not used directly but indirectly via the
 * {@link Overload#addHandler} method.
 *
 * <p>If you nevertheless want to instantiate it by hand and then use it with the
 * {@code Overload} class you can do this as follows:
 *
 * <code>
 *   this.myMethod = function(number:Number, string:String):String {
 *       return (number + ", " + string);
 *   }
 *   var overload:Overload = new Overload(this);
 *   var handler:OverloadHandler = new SimpleOverloadHandler([Number, String], myMethod);
 *   overload.addHandler(handler);
 *   trace(overload.forward([2, "myString"]));
 * </code>
 *
 * <p>Note that the handlers arguments signature (the arguments' types) match exactly
 * the ones of the method {@code myMethod}.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.overload.SimpleOverloadHandler extends BasicClass implements OverloadHandler {
	
	/** Contains the arguments types of the method. */
	private var argumentsTypes:Array;
	
	/** The method to execute on the given target. */
	private var method:Function;
	
	/**
	 * Constructs a new {@code SimpleOverloadHandler} instance.
	 *
	 * <p>If the passed-in {@code argumentsTypes} array is {@code null} or
	 * {@code undefined} an empty array is used instead.
	 *
	 * <p>The passed-in {@code argumentsTypes} are the types of arguments this handler
	 * expects the real arguments to have. The arguments' types thus are also the types
	 * of arguments the method, this handler forwards to, expects. The {@link #matches}
	 * and {@link #isMoreExplicit} methods do their job based on the arguments' types.
	 *
	 * <p>An argument-type is represented by a class or interface, that is a 
	 * {@code Function} in ActionScript. An argument type can for example be
	 * {@code Number}, {@code String}, {@code org.as2lib.core.BasicClass},
	 * {@code org.as2lib.core.BasicInterface} or any other class or interface.
	 *
	 * <p>An argument-type of value {@code null} or {@code undefined} is interpreted
	 * as any type allowed and is less explicit then any other type.
	 *
	 * <p>The arguments' types determine what method call is forwarded to this handler
	 * which then invokes the passed-in {@code method}. The forwarding to this handler
	 * normally takes place if it's matching the passed-in real arguments,
	 * {@link #matches}, and if it is the most explicit overload handler,
	 * {@link #isMoreExplicit}.
	 *
	 * @param argumentsTypes the arguments' types of the method
	 * @param method the actual method to execute on the target if the argumetns' types
	 * match
	 * @throws IllegalArgumentException if the passed-in {@code method} is {@code null}
	 * or {@code undefined}
	 */
	public function SimpleOverloadHandler(argumentsTypes:Array, method:Function) {
		if (!method) throw new IllegalArgumentException("Method to be executed by the overload handler must not be null or undefined.", this, arguments);
		if (!argumentsTypes) argumentsTypes = [];
		this.argumentsTypes = argumentsTypes;
		this.method = method;
	}
	
	/**
	 * Checks whether the passed-in {@code realArguments} match the arguments' types
	 * of this overload handler.
	 *
	 * <p>If the passed-in {@code realArguments} array is {@code null} or
	 * {@code undefined}, an empty array is used instead.
	 *
	 * <p>If a real argument has the value {@code null} or {@code undefined} it matches
	 * every type.
	 *
	 * <p>If the expected argument-type is {@code null} or {@code undefined} it matches
	 * every real argument. That means {@code null} and {@code undefined} are
	 * interpreted as {@code Object}, which also matches every real argument.
	 *
	 * @param realArguments the real arguments to match against the arguments' types
	 * @return {@code true} if the real arguments match the arguments' types else
	 * {@code false}
	 */
	public function matches(realArguments:Array):Boolean {
		if (!realArguments) realArguments = [];
		var i:Number = realArguments.length;
		if (i != argumentsTypes.length) return false;
		while (--i-(-1)) {
			// null == undefined
			if (realArguments[i] != null) {
				// An expected type of value null or undefined gets interpreted as: whatever.
				if (argumentsTypes[i] != null) {
					if (!ObjectUtil.typesMatch(realArguments[i], argumentsTypes[i])) {
						return false;
					}
				}
			}
		}
		return true;
	}
	
	/**
	 * Executes the method of this handler on the given {@code target} passing-in the
	 * given {@code args}.
	 *
	 * <p>The {@code this} scope of the method refers to the passed-in {@code target}
	 * on execution.
	 *
	 * @param target the target object to invoke the method on
	 * @param args the arguments to pass-in on method invocation
	 * @return the result of the method invocation
	 */
	public function execute(target, args:Array) {
		return method.apply(target, args);
	}
	
	/**
	 * Checks if this overload handler is more explicit than the passed-in
	 * {@code handler}.
	 *
	 * <p>The check is based on the arguments' types of both handlers. They are
	 * compared one by one.
	 *
	 * <p>What means more explicit? The type {@code String} is for example more
	 * explicit than {@code Object}. The type {@code org.as2lib.core.BasicClass} is
	 * also more explicit than {@code Object}. And the type
	 * {@code org.as2lib.env.overload.SimpleOverloadHandler} is more explicit than
	 * {@code org.as2lib.core.BasicClass}. I hope you get the image. As you can see,
	 * the explicitness depends on the inheritance hierarchy.
	 * 
	 * <p>Note that classes are supposed to be more explicit than interfaces.
	 *
	 * <ul>
	 *   <li>If the passed-in {@code handler} is {@code null} {@code true} will be
	 *       returned.</li>
	 *   <li>If the passed-in {@code handler}'s {@code getArguments} method returns
	 *       {@code null} an empty array will be used instead.</li>
	 *   <li>If the arguments' lengths do not match, {@code true} will be returned.</li>
	 *   <li>If one argument-type is {@code null} it is less explicit than no matter
	 *       what type it is compared with.</li>
	 * </ul>
	 *
	 * @param handler the handler to compare this handler with regarding its
	 * explicitness
	 * @return {@code true} if this handler is more explicit else {@code false} or
	 * {@code null} if the two handlers have the same explicitness
	 */
	public function isMoreExplicit(handler:OverloadHandler):Boolean {
		// explicitness range: null, undefined -> Object -> Number -> ...
		if (!handler) return true;
		var s:Number = 0;
		var t:Array = handler.getArgumentsTypes();
		if (!t) t = [];
		var i:Number = argumentsTypes.length;
		if (i != t.length) return true;
		while (--i-(-1)) {
			if (argumentsTypes[i] != t[i]) {
				var o = new Object();
				o.__proto__ = argumentsTypes[i].prototype;
				if (!argumentsTypes[i]) {
					s--;
				} else if (!t[i]) {
					s -= -1;
				} else if (ObjectUtil.isInstanceOf(o, t[i])) {
					s -= -1;
				} else {
					s--;
				}
			}
		}
		if (s == 0) {
			return null;
		}
		return (s > 0);
	}
	
	/**
	 * Returns the arguments' types used to match against the real arguments.
	 *
	 * <p>The arguments' types determine for which types of arguments the method was
	 * declared for. That means which arguments' types the method expects.
	 *
	 * @return the arguments' types the method expects
	 */
	public function getArgumentsTypes(Void):Array {
		return argumentsTypes;
	}
	
	/**
	 * Returns the method this overload handler was assigned to.
	 *
	 * <p>This is the method to invoke passing the appropriate arguments when this
	 * handler matches the arguments and is the most explicit one.
	 *
	 * @return the method to invoke when the real arguments match the ones of this
	 * handler and this handler is the most explicit one
	 */
	public function getMethod(Void):Function {
		return method;
	}
	
	/**
	 * Returns a detailed string representation of this overload handler.
	 *
	 * <p>The string representation is composed as follows:
	 * <pre>[object SimpleOverloadHandler(firstArgumentType, ..)]</pre>
	 * 
	 * @returns the string representation of this overload handler
	 */
	public function toString():String {
		// TODO: Extract into a Stringifier.
		var result:String = "[object SimpleOverloadHandler";
		var l:Number = argumentsTypes.length;
		if(l > 0) {
			result += "(";
		}
		for(var i:Number = 0; i < l; i++) {
			if(i != 0) {
				result += ", ";
			}
			result += ReflectUtil.getTypeName(argumentsTypes[i]);
		}
		if(l > 0) {
			result += ")";
		}
		return result + "]";
	}
	
}