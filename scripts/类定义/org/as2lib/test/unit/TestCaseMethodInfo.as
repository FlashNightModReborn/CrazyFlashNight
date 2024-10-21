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
import org.as2lib.data.holder.array.TypedArray;
import org.as2lib.data.holder.Iterator;
import org.as2lib.data.holder.array.ArrayIterator;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.util.StopWatch;
import org.as2lib.util.StringUtil;
import org.as2lib.test.unit.ExecutionInfo;

/**
 * Informationholder for all Informations related to the execution of a Method within a Testcase.
 * 
 * @author Martin Heidegger
 */
class org.as2lib.test.unit.TestCaseMethodInfo extends BasicClass {
	
	/** Internal Holder for the Reflections Information about the method. */
	private var methodInfo:MethodInfo;
	
	/** Holder for the Stopwatch that contains the execution time. */
	private var stopWatch:StopWatch;
	
	/** All collected Informations for the execution. */
	private var infos:TypedArray;
	
	/** Information if the method was executed by @see #executeTo */
	private var executed:Boolean = false;
	
	/**	
	 * Constructs a new Informations for a TestCase method.
	 * 
	 * @param methodInfo Reflection based information of the method.
	 */
	public function TestCaseMethodInfo(methodInfo:MethodInfo) {
		this.methodInfo = methodInfo;
		
		stopWatch = new StopWatch();
		infos = new TypedArray(ExecutionInfo);
	}
	
	/**
	 * Getter for the Stopwatch that is held by this class.
	 * 
	 * @return StopWatch related to this class.
	 */
	public function getStopWatch(Void):StopWatch {
		return stopWatch;
	}
	
	/**
	 * Information if the method contains errors.
	 * 
	 * @return true if the method contains errors.
	 */
	public function hasErrors(Void):Boolean {
		var i:Number = infos.length;
		while (--i-(-1)) {
			if(infos[i].isFailed()) {
				return true;
			}
		}
		return false;
	}
	
	/**
	 * Getter for the available operation time.
	 * 
	 * @return Operation time in milliseconds.
	 */
	public function getOperationTime(Void):Number {
		return getStopWatch().getTimeInMilliSeconds();
	}
	
	/**
	 * Getter for the Reflection based method information.
	 * 
	 * @return Original MethodInfo to the executed method.
	 */
	public function getMethodInfo(Void):MethodInfo {
		return this.methodInfo;
	}
	
	/**
	 * Adds a Information about the execution of the method.
	 * 
	 * @param info Information that should be added.
	 */
	public function addInfo(info:ExecutionInfo):Void {
		infos.push(info);
	}
	
	/**
	 * Getter for all infos occured during the execution.
	 * Returns a copy of all infos!
	 * 
	 * @return List of all infos occured during execution.
	 */
	public function getInfos(Void):TypedArray {
		return infos.concat();
	}
	
	/**
	 * Getter for all errors occured during the execution.
	 * 
	 * @return List of all errors occured during execution of the method.
	 */
	public function getErrors(Void):TypedArray {
		var result:TypedArray = new TypedArray(ExecutionInfo);
		var i:Number = 0;
		var l:Number = infos.length;
		while (i<l) {
			if(infos[i].isFailed()) {
				result.push(infos[i]);
			}
			i-=(-1);
		}
		return result;
	}
	
	/**
	 * @return True if the method was executed by @see #executeTo
	 */
	public function isExecuted(Void):Boolean {
		return executed;
	}

	/**
	 * Sets the current state of execution.
	 * 
	 * @param executed True if the method has been executed, else false.
	 */
	public function setExecuted(executed:Boolean):Void {
		this.executed = executed;
	}
	
	/**
	 * Extended .toString implementation.
	 * 
	 * @return TestCaseMethodInfo as well formated String.
	 */
	public function toString():String {
		var result:String = getMethodInfo().getName()+"() ["+getStopWatch().getTimeInMilliSeconds()+"ms]";
		var errors:Array = getErrors();
		if(errors.length > 1) {
			result += " "+errors.length+" errors occured";
		} else if(errors.length > 0) {
			result += " 1 error occured";
			
		}
		var errorIterator:Iterator = new ArrayIterator(errors);
		while(errorIterator.hasNext()) {
			var error = errorIterator.next();
			result += "\n"+StringUtil.addSpaceIndent(error.getMessage(), 2);
		}
		if(hasErrors()) {
			result += "\n";
		}
		return result;
	}
	
	/**
	 * Getter for the complete name of the methodinfo
	 * 
	 * @return Complete name as string of the methodinfo.
	 */
	public function getName(Void):String {
		return methodInfo.getFullName();
	}
}