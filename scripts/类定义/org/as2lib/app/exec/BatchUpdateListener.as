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

import org.as2lib.app.exec.Batch;

/**
 * {@code BatchUpdateListener} is a defintion for a observer for updates of a
 * {@link Batch}.
 * 
 * <p>To observe changes/updates of a {@code Batch} you can implement this
 * interface and add your implementation with {@link Batch#addListener} to
 * observe a certain {@code Batch}.
 * 
 * <p>{@code start}, {@code error} and {@code finish} are no accepted changes of
 * the state.
 * 
 * @author Martin Heidegger
 * @version 2.0
 * @see Process
 */
interface org.as2lib.app.exec.BatchUpdateListener {
	
	/**
	 * Method to be executed if a {@code Batch} property changes.
	 * 
	 * @param batch {@link Batch} that changed some properties
	 */
	public function onBatchUpdate(batch:Batch):Void;	
}