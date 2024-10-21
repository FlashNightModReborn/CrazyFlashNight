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
import org.as2lib.io.file.TextFile;
import org.as2lib.data.type.Byte;
import org.as2lib.env.reflect.ReflectUtil;

/**
 * {@code SimpleTextFile} represents the simplest way for accessing the file informations.
 * 
 * <p>Supports all necessary features for {@code TextFile} without any other advantages.
 * 
 * @author Martin Heidegger
 * @version 2.0
 */
class org.as2lib.io.file.SimpleTextFile extends BasicClass implements TextFile {
	
	/** Content of the file. */
	private var source:String;
	
	/** Location of the file. */
	private var uri:String;
	
	/** Size of the file in bytes. */
	private var size:Byte;
	
	/**
	 * Constructs a new {@code SimpleTextFile}.
	 * 
	 * @param source content of the {@code TextFile} to create
	 * @param size size in {@link Byte} of the loaded resource
	 * @param uri location of the loaded resource
	 */
	public function SimpleTextFile(source:String, size:Byte, uri:String) {
		this.source = source;
		this.uri = uri;
		this.size = size;
	}
	
	/**
	 * Returns the location of the resource corresponding to the content.
	 * 
	 * <p>Note: Might be the URI of the resource or null if its not requestable
	 * or the internal location corresponding to the instance path (if its without
	 * any connection to a real file).
	 * 
	 * @return location of the resource related to the content
	 */
	public function getLocation(Void):String {
		return uri;
	}
	
	/**
	 * Returns the content of the file
	 * 
	 * @return content of the file
	 * @see TextFile#getContent
	 */
	public function getContent(Void):String {
		return source;
	}
	
	/**
	 * Returns the size of the file in bytes.
	 * 
	 * @return size of the file in bytes
	 */
	public function getSize(Void):Byte {
		return size;
	}
	
	/**
	 * Extended Stringifier
	 * 
	 * Example:
	 * {@code [type org.as2lib.io.file.SimpleTextFile | Location: MyTextFile.txt; Size: 12KB; ]}
	 * 
	 * @return the {@code TextFile} as string
	 */
	public function toString():String {
		var result:String;
		result = "[type " + ReflectUtil.getTypeNameForInstance(this)
				 + " | Location: " + getLocation()
				 + "; Size: " + getSize().toString(false, 2)
				 + "; ]";
		return result;
	}
}