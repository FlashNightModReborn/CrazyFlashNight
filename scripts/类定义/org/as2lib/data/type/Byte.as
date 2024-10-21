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

import org.as2lib.data.type.Bit;

/**
 * {@code Byte} is represents a byte value.
 * 
 * <p>{@code Byte} can be used for a different kind of formatting of a byte value.
 * It allows to access the value as bit, kilo-bit, mega-bit, giga-bit, tera-bit,
 * byte, kilo-byte, mega-byte, giga-byte and tera-byte.
 * 
 * @author Martin Heidegger
 * @version 1.1
 */
class org.as2lib.data.type.Byte extends Bit {
	
	/** Shortname of byte. */
	private static var SHORT_BYTE:String = "B";
	
	/** Shortname of kilo-byte. */
	private static var SHORT_KILO_BYTE:String = "KB";
	
	/** Shortname of mega-byte. */
	private static var SHORT_MEGA_BYTE:String = "MB";
	
	/** Shortname of giga-byte. */
	private static var SHORT_GIGA_BYTE:String = "GB";
	
	/** Shortname of tera-byte. */
	private static var SHORT_TERA_BYTE:String = "TB";
	
	/**
	 * Constructs a new {@code Byte}.
	 * 
	 * @param bytes value in byte
	 */
	public function Byte(bytes:Number) {
		super(bytes*BYTE);
	}
	
	/**
	 * Extended toString method for a well formatted byte value.
	 * 
	 * <p>This method uses the next matching size and adds the matching Shortname for it.
	 * 
	 * <p>Examples:
	 * <code>
	 *   new ByteFormat(1).toString(); // 1B
	 *   new ByteFormat(1234).toString(); // 1.21KB
	 *   new ByteFormat(15002344).toString(); // 14.31MB
	 * </code>
	 * 
	 * @return bytes as string with correct ending.
	 * @see BitFormat#DEFAULT_FLOATING_POINTS
	 */
	public function toString():String {
		if(bit < KILO_BYTE) {
			return getBytes()+SHORT_BYTE;
		} else if(bit < MEGA_BYTE) {
			return getKiloBytes()+SHORT_KILO_BYTE;
		} else if(bit < GIGA_BYTE) {
			return getMegaBytes()+SHORT_MEGA_BYTE;
		} else if(bit < TERA_BYTE) {
			return getGigaBytes()+SHORT_GIGA_BYTE;
		} else {
			return getTeraBytes()+SHORT_TERA_BYTE;
		}
	}
}