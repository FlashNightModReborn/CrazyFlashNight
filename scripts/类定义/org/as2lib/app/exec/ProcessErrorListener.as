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

import org.as2lib.app.exec.Process;

/**
 * {@code ProcessErrorListener} is a defintion for a observer of error that occur
 * during the execution of a  {@link Process}.
 * 
 * <p>To observe errors that occur during the execution of a {@code Process} you
 * can implement this interface and add your implementation with {@link Process#addListener}
 * to observe a certain {@code Process}.
 * 
 * @author Martin Heidegger
 * @version 2.0
 * @see Process
 */
interface org.as2lib.app.exec.ProcessErrorListener {
	
    /**
     * Method to be executed if a error occured during the execution of the {@code Process}
     * 
     * @param process {@link Process} where a error occured
     * @param error error that occured during execution
     * @return {@code true} to consume the event
     */
    public function onProcessError(process:Process, error):Boolean;
}