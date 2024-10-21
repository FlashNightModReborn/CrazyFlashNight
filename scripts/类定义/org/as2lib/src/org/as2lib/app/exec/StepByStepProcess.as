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
 
import org.as2lib.app.exec.Process;

/**
 * {@code StepByStepProcess} is a process that can be executed in parts(steps).
 * 
 * <p>There are algorithms or other things that are not possible to be executed 
 * within one frame since MM Flash Player has a max time limit for the execution
 * of code.
 * 
 * <p>{@link org.as2lib.app.exec.Processor} allows processing of implementations
 * by executing {@link #nextStep} until eigther the process has finished.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
interface org.as2lib.app.exec.StepByStepProcess extends Process {
	
	/**
	 * Executes the next step of the process.
	 */
	public function nextStep(Void):Void;
}