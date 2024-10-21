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
import org.as2lib.data.type.NumberFormatException;

/**
 * {@code Integer} represents an integer value.
 *
 * <p>A integer is a positive or negative natural number including 0.
 * 
 * @author Martin Heidegger.
 */
class org.as2lib.data.type.Integer extends Number implements BasicInterface {
	
	/** The actual integer. */
	private var int:Number;
	
	/**
	 * Constructs a new {@code Integer} instance.
	 *
	 * <p>The passed-in {@code number} is transformed into an integer. The {@code number}
	 * will be floored so that only the base will be used as integer, if it has decimal
	 * places.
	 * 
	 * @param number the number to convert to an integer
	 * @throws NumberFormatException if the passed-in {@code number} is infinity or
	 * -infinity.
	 */
	public function Integer(number:Number) {
		if (number == Infinity || number == -Infinity) {
			throw new NumberFormatException("Infinity is not evaluateable as integer", this, arguments);
		} else {
			int = number - number%1;
		}
	}
	
	/**
	 * Returns this integer as number.
	 * 
	 * @return this integer as number
	 */
	public function valueOf(Void):Number {
		return int;
	}
	
	/**
	 * Returns the string representation of this integer.
	 * 
	 * @return the string representation of this integer
	 */
	public function toString():String {
		return int.toString();
	}

}