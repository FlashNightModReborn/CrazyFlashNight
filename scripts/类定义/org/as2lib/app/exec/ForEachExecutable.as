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
 
import org.as2lib.app.exec.Executable;

/**
 * {@code ForEachExecutable} is a extension to {@link Executable} to execute the
 * certain executale for all childs within a object.
 * 
 * @author Martin Heidegger
 * @version 1.0 */ 
interface org.as2lib.app.exec.ForEachExecutable extends Executable {

	/**
	 * Iterates through the passed-in {@code object} and invokes the 
	 * {@link #execute} method for every member passing-in the member itself,
	 * the name of the member and the passed-in {@code object}.
	 *
	 * @param object the object to iterate over
	 * @return list with the result of each execution
	 */
	public function forEach(object):Array;
}