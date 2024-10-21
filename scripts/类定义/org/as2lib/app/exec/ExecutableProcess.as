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
import org.as2lib.app.exec.Executable;
import org.as2lib.util.MethodUtil;

/**
 * {@code ExecutableProcess} is a Wrapper for {@link Executable}'s to be
 * executable as a {@link org.as2lib.app.exec.Process}.
 * 
 * <p>As Executables have no response features this is a wrapper for using any
 * executable as process.
 *
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.app.exec.ExecutableProcess extends AbstractProcess {

	/** Arguments to be applied to the executable at execution */
	private var args:Array;
	
	/** Executable to be executed */
	private var executable:Executable;
	
	/**
	 * Creates a new ExecutableProcess.
	 * 
	 * @param executable Executeable to be executed on process start.	 */
	public function ExecutableProcess(executable:Executable, args:Array) {
		super();
		this.executable = executable;
		this.args = args;
	}
	
	/**
	 * Implementation of {@link AbstractProcess#run}.	 */
	private function run() {
		MethodUtil.invoke("execute", executable, args);
	}
}