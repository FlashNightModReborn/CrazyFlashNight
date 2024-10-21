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

import org.as2lib.io.file.FileLoader;

/**
 * {@code LoadErrorListener} can be implemented if its necessary to listen
 * to {@code onLoadError} events of {@link FileLoader}s.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
interface org.as2lib.io.file.LoadErrorListener {
	
	/**
	 * Event to be published if a error occured during loading of a certain resource.
	 * 
	 * @param fileLoader {@code FileLoader} that executes the request
	 * @param errorCode error-code to fast identify the concrete error
	 * @param error information to the certain error
	 * @return {@code true} to consume the event
	 */
	public function onLoadError(fileLoader:FileLoader, errorCode:String, error):Boolean;
}