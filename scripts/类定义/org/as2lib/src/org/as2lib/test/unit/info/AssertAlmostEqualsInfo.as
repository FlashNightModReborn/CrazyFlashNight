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
 * Information holder and examiner of a assertAlmostEquals call.
 * 
 * @author Martin Heidegger.
 */
class org.as2lib.test.unit.info.AssertAlmostEqualsInfo extends AbstractAssertInfo {
	
	/** Internal holder of the variable value. */
	private var val:Number;
	
	/** Internal holder of the value to compare. */
	private var compareTo:Number;
	
	/** Internal holder of the maximal difference between those two values. */
	private var maxDiff:Number;
	
	/**
	 * Constructs a new AssertAlmostEqualsInfo.
	 * 
	 * @param message Message if the assertion fails.
	 * @param val Value to be compared.
	 * @param maxDiff Maximum difference between those two numbers.
	 * @param compareTo Value to be compared with.
	 */
	public function AssertAlmostEqualsInfo(message:String, val:Number, compareTo:Number, maxDiff:Number) {
		super(message);
		this.val = val;
		this.compareTo = compareTo;
		this.maxDiff = maxDiff;
	}
	
	/**
	 * Overriding of @see AbstractAssertInfo#execute
	 * 
	 * @return True if the execution fails.
	 */
	public function execute(Void):Boolean {
		return ( (val > compareTo && val-maxDiff > compareTo) || (val < compareTo && val+maxDiff < compareTo) );
	}
	
	/**
	 * Implementation of @see AbstractAssertInfo#getFailureMessage
	 * 
	 * @return Message on failure
	 */
	private function getFailureMessage(Void):String {
		var result:String = "assertAlmostEquals failed";
		if(hasMessage()) {
			result += " with message: "+message;
		}
		if(val > compareTo) {
			result += "!\n"+StringUtil.addSpaceIndent(val+" > "+compareTo+" and even "+val+" - "+maxDiff+" > "+compareTo, 2);
		} else {
			result += "!\n"+StringUtil.addSpaceIndent(val+" < "+compareTo+" and even "+val+" + "+maxDiff+" < "+compareTo, 2);
		}
		return result;
	}
	
	
	/**
	 * Implementation of @see AbstractAssertInfo#getSuccessMessage
	 * 
	 * @return Message on success
	 */
	private function getSuccessMessage(Void):String {
		return ("assertAlmostEquals executed. \n"+StringUtil.addSpaceIndent(val+" ~(+/-"+maxDiff+") "+compareTo, 2));
	}
}