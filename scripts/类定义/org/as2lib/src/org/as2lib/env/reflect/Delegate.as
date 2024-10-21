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

/**
 * {@code Delegate} offers with {@link Delegate#createDelegate} a method for
 * using old-style Template classes.
 * 
 * <p>Using event handling like in common MovieClips creates problems in OOP
 * ActionScript due to the fact that it uses functions as event executions 
 * without minding about that the scope always refers to the MovieClip.
 * {@code Delegate.createDelegate} allows a proper Workaround for the redirection
 * of such methods to a proper different scope.
 * 
 * <p>Example:
 * 
 * <p>Test class:
 * <code>
 *   class com.domain.MyMovieClipController {
 *     private var content:String;
 *     
 *     public function MyMovieClipController(content:String) {
 *       this.content = content;
 *     }
 *     
 *     public function onEnterFrame() {
 *       trace(content);
 *     }
 *   }
 * </code>
 * 
 * <p>Usage:
 * <code>
 *   import com.domain.MyMovieClipController;
 *   import org.as2lib.env.reflect.Delegate;
 *  
 *   var mc:MyMovieClipController = new MyMovieClipController("Hello World!");
 *   
 *   // Following will not work because of the wrong scope
 *   _root.onEnterFrame = mc.onEnterFrame;
 *   
 *   // Workaround using delegate
 *   _root.onEnterFrame = Delegate.create(mc, onEnterFrame);
 * </code>
 * 
 * @author Martin Heidegger
 * @version 1.0 */
class org.as2lib.env.reflect.Delegate {
	
	/**
	 * Creates a method that delegates its arguments to a certain scope.
	 * 
	 * @param scope Scope to be used by calling this method.
	 * @param method Method to be executed at the scope.
	 * @return Function that delegates its call to a different scope & method.	 */
	public static function create(scope, method:Function):Function {
		var result:Function;
		result = function() {
			return arguments.callee.method.apply(arguments.callee.scope, arguments);
		};
		result.scope = scope;
		result.method = method;
		return result;
	}
	
	/**
	 * Creates a method that delegates its arguments to a certain scope and
	 * uses additional fixed arguments.
	 * 
	 * <p>Example:
	 * <code>
	 *   import org.as2lib.env.reflect.Delegate;
	 *   
	 *   function test(a:String, b:Number, c:String) {
	 *   	trace(a+","+b+","+c);
	 *   }
	 *   
	 *   var delegate:Function = Delegate.createExtendedDelegate(this, test, ["a"]);
	 *   delegate(1,"b"); // will trace "a,1,b"
	 * </code>
	 * 
	 * 
	 * @param scope Scope to be used by calling this method.
	 * @param method Method to be executed at the scope.
	 * @param args Arguments to be used at first position.
	 * @return Function that delegates its call to a different scope & method.
	 * @TODO find better name	 */
	public static function createExtendedDelegate(scope, method:Function, args:Array):Function {
		var result:Function;
		result = function() {
			return arguments.callee.method.apply(arguments.callee.scope, arguments.callee.args.concat(arguments));
		};
		result.scope = scope;
		result.method = method;
		result.args = args;
		return result;
	}
		
	/**
	 * Private Constructor to prevent instantiation.	 */
	private function Delegate(Void) {
	}
	
}