/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
 
import org.as2lib.io.file.File;

/**
 * {@code TextFile} is a holder for human readable external resources.
 * 
 * <p>{@code TextFile} provides access to the content of the real file.
 * 
 * <p>{@code TextFile} is <b>not</b> built to represent binary files.
 * 
 * @author Martin Heidegger
 * @version 2.0
 */
interface org.as2lib.io.file.TextFile extends File {
	
	/**
	 * Returns the complete content of the file.
	 * 
	 * @return content of the file
	 */
	public function getContent(Void):String;
}