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

import org.as2lib.data.type.Integer;
import org.as2lib.data.type.NumberFormatException;

/**
 * {@code NaturalNumber} represents a natural number.
 *
 * <p>Natural numbers are positive integers excluding 0 in this case. If you want
 * to allow 0 use {@code NaturalNumberIncludingZero} instead.
 * 
 * @author Martin Heidegger
 * @see org.as2lib.data.type.NaturalNumberIncludingZero
 */
class org.as2lib.data.type.NaturalNumber extends Integer {
	
	/**
	 * Constructs a new {@code NaturalNumber} instance.
	 *
	 * <p>Decimal places are cropped from the passed-in {@code number} if it has at least
	 * one. The passed-in {@code number} must also not be negative.
	 * 
	 * @param number the natural number
	 * @throws NumberFormatException if the passed-in {@code number} is negative number,
	 * zero or (-)infinity
	 */
	public function NaturalNumber(number:Number) {
		super (number);
		if (int <= 0) {
			throw new NumberFormatException("Natural numbers don't inlude negative numbers or numbers that get zero if they were round down, like: "+number+".", this, arguments);
		}
	}
	
}