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

/**
 * {@code OverloadHandler} declares methods needed by overload handlers.
 *
 * <p>Overload handlers are used by the {@link Overload} class to identify the 
 * corresponding method for a specific list of arguments. Whereby the overload handler
 * holds the method and the expected arguments' types of this method.
 *
 * <p>It also offers functionalities to match real arguments against the expected
 * arguments' types, {@link #matches}, and to determine which overload handler or
 * rather which arguments' types of two handlers are more explicit,
 * {@link #isMoreExplicit}.
 *
 * <p>It also offers the ability to invoke/execute the target method on a target scope
 * passing-in a list of arguments.
 *
 * @author Simon Wacker
 */
interface org.as2lib.env.overload.OverloadHandler extends BasicInterface {
	
	/**
	 * Checks whether the passed-in {@code realArguments} match the expected arguments'
	 * types of this overload handler.
	 *
	 * @param realArguments the real arguments to match against the arguments' types
	 * @return {@code true} if the {@code realArguments} match the arguments' types
	 * else {@code false}
	 */
	public function matches(realArguments:Array):Boolean;
	
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
	public function execute(target, args:Array);
	
	/**
	 * Checks if this overload handler is more explicit than the passed-in
	 * {@code handler}.
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
	 * @param handler the handler to compare this handler with regarding explicitness
	 * @return {@code true} if this handler is more explicit else {@code false} or
	 * {@code null} if the two handlers have the same explicitness
	 */
	public function isMoreExplicit(handler:OverloadHandler):Boolean;
	
	/**
	 * Returns the arguments' types used to match against the real arguments.
	 *
	 * <p>The arguments' types determine for which types of arguments the method was
	 * declared for. That means which arguments' types the method expects.
	 *
	 * @return the arguments' types the method expects
	 */
	public function getArgumentsTypes(Void):Array;
	
	/**
	 * Returns the method this overload handler was assigned to.
	 *
	 * <p>This is the method to invoke passing the appropriate arguments when this
	 * handler matches the arguments and is the most explicit one.
	 *
	 * @return the method to invoke when the real arguments match the ones of this
	 * handler and this handler is the most explicit one
	 */
	public function getMethod(Void):Function;
	
}