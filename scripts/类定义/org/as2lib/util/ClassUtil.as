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
 * {@code ClassUtil} contains fundamental operations to efficiently and easily
 * work with any class. All methods here are supposed to be used with functions
 * treated as classes.
 * 
 * @author Martin Heidegger
 * @author Simon Wacker
 */
class org.as2lib.util.ClassUtil extends BasicClass {
	
	/**
	 * Checks if the passed-in {@code subClass} is extended by the passed-in
	 * {@code superClass}.
	 * 
	 * @param subClass the class to check
	 * @param superClass the class to match
	 * @return {@code true} if {@code subClass} is a sub-class of {@code superClass}
	 */
	public static function isSubClassOf(subClass:Function, superClass:Function):Boolean {
		var base:Object = subClass.prototype;
		// A superclass has to be in the prototype chain
		while(base !== undefined) {
			base = base.__proto__;
			if(base === superClass.prototype) {
				return true;
			}
		}
		return false;
	}
	
	/**
	 * Checks if the passed-in {@code clazz} implements the passed-in {@code
	 * interfaze}.
	 * 
	 * @param clazz the class to check
	 * @param interfaze the interface the {@code clazz} may implement
	 * @return {@code true} if the passed-in {@code clazz} implements the passed-in
	 * {@code interfaze} else {@code false}
	 */
	public static function isImplementationOf(clazz:Function, interfaze:Function):Boolean {
		// A interface must not be in the prototype chain.
		if (isSubClassOf(clazz, interfaze)) {
			return false;
		}
		// If it's an interface then it must not be extended but the class has
		// to be an instance of it
		return (createCleanInstance(clazz) instanceof interfaze);
	}
	
	/**
	 * Creates a new instance of the passed-in {@code clazz} without invoking its 
	 * constructor.
	 * 
	 * @param clazz the	class to create a new instance of
	 * @return new instance of the passed-in class.
	 * @author Martin Heidegger
	 * @author Ralf Bokelberg (www.qlod.com)
	 */
	public static function createCleanInstance(clazz:Function):Object {
		var result:Object = new Object();
		result.__proto__ = clazz.prototype;
		result.__constructor__ = clazz;
		return result;
	}
	
	/**
	 * Creates a new instance of the passed-in {@code clazz} applying the
	 * passed-in {@code args} to the constructor.
	 * 
	 * <p>This util is mostly made for MTASC compatibility because it doesn't
	 * allow {@code new clazz()} for usual variables.
	 * 
	 * @param clazz Class to be instanciated
	 * @param args Arguments to be applied to the constructor
	 * @return new instance of the class	 */
	public static function createInstance(clazz:Function, args:Array) {
		if (!clazz) return null;
		var result:Object = new Object();
		result.__proto__ = clazz.prototype;
		result.__constructor__ = clazz;
		clazz.apply(result, args);
		return result;
	}
}