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

import org.as2lib.app.exec.Batch;

/**
 * {@code BatchErrorListener} is a defintion for a observer of error that occur
 * during the execution of a  {@link Batch}.
 * 
 * <p>To observe errors that occur during the execution of a {@code Batch} you
 * can implement this interface and add your implementation with {@link Batch#addListener}
 * to observe a certain {@code Batch}.
 * 
 * @author Martin Heidegger
 * @version 2.0
 * @see Batch
 */
interface org.as2lib.app.exec.BatchErrorListener {
	
    /**
     * Method to be executed if a error occured during the execution of the {@code Batch}
     * 
     * @param batch {@link Batch} where a error occured
     * @param error error that occured during execution
     * @return {@code true} to consume the event
     */
	public function onBatchError(batch:Batch, error):Boolean;
}