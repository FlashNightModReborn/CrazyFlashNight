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
 * {@code ProcessPauseListener} is a defintion for a observer of a pausing of a
 * {@link Process}.
 * 
 * <p>To observe a pausing of a {@code Process} you can implement this interface
 * and add your implementation with {@link Process#addListener} to observe a
 * certain {@code Process}.
 * 
 * @author Martin Heidegger
 * @version 2.0
 * @see Process
 */
interface org.as2lib.app.exec.ProcessPauseListener {
	
	/**
	 * Method to be executed if a process pauses.
	 * 
	 * @param process {@link Process} that paused execution
	 */
	public function onProcessPause(process:Process):Void;
}