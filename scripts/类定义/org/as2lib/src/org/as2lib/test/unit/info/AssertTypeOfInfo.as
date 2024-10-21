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
 * Information holder and examiner of a assertTypeOf call.
 * 
 * @author Martin Heidegger.
 */
class org.as2lib.test.unit.info.AssertTypeOfInfo extends AbstractAssertInfo {
	
	/** Internal holder of the variable value. */
	private var val;
	
	/** Internal holder of the type value. */
	private var type:String;
	
	/**
	 * Constructs a new AssertTypeOfInfo.
	 * 
	 * @param message Message if the assertion fails.
	 * @param val Value to be checked.
	 * @param type Type of the value
	 */
	public function AssertTypeOfInfo(message:String, val, type:String) {
		super(message);
		this.val = val;
		this.type = type;
	}
	
	/**
	 * Overriding of @see AbstractAssertInfo#execute
	 * 
	 * @return True if the execution fails.
	 */
	public function execute(Void):Boolean {
		return(typeof val != type);
	}
	
	/**
	 * Implementation of @see AbstractAssertInfo#getFailureMessage
	 * 
	 * @return Message on failure
	 */
	private function getFailureMessage(Void):String {
		var result:String = "assertTypeOf failed";
		if(hasMessage()) {
			result += " with message: "+message;
		}
		result += "!\n"
				+ (typeof val) + "(typeof '"+val.toString()+"') != "+type;
		return result;
	}
	
	
	/**
	 * Implementation of @see AbstractAssertInfo#getSuccessMessage
	 * 
	 * @return Message on success
	 */
	private function getSuccessMessage(Void):String {
		return ("assertTypeOf executed. (typeof '"+val.toString()+"') == "+type+".");
	}
}