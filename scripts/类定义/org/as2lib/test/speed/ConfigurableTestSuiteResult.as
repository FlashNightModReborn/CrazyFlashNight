/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.test.speed.TestSuiteResult;
import org.as2lib.test.speed.TestResult;

/**
 * {@code ConfigurableTestSuiteResult} declares methods needed to configure test
 * suites.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.test.speed.ConfigurableTestSuiteResult extends TestSuiteResult {
	
	/**
	 * Adds a new test result.
	 * 
	 * @param testResult the new test result to add
	 */
	public function addTestResult(testResult:TestResult):Void;
	
}