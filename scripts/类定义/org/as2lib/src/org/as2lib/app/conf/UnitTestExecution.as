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

import org.as2lib.app.exec.Process;
import org.as2lib.app.exec.AbstractProcess;
import org.as2lib.test.unit.LoggerTestListener;
import org.as2lib.test.unit.TestSuiteFactory;
import org.as2lib.test.unit.TestSuite;

/**
 * Prepared configuration to execute Testcases.
 * <p>Use this class to simplify your configuration for the execution of Testcases.
 * <p>As common for as2lib configuration you can use this configuration within your application
 * execution to start and configure a TestSystem.
 * 
 * Example:
 * <code>
 *   import org.as2lib.app.conf.AbstractConfiguration;
 *   import com.domain.test.*
 *   
 *   class main.Configuration extends AbstractConfiguration {
 *     public static function init(Void):Void {
 *       init(UnitTestExecution);
 *     }
 *     
 *     public function setReferences(Void):Void {
 *       use(MyTestCase);
 *       use(MyTestCase2);
 *       use(MyTestCase3);
 *     }
 *   }
 * </code>
 *
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.app.conf.UnitTestExecution extends AbstractProcess implements Process {
	
	/**
	 * Runs all available Testcases.
	 */
	public function run(Void):Void {
		
		// Execute all Testcases that are available at runtime
		var factory:TestSuiteFactory = new TestSuiteFactory();
		
		var testSuite:TestSuite = factory.collectAllTestCases();
		testSuite.addListener(LoggerTestListener.getInstance());
		
		// Starts the Runner as a subprocess.
		startSubProcess(testSuite);
	}
}