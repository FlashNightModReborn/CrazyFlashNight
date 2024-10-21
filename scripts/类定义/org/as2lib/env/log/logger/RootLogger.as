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

import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.logger.SimpleHierarchicalLogger;

/**
 * {@code RootLogger} represents the root in a logger hierarchy.
 *
 * <p>The name of a root logger is by default {@code "root"}.
 *
 * <p>You must set a log level because otherwise the level in the hierarchy could
 * be {@code null} which could cause unexpected behavior.
 *
 * <p>This class is normally used in conjunction with the {@link LoggerHierarchy}.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.log.logger.RootLogger extends SimpleHierarchicalLogger {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = SimpleHierarchicalLogger;
	
	/**
	 * Constructs a new {@code RootLogger} instance.
	 *
	 * <p>The name is automatically set to {@code "root"}.
	 *
	 * @param level the level of this logger
	 * @throws IllegalArgumentException if the passed-in {@code level} is {@code null}
	 * or {@code undefined}
	 */
	public function RootLogger(level:LogLevel) {
		super("root");
		setLevel(level);
	}
	
	/**
	 * Sets the level of this logger.
	 *
	 * <p>A level of value {@code null} or {@code undefined} is not allowed.
	 *
	 * @param level the new level of this logger
	 * @throws IllegalArgumentException when {@code level} is {@code null} or
	 * {@code undefined}
	 */
	public function setLevel(level:LogLevel):Void {
		if (!level) throw new IllegalArgumentException("The instance [" + this + "] is not allowed to have a level value of null.", this, arguments);
		super.setLevel(level);
	}
	
}