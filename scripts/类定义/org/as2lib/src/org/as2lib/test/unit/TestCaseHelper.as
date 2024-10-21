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
 
import org.as2lib.test.unit.TestCase;
import org.as2lib.test.unit.TestCaseRunner;

/**
 * {@code TestCaseHelper} is a class that helps writing {@link TestCase}s.
 * <p>A {@code TestCase} allows proper execution for any kind of test. But if
 * you want to refactor/break apart your code and simplify your test it disallows
 * you to handle assertions.
 * 
 * <p>A common example is if you want to test for a interface. Any implementation
 * has to match the rules of the interface. A standardised test for the interface
 * would therefore be a helper. Code could look like this:
 * 
 * <p>Interface
 * <code>
 *   interface MyInterface {
 *   	public function addInstance(obj):Void;
 *   	public function containsInstance(obj):Void;
 *   	public function removeInstance(obj):Void;
 *   }
 * </code>
 * 
 * <p>Implementation #1
 * <code>
 *   import org.as2lib.util.ArrayUtil;
 * 
 *   class MyImplementationA implements MyInterface {
 *   	private var array:Array;
 *   	
 *   	public fucntion MyImplementationA() {
 *   		array = new Array();
 *   	}
 *   	
 *   	public function addInstance(obj):Void {
 *   		removeInstance(obj);
 *   		array.push(obj);
 *   	}
 *   	
 *   	public function removeInstance(obj):Void {
 *   		ArrayUtil.removeElement(array, obj);
 *   	}
 *   	
 *   	public function containsInstance(obj):Boolean {
 *   		for (var i:Number = 0; i < array.length; i++) {
 *   			if (array[i] === obj) {
 *   				return true;
 *   			}
 *   		}
 *   		return false;
 *   	}
 *   }
 * </code>
 * 
 * <p>Implementation #2
 * <code>
 *   class MyImplementationB extends MyImplementationA {
 *   	public function containsInstance(obj):Boolean {
 *   		for (var i:Number = array.length-1; i > 0; i++) {
 *   			if (array[i] === obj) {
 *   				return true;
 *   			}
 *   		}
 *   		return false;
 *   	}
 *   }
 * </code>
 * 
 * <p>Test for the Interface
 * <code>
 *   import org.as2lib.test.unit.TestCaseHelper;
 *   import org.as2lib.test.mock.MockControl;
 *   
 *   class TMyInterface extends TestCaseHelper {
 *   	public function testAccess(instance:MyInterface) {
 *   		var mC:MockControl = new MockControl(Object);
 *   		mC.replay();
 *   		assertfalse("Instance should not be contained",	
 *   			instance.containsListener(mC.getMock()));
 *   		instance.addInstance(mC.getMock());
 *   		assertTrue("Instance should be contained",
 *   			instance.containsListener(mC.getMock()));
 *   		instance.removeInstance(mC.getMock());
 *   		assertfalse("Instance should not be contained",
 *   			instance.containsListener(mC.getMock()));
 *   		instance.addInstance(mC.getMock());
 *   		instance.addInstance(mC.getMock());
 *   		instance.removeInstance(mC.getMock());
 *   		assertfalse("Instance should not be contained after double adding",
 *   			instance.containsListener(mC.getMock()));
 *   		mC.verify();
 *   	}
 *   }
 * </code>
 * 
 * <p>Test for Implementation A
 * <code>
 * 	 import org.as2lib.test.unit.TestCase;
 * 	 
 * 	 class TMyImplementationA extends TestCase {
 * 	 
 * 	 	public function testMyInterface() {
 * 	 		var i:TMyInterface = new TMyInterface(this);
 * 	 		i.testAccess(new MyImplementationA());
 * 	 	}
 * 	 }
 * </code>
 * 
 * <p>Test for Implementation B
 * <code>
 * 	 import org.as2lib.test.unit.TestCase;
 * 	 
 * 	 class TMyImplementationB extends TestCase {
 * 	 
 * 	 	public function testMyInterface() {
 * 	 		var i:TMyInterface = new TMyInterface(this);
 * 	 		i.testAccess(new MyImplementationB());
 * 	 	}
 * 	 }
 * </code>
 * 
 * @author Martin Heidegger
 * @version 1.1
 */
class org.as2lib.test.unit.TestCaseHelper extends TestCase {
	
	/** Reference testCase to work with */
	private var testCase:TestCase;
	
	/**
	 * Flag to hide from getting collected by
	 * {@link org.as2lib.test.unit.TestSuiteFactory#collectAllTestCases}
	 * 
	 * @return true to block collecting
	 */
	public static function blockCollecting(Void):Boolean {
		return true;
	}
	
	/**
	 * Constructs a new {@code TestCaseHelper} instance.
	 * 
	 * @param testCase {@code TestCase} instance that should be used with all
	 *        assertions.
	 */
	public function TestCaseHelper(testCase:TestCase) {
		this.testCase = testCase;
		testRunner = TestCaseRunner(testCase.getTestRunner());
	}
}