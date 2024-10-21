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

import org.as2lib.util.ClassUtil;
import org.as2lib.app.exec.Call;

/**
 * Constructor Call is to call a constructor by remote.
 * It default application is within Testcases where you try if a constructor throws a exception.
 *
 * @author Martin Heidegger
 * @author Christoph Atteneder
 */
class org.as2lib.app.exec.ConstructorCall extends Call {
	
	/** The Class to be instanciated. */
	private var clazz:Function;
	
	/**
	 * Constructs a new Call instance.
	 *
	 * @param clazz Class to be constructed.
	 */
	public function ConstructorCall(clazz:Function) {
		super (this, clazz);
		this.clazz = clazz;
	}
	
	/**
	 * Executes the passed method on the passed object with the given
	 * arguments and returns the result of the execution.
	 *
	 * @param args the arguments that shall be passed
	 * @return the result of the method execution
	 */
	public function execute() {
		var instance = ClassUtil.createCleanInstance(clazz);
		return clazz.apply(instance, arguments);
	}
	
}