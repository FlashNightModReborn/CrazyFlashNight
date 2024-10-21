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
import org.as2lib.io.file.TextFile;
import org.as2lib.io.file.TextFileFactory;
import org.as2lib.io.file.PropertiesFile;

/**
 * {@code PropertiesFileFactory} is a implementation of {@link TextFileFactory} for
 * creating {@code PropertiesFile} instances.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.io.file.PropertiesFileFactory extends BasicClass implements TextFileFactory {
	
	/**
	 * Creates a new {@code PropertiesFile} instance for the loaded resource.
	 * 
	 * @param source content of the file to create
	 * @param size size in bytes of the loaded resource
	 * @param uri location of the loaded resource
	 * @return a property file that represents the resource
	 */
	public function createTextFile(source:String, size:Byte, uri:String):TextFile {
		return (new PropertiesFile(source, size, uri));
	}

}