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
 * {@code Degree} represents a angle in degree.
 * 
 * @author Martin Heidegger
 */
class org.as2lib.data.type.Degree extends Number implements Angle {
	
	/** Angle in degree. */
	private var degree:Number;
	
	/**
	 * Constructs a new {@code Degree} instance.
	 * 
	 * @param degree the angle in degree
	 */
	public function Degree(degree:Number) {
		this.degree = degree;
	}
	
	/**
	 * Returns the angle in degree as number.
	 * 
	 * @return the angle in degree as number
	 */
	public function valueOf(Void):Number {
		return degree;
	}
	
	/**
	 * Returns the angle in radian.
	 * 
	 * @return the angle in radian
	 */
	public function toRadian(Void):Number {
		return (degree * Math.PI/180);
	}
	
	/**
	 * Returns the angle in degree.
	 * 
	 * @return the angle in degree
	 */
	public function toDegree(Void):Number {
		return degree;
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