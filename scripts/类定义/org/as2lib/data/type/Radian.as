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

import org.as2lib.data.type.Angle;
import org.as2lib.Config;

/**
 * {@code Radian} represents a angle in radian.
 * 
 * @author Martin Heidegger
 */
class org.as2lib.data.type.Radian extends Number implements Angle {
	
	/** The angle in radian. */
	private var radian:Number;
	
	/**
	 * Constructs a new {@code Radian} instance.
	 * 
	 * @param radian the angle in radian
	 */
	public function Radian(radian:Number) {
		this.radian = radian;
	}
	
	/**
	 * Returns the angle in radian as number.
	 * 
	 * @return the angle in radian as number
	 */
	public function valueOf(Void):Number {
		return radian;
	}
	
	/**
	 * Returns the angle in radian.
	 * 
	 * @return the angle in radian
	 */
	public function toRadian(Void):Number {
		return radian;
	}
	
	/**
	 * Returns the angle in degree.
	 * 
	 * @return the angle in degree
	 */
	public function toDegree(Void):Number {
		return radian*180/Math.PI;
	}
	
	/**
	 * Returns the string representation of this instance.
	 *
	 * <p>The string representation is obtained via the stringifier returned by the
	 * {@link Config#getObjectStringifier} method.
	 * 
	 * @return the string representation of this instance
	 */
	public function toString():String {
		return Config.getObjectStringifier().execute(this);
	}
}