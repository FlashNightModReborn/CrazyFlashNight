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

import org.as2lib.core.BasicClass;
import org.as2lib.data.holder.Iterator;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.except.UnsupportedOperationException;

/**
 * {@code ProtectedIterator} is used to iterate over any data holder
 * without being able to remove elements.
 * 
 * <p>This class acts as a wrapper for any class that implements the
 * {@code Iterator} interface and wants to be protected.
 *
 * @author Simon Wacker
 * @author Michael Herrmann
 */
class org.as2lib.data.holder.ProtectedIterator extends BasicClass implements Iterator {
	
	/** Holds the iterator this protected iterator delegates to. */
	private var iterator:Iterator;
	
	/**
	 * Constructs a new {@code ProtectedIterator} instance.
	 * 
	 * <p>This iterator forwards all functionality to the wrapped passed-in
	 * {@code iterator}, except the removal of the current element.
	 * 
	 * @param iterator the iterator to protect
	 * @throws IllegalArgumentException if the passed-in {@code iterator}
	 * is {@code null} or {@code undefined}
	 */
	public function ProtectedIterator(iterator:Iterator) {
		if (!iterator) throw new IllegalArgumentException("Argument 'iterator' [" + iterator + "] to protect is not allowed to be 'null' or 'undefined'.", this, arguments);
		this.iterator = iterator;
	}
	
	/**
	 * Returns whether there are more elements to iterate over.
	 *
	 * <p>For any special functionality that may be performed refer to the
	 * wrapped iterator that has been passed-in on construction. This method
	 * simply delegates to the wrapped iterator.
	 *
	 * @return {@code true} if there is a next element else {@code false}
	 */
	public function hasNext(Void):Boolean {
		return iterator.hasNext();
	}
	
	/**
	 * Returns the next element.
	 *
	 * <p>For any special functionality that may be performed refer to the
	 * wrapped iterator that has been passed-in on construction. This method
	 * simply delegates to the wrapped iterator.
	 *
	 * @return the next element
	 * @throws org.as2lib.data.holder.NoSuchElementException if there is
	 * no next element
	 */
	public function next(Void) {
		return iterator.next();
	}
	
	/**
	 * This method always throws an {@code UnsupportedOperationException}
	 * because this method is not supported by this iterator and has the
	 * duty to not let the removal of elements happen.
	 *
	 * @throws UnsupportedOperationException
	 */
	public function remove(Void):Void {
		throw new UnsupportedOperationException("This Iterator does not support the remove() method.", this, arguments);
	}
	
}