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

import org.as2lib.test.unit.AbstractAssertInfo;

/**
 * Information holder and examiner of a assertNotUndefined call.
 * 
 * @author Martin Heidegger.
 */
class org.as2lib.test.unit.info.AssertNotUndefinedInfo extends AbstractAssertInfo {
	
	/** Internal holder of the variable value. */
	private var val;
	
	/**
	 * Constructs a new AssertNotUndefinedInfo.
	 * 
	 * @param message Message if the assertion fails.
	 * @param val Value that should not be undefined.
	 */
	public function AssertNotUndefinedInfo(message:String, val) {
		super(message);
		this.val = val;
	}
	
	/**
	 * Overriding of @see AbstractAssertInfo#execute
	 * 
	 * @return True if the execution fails.
	 */
	public function execute(Void):Boolean {
		return(val === undefined);
	}
	
	/**
	 * Implementation of @see AbstractAssertInfo#getFailureMessage
	 * 
	 * @return Message on failure
	 */
	private function getFailureMessage(Void):String {
		var result:String = "assertNotUndefined failed";
		if(hasMessage()) {
			result += " with message: "+message;
		}
		result += "!\n"
				+ "  "+val+" === undefined";
		return result;
	}
	
	/**
	 * Implementation of @see AbstractAssertInfo#getSuccessMessage
	 * 
	 * @return Message on success
	 */
	private function getSuccessMessage(Void):String {
		return ("assertNotUndefined executed. "+val+" !== undefined.");
	}
}