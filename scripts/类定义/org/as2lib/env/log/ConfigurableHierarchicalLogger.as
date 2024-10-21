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

import org.as2lib.env.log.HierarchicalLogger;

/**
 * {@code ConfigurableHierarchicalLogger} declares methods needed to configure
 * hierarchical loggers.
 * 
 * <p>Loggers that shall be used with the {@link LoggerHierarchy} repository must
 * implement this interface.
 *
 * @author Simon Wacker
 */
interface org.as2lib.env.log.ConfigurableHierarchicalLogger extends HierarchicalLogger {
	
	/**
	 * Sets the parent of this logger.
	 *
	 * <p>The parent is used to obtain needed configuration like handlers
	 * and levels.
	 * 
	 * @param parent the parent of this logger
	 */
	public function setParent(parent:HierarchicalLogger):Void;
	
	/**
	 * Sets the name of this logger.
	 *
	 * <p>The passed-in {@code name} must exist of the path as well as the actual
	 * identifier. That means it must be fully qualified.
	 * 
	 * <p>The {@link LoggerHierarchy} prescribes that the different parts of the name
	 * must be separated by periods. If you do not want to use it with the
	 * {@code LoggerHierarchy} you can of course separate the different parts as you
	 * please.
	 *
	 * @param name the name of this logger
	 */
	public function setName(name:String):Void;
	
}