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
import org.as2lib.io.file.TextFile;
import org.as2lib.data.type.Byte;

/**
 * {@code TextFileFactory} is a integration layer for {@link org.as2lib.util.TextFileLoader}.
 * 
 * <p>{@code TextFileLoader} applies the loaded resource to {@code TextFileFactory} 
 * property. The implementations of {@code TextFileLoader} can variy the result of 
 * the loaded file.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
interface org.as2lib.io.file.TextFileFactory extends BasicInterface {
	
	/**
	 * Creates a new {@code TextFile} instance for the loaded resource.
	 * 
	 * @param source content of the {@code TextFile} to create
	 * @param size size in {@link Byte} of the loaded resource
	 * @param uri URI that has been loaded
	 * @return {@code TextFile} that represents the resource
	 */
	public function createTextFile(source:String, size:Byte, uri:String):TextFile;
}