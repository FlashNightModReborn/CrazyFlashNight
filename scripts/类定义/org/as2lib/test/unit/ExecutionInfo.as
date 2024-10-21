/**
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

/**
 * Interface for all Informations occured during the execution of a method of a testcase.
 * 
 * @autor Martin Heidegger
 */
interface org.as2lib.test.unit.ExecutionInfo extends BasicInterface {
	
	/**
	 * @return true if the information should be recognized as failure
	 */
	public function isFailed(Void):Boolean;
	
	/**
	 * Returns the message to the information.
	 * 
	 * @return Message to the assertion.
	 */
	public function getMessage(Void):String;
}