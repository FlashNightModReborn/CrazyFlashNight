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

import org.as2lib.io.file.FileLoader;

/**
 * {@code LoadCompleteListener} can be implemented if its necessary to listen
 * to {@code onLoadComplete} events of {@link FileLoader}s.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
interface org.as2lib.io.file.LoadCompleteListener {
	
	/**
	 * Event to be published if the file finished loading.
	 * 
	 * <p>This event will only occur after the {@code FileLoader} was started.
	 * 
	 * <p>This event will not occur if the file was not available.
	 * 
	 * @param fileLoader {@code FileLoader} that contains the requested resource
	 */
	public function onLoadComplete(fileLoader:FileLoader):Void;
}