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

import org.as2lib.core.BasicClass;
import org.as2lib.test.speed.TestResult;
import org.as2lib.test.speed.ConfigurableTestSuiteResult;
import org.as2lib.test.speed.layout.MethodInvocationLayout;
import org.as2lib.test.speed.layout.MethodLayout;
import org.as2lib.test.speed.layout.ClassLayout;
import org.as2lib.test.speed.layout.PackageLayout;
import org.as2lib.test.speed.layout.MethodInvocationTreeLayout;

/**
 * {@code AbstractTest} provides implementations for methods needed when implementing
 * the {@link Test} interface and some extra methods commonly needed.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.AbstractTest extends BasicClass {
	
	/** Do not layout the result in any specific way. */
	public static var NONE:Number = -1;
	
	/** Layout the result with method invocations as highest structural level. */
	public static var METHOD_INVOCATION:Number = 0;
	
	/** Layout the result with methods as highest structural level. */
	public static var METHOD:Number = 1;
	
	/** Layout the result with classes as highest structural level. */
	public static var CLASS:Number = 2;
	
	/** Layout the result with packages as highest structural level. */
	public static var PACKAGE:Number = 3;
	
	/**
	 * Layout the result to depict the order of method invocations. This means that the
	 * tree is ordered firstly in depth according to which method called which other
	 * method and secondly sorted by the correct succession of method invocations.	 */
	public static var METHOD_INVOCATION_TREE:Number = 4;
	
	/** The result of this test. */
	private var result:ConfigurableTestSuiteResult;
	
	/**
	 * Constructs a new {@code AbstractTest} instance.	 */
	private function AbstractTest(Void) {
	}
	
	/**
	 * Return the result of this test.
	 * 
	 * <p>The following layouts are applicable:
	 * <ul>
	 *   <li>{@link #NONE}</li>
	 *   <li>{@link #METHOD_INVOCATION}</li>
	 *   <li>{@link #METHOD}</li>
	 *   <li>{@link #CLASS}</li>
	 *   <li>{@link #PACKAGE}</li>
	 *   <li>{@link #METHOD_INVOCATION_TREE} (default)</li>
	 * </ul>
	 * 
	 * @param layout (optional) the layout of the returned test result
	 * @return this test's result
	 */
	public function getResult(layout:Number):TestResult {
		switch (layout) {
			case NONE:
				return this.result;
				break;
			case METHOD_INVOCATION:
				return (new MethodInvocationLayout()).layOut(this.result);
				break;
			case METHOD:
				return (new MethodLayout()).layOut(this.result);
				break;
			case CLASS:
				return (new ClassLayout()).layOut(this.result);
				break;
			case PACKAGE:
				return (new PackageLayout()).layOut(this.result);
				break;
			default:
				return (new MethodInvocationTreeLayout()).layOut(this.result);
				break;
		}
	}
	
	/**
	 * Sets this test's result.
	 * 
	 * @param result this test's result	 */
	private function setResult(result:ConfigurableTestSuiteResult):Void {
		this.result = result;
	}
	
}