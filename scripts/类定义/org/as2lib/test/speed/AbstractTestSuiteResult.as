/*
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

import org.as2lib.test.speed.AbstractTestResult;
import org.as2lib.test.speed.TestResult;
import org.as2lib.test.speed.TestSuiteResult;
import org.as2lib.test.speed.MethodInvocation;
import org.as2lib.test.speed.MethodInvocationHolder;

/**
 * {@code AbstractTestSuiteResult} provides implementations of methods needed by
 * implementations of the {@link TestSuiteResult} interface.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.AbstractTestSuiteResult extends AbstractTestResult {
	
	/** Sort by name. */
	public static var NAME:Number = 0;
	
	/** Sort by time. */
	public static var TIME:Number = 1;
	
	/** Sort by average time. */
	public static var AVERAGE_TIME:Number = 2;
	
	/** Sort by time percentage. */
	public static var TIME_PERCENTAGE:Number = 3;
	
	/** Sort by method invocation count. */
	public static var METHOD_INVOCATION_COUNT:Number = 4;
	
	/** Sort by method invocation percentage. */
	public static var METHOD_INVOCATION_PERCENTAGE:Number = 5;
	
	/** Sort by the succession of method invocations. */
	public static var METHOD_INVOCATION_SUCCESSION:Number = 6;
	
	/** Test results of all sub-tests. */
	private var testResults:Array;
	
	/**
	 * Constructs a new {@code AbstractTestSuiteResult} instance.	 */
	private function AbstractTestSuiteResult(Void) {
		this.testResults = new Array();
	}
	
	/**
	 * Returns this instance with correct type. This is needed for proper compile-time
	 * checks.
	 * 
	 * @return this instance with its correct type	 */
	private function getThis(Void):TestSuiteResult {
		return TestSuiteResult(this);
	}
	
	/**
	 * Returns the time needed per method invocation.
	 * 
	 * @return the time needed per method invocation
	 */
	public function getAverageTime(Void):Number {
		return (Math.round((getThis().getTime() / getThis().getMethodInvocationCount()) * 100) / 100);
	}
	
	/**
	 * Returns all profiled method invocations as {@link MethodInvocation} instances.
	 * 
	 * @return all profiled method invocations as {@code MethodInvocation} instances
	 */
	public function getAllMethodInvocations(Void):Array {
		var result:Array = new Array();
		for (var i:Number = 0; i < this.testResults.length; i++) {
			var testResult:TestResult = this.testResults[i];
			if (testResult instanceof MethodInvocation) {
				result.push(testResult);
			} else if (testResult instanceof MethodInvocationHolder) {
				result.push(MethodInvocationHolder(testResult).getMethodInvocation());
			}
			if (testResult instanceof TestSuiteResult) {
				result = result.concat(TestSuiteResult(testResult).getAllMethodInvocations());
			}
		}
		return result;
	}
	
	/**
	 * Returns whether this test suite result has any method invocations.
	 * 
	 * @return {@code true} if this test suite result has method invocations else
	 * {@code false}
	 */
	public function hasMethodInvocations(Void):Boolean {
		return (getThis().getAllMethodInvocations().length > 0);
	}
	
	/**
	 * Returns the total number of method invocations.
	 * 
	 * @return the total number of method invocations
	 */
	public function getMethodInvocationCount(Void):Number {
		return getThis().getAllMethodInvocations().length;
	}
	
	/**
	 * Returns the percentage of method invocations in relation to the passed-in
	 * {@code totalMethodInvocationCount}.
	 * 
	 * @param totalMethodInvocationCount the total number of method invocations to
	 * calculate the percentage with
	 * @return the percentage of method invocations of this result
	 */
	public function getMethodInvocationPercentage(totalMethodInvocationCount:Number):Number {
		return (Math.round((getThis().getMethodInvocationCount() / totalMethodInvocationCount) * 10000) / 100);
	}
	
	/**
	 * Returns all test results as {@link TestResult} instances directly of this test
	 * suite.
	 * 
	 * @return all test results of this test suite
	 */
	public function getTestResults(Void):Array {
		return this.testResults.concat();
	}
	
	/**
	 * Returns whether this test suite result has sub-test results.
	 * 
	 * @return {@code true} if this test suite has sub-test results else {@code false}
	 */
	public function hasTestResults(Void):Boolean {
		return (this.testResults.length > 0);
	}
	
	/**
	 * Returns the number of direct sub-test results.
	 * 
	 * @return the number of direct sub-test results
	 */
	public function getTestResultCount(Void):Number {
		return this.testResults.length;
	}
	
	/**
	 * Adds a new sub-test result.
	 * 
	 * <p>If {@code testResult} is {@code null} or {@code undefined} it wll be
	 * ignored, this means not added.
	 * 
	 * @param testResult the new test result to add
	 */
	public function addTestResult(testResult:TestResult):Void {
		if (testResult) {
			this.testResults.push(testResult);
		}
	}
	
	/**
	 * Sorts this test suite result and its sub-test results.
	 * 
	 * <p>Supported sort properties are:
	 * <ul>
	 *   <li>{@link #NAME}</li>
	 *   <li>{@link #TIME}</li>
	 *   <li>{@link #AVERAGE_TIME}</li>
	 *   <li>{@link #TIME_PERCENTAGE}</li>
	 *   <li>{@link #METHOD_INVOCATION_COUNT}</li>
	 *   <li>{@link #METHOD_INVOCATION_PERCENTAGE}</li>
	 *   <li>{@link #METHOD_INVOCATION_SUCCESSION}</li>
	 * </ul>
	 * 
	 * @param property the property to sort by
	 * @param descending determines whether to sort descending {@code true} or
	 * ascending {@code false}
	 */
	public function sort(property:Number, descending:Boolean):Void {
		if (property == null) return;
		var comparator:Function = getComparator(property);
		if (comparator) {
			if (descending) {
				this.testResults.sort(comparator, Array.DESCENDING);
			} else {
				this.testResults.sort(comparator);
			}
		}
		for (var i:Number = 0; i < this.testResults.length; i++) {
			var testSuiteResult:TestSuiteResult = TestSuiteResult(this.testResults[i]);
			if (testSuiteResult) {
				testSuiteResult.sort(property, descending);
			}
		}
	}
	
	/**
	 * Returns the comparator for the passed-in {@code property}.
	 * 
	 * @param property the property to return the comparator for
	 * @return the comparator for the passed-in {@code property}
	 */
	private function getComparator(property:Number):Function {
		switch (property) {
			case NAME:
				return getNameComparator();
				break;
			case TIME:
				return getTimeComparator();
				break;
			case AVERAGE_TIME:
				return getAverageTimeComparator();
				break;
			case TIME_PERCENTAGE:
				return getTimePercentageComparator();
				break;
			case METHOD_INVOCATION_COUNT:
				return getMethodInvocationCountComparator();
				break;
			case METHOD_INVOCATION_PERCENTAGE:
				return getMethodInvocationPercentageComparator();
				break;
			case METHOD_INVOCATION_SUCCESSION:
				return getMethodInvocationSuccessionComparator();
				break;
			default:
				return null;
				break;
		}
	}
	
	/**
	 * Returns the comparator that compares test results by their names.
	 * 
	 * @return the comparator that compares test results by their names
	 */
	private function getNameComparator(Void):Function {
		// returning function directly is not flex compatible
		// flex compiler would not recognize return statement
		// seems to be a flex compiler bug
		var r:Function = function(a:TestResult, b:TestResult):Number {
			var m:String = a.getName();
			var n:String = b.getName();
			if (m == n) return 0;
			if (m > n) return 1;
			return -1;
		};
		return r;
	}
	
	/**
	 * Returns the comparator that compares the results by their needed time.
	 * 
	 * @return the comparator that compares the results by their needed time
	 */
	private function getTimeComparator(Void):Function {
		// returning function directly is not flex compatible
		// flex compiler would not recognize return statement
		// seems to be a flex compiler bug
		var r:Function = function(a:TestResult, b:TestResult):Number {
			var m:Number = a.getTime();
			var n:Number = b.getTime();
			if (m == n) return 0;
			if (m > n) return 1;
			return -1;
		};
		return r;
	}
	
	/**
	 * Returns the comparator that compares the results by their average time.
	 * 
	 * @return the comparator that compares the results by their average time
	 */
	private function getAverageTimeComparator(Void):Function {
		// returning function directly is not flex compatible
		// flex compiler would not recognize return statement
		// seems to be a flex compiler bug
		var r:Function = function(a:TestResult, b:TestResult):Number {
			if (a instanceof TestSuiteResult
					&& b instanceof TestSuiteResult) {
				var m:Number = TestSuiteResult(a).getAverageTime();
				var n:Number = TestSuiteResult(b).getAverageTime();
				if (m == n) return 0;
				if (m > n) return 1;
				return -1;
			}
			var m:Number = a.getTime();
			var n:Number = b.getTime();
			if (m == n) return 0;
			if (m > n) return 1;
			return -1;
		};
		return r;
	}
	
	/**
	 * Returns the comparator that compares the results by their needed time in
	 * percentage.
	 * 
	 * @return the comparator that compares the results by their needed time in
	 * percentage.
	 */
	private function getTimePercentageComparator(Void):Function {
		var scope:TestResult = getThis();
		// returning function directly is not flex compatible
		// flex compiler would not recognize return statement
		// seems to be a flex compiler bug
		var r:Function = function(a:TestResult, b:TestResult):Number {
			var m:Number = a.getTimePercentage(scope.getTime());
			var n:Number = b.getTimePercentage(scope.getTime());
			if (m == n) return 0;
			if (m > n) return 1;
			return -1;
		};
		return r;
	}
	
	/**
	 * Returns the comparator that compares the results by their invocation count.
	 * 
	 * @return the comparator that compares the results by their invocation count
	 */
	private function getMethodInvocationCountComparator(Void):Function {
		// returning function directly is not flex compatible
		// flex compiler would not recognize return statement
		// seems to be a flex compiler bug
		var r:Function = function(a:TestResult, b:TestResult):Number {
			if (a instanceof TestSuiteResult
					&& b instanceof TestSuiteResult) {
				var m:Number = TestSuiteResult(a).getMethodInvocationCount();
				var n:Number = TestSuiteResult(b).getMethodInvocationCount();
				if (m == n) return 0;
				if (m > n) return 1;
				return -1;
			}
			return 0;
		};
		return r;
	}
	
	/**
	 * Returns the comparator that compares the results by their method invocation
	 * count in percentage.
	 * 
	 * @return the comparator that compares the results by their method invocation
	 * count in percentage
	 */
	private function getMethodInvocationPercentageComparator(Void):Function {
		var scope:TestSuiteResult = getThis();
		// returning function directly is not flex compatible
		// flex compiler would not recognize return statement
		// seems to be a flex compiler bug
		var r:Function = function(a:TestResult, b:TestResult):Number {
			if (a instanceof TestSuiteResult
					&& b instanceof TestSuiteResult) {
				var m:Number = TestSuiteResult(a).getMethodInvocationPercentage(scope.getMethodInvocationCount());
				var n:Number = TestSuiteResult(b).getMethodInvocationPercentage(scope.getMethodInvocationCount());
				if (m == n) return 0;
				if (m > n) return 1;
				return -1;
			}
			return 0;
		};
		return r;
	}
	
	/**
	 * Returns the method invocation succession comparator.
	 * 
	 * @return the method invocation succession comparator
	 */
	private function getMethodInvocationSuccessionComparator(Void):Function {
		// returning function directly is not flex compatible
		// flex compiler would not recognize return statement
		// seems to be a flex compiler bug
		var r:Function = function(a:TestResult, b:TestResult):Number {
			var m:MethodInvocation;
			var n:MethodInvocation;
			if (a instanceof MethodInvocation) m = MethodInvocation(a);
			else if (a instanceof MethodInvocationHolder) m = MethodInvocationHolder(a).getMethodInvocation();
			if (b instanceof MethodInvocation) n = MethodInvocation(b);
			else if (b instanceof MethodInvocationHolder) n = MethodInvocationHolder(b).getMethodInvocation();
			if (a && b) {
				if (m.isPreviousMethodInvocation(n)) return -1;
				if (n.isPreviousMethodInvocation(m)) return 1;
			}
			return 0;
		};
		return r;
	}
	
}