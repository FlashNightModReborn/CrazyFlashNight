/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
 
import org.as2lib.env.log.LogLevel;
import org.as2lib.env.log.level.AbstractLogLevel;

/**
 * {@code DynamicLogLevel} lets you dynamically create your own levels.
 *
 * <p>The default levels {@code ALL}, {@code DEBUG, {@code INFO}, {@code WARNING},
 * {@code ERROR}, {@code FATAL} and {@code NONE} normally meet all requirements.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.log.level.DynamicLogLevel extends AbstractLogLevel implements LogLevel {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractLogLevel;
	
	/**
	 * Constructs a new {@code DynamicLogLevel} instance.
	 *
	 * @param level the level represented by a number
	 * @param name the name of the level
	 * @throws IllegalArgumentException if passed-in {@code level} is {@code null} or
	 * {@code undefined}
	 */
	public function DynamicLogLevel(level:Number, name:String) {
		super (level, name);
	}
	
}