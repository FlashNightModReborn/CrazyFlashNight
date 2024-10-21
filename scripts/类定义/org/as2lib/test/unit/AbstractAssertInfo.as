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
 
import org.as2lib.core.BasicClass;
import org.as2lib.test.unit.ExecutionInfo;
import org.as2lib.env.except.AbstractOperationException;

/**
 * Implementation of @see ExecutionInfo as basis for all AssertInformations.
 * 
 * @autor Martin Heidegger
 */
class org.as2lib.test.unit.AbstractAssertInfo extends BasicClass implements ExecutionInfo {
	
	/** True if the execution has failed. */
	private var failed:Boolean;
	
	/** True if the assertion has been executed. */
	private var executed:Boolean;
	
	/** Message applied to the assertion. */
	private var message:String;
	
	/**
	 * Constructs a new AbstractAssertInfo.
	 * 
	 * @param message Message for the AssertInformation.
	 */
	public function AbstractAssertInfo(message:String) {
		this.message = message;
		executed = false;
		failed = false;
	}
	
	/**
	 * @return true if the assertion failed.
	 */
	public function isFailed(Void):Boolean {
		if(!executed) {
			failed = execute();
			executed = true;
		}
		return failed;
	}
	
	/**
	 * Template method to be overwritten. This will be called by the first
	 * time if isFailed() was executed.
	 * 
	 * Note: The method failes by standard.
	 *
	 * @return true if the execution failed, false if it didn't.
	 */
	private function execute(Void):Boolean {
		return true;
	}
	
	/**
	 * Information getter if a message has been applied to the information.
	 * 
	 * Only for internal use. It applies in all/most extended classes.
	 * 
	 * @return true if a message has been applied to the infromation.
	 */
	private function hasMessage(Void):Boolean {
		return(message.length > 0);
	}
	
	
	/**
	 * @return The message if the assertion doesn't fail.
	 */
	private function getFailureMessage(Void):String {
		throw new AbstractOperationException("getFailureMessage() is ment to be extended.", this, arguments);
		return "";
	}
	
	/**
	 * @return The message if the assertion doesn't fail.
	 */
	private function getSuccessMessage(Void):String {
		throw new AbstractOperationException("getSuccessMessage() is ment to be extended.", this, arguments);
		return "";
	}
	
	/**
	 * Returns the message to the assertion.
	 * If this assertion failed it should return the errorinfo, else the successinfo.
	 * 
	 * @return Message to the assertion.
	 */
	public function getMessage(Void):String {
		if(isFailed()) {
			return getFailureMessage();
		} else {
			return getSuccessMessage();
		}
	}
}