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
 * {@code ProcessResumeListener} is a defintion for a observer of a resuming of a
 * {@link Process}.
 * 
 * <p>To observe a resuming of a {@code Process} you can implement this interface
 * and add your implementation with {@link Process#addListener} to observe a
 * certain {@code Process}.
 * 
 * @author Martin Heidegger
 * @version 2.0
 * @see Process
 */
interface org.as2lib.app.exec.ProcessResumeListener {
	
	/**
	 * Method to be executed if a process awakes from pause.
	 * 
	 * @param process {@link Process} that resumes execution
	 */
	public function onProcessResume(process:Process):Void;
}