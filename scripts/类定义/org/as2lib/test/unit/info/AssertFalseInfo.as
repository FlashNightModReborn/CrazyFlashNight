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
import org.as2lib.util.StringUtil;

/**
 * Information holder and examiner of a assertFalse call.
 * 
 * @author Martin Heidegger.
 */
class org.as2lib.test.unit.info.AssertFalseInfo extends AbstractAssertInfo {
	
	/** Internal holder of the variable value. */
	private var val;
	
	/**
	 * Constructs a new AssertFalseInfo.
	 * 
	 * @param message Message if the assertion fails.
	 * @param val Value that should be false.
	 */
	public function AssertFalseInfo(message:String, val) {
		super(message);
		this.val = val;
	}
	
	/**
	 * Overriding of @see AbstractAssertInfo#execute
	 * 
	 * @return True if the execution fails.
	 */
	public function execute(Void):Boolean {
		return(val !== false);
	}
	
	/**
	 * Implementation of @see AbstractAssertInfo#getFailureMessage
	 * 
	 * @return Message on failure
	 */
	private function getFailureMessage(Void):String {
		var result:String = "assertFalse failed";
		if(hasMessage()) {
			result += " with message: "+message;
		}
		result += "!\n"+StringUtil.addSpaceIndent(val+" !== false", 2);
		return result;
	}
	
	/**
	 * Implementation of @see AbstractAssertInfo#getSuccessMessage
	 * 
	 * @return Message on success
	 */
	private function getSuccessMessage(Void):String {
		return ("assertFalse executed.");
	}
}