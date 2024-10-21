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

import org.as2lib.app.exec.AbstractProcess;
import org.as2lib.app.exec.Process;
import org.as2lib.util.ClassUtil;

/**
 * Helper class for a simpler creation of Configurations.
 * <p>Helper to start processes that might be useful within a configuration: like starting
 * a TestRunner or predefined action templates.
 *
 * @author Martin Heidegger
 * @version 1.0 */
class org.as2lib.app.conf.AbstractConfiguration extends AbstractProcess {
	
	/**
	 * Helper method to initialise a application.
	 * 
	 * @overload #initClass
	 * @overload #initConfig	 */
	public static function init(Void):Void {
		if(typeof arguments[0] == "function") {
			initClass(arguments[0]);
		} else if(arguments[0] instanceof Process) {
			initProcess(arguments[0]);
		}
	}
	
	/**
	 * Initializes a Configuration class.
	 * <p> Applies {@code .init()} to a configuration class and does nothing with any other class.
	 * 
	 * @see Configuration	 */
	public static function initClass(clazz:Function):Void {
		if(ClassUtil.isImplementationOf(clazz, Process)) {
			initProcess(new clazz());
		}
	}
	
	/**
	 * Initializes a Configuration instance.
	 * <p>Applies {@code .init()} to the configuration instance.
	 * 
	 * @see Configuration	 */
	public static function initProcess(process:Process):Void {
		process.start();
	}
	
	/**
	 * Helper method to get references to classes. 
	 * <p>Mtasc doesn't allow references without useage like: <code>MyTest;</code>
	 * so use this method to create references to your tests like: <code> use(MyTest); </code>
	 *
	 * @param cls Class to be referenced. 
	 */
	private function use(cls:Function):Void {
	}
	
}