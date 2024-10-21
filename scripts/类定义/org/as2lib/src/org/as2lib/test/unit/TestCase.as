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

import org.as2lib.data.holder.Map;
import org.as2lib.data.holder.map.HashMap;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.log.LogSupport;
import org.as2lib.env.overload.Overload;
import org.as2lib.test.unit.info.*;
import org.as2lib.test.unit.ExecutionInfo;
import org.as2lib.test.unit.Test;
import org.as2lib.test.unit.TestRunner;
import org.as2lib.test.unit.TestCaseRunner;
import org.as2lib.app.exec.Call;
import org.as2lib.app.exec.Executable;
import org.as2lib.app.exec.Process;
import org.as2lib.util.ObjectUtil;
import org.as2lib.test.unit.LoggerTestListener;

/**
 * {@code Testcase} is the basic class to extend for unit-tests.
 * 
 * <p>A {@code TestCase} contains the API to write unit-tests.
 * 
 * <p>It is handled as an abstract class this means you have to extend it if you 
 * want to work with the system (similar to the most other unit testing systems).
 * 
 * <p>Example for a simple test:
 * <code>
 *   import org.as2lib.test.unit.TestCase;
 * 
 *   class MyTestCase extends TestCase {}
 * </code>
 * 
 * <p>To execute a {@code TestCase} you just have to call {@code run()}. It logs
 * automatically with {@link LoggerTestListener}.
 * 
 * <p>The test will return detailed informations about the executed method. The
 * method {@code fail} will simply fail the test.
 * 
 * <p>Example for a test that fails:
 * <code>
 *   import org.as2lib.test.unit.TestCase;
 * 
 *   class MyTestCase extends TestCase {
 *     public function testOne(Void):Void {
 *       if (1 == 0) { // example to show that fail can be used everywhere.
 *         fail ("Error occured");
 *       }
 *     }
 *   }
 * </code>
 * 
 * <p>Within the "test"-methods you have access to different assert methods. Those
 * methods fail if a certain condition is given or not and add a information for
 * the failure to the informations about the execution.
 * 
 * <p>Example for a assertion:
 * <code>
 *   import org.as2lib.test.unit.TestCase;
 * 
 *   class MyTestCase extends TestCase {
 *     public function testOne(Void):Void {
 *       assertEquals("1 is not 0", 1, 0);
 *     }
 *   }
 * </code>
 * 
 * <p>Supported assert methods are:
 * <table>
 *   <thead>
 *     <tr>
 *       <th>method name</th>
 *       <th>condition</th>
 *     </tr>
 *   </thead>
 *   <tbody>
 *     <tr>
 *       <th>assertTrue</th>
 *       <td><i>value</i> === true</td>
 *     </tr>
 *     <tr>
 *       <th>assertFalse</th>
 *       <td><i>value</i> === false</td>
 *     </tr>
 *     <tr>
 *       <th>assertEquals</th>
 *       <td>ObjectUtil.compare(<i>a</i>,<i>b</i>);</td>
 *     </tr>
 *     <tr>
 *       <th>assertAlmostEquals</th>
 *       <td>(<i>a</i> < <i>b</i> && <i>a</i>+x > <i>b</i>) ||
 *       	 (<i>a</i> > <i>b</i> && <i>a</i>-x < <i>b</i>)</td>
 *     </tr>
 *     <tr>
 *       <th>assertNotEquals</th>
 *       <td>!ObjectUtil.compare(<i>a</i>,<i>b</i>);</td>
 *     </tr>
 *     <tr>
 *       <th>assertSame</th>
 *       <td><i>a</i> === <i>b</i></td>
 *     </tr>
 *     <tr>
 *       <th>assertNotSame</th>
 *       <td><i>a</i> !== <i>b</i></td>
 *     </tr>
 *     <tr>
 *       <th>assertNull</th>
 *       <td><i>value</i> === null</td>
 *     </tr>
 *     <tr>
 *       <th>assertNotNull</th>
 *       <td><i>value</i> !== null</td>
 *     </tr>
 *     <tr>
 *       <th>assertUndefined</th>
 *       <td><i>value</i> === undefined</td>
 *     </tr>
 *     <tr>
 *       <th>assertNotUndefined</th>
 *       <td><i>value</i> !== undefined</td>
 *     </tr>
 *     <tr>
 *       <th>assertEmpty</th>
 *       <td><i>value</i> == null (equals == undefined)</td>
 *     </tr>
 *     <tr>
 *       <th>assertNotEmpty</th>
 *       <td><i>value</i> != null (equals != undefined)</td>
 *     </tr>
 *     <tr>
 *       <th>assertInfinity</th>
 *       <td><i>value</i> === Infinity</td>
 *     </tr>
 *     <tr>
 *       <th>assertNotInfinity</th>
 *       <td><i>value</i> !== Infinity</td>
 *     </tr>
 *     <tr>
 *       <th>assertThrows</th>
 *       <td><i>call</i>(<i>arguments</i>) throws <i>exception</i></td>
 *     </tr>
 *     <tr>
 *       <th>assertNotThrows</th>
 *       <td><i>call</i>(<i>arguments</i>) doesnt throw <i>exception</i></td>
 *     </tr>
 *     <tr>
 *       <th>assertTypeOf</th>
 *       <td><i>value</i> typeof <i>type</i></td>
 *     </tr>
 *     <tr>
 *       <th>assertInstanceOf</th>
 *       <td><i>value</i> instanceof <i>type</i></td>
 *     </tr>
 *   </tbody>
 * </table>
 * 
 * <p>The system will fetch all methods with a name that starts with "test" and
 * execute them in a new, isolated instance of the {@code TestCase} to prevent
 * tests inteferences.
 * 
 * <p>Example for a test with instance properties:
 * <code>
 *   import org.as2lib.test.unit.TestCase;
 * 
 *   class MyTestCase extends TestCase {
 *     private var a:String;
 * 
 *     private function testOne(Void):Void {
 *       trace(a); // undefined
 *       a = "1";
 *       trace(a); // 1
 *     }
 *   
 *     private function testTwo(Void):Void {
 *       trace(a); // undefined
 *       a = "1";
 *       trace(a); // 1
 *     }
 *   }
 * </code>
 * 
 * <p>The method {@link #setUp} allows preparing the new instance.
 * The method {@link #tearDown} allows to clear those preparations.
 *
 * <p>Example with {@code setUp} and {@code tearDown}:
 * <code>
 *   import org.as2lib.test.unit.TestCase;
 * 
 *   class MyTestCase extends TestCase {
 * 
 *     private static var content:String="1";
 *   
 *     private static function setContent(newContent:String):Void {
 *       content = newContent;
 *     }
 *     
 *     private static function getContent(Void):String {
 *       return content;
 *     }
 *     
 *     private var cache:String;
 * 
 *     private function setUp() {
 *       cache = getContent();
 *     }
 *   
 *     private function testOne() {
 *       trace(getContent()); // 1
 *       setContent("2");
 *       trace(getContent()); // 2
 *     }
 *   
 *     private function testTwo() {
 *       trace(getContent()); // 1
 *       setContent("3");
 *       trace(getContent()); // 3
 *     }
 *   
 *     private function tearDown() {
 *       setContent(cache);
 *     }
 *   }
 * </code>
 *
 * @author Martin Heidegger
 * @version 2.0
 * @see org.as2lib.test.unit.TestSuite
 * @see org.as2lib.test.unit.Test
 * @see org.as2lib.test.unit.TestRunner
 */

class org.as2lib.test.unit.TestCase extends LogSupport implements Test {
	
	/* Defaut maximal difference used in {@code assertAlmostEquals}. */
	public static var DEFAULT_MAX_DIFF:Number = 1e-10;
	
	/** All {@code TestRunner}s mapped to classes. */
	private static var testRunners:Map = new HashMap();
	
	/** 
	 * Blocks the collection of 
	 * {@code org.as2lib.test.unit.TestSuiteFactory#collectAllTestCases}.
	 * 
	 * @return {@code true} to block the collection
	 */
	public static function blockCollecting(Void):Boolean {
		return true;
	}
	
	/**
	 * Returns the {@code TestRunner} that applies to this {@code TestCase} instance.
	 * 
	 * <p>Its required to execute methods of a Test that this runs in a clean
	 * instance that should not contain any state. To keep one {@code TestRunner}
	 * per class it is necessary to save {@code TestRunner} in a {@code HashMap}
	 * that stores the correct {@code TestCaseRunner} to the {@code TestCase}.
	 *  
	 * @param instance instance to fetch the correct {@code TestCaseRunner}
	 * @return {@code TestRunner} that applies to this {@code TestCase} instance
	 */
	private static function getClassTestRunner(instance:TestCase):TestCaseRunner {
		var clazz = instance["__proto__"];
		var p:TestCaseRunner = testRunners.get(clazz);
		if (!p) {
			p = new TestCaseRunner(instance);
			testRunners.put(clazz, p);
		}
		return p;
	}
	
	/* Executor for this testcase. */
	private var testRunner:TestCaseRunner;
		
	/**
	 * Abstract constructor.
	 */
	private function TestCase(Void) {}
	
	/**
	 * Template method to set up the testcase before running a method.
	 * 
	 * <p>This method will get called before executing each method in a clean,
	 * new instance.
	 */
	public function setUp(Void):Void {}
	
	/**
	 * Template method to tear down the testcase after running a method.
	 * 
	 * <p>This method will get called after the execution of each method of this
	 * testcase.
	 */
	public function tearDown(Void):Void {}
	
	/**
	 * Runs this testcase.
	 * 
	 * <p>Runs all methods of this testcase in an new container and logs all its
	 * events.
	 * 
	 * @see Test#run
	 * @return {@code TestRunner} to the {@code TestCase}
	 */
	public function run(Void):TestRunner {
		var testRunner:TestRunner = getTestRunner();
		testRunner.addListener(LoggerTestListener.getInstance());
		testRunner.start();
		return testRunner;
	}
	
	/**
	 * Returns the {@code TestRunner} that executes this {@code TestCase}.
	 * 
	 * @return {@code TestRunner} that executes this {@code TestCase}
	 */
	public function getTestRunner(Void):TestRunner {
		if (!testRunner) {
			testRunner = getClassTestRunner(this);
		}
		return testRunner;
	}
	
	/**
	 * Pauses the execution of this testcase.
	 * 
	 * <p>This method has been introduces to pause the execution of this method.
	 * The run will not be completed if {@code resume} will not be called!
	 */
	private function pause(Void):Void {
		testRunner.pause();
	}
	
	/**
	 * Resumes the run of this method.
	 * 
	 * <p>This method resumes the exeuction of a {@code TestCase} that has been
	 * paused with {@code pause}.
	 */
	private function resume(Void):Void {
		testRunner.resume();
	}
	
	/**
	 * Method to start a subprocess for this process.
	 * 
	 * @param process process to start
	 * @param args arguments to be used for the process
	 * @param callBack call to be executed if the execution finishes	 */
	private function startProcess(process:Process, args:Array, callBack:Executable):Void {
		testRunner.startSubProcess(process, args, callBack);
	}
	
	/**
	 * Adds a execution info to the process.
	 * 
	 * @param info info to be added
	 * @return {@code false} if the info is a error, else {@code true}
	 */
	private function addInfo(info:ExecutionInfo):Boolean {
		testRunner.addInfo(info);
		return !info.isFailed();
	}
	
	/**
	 * Simply fails the current Testcase.
	 * 
	 * @param message message to the failing of the method
	 */
	private function fail(message:String):Void {
		message = (typeof message == "string") ? message : "<no message applied>";
		addInfo(new FailureInfo(message));
	}
	
	/**
	 * @overload #assertTrueWithMessage
	 * @overload #assertTrueWithoutMessage
	 */
	private function assertTrue():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertTrueWithMessage);
		overload.addHandler([Object], assertTrueWithoutMessage);
		overload.addHandler([], assertTrueWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is {@code true}.
	 * 
	 * @param val boolean that should be {@code true}.
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertFalse
	 * @see #assertTrue
	 * @see #assertTrueWithMessage
	 */
	private function assertTrueWithoutMessage(val:Boolean):Boolean {
		return assertTrueWithMessage("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is {@code true} or fails with the
	 * passed-in {@code message}.
	 * 
	 * <p>This methods asserts the same like {@code assertTrueWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val boolean that should be {@code true}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertFalse
	 * @see #assertTrue
	 * @see #assertTrueWithoutMessage
	 */
	private function assertTrueWithMessage(message:String, val:Boolean):Boolean {
		return addInfo(new AssertTrueInfo(message, val));
	}
	
	/**
	 * @overload #assertFalseWithMessage
	 * @overload #assertFalseWithoutMessage
	 */
	private function assertFalse():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertFalseWithMessage);
		overload.addHandler([Object], assertFalseWithoutMessage);
		overload.addHandler([], assertFalseWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is {@code false} else it fails.
	 * 
	 * @param val boolean that should be {@code false}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertTrue
	 * @see #assertFalse
	 * @see #assertFalseWithMessage
	 */
	private function assertFalseWithoutMessage(val:Boolean):Boolean {
		return assertFalseWithMessage("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is {@code false} or fails with the
	 * passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertFalseWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val boolean that should be {@code false} 
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertTrue
	 * @see #assertFalse
	 * @see #assertFalseWithoutMessage
	 */
	private function assertFalseWithMessage(message:String, val:Boolean):Boolean {
		return addInfo(new AssertFalseInfo(message, val));
	}
	
	/**
	 * @overload #assertEqualsWithMessage
	 * @overload #assertEqualsWithoutMessage
	 */
	private function assertEquals():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object, Object], assertEqualsWithMessage);
		overload.addHandler([String, Object], assertEqualsWithMessage);
		overload.addHandler([Object, Object], assertEqualsWithoutMessage);
		overload.addHandler([String, String], assertEqualsWithoutMessage);
		overload.addHandler([Object], assertEqualsWithoutMessage);
		overload.addHandler([], assertEqualsWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the two passed-in parameters are equal.
	 * 
	 * <p>This method compares two variables by {@link org.as2lib.util.ObjectUtil#compare}.
	 * 
	 * <p>In contrast to {@code assertSame} that compares by "===" if both
	 * are exactly the same this method compares the value of the two
	 * parameters.
	 * 
	 * @param val parameter that should be compared
	 * @param compareTo parameter to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertSame
	 * @see #assertNotEquals
	 * @see #assertEquals
	 * @see #assertEqualsWithMessage
	 */
	private function assertEqualsWithoutMessage(val, compareTo):Boolean {
		return assertEqualsWithMessage("", val, compareTo);
	}
	
	/**
	 * Asserts if the two passed-in parameters are equal or fails with the passed-in
	 * {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertEqualsWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should be compared
	 * @param compareTo parameter to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertSame
	 * @see #assertNotEquals
	 * @see #assertEquals
	 * @see #assertEqualsWithoutMessage
	 */
	private function assertEqualsWithMessage(message:String, val, compareTo):Boolean {
		return addInfo(new AssertEqualsInfo(message, val, compareTo));
	}
	
	/**
	 * @overload #assertAlmostEqualsWithMessageWithMaxDiff
	 * @overload #assertAlmostEqualsWithoutMessageWithMaxDiff
	 * @overload #assertAlmostEqualsWithMessageWithoutMaxDiff
	 * @overload #assertAlmostEqualsWithoutMessageWithoutMaxDiff
	 */
	private function assertAlmostEquals():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler(
			[String, Number, Number, Number],
			assertAlmostEqualsWithMessageWithMaxDiff);
		overload.addHandler(
			[String, Number, Number],
			assertAlmostEqualsWithMessageWithoutMaxDiff);
		overload.addHandler(
			[Number, Number, Number],
			assertAlmostEqualsWithoutMessageWithMaxDiff);
		overload.addHandler(
			[Number, Number],
			assertAlmostEqualsWithoutMessageWithoutMaxDiff);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the two passed-in numbers are the almost the same.
	 * 
	 * <p>This method compares two numbers by using the unsharpening buffer
	 * {@link #DEFAULT_MAX_DIFF}.
	 * 
	 * @param val {@code number} to be compared
	 * @param compareTo {@code number} to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertSame
	 * @see #assertEquals
	 * @see #assertAlmostEquals
	 */
	private function assertAlmostEqualsWithoutMessageWithoutMaxDiff(val:Number,
			compareTo:Number):Boolean {
		return assertAlmostEqualsWithMessageWithMaxDiff("", val, compareTo,
			DEFAULT_MAX_DIFF);
	}
	
	/**
	 * Asserts if the two passed-in numbers are the almost the same or fails
	 * with the passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like
	 * {@code assertAlmostEqualsWithoutMessageWithoutMaxDiff} but it adds a message
	 * to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val {@code number} to be compared
	 * @param compareTo {@code number} to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertSame
	 * @see #assertEquals
	 * @see #assertAlmostEquals
	 */
	private function assertAlmostEqualsWithMessageWithoutMaxDiff(message:String,
			val:Number, compareTo:Number):Boolean {
		return assertAlmostEqualsWithMessageWithMaxDiff(message, val, compareTo,
			DEFAULT_MAX_DIFF);
	}
	
	/**
	 * Asserts if the two passed-in numbers are the almost the same.
     *
	 * <p>This method compares two numbers by using the passed-in unsharpening buffer
	 * {@code maxDiff}.
	 * 
	 * @param val {@code number} to be compared
	 * @param compareTo {@code number} to compare with {@code val}
	 * @param maxDiff maximum difference between the passed-in numbers
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertSame
	 * @see #assertEquals
	 * @see #assertAlmostEquals
	 */
	private function assertAlmostEqualsWithoutMessageWithMaxDiff(val:Number,
			compareTo:Number, maxDiff:Number):Boolean {
		return assertAlmostEqualsWithMessageWithMaxDiff("", val, compareTo, maxDiff);
	}
	
	/**
	 * Asserts if the two passed-in numbers are the almost the same or fails
	 * with the passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertAlmostEqualsWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val number1 to be compared.
	 * @param compareTo number2 to compare with val.
	 * @param maxDiff max. difference between those two numbers.
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertSame
	 * @see #assertEquals
	 * @see #assertAlmostEquals
	 */
	private function assertAlmostEqualsWithMessageWithMaxDiff(message:String,
			val:Number, compareTo:Number, maxDiff:Number):Boolean {
		return addInfo(new AssertAlmostEqualsInfo(message, val, compareTo, maxDiff));
	}
	
	/**
	 * @overload #assertNotEqualsWithMessage
	 * @overload #assertNotEqualsWithoutMessage
	 */
	private function assertNotEquals():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object, Object], assertNotEqualsWithMessage);
		overload.addHandler([String, Object], assertNotEqualsWithMessage);
		overload.addHandler([Object, Object], assertNotEqualsWithoutMessage);
		overload.addHandler([String, String], assertNotEqualsWithoutMessage);
		overload.addHandler([Object], assertNotEqualsWithoutMessage);
		overload.addHandler([], assertNotEqualsWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the two passed-in parameters are not equal.
	 * 
	 * <p>This method compares two variables by {@link org.as2lib.util.ObjectUtil#compare}
	 * and fails if it returns {@code true}.
	 * 
	 * <p>In contrast to {@code assertNotSame} that compares by "!==" if both
	 * are exactly the same this method compares the value of the two
	 * parameters.
	 * 
	 * @param val parameter that should be compared
	 * @param compareTo parameter to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotSame
	 * @see #assertEquals
	 * @see #assertNotEquals
	 * @see #assertNotEqualsWithMessage
	 */
	private function assertNotEqualsWithoutMessage(val, compareTo):Boolean {
		return assertNotEqualsWithMessage("", val, compareTo);
	}
	
	/**
	 * Asserts if the two passed-in parameters are not equal of fails with the passed-in
	 * {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertNotEqualsWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should be compared
	 * @param compareTo parameter to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotSame
	 * @see #assertEquals
	 * @see #assertNotEquals
	 * @see #assertNotEqualsWithoutMessage
	 */
	private function assertNotEqualsWithMessage(message:String, val, compareTo):Boolean {
		return addInfo(new AssertNotEqualsInfo(message, val, compareTo));
	}
	
	/**
	 * @overload #assertSameWithMessage
	 * @overload #assertSameWithoutMessage
	 */
	private function assertSame():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object, Object], assertSameWithMessage);
		overload.addHandler([String, Object], assertSameWithMessage);
		overload.addHandler([Object, Object], assertSameWithoutMessage);
		overload.addHandler([String, String], assertSameWithoutMessage);
		overload.addHandler([Object], assertSameWithoutMessage);
		overload.addHandler([], assertSameWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the two passed-in parameters are the same.
	 * 
	 * <p>This method compares two variables by "===".
	 * 
	 * <p>In contrast to {@code assertEquals} that compares by {@code ObjectUtil.compare}
	 * the value this method compares if both parameters are exactly the same.
	 * 
	 * @param val parameter that should be compared
	 * @param compareTo parameter to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotSame
	 * @see #assertEquals
	 * @see #assertSame
	 * @see #assertSameWithMessage
	 */
	private function assertSameWithoutMessage(val, compareTo):Boolean {
		return assertSameWithMessage("", val, compareTo);
	}
	
	/**
	 * Asserts if the two passed-in parameters are the same or fails with the passed-in
	 * {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertSameWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should be compared
	 * @param compareTo parameter to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotSame
	 * @see #assertEquals
	 * @see #assertSame
	 * @see #assertSameWithoutMessage
	 */
	private function assertSameWithMessage(message:String, val, compareTo):Boolean {
		return addInfo(new AssertSameInfo(message, val, compareTo));
	}
	
	/**
	 * @overload #assertNotSameWithMessage
	 * @overload #assertNotSameWithoutMessage
	 */
	private function assertNotSame():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object, Object], assertNotSameWithMessage);
		overload.addHandler([String, Object], assertNotSameWithMessage);
		overload.addHandler([Object, Object], assertNotSameWithoutMessage);
		overload.addHandler([String, String], assertNotSameWithoutMessage);
		overload.addHandler([Object], assertNotSameWithoutMessage);
		overload.addHandler([], assertNotSameWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the two passed-in parameters are the not same.
	 * 
	 * <p>This method compares two variables by "!==".
	 * 
	 * <p>In contrast to {@code assertNotEquals} that compares by !{@code ObjectUtil.compare}
	 * the value this method compares if both parameters are not exactly the same.
	 * 
	 * @param val parameter that should be compared
	 * @param compareTo parameter to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertSame
	 * @see #assertNotEquals
	 * @see #assertNotSame
	 * @see #assertNotSameWithMessage
	 */
	private function assertNotSameWithoutMessage(val, compareTo):Boolean {
		return assertNotSameWithMessage("", val, compareTo);
	}
	
	/**
	 * Asserts if the two passed-in parameters are the not same or fails with the
	 * passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertNotSameWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should be compared
	 * @param compareTo parameter to compare with {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertSame
	 * @see #assertNotEquals
	 * @see #assertNotSame
	 * @see #assertNotSameWithoutMessage
	 */
	private function assertNotSameWithMessage(message:String, val, compareTo):Boolean {
		return addInfo(new AssertNotSameInfo(message, val, compareTo));
	}
	
	/**
	 * @overload #assertNullWithMessage
	 * @overload #assertNullWithoutMessage
	 */
	private function assertNull():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertNullWithMessage);
		overload.addHandler([Object], assertNullWithoutMessage);
		overload.addHandler([], assertNullWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is (===) {@code null}.
	 * 
	 * @param val parameter that should be {@code null}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotNull
	 * @see #assertUndefined
	 * @see #assertEmpty
	 * @see #assertNull
	 * @see #assertNullWithMessage
	 */
	private function assertNullWithoutMessage(val):Boolean {
		return assertNullWithMessage("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is (===) {@code null} or fails with
	 * the passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertNullWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should be {@code null}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotNull
	 * @see #assertUndefined
	 * @see #assertEmpty
	 * @see #assertNull
	 * @see #assertNullWithoutMessage
	 */
	private function assertNullWithMessage(message:String, val):Boolean {
		return addInfo(new AssertNullInfo(message, val));
	}
	
	/**
	 * @overload #assertNotNullWithMessage
	 * @overload #assertNotNullWithoutMessage
	 */
	private function assertNotNull():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertNotNullWithMessage);
		overload.addHandler([Object], assertNotNullWithoutMessage);
		overload.addHandler([], assertNotNullWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is not (!==) {@code null}.
	 * 
	 * @param val parameter that should not be {@code null}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNull
	 * @see #assertNotUndefined
	 * @see #assertNotEmpty
	 * @see #assertNotNull
	 * @see #assertNotNullWithMessage
	 */
	private function assertNotNullWithoutMessage(val):Boolean {
		return assertNotNullWithMessage("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is not (!==) {@code null} or fails with
	 * the passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertNotNullWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should not be {@code null}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNull
	 * @see #assertNotUndefined
	 * @see #assertNotEmpty
	 * @see #assertNotNull
	 * @see #assertNotNullWithoutMessage
	 */
	private function assertNotNullWithMessage(message:String, val):Boolean {
		return addInfo(new AssertNotNullInfo(message, val));
	}
	
	/**
	 * @overload #assertUndefinedWithMessage
	 * @overload #assertUndefinedWithoutMessage
	 */
	private function assertUndefined():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertUndefinedWithMessage);
		overload.addHandler([Object], assertUndefinedWithoutMessage);
		overload.addHandler([], assertUndefinedWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is (===) {@code undefined}.
	 * 
	 * @param val parameter that should be {@code undefined}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotUndefined
	 * @see #assertNull
	 * @see #assertEmpty
	 * @see #assertUndefined
	 * @see #assertUndefinedWithMessage
	 */
	private function assertUndefinedWithoutMessage(val):Boolean {
		return assertUndefinedWithMessage("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is (===) {@code undefined} or fails 
	 * with the passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertUndefinedWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should be {@code undefined}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotUndefined
	 * @see #assertNull
	 * @see #assertEmpty
	 * @see #assertUndefined
	 * @see #assertUndefinedWithoutMessage
	 */
	private function assertUndefinedWithMessage(message:String, val):Boolean {
		return addInfo(new AssertUndefinedInfo(message, val));
	}
	
	/**
	 * @overload #assertNotUndefinedWithMessage
	 * @overload #assertNotUndefinedWithoutMessage
	 */
	private function assertNotUndefined():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertNotUndefinedWithMessage);
		overload.addHandler([Object], assertNotUndefinedWithoutMessage);
		overload.addHandler([], assertNotUndefinedWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is not (!==) {@code undefined}.
	 * 
	 * @param val parameter that should not be {@code undefined}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertUndefined
	 * @see #assertNotNull
	 * @see #assertNotEmpty
	 * @see #assertNotUndefined
	 * @see #assertNotUndefinedWithMessage
	 */
	private function assertNotUndefinedWithoutMessage(val):Boolean {
		return assertNotUndefined("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is not (!==) {@code undefined} or fails
	 * with the passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertNotUndefinedWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should not be {@code undefined}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertUndefined
	 * @see #assertNotNull
	 * @see #assertNotEmpty
	 * @see #assertNotUndefined
	 * @see #assertNotUndefinedWithoutMessage
	 */
	private function assertNotUndefinedWithMessage(message:String, val):Boolean {
		return addInfo(new AssertNotUndefinedInfo(message, val));
	}
	
	/**
	 * @overload #assertInfinityWithMessage
	 * @overload #assertInfinityWithoutMessage
	 */
	private function assertInfinity():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertInfinityWithMessage);
		overload.addHandler([Object], assertInfinityWithoutMessage);
		overload.addHandler([], assertInfinityWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is (===) {@code Infinity}.
	 * 
	 * @param val parameter that should be {@code Infinity}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotInfinity
	 * @see #assertInfinity
	 * @see #assertInfinityWithMessage
	 */
	private function assertInfinityWithoutMessage(val):Boolean {
		return assertInfinityWithMessage("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is (===) {@code Infinity} or fails
	 * with the passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertInfinityWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should be {@code Infinity}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotInfinity
	 * @see #assertInfinity
	 * @see #assertInfinityWithoutMessage
	 */
	private function assertInfinityWithMessage(message:String, val):Boolean {
		return addInfo(new AssertInfinityInfo(message, val));
	}
	
	/**
	 * @overload #assertNotInfinityWithMessage
	 * @overload #assertNotInfinityWithoutMessage
	 */
	private function assertNotInfinity():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertNotInfinityWithMessage);
		overload.addHandler([Object], assertNotInfinityWithoutMessage);
		overload.addHandler([], assertNotInfinityWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is not (!==) {@code Infinity}.
	 * 
	 * @param val parameter that should not be {@code Infinity}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertInfinity
	 * @see #assertNotInfinity
	 * @see #assertNotInfinityWithMessage
	 */
	private function assertNotInfinityWithoutMessage(val):Boolean {
		return assertNotInfinityWithMessage("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is not (!==) {@code Infinity} or fails
	 * with the passed-in {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertInfinityWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should not be {@code Infinity}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertInfinity
	 * @see #assertNotInfinity
	 * @see #assertNotInfinityWithoutMessage
	 */
	private function assertNotInfinityWithMessage(message:String, val):Boolean {
		return addInfo(new AssertNotInfinityInfo(message, val));
	}
	
	/**
	 * @overload #assertEmptyWithMessage
	 * @overload #assertEmptyWithoutMessage
	 */
	private function assertEmpty():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertEmptyWithMessage);
		overload.addHandler([Object], assertEmptyWithoutMessage);
		overload.addHandler([], assertEmptyWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is empty.
	 * 
	 * <p>Empty means to be {@code === null} or {@code === undefined}.
	 * 
	 * @param val parameter that should be empty
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNull
	 * @see #assertUndefined
	 * @see #assertNotEmpty
	 * @see #assertEmpty
	 * @see #assertEmptyWithMessage
	 */
	private function assertEmptyWithoutMessage(val):Boolean {
		return assertEmptyWithMessage("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is empty or fails with the passed-in
	 * {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertEmptyWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should be empty
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNull
	 * @see #assertUndefined
	 * @see #assertNotEmpty
	 * @see #assertEmpty
	 * @see #assertEmptyWithoutMessage
	 */
	private function assertEmptyWithMessage(message:String, val):Boolean {
		return addInfo(new AssertEmptyInfo(message, val));
	}
	
	/**
	 * @overload #assertNotEmptyWithMessage
	 * @overload #assertNotEmptyWithoutMessage
	 */
	private function assertNotEmpty():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([String, Object], assertNotEmptyWithMessage);
		overload.addHandler([Object], assertNotEmptyWithoutMessage);
		overload.addHandler([], assertNotEmptyWithoutMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is not empty.
	 * 
	 * <p>Not empty means to be {@code !== null} and {@code !== undefined}.
	 * 
	 * @param val parameter that should not be empty
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotNull
	 * @see #assertNotUndefined
	 * @see #assertEmpty
	 * @see #assertNotEmpty
	 * @see #assertNotEmptyWithMessage
	 */
	private function assertNotEmptyWithoutMessage(val):Boolean {
		return assertNotEmptyWithMessage("", val);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is not empty or fails with the passed-in
	 * {@code message}.
	 * 
	 * <p>This method asserts the same like {@code assertNotEmptyWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter that should not be empty
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotNull
	 * @see #assertNotUndefined
	 * @see #assertEmpty
	 * @see #assertNotEmpty
	 * @see #assertNotEmptyWithoutMessage
	 */
	private function assertNotEmptyWithMessage(message:String, val):Boolean {
		return addInfo(new AssertNotEmptyInfo(message, val));
	}
	
	/**
	 * @overload #assertThrowsWithCall
	 * @overload #assertThrowsWithCallAndType
	 * @overload #assertThrowsWithCallAndMessage
	 * @overload #assertThrowsWithCallAndMessageAndType
	 * @overload #assertThrowsWithString
	 * @overload #assertThrowsWithStringAndType
	 * @overload #assertThrowsWithStringAndMessage
	 * @overload #assertThrowsWithStringAndMessageAndType
	 * @overload #assertThrowsWithFunction
	 * @overload #assertThrowsWithFunctionAndType
	 * @overload #assertThrowsWithFunctionAndMessage
	 * @overload #assertThrowsWithFunctionAndMessageAndType
	 */
	private function assertThrows():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler(
		    [Executable, Array],
			assertThrowsWithCall);
		overload.addHandler(
		    [Object, String, Array],
			assertThrowsWithString);
		overload.addHandler(
		    [Object, Function, Array],
			assertThrowsWithFunction);
		overload.addHandler(
		    [Object, Executable, Array],
			assertThrowsWithCallAndType);
		overload.addHandler(
		    [Object, Object, String, Array],
			assertThrowsWithStringAndType);
		overload.addHandler(
		    [Object, Object, Function, Array],
			assertThrowsWithFunctionAndType);
		overload.addHandler(
		    [String, Executable, Array],
			assertThrowsWithCallAndMessage);
		overload.addHandler(
		    [String, Object, String, Array],
			assertThrowsWithStringAndMessage);
		overload.addHandler(
		    [String, Object, Function, Array],
			assertThrowsWithFunctionAndMessage);
		overload.addHandler(
		    [String, Object, Executable, Array],
			assertThrowsWithCallAndMessageAndType);
		overload.addHandler(
		    [String, Object, Object, String, Array],
			assertThrowsWithStringAndMessageAndType);
		overload.addHandler(
		    [String, Object, Object, Function, Array],
			assertThrowsWithFunctionAndMessageAndType);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the execution of a {@link Executable} throws any exception.
	 * 
	 * <p>This method executes at the passed-in {@code executable} the method
	 * {@code execute} using the passed-in {@code args} and checks if it throws any
	 * exception.
	 * 
	 * <p>The assertion fails if the method did not throw any exception.
	 * 
	 * @param executable {@code Executable} that should be executed
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithCallAndMessage
	 */
	private function assertThrowsWithCall(executable:Executable, args:Array):Boolean {
		return assertThrowsWithCallAndMessage("", executable, args);
	}
	
	/**
	 * Asserts if the execution of a {@link Executable} throws a certain exception.
	 * 
	 * <p>This method executes at the passed-in {@code executable} the method
	 * {@code execute} using the passed-in {@code args} and checks if it throws the
	 * expected exception.
	 * 
	 * <p>The assertion fails if the method did not throw any exception or if it
	 * throw a exception of the wrong type.
	 * 
	 * @param type type of the exception that should be thrown
	 * @param executabe {@code Executable} to be executed
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithCallAndMessageAndType
	 */
	private function assertThrowsWithCallAndType(type, executable:Executable,
			args:Array):Boolean {
		return assertThrowsWithCallAndMessageAndType("", type, executable, args);
	}
	
	/**
	 * Asserts if the execution of the passed-in {@code name} to the passed-in
	 * {@code scope} throws any exception.
	 * 
	 * <p>This method executes within the passed-in {@code scope} the method with
	 * the name of the passed-in {@code name} and checks if it throws any exception.
	 * 
	 * <p>The assertion fails if the method did not throw any exception.
	 * 
	 * @param scope object to be used a scope
	 * @param name name of the method to be executed within the scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithStringAndMessage
	 */
	private function assertThrowsWithString(scope, name:String, args:Array):Boolean {
		return assertThrowsWithStringAndMessage("", scope, name, args);
	}
	
	/**
	 * Asserts if the execution of the passed-in {@code name} to the passed-in
	 * {@code scope} throws any exception.
	 * 
	 * <p>This method executes within the passed-in {@code scope} the method with
	 * the name of the passed-in {@code name} and checks if it throws the
	 * expected exception.
	 * 
	 * <p>The assertion fails if the method did not throw any exception or if it
	 * throw a exception of the wrong type.
	 * 
	 * @param type	type of the exception that should be thrown
	 * @param scope object to be used a scope
	 * @param name name of the method to be executed within the scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithStringAndMessageAndType
	 */
	private function assertThrowsWithStringAndType(type, scope, name:String,
			args:Array):Boolean {
		return assertThrowsWithStringAndMessageAndType("", type, scope, name, args);
	}
	
	/**
	 * Asserts if the passed-in {@code method} throw any exception during its execution
	 * to the passed-in {@code scope}.
	 * 
	 * <p>This method executes within the passed-in {@code scope} the passed-in 
	 * {@code method} using the passed-in {@code args} and checks if it throws
	 * the expected exception.
	 * 
	 * <p>The assertion fails if the method did not throw any exception.
	 * 
	 * @param scope object to be used a scope
	 * @param method method that should be executed with the certain scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithFunctionAndMessage
	 */
	private function assertThrowsWithFunction(scope, method:Function,
			args:Array):Boolean {
		return assertThrowsWithFunctionAndMessage("", scope, method, args);
	}
	
	/**
	 * Asserts if the passed-in {@code method} throw any exception during its execution
	 * to the passed-in {@code scope}.
	 * 
	 * <p>This method executes within the passed-in {@code scope} the passed-in 
	 * {@code method} using the passed-in {@code args} and checks if it throws
	 * any exception.
	 * 
	 * <p>The assertion fails if the method did not throw any exception  or if it
	 * throw a exception of the wrong type.
	 * 
	 * @param type type of the exception that should be thrown
	 * @param scope object to be used a scope
	 * @param method method that should be executed with the certain scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithFunctionAndMessageAndType
	 */
	private function assertThrowsWithFunctionAndType(type, inObject, func:Function,
			args:Array):Boolean {
		return assertThrowsWithFunctionAndMessageAndType("", type, inObject, func, args);
	}
	
	/**
	 * Asserts if the execution of a {@link Executable} throws any exception.
	 * 
	 * <p>This methods asserts the same like {@code assertThrowsWithCall}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param executable {@code Executable} that should be executed
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithCall
	 */
	private function assertThrowsWithCallAndMessage(message:String, executable:Executable,
			args:Array):Boolean {
		return assertThrowsWithCallAndMessageAndType(message, null, executable, args);
	}
	
	/**
	 * Asserts if the execution of a {@link Executable} throws a certain exception.
	 * 
	 * <p>This methods asserts the same like {@code assertThrowsWithCallAndType}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param type type of the exception that should be thrown
	 * @param executable {@code Executable} that should be executed
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithCallAndType
	 */
	private function assertThrowsWithCallAndMessageAndType(message:String, type,
			executable:Executable, args:Array):Boolean {
		return addInfo(new AssertThrowsInfo(message, type, executable, args));
	}
	
	/**
	 * Asserts if the execution of the passed-in {@code name} to the passed-in
	 * {@code scope} throws any exception.
	 * 
	 * <p>This methods asserts the same like {@code assertThrowsWithString}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param scope object to be used a scope
	 * @param name name of the method to be executed within the scope
	 * @param args arguments to be used for the execution
	 * @throws IllegalArgumentException if the method with the passed-in {@code name}
	 *         is not available with the passed-in {@code scope}.
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithString
	 */
	private function assertThrowsWithStringAndMessage(message:String, scope,
			name:String, args:Array):Boolean {
		if(ObjectUtil.isTypeOf(scope[name], "function")) {
			return assertThrowsWithCallAndMessage(message, new Call(scope,
				scope[name]), args);
		} else {
			throw new IllegalArgumentException("The method '"+name+"' is not available"
				+" within "+scope.toString(), this, arguments);
		}
	}
	
	/**
	 * Asserts if the execution of the passed-in {@code name} to the passed-in
	 * {@code scope} throws a certain exception.
	 * 
	 * <p>This methods asserts the same like {@code assertThrowsWithStringAndType}
	 * but it adds a message to the failure.
	 * 
	 * @param type type of the exception that should be thrown
	 * @param message message to be provided if the assertion fails
	 * @param scope object to be used a scope
	 * @param name name of the method to be executed within the scope
	 * @param args arguments to be used for the execution
	 * @throws IllegalArgumentException if the method with the passed-in {@code name}
	 *         is not available with the passed-in {@code scope}.
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithStringAndType
	 */
	private function assertThrowsWithStringAndMessageAndType(message:String, type,
			scope, name:String,args:Array):Boolean {
		if(ObjectUtil.isTypeOf(scope[name], "function")) {
			return assertThrowsWithFunctionAndMessageAndType(message, type,
				scope, scope[name], args);
		} else {
			throw new IllegalArgumentException("The method '"+name+"' is not available"
				+" within "+scope.toString(), this, arguments);
		}
	}
	
	/**
	 * Asserts if the passed-in {@code method} throw any exception during its execution
	 * to the passed-in {@code scope}.
	 * 
	 * <p>This methods asserts the same like {@code assertThrowsWithFunction}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param scope object to be used a scope
	 * @param method method that should be executed with the certain scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithFunction
	 */
	private function assertThrowsWithFunctionAndMessage(message:String, scope,
			method:Function, args:Array):Boolean {
		return assertThrowsWithCallAndMessage(message, new Call(scope, method),
			args);
	}
	
	/**
	 * Asserts if the passed-in {@code method} throw any exception during its execution
	 * to the passed-in {@code scope}.
	 * 
	 * <p>This methods asserts the same like {@code assertThrowsWithFunctionAnyType}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param type type of the exception that should be thrown
	 * @param scope object to be used a scope
	 * @param method method that should be executed with the certain scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithFunctionAndType
	 */
	private function assertThrowsWithFunctionAndMessageAndType(message:String,
			type, scope, method:Function, args:Array):Boolean {
		return assertThrowsWithCallAndMessageAndType(message, type,
			new Call(scope, method), args);
	}
	
	/**
	 * @overload #assertNotThrowsWithCall
	 * @overload #assertNotThrowsWithCallAndType
	 * @overload #assertNotThrowsWithCallAndMessage
	 * @overload #assertNotThrowsWithCallAndMessageAndType
	 * @overload #assertNotThrowsWithString
	 * @overload #assertNotThrowsWithStringAndType
	 * @overload #assertNotThrowsWithStringAndMessage
	 * @overload #assertNotThrowsWithStringAndMessageAndType
	 * @overload #assertNotThrowsWithFunction
	 * @overload #assertNotThrowsWithFunctionAndType
	 * @overload #assertNotThrowsWithFunctionAndMessage
	 * @overload #assertNotThrowsWithFunctionAndMessageAndType
	 */
	private function assertNotThrows():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler(
			[Executable, Array],
			assertNotThrowsWithCall);
		overload.addHandler(
			[Object, String, Array],
			assertNotThrowsWithString);
		overload.addHandler(
			[Object, Function, Array],
			assertNotThrowsWithFunction);
		overload.addHandler(
			[Object, Executable, Array],
			assertNotThrowsWithCallAndType);
		overload.addHandler(
			[Object, Object, String, Array],
			assertNotThrowsWithStringAndType);
		overload.addHandler(
			[Object, Object, Function, Array],
			assertNotThrowsWithFunctionAndType);
		overload.addHandler(
			[String, Executable, Array],
			assertNotThrowsWithCallAndMessage);
		overload.addHandler(
			[String, Object, String, Array],
			assertNotThrowsWithStringAndMessage);
		overload.addHandler(
			[String, Object, Function, Array],
			assertNotThrowsWithFunctionAndMessage);
		overload.addHandler(
			[String, Object, Executable, Array],
			assertNotThrowsWithCallAndMessageAndType);
		overload.addHandler(
			[String, Object, Object, String, Array],
			assertNotThrowsWithStringAndMessageAndType);
		overload.addHandler(
			[String, Object, Object, Function, Array],
			assertNotThrowsWithFunctionAndMessageAndType);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the execution of a {@link Executable} does not throw any exception.
	 * 
	 * <p>This method executes at the passed-in {@code executable} the method
	 * {@code execute} using the passed-in {@code args} and checks if it throws a
	 * exception.
	 * 
	 * <p>The assertion fails if the method throws any exception.
	 * 
	 * @param executable {@code Executable} that should be executed
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotThrowsWithCallAndMessage
	 */
	private function assertNotThrowsWithCall(executable:Executable, args:Array):Boolean {
		return assertNotThrowsWithCallAndMessage("", executable, args);
	}
	
	/**
	 * Asserts if the execution of a {@link Executable} does not throw a certain
	 * exception.
	 * 
	 * <p>This method executes at the passed-in {@code executable} the method
	 * {@code execute} using the passed-in {@code args} and checks if it does not
	 * throw a expected exception.
	 * 
	 * <p>The assertion fails if the method throws a exception of the passed-in
	 * {@code type}.
	 * 
	 * @param type type of the exception that should not be thrown
	 * @param executabe {@code Executable} to be executed
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotThrowsWithCallAndMessageAndType
	 */
	private function assertNotThrowsWithCallAndType(type, executable:Executable,
			args:Array):Boolean {
		return assertNotThrowsWithCallAndMessageAndType("", type, executable, args);
	}
	
	/**
	 * Asserts if the execution of the passed-in {@code name} to the passed-in
	 * {@code scope} does not throw any exception.
	 * 
	 * <p>This method executes within the passed-in {@code scope} the method with
	 * the name of the passed-in {@code name} and checks if it throws any exception.
	 * 
	 * <p>The assertion fails if the method throws any exception.
	 * 
	 * @param scope object to be used a scope
	 * @param name name of the method to be executed within the scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotThrowsWithStringAndMessage
	 */
	private function assertNotThrowsWithString(scope, name:String,
			args:Array):Boolean {
		return assertNotThrowsWithStringAndMessage("", scope, name, args);
	}
	
	/**
	 * Asserts if the execution of the passed-in {@code name} to the passed-in
	 * {@code scope} does not throws a certain exception.
	 * 
	 * <p>This method executes within the passed-in {@code scope} the method with
	 * the name of the passed-in {@code name} and checks if it does not throw the
	 * expected exception.
	 * 
	 * <p>The assertion fails if the method throws a exception of the passed-in
	 * {@code type}.
	 * 
	 * @param type type of the exception that should not be thrown
	 * @param scope object to be used a scope
	 * @param name name of the method to be executed within the scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotThrowsWithStringAndMessageAndType
	 */
	private function assertNotThrowsWithStringAndType(type, scope, name:String,
			args:Array):Boolean {
		return assertNotThrowsWithStringAndMessageAndType("", type, scope,
			name, args);
	}
	
	/**
	 * Asserts if the passed-in {@code method} does not throw any exception during
	 * its execution to the passed-in {@code scope}.
	 * 
	 * <p>This method executes within the passed-in {@code scope} the passed-in 
	 * {@code method} using the passed-in {@code args} and checks if it does not
	 * throw the expected exception.
	 * 
	 * <p>The assertion fails if the method throws any exception.
	 * 
	 * @param scope object to be used a scope
	 * @param method method that should be executed with the certain scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotThrowsWithFunctionAndMessage
	 */
	private function assertNotThrowsWithFunction(scope, method:Function,
			args:Array):Boolean {
		return assertNotThrowsWithFunctionAndMessage("", scope, method, args);
	}
	
	/**
	 * Asserts if the passed-in {@code method} throw a certain exception during
	 * its execution to the passed-in {@code scope}.
	 * 
	 * <p>This method executes within the passed-in {@code scope} the passed-in 
	 * {@code method} using the passed-in {@code args} and checks if it throws
	 * a certain exception.
	 * 
	 * <p>The assertion fails if the method throws a exception of the passed-in
	 * {@code type}.
	 * 
	 * @param type type of the exception that should not be thrown
	 * @param scope object to be used a scope
	 * @param method method that should be executed with the certain scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotThrowsWithFunctionAndMessageAndType
	 */
	private function assertNotThrowsWithFunctionAndType(type, scope,
			method:Function, args:Array):Boolean {
		return assertNotThrowsWithFunctionAndMessageAndType("", type, scope,
			method, args);
	}
	
	/**
	 * Asserts if the execution of a {@link Executable} does not throw any exception.
	 * 
	 * <p>This methods asserts the same like {@code assertNotThrowsWithCall}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param executable {@code Executable} that should be executed
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotThrowsWithCall
	 */
	private function assertNotThrowsWithCallAndMessage(message:String,
			executable:Executable, args:Array):Boolean {
		return assertNotThrowsWithCallAndMessageAndType(message, null, executable, args);
	}
	
	/**
	 * Asserts if the execution of a {@link Executable} does not throw a certain
	 * exception.
	 * 
	 * <p>This methods asserts the same like {@code assertNotThrowsWithCallAndType}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param type type of the exception that should not be thrown
	 * @param executable {@code Executable} that should be executed
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithCallAndType
	 */
	private function assertNotThrowsWithCallAndMessageAndType(message:String,
			type, executable:Executable, args:Array):Boolean {
		return addInfo(new AssertNotThrowsInfo(message, type, executable, args));
	}
	
	/**
	 * Asserts if the execution of the passed-in {@code name} to the passed-in
	 * {@code scope} does not throw any exception.
	 * 
	 * <p>This methods asserts the same like {@code assertNotThrowsWithString}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param scope object to be used a scope
	 * @param name name of the method to be executed within the scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @throws IllegalArgumentException if the method with the passed-in {@code name}
	 *         is not available with the passed-in {@code scope}.
	 * @see #assertNotThrowsWithString
	 */
	private function assertNotThrowsWithStringAndMessage(message:String, inObject,
			name:String, args:Array):Boolean {
		if(ObjectUtil.isTypeOf(inObject[name], "function")) {
			return assertNotThrowsWithCallAndMessage(message, new Call(inObject,
				inObject[name]), args);
		} else {
			throw new IllegalArgumentException("The method '"+name+"' is not available"
				+" within "+inObject.toString(), this, arguments);
		}
	}
	
	/**
	 * Asserts if the execution of the passed-in {@code name} to the passed-in
	 * {@code scope} does not throw a certain exception.
	 * 
	 * <p>This methods asserts the same like {@code assertNotThrowsWithStringAndType}
	 * but it adds a message to the failure.
	 * 
	 * @param type type of the exception that should not be thrown
	 * @param message message to be provided if the assertion fails
	 * @param scope object to be used a scope
	 * @param name name of the method to be executed within the scope
	 * @param args arguments to be used for the execution
	 * @throws IllegalArgumentException if the method with the passed-in {@code name}
	 *         is not available with the passed-in {@code scope}.
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotThrowsWithStringAndType
	 */
	private function assertNotThrowsWithStringAndMessageAndType(message:String,
			type, scope, name:String, args:Array):Boolean {
		if(ObjectUtil.isTypeOf(scope[name], "function")) {
			return assertNotThrowsWithCallAndMessageAndType(message, type,
				new Call(scope, scope[name]), args);
		} else {
			throw new IllegalArgumentException("The method '"+name+"' is not available"
				+" within "+scope.toString(), this, arguments);
		}
	}
	
	/**
	 * Asserts if the passed-in {@code method} does not throw any exception during 
	 * its execution to the passed-in {@code scope}.
	 * 
	 * <p>This methods asserts the same like {@code assertNotThrowsWithFunction}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param scope object to be used a scope
	 * @param method method that should be executed with the certain scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertNotThrowsWithFunction
	 */
	private function assertNotThrowsWithFunctionAndMessage(message:String, scope,
			method:Function, args:Array):Boolean {
		return assertNotThrowsWithCallAndMessage(message, new Call(scope, method), args);
	}
	
	/**
	 * Asserts if the passed-in {@code method} does not throw any exception during
	 * its execution to the passed-in {@code scope}.
	 * 
	 * <p>This methods asserts the same like {@code assertNotThrowsWithFunctionAnyType}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param type type of the exception that should not be thrown
	 * @param scope object to be used a scope
	 * @param method method that should be executed with the certain scope
	 * @param args arguments to be used for the execution
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertThrowsWithFunctionAndType
	 */
	private function assertNotThrowsWithFunctionAndMessageAndType(message:String,
			type, scope, method:Function, args:Array):Boolean {
		return assertNotThrowsWithCallAndMessageAndType(message, type,
			new Call(scope, method), args);
	}
	
	/**
	 * @overload #assertTypeOfWithMessage
	 * @overload #assertTypeOfWithoutMessage
	 */
	private function assertTypeOf():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([Object, String], assertTypeOfWithoutMessage);
		overload.addHandler([String, Object, String], assertTypeOfWithMessage);
		return overload.forward(arguments);
	}
	
	/**
	 * Asserts if the passed-in {@code val} matches the passed-in {@code type}.
	 * 
	 * <p>Checks with {@code typeof} if the {@code typeof} of the passed-in
	 * {@code val} matches the passed in {@code type}.
	 * 
	 * @param val parameter to check the type
	 * @param type expected type of {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertTypeOfWithMessage
	 * @see org.as2lib.util.ObjectUtil#isTypeOf
	 */
	private function assertTypeOfWithoutMessage(val, type:String):Boolean {
		return assertTypeOfWithMessage("", val, type);
	}
	
	/**
	 * Asserts if the passed-in {@code val} matches the passed-in {@code type} or
	 * fails with the passed-in {@code message}.
	 * 
	 * <p>This methods asserts the same like {@code assertTypeOfWithoutMessage}
	 * but it adds a message to the failure.
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter to check the type
	 * @param type expected type of {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertTypeOfWithoutMessage
	 */
	private function assertTypeOfWithMessage(message:String, val,
			type:String):Boolean {
		return addInfo(new AssertTypeOfInfo(message, val, type));
	}
	
	/** 
	 * @overload #assertInstanceOfWithMessage
	 * @overload #assertInstanceOfWithoutMessage
	 */
	private function assertInstanceOf():Boolean {
		var overload:Overload = new Overload(this);
		overload.addHandler([Object, Function], assertInstanceOfWithoutMessage);
		overload.addHandler([String, Object, Function], assertInstanceOfWithMessage);
		return overload.forward(arguments);
	}
	
	
	/**
	 * Asserts if the passed-in {@code val} is a instance of the passed-in
	 * {@code type}.
	 * 
	 * <p>Checks with {@code instanceof} if the passed-in {@code val} is a 
	 * instance of the passed in {@code type}.
	 * 
	 * @param val parameter to check the type
	 * @param type expected type of {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertInstanceOfWithMessage
	 * @see org.as2lib.util.ObjectUtil#isInstanceOf
	 */
	private function assertInstanceOfWithoutMessage(val, type:Function):Boolean {
		return assertInstanceOfWithMessage("", val, type);
	}
	
	/**
	 * Asserts if the passed-in {@code val} is a instance of the passed-in
	 * {@code type} or fails with the passed-in {@code message}
	 * 
	 * @param message message to be provided if the assertion fails
	 * @param val parameter to check the type
	 * @param type expected type of {@code val}
	 * @return {@code true} if no error occured else {@code false}
	 * @see #assertInstanceOfWithoutMessage
	 */
	private function assertInstanceOfWithMessage(message:String, val,
			type:Function):Boolean {
		return addInfo(new AssertInstanceOfInfo(message, val, type));
	}

}