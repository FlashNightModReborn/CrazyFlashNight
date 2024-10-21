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
import org.as2lib.data.holder.array.ArrayIterator;
import org.as2lib.data.holder.array.TypedArray;
import org.as2lib.data.holder.Iterator;
import org.as2lib.test.unit.TestResult;
import org.as2lib.test.unit.TestCase;
import org.as2lib.test.unit.TestCaseMethodInfo;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.util.StringUtil;
import org.as2lib.data.type.Time;

/**
 * {@code TestCaseResult} contains all informations about the execution of a {@code TestCase}.
 * 
 * <p>{@link TestCaseRunner} contains all states of execution of the {@code TestCase}
 * and {@code TestCaseResult} contains all informations about the execution.
 * 
 * @author Martin Heidegger.
 * @version 1.0
 * @see TestCase
 * @see TestCaseRunner
 */
class org.as2lib.test.unit.TestCaseResult extends BasicClass implements TestResult {
	
	/** Reference to the related testcase. */
	private var testCase:TestCase;
	
	/** All methods contained in the Testcase. */
	private var testCaseMethodInfos:TypedArray;
	
	/** Flag if the TestCase has been finished. */
	private var finished:Boolean;
	
	/** Flag if the TestCase has been started. */
	private var started:Boolean;
	
	/**
	 * Constructs a new {@code TestCaseResult}.
	 * 
	 * @param testCase {@coce TestCase} related to the informations
	 */
	public function TestCaseResult(testCase:TestCase) {
		this.testCase = testCase;
		this.started = false;
		this.finished = false;
	}
	
	/**
	 * Returns all informations in a list about the methods contained within the
	 * {@code TestCase}.
	 *
	 * <p>All methods get wrapped within {@code TestCaseMethodInfo}s. Only methods
	 * that start with "test" are contained within this list.
	 * 
	 * @return list of all methods contained within the related {@code TestCase}
	 */
	public function getMethodInfos(Void):TypedArray {
		// Lacy Initialisation for load balancing. All Methods get evaluated by starting this TestCaseResult
		// But not by starting all Available TestCaseResult, as it wood if this would be directly inside the
		// Constructor.
		if(!testCaseMethodInfos){
			testCaseMethodInfos = fetchTestCaseMethodInfos();
		}
		return testCaseMethodInfos;
	}
	
	/**
	 * Fetches all methods starting with "test" within the {@code TestCase}
	 * 
	 * @return list of all methods contained within the related {@code TestCase}
	 */
	private function fetchTestCaseMethodInfos(Void):TypedArray {
		var result:TypedArray = new TypedArray(TestCaseMethodInfo);
		var methods:Array = ClassInfo.forInstance(testCase).getMethods();
		if(methods) {
			for (var i:Number = methods.length-1; i >= 0; i--) {
				var method:MethodInfo = methods[i];
				if (StringUtil.startsWith(method.getName(), 'test')) {
					result.push(new TestCaseMethodInfo(method));
				}
			}
		}
		return result;
	}
	
	/**
	 * Returns the related {@code TestCase}.
	 * 
	 * @return instance of the related {@code TestCase}
	 */
	public function getTestCase(Void):TestCase {
		return testCase;
	}
	
	/**
	 * Returns the class name of the related {@code TestCase}.
	 * 
	 * @return class name of the related TestCase.
	 */
	public function getName(Void):String {
		return ClassInfo.forInstance(getTestCase()).getFullName();
	}
	
	/**
	 * Implementation of @see TestResult#getTestResults.
	 * 
	 * @return This TestCaseResult in a new list for Results.
	 */
	public function getTestResults(Void):TypedArray {
		var result:TypedArray = new TypedArray(TestResult);
		result.push(this);
		return result;
	}
	
	/**
	 * Returns all result to the TestCase results.
	 * Implementation of @see TestResult#getTestCaseResults.
	 * 
	 * @return The Testcase in a list of TestCaseResults.
	 */
	public function getTestCaseResults(Void):TypedArray {
		var result:TypedArray = new TypedArray(TestCaseResult);
		result.push(this);
		return result;
	}
	
	/**
	 * Returns the percentage ({@code 0}-{@code 100}) of the executed methods.
	 * 
	 * @return percentage of execution
	 */
	public function getPercentage(Void):Number {
		var finished:Number = 0;
		
		var a:Array = getMethodInfos();
		var total:Number = a.length;
		var i:Number = a.length;
		
		while(--i-(-1)) {
			if(a[i].hasFinished()) {
				finished ++;
			}
		}
		
		return (100/total*finished);
	}
	
	/**
	 * Returns {@code true} if the {@code TestCase} has been finished.
	 * 
	 * @return {@code true} if the {@code TestCase} has been finished
	 */
	public function hasFinished(Void):Boolean {
		if (finished) return true; // Caching of a true result as performance enhancement.
		var methodIterator:Iterator = new ArrayIterator(getMethodInfos());
		while (methodIterator.hasNext()) {
			if(!methodIterator.next().hasFinished()) {
				return false;
			}
		}
		return (finished=true);
	}
	
	/**
	 * Returns {@code true} if the {@code TestCase} has been started.
	 * 
	 * @return {@code true} if the {@code TestCase} has been started
	 */
	public function hasStarted(Void):Boolean {
		if (started) return true; // Caching of a true result as performance enhancement.
		var methodIterator:Iterator = new ArrayIterator(getMethodInfos());
		while (methodIterator.hasNext()) {
			if (methodIterator.next().hasFinished()) {
				return (started=true);
			}
		}
		return false;
	}
	
	/**
	 * Returns the total operation time for all methods executed for the {@code TestCase}.
	 * 
	 * @return total operation time of the {@code TestCase}
	 */
	public function getOperationTime(Void):Time {
		var result:Number = 0;
		var methodIterator:Iterator = new ArrayIterator(getMethodInfos());
		while (methodIterator.hasNext()) {
			result += methodIterator.next().getStopWatch().getTimeInMilliSeconds();
		}
		return (new Time(result));
	}
	
	/**
	 * Returns {@code true} if the errors occured during the execution of {@code TestCase}.
	 * 
	 * @return {@code true} if the errors occured during the execution of {@code TestCase}.
	 */
	public function hasErrors(Void):Boolean {
		var methodIterator:Iterator = new ArrayIterator(getMethodInfos());
		while (methodIterator.hasNext()) {
			if (methodIterator.next().hasErrors()) {
				return true;
			}
		}
		return false;
	}
	
	/**
	 * Extended .toString implementation.
	 * 
	 * @return {@code TestCaseResult} as well formated {@code String}
	 */
	public function toString():String {
		var result:String;
		var methodResult:String = "";
		var ms:Number = 0;
		var errors:Number = 0;
		var methodInfos:Array = getMethodInfos();
		var iter:Iterator = new ArrayIterator(methodInfos);
		while (iter.hasNext()) {
			var method:TestCaseMethodInfo = iter.next();
			ms += method.getStopWatch().getTimeInMilliSeconds();
			if(method.hasErrors()) {
				errors += method.getErrors().length;
				methodResult += "\n"+StringUtil.addSpaceIndent(method.toString(), 3);
			}
		}
		
		result = getName()+" run "+methodInfos.length+" methods in ["+ms+"ms]. ";
		
		result += (errors>0) ? errors + ((errors > 1) ? " errors" : " error") + " occured" + methodResult : "no error occured";
		
		return result;
	}
}