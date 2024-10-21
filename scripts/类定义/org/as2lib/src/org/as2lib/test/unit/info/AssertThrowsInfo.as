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
import org.as2lib.app.exec.Executable;
import org.as2lib.util.StringUtil;
import org.as2lib.env.reflect.ClassInfo;

/**
 * Information holder and examiner of a assertThrows call.
 * 
 * @author Martin Heidegger.
 */
class org.as2lib.test.unit.info.AssertThrowsInfo extends AbstractAssertInfo {
	
	/** Holder for the Exception type. */
	private var type;
	
	/** Holder for the call to be executed. */
	private var toCall:Executable;
	
	/** Holder for the arguments for the call. */
	private var args:Array;
	
	/** Holder for a thrown exception. */
	private var exception;
	
	/** Flag if a exception was thrown. */
	private var exceptionThrown:Boolean = false;
	
	/**
	 * Constructs a new AssertThrowsInfo.
	 * 
	 * @param message Message if the assertion fails.
	 * @param type Exception type that should be thrown. (if null is given, it fails if no exception was thrown).
	 * @param toCall Call to be executed
	 * @param args Arguments for the Call.
	 */
	public function AssertThrowsInfo(message:String, type, toCall:Executable, args:Array) {
		super(message);
		this.type = type;
		this.toCall = toCall;
		this.args = args;
	}
	
	/**
	 * Overriding of @see AbstractAssertInfo#execute
	 * 
	 * @return True if the execution fails.
	 */
	public function execute(Void):Boolean {
		try {
			// cat to Object because of Flash compiler bug with interfaces
			toCall.execute.apply(Object(toCall), args);
		} catch(e) {
			exception = e;
			exceptionThrown = true;
			if(type != null) {
				return(!(e instanceof type));
			} else {
				return false;
			}
		}
		return true;
	}
	
	/**
	 * Implementation of @see AbstractAssertInfo#getFailureMessage
	 * 
	 * @return Message on failure
	 */
	private function getFailureMessage(Void):String {
		var result:String = "assertThrows failed";
		if(hasMessage()) {
			result += " with message: "+message;
		}
		if(type == null) {
			result += "!\n  No exception thrown - Any exception expected";
		} else {
			result += "!\n  - Expected exception:\n      ";
			if(typeof type == "function") {
				result += ClassInfo.forClass(type).getFullName();
			} else {
				result += type;
			}
			if(exceptionThrown) {
				result += "\n  - Thrown exception:\n"+StringUtil.addSpaceIndent(exception.toString(), 6);
			} else {
				result += "\n  - No exception thrown.";
			}
		}
		return result;
	}
	
	/**
	 * Implementation of @see AbstractAssertInfo#getSuccessMessage
	 * 
	 * @return Message on success
	 */
	private function getSuccessMessage(Void):String {
		var result:String = "assertThrows executed. ";
		
		if(typeof type == "function") {
			result += ClassInfo.forClass(type).getFullName();
		} else {
			result += type;
		}
		
		result += "was thrown by calling "+toCall.toString()+".";
		
		return result;
	}
}