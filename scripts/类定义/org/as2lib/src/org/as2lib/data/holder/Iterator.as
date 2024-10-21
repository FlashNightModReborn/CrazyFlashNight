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

import org.as2lib.core.BasicInterface;

/**
 * {@code Iterator} is used to iterate over data holders.
 *
 * <p>An iterator is quite simple to use. There is one method to check whether there
 * are more elements left to iterate over {@link #hasNext}, one method to get the
 * next element {@link #next} and one to remove the current element {@link #remove}.
 * 
 * <p>Example:
 * <code>
 *   var iterator:Iterator = new MyIterator("value1", "value2", "value3");
 *   while (iterator.hasNext()) {
 *       trace(iterator.next());
 *   }
 * </code>
 *
 * <p>Output:
 * <pre>
 *   value1
 *   value2
 *   value3
 * </pre>
 *
 * @author Simon Wacker
 * @author Michael Herrmann
 */
interface org.as2lib.data.holder.Iterator extends BasicInterface {
	
	/**
	 * Returns whether there is another element to iterate over.
	 * 
	 * @return {@code true} if there is at least one element left to iterate
	 * over
	 */
	public function hasNext(Void):Boolean;
	
	/**
	 * Returns the next element.
	 * 
	 * @return the next element
	 * @throws org.as2lib.data.holder.NoSuchElementException if there is no next element
	 */
	public function next(Void);
	
	/**
	 * Removes the currently selected element from this iterator and from the data holder
	 * this iterator iterates over.
	 * 
	 * @throws org.as2lib.env.except.IllegalStateException if you try to remove an element
	 * when none is selected
	 * @throws org.as2lib.env.except.UnsupportedOperationException if this method is not
	 * supported by the concrete implementation of this interface
	 */
	public function remove(Void):Void;
	
}