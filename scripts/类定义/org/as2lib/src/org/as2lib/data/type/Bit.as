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

/**
 * {@code Bit} is represents a bit value.
 * 
 * <p>{@code Bit} can be used for a different kind of formatting of a bit value.
 * It allows to access the value as bit, kilo-bit, mega-bit, giga-bit, tera-bit,
 * byte, kilo-byte, mega-byte, giga-byte and tera-byte.
 * 
 * @author Martin Heidegger
 * @version 1.1
 */
class org.as2lib.data.type.Bit extends BasicClass {
	
	/** Default floating points used. */
	public static var DEFAULT_FLOATING_POINTS:Number = 2;
	
	/** Size of a kilo. */
	private static var KILO:Number = 1024;
	
	/** Size of a kilobit. */
	private static var KILO_BIT:Number = KILO;
	
	/** Size of a megabit. */
	private static var MEGA_BIT:Number = KILO_BIT*KILO;
	
	/** Size of a gigabit. */
	private static var GIGA_BIT:Number = MEGA_BIT*KILO;
	
	/** Size of a terabit. */
	private static var TERA_BIT:Number = GIGA_BIT*KILO;
	
	/** Size of a byte. */
	private static var BYTE:Number = 8;
	
	/** Size of a kilobyte. */
	private static var KILO_BYTE:Number = KILO*BYTE;
	
	/** Size of a megabyte. */
	private static var MEGA_BYTE:Number = KILO_BYTE*KILO;
	
	/** Size of a gigabyte. */
	private static var GIGA_BYTE:Number = MEGA_BYTE*KILO;
	
	/** Size of a terabyte. */
	private static var TERA_BYTE:Number = GIGA_BYTE*KILO;
	
	/** Shortname of bit. */
	private static var SHORT_BIT:String = "b";
	
	/** Shortname of kilobit. */
	private static var SHORT_KILO_BIT:String = "Kb";
	
	/** Shortname of megabit. */
	private static var SHORT_MEGA_BIT:String = "Mb";
	
	/** Shortname of gigabit. */
	private static var SHORT_GIGA_BIT:String = "Gb";
	
	/** Shortname of terabit. */
	private static var SHORT_TERA_BIT:String = "Tb";
	
	/** Holder for the amount of bits. */
	private var bit:Number;
	
	/** Holder for the comma seperation. */
	private var comma:Number;
	
	/**
	 * Constructs a new {@code Bit}.
	 * 
	 * @param bit value in bit
	 */
	public function Bit(bit:Number) {
		this.bit = bit;
		comma = DEFAULT_FLOATING_POINTS;
	}
	
	/**
	 * Sets the used amount of values after the comma.
	 * 
	 * <p>This method does not change anything if {@code fp} is smaller than 0
	 * or not passed-in.
	 * 
	 * @param fp amount of characters after the floating point
	 * @return the current instance
	 */
	public function setFloatingPoints(fp:Number):Bit {
		if(fp >= 0 && fp != null) {
			this.comma = fp;
		}
		return this;
	}
	
	/**
	 * Rounds a number by a count of floating points.
	 * 
	 * @param num {@code Number} to be rounded
	 * @param fp amount of characters after the floating point
	 */
	private function round(num:Number, fp:Number):Number {
		var result:Number = 1;
		for(var i:Number = 0; i<fp; i++) {
			result *= 10;
		}
		return (Math.round(num*result)/result);
	}
	
	/**
	 * Returns the value in bit.
	 * 
	 * @return value in bit
	 */
	public function getBit(Void):Number {
		return bit;
	}
	
	/**
	 * Returns the value in bytes.
	 * 
	 * @return value in bytes
	 */
	public function getBytes(Void):Number {
		return round(bit/BYTE, comma);
	}
	
	/**
	 * Returns the value in kilobit.
	 * 
	 * @return value in kilobit
	 */
	public function getKiloBit(Void):Number {
		return round(bit/KILO_BIT, comma);
	}
	
	/**
	 * Returns the value in kilobytes.
	 * 
	 * @return value in kilobytes
	 */
	public function getKiloBytes(Void):Number {
		return round(bit/KILO_BYTE, comma);
	}
	
	/**
	 * Returns the value in megabit.
	 * 
	 * @return value in megabit
	 */
	public function getMegaBit(Void):Number {
		return round(bit/MEGA_BIT, comma);
	}
	
	/**
	 * Returns the value in megabytes.
	 * 
	 * @return value in megabytes
	 */
	public function getMegaBytes(Void):Number {
		return round(bit/MEGA_BYTE, comma);
	}
	
	/**
	 * Returns the value in gigabit.
	 * 
	 * @return value in gigabit
	 */
	public function getGigaBit(Void):Number {
		return round(bit/GIGA_BIT, comma);
	}
	
	/**
	 * Returns the value in gigabytes.
	 * 
	 * @return value in gigabytes
	 */
	public function getGigaBytes(Void):Number {
		return round(bit/GIGA_BYTE, comma);
	}
	
	/**
	 * Returns the value in terabit.
	 * 
	 * @return value in terabit
	 */
	public function getTeraBit(Void):Number {
		return round(bit/TERA_BIT, comma);
	}
	
	/**
	 * Returns the value in terabytes.
	 * 
	 * @return value in terabytes
	 */
	public function getTeraBytes(Void):Number {
		return round(bit/TERA_BYTE, comma);
	}
	
	/**
	 * Extended toString method for a well formatted bit value.
	 * 
	 * <p>This method uses the next matching size and adds the matching Shortname for it.
	 * 
	 * <p>Examples:
	 * <code>
	 *   new BitFormat(1).toString(); // 1b
	 *   new BitFormat(1234).toString(); // 1.21Kb
	 *   new BitFormat(15002344).toString(); // 14.31Mb
	 * </code>
	 * 
	 * @return bits in the next matching size with the matchin unit
	 * @see #DEFAULT_FLOATING_POINTS
	 */
	public function toString():String {
		if(bit < KILO_BIT) {
			return getBit()+SHORT_BIT;
		} else if(bit < MEGA_BIT) {
			return getKiloBit()+SHORT_KILO_BIT;
		} else if(bit < GIGA_BIT) {
			return getMegaBit()+SHORT_MEGA_BIT;
		} else if(bit < TERA_BIT) {
			return getGigaBit()+SHORT_GIGA_BIT;
		} else {
			return getTeraBit()+SHORT_TERA_BIT;
		}
	}
	
	/**
	 * 
	 */
	public function valueOf():Number {
		return getBytes();
	}
}