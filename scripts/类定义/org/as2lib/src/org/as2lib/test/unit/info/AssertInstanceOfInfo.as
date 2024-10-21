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
import org.as2lib.util.ObjectUtil;
import org.as2lib.util.StringUtil;
import org.as2lib.env.reflect.ClassInfo;

/**
 * Information holder and examiner of a assertInstanceOf call.
 * 
 * @author Martin Heidegger.
 */
class org.as2lib.test.unit.info.AssertInstanceOfInfo extends AbstractAssertInfo {
	
	/** Internal holder of the variable value. */
	private var val;
	
	/** Internal holder of the type value. */
	private var type:Function;
	
	/**
	 * Constructs a new AssertInstanceOfInfo.
	 * 
	 * @param message Message if the assertion fails.
	 * @param val Value to be checked.
	 * @param type Type of the value.
	 */
	public function AssertInstanceOfInfo(message:String, val, type:Function) {
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
		return (!(ObjectUtil.typesMatch(val, type)));
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
		result += "!\n"+StringUtil.addSpaceIndent("'"+val+"' is not a instance of '"+ClassInfo.forClass(type).getFullName()+"'", 2);
		return result;
	}
	
	
	/**
	 * Implementation of @see AbstractAssertInfo#getSuccessMessage
	 * 
	 * @return Message on success
	 */
	private function getSuccessMessage(Void):String {
		return ("assertInstanceOf executed.\n"+StringUtil.addSpaceIndent("'"+val+"' is a instance of '"+ClassInfo.forClass(type).getFullName()+"'.", 2));
	}
}