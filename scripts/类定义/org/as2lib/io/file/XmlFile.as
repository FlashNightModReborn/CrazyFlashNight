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

import org.as2lib.data.type.Byte;
import org.as2lib.io.file.SimpleTextFile;

/**
 * {@code XmlFile} is implementation of {@code TextFile} for a xml resource.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.io.file.XmlFile extends SimpleTextFile {
	
	/** Container Xml file. */
	private var xml:XML;
	
	/**
	 * Constructs a new {@code XmlFile}.
	 * 
	 * @param source content of the {@code XmlFile} to create
	 * @param size size in {@link Byte} of the loaded resource
	 * @param uri location of the loaded resource
	 */
	public function XmlFile(source:String, size:Byte, uri:String) {
		super(source, size, uri);
		xml = new XML();
		xml.parseXML(source);
	}
	
	/**
	 * Returns the XML content in form of a proper accessable {@code XML} instance.
	 * 
	 * @return {@code XML} instance to access the XML content
	 */
	public function getXml(Void):XML {
		return xml;
	}
}