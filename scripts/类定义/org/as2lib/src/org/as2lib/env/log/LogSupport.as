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
import org.as2lib.env.log.Logger;
import org.as2lib.env.reflect.ReflectUtil;
import org.as2lib.env.log.LogManager;

/**
 * {@code LogSupport} can be used to easily gain access to loggers.
 * 
 * <p>You may extend this class to be able to access the logger appropriate to
 * your specific class with the getter property {@link logger} or the {@code getLogger}
 * method.
 * 
 * <p>Example:
 * <code>
 *   class MyClass extends LogSupport {
 *     
 *     public function test() {
 *       logger.info("hi");
 *     }
 *     
 *   }
 * </code>
 * 
 * @author Martin Heidegger
 * @version 2.0
 */
class org.as2lib.env.log.LogSupport extends BasicClass {
	
	/**
	 * Returns the logger for the given {@code scope}.
	 * 
	 * @param scope the scope to return a logger for
	 * @return the logger corresponding to the given {@code scope}
	 */
	public static function getLoggerByScope(scope):Logger {
		if (typeof scope == "function") {
			return getLoggerByClass(scope);
		} else {
			return getLoggerByInstance(scope);
		}
	}
	
	/**
	 * Return the logger for the given {@code instance}.
	 * 
	 * @param instance the instance to return a logger for
	 * @return the logger corresponding to the given {@code instance}
	 */
	public static function getLoggerByInstance(instance):Logger {
		var p = instance.__proto__;
		if (p.__as2lib__logger !== null && p.__as2lib__logger === p.__proto__.__as2lib__logger) {
			return storeLoggerInPrototype(p, LogManager.getLogger(
				ReflectUtil.getTypeNameForInstance(instance)));
		}
		return p.__as2lib__logger;
	}
	
	/**
	 * Returns the logger for the given {@code clazz}.
	 * 
	 * @param clazz the clazz to return a logger for
	 * @return the logger corresponding to the given {@code clazz}
	 */
	public static function getLoggerByClass(clazz:Function):Logger {
		var	p = clazz["prototype"];
		if (p.__as2lib__logger !== null && p.__as2lib__logger === p.__proto__.__as2lib__logger) {
			return storeLoggerInPrototype(p, LogManager.getLogger(
				ReflectUtil.getTypeNameForType(clazz)));
		}
		return p.__as2lib__logger;
	}
	
	/**
	 * Stores the given {@code logger} in the given {@code prototype}.
	 * 
	 * @param prototype the prototype to store the given {@code logger} in
	 * @param logger the logger to store in the given {@code prototype}
	 * @return the given {@code logger}
	 */
	private static function storeLoggerInPrototype(prototype, logger:Logger):Logger {
		prototype.__as2lib__logger = logger;
		if (!prototype.__as2lib__logger) {
			prototype.__as2lib__logger = null;
		}
		return logger;
	}
	
	/** The logger for your sub-class. */
	public var logger:Logger;
	
	/**
	 * Constructs a new {@code LogSupport} instance.
	 */
	public function LogSupport(Void) {
		// creates property within constructor because of Macromedia scope bug
		addProperty("logger", getLogger, null);
	}
	
	/**
	 * Returns the logger for this instance.
	 * 
	 * @return the logger corresponding to this instance
	 */
	public function getLogger(Void):Logger {
		return getLoggerByInstance(this);
	}
	
}