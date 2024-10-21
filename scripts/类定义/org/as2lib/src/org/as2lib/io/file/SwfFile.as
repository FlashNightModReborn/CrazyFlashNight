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
import org.as2lib.data.type.Byte;
import org.as2lib.env.reflect.ReflectUtil;
import org.as2lib.io.file.MediaFile;

/**
 * {@code SwfFile} holds all information of a loaded SWF-file.
 * 
 * <p>Note that this file can also be used to represent images.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.io.file.SwfFile extends BasicClass implements MediaFile {

	/** Size of the file in bytes. */
	private var size:Byte;

	/** Location of the file. */
	private var uri:String;

	/** Container of the loaded MovieClip */
	private var container:MovieClip;
	
	/**
	 * Constructs a new {@code SwfFile}.
	 * 
	 * @param container {@code MovieClip} that contains the loaded {@code .swf}
	 * @param uri (optional) URI to use as location ({@code container._url} will
	 * 		  be used as default).
	 * @param size (optional) size of the loaded {@code .swf}
	 *        ({@code container.getBytesTotal()} will be used as default.)
	 */
	public function SwfFile(container:MovieClip, uri:String, size:Byte) {
		if (!size) {
			size = new Byte(container.getBytesTotal());
		}
		if (!uri) {
			uri = container._url;
		}
		this.size = size;
		this.uri = uri;
		this.container = container;
	}
	
	/**
	 * Returns the container to the resource.
	 * 
	 * @return {@code MovieClip} that contains the {@code .swf}
	 */
	public function getContainer(Void):MovieClip {
		return container;
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
	 * {@code [type org.as2lib.io.file.SwfResource | Location: MyFile.txt; Size: 12KB; ]}
	 * 
	 * @return the {@code SwfResource} as string
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