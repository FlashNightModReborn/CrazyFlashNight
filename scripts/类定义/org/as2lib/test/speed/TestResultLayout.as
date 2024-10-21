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

import org.as2lib.core.BasicInterface;
import org.as2lib.test.speed.TestSuiteResult;

/**
 * {@code TestResultLayout} lays test results out.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.test.speed.TestResultLayout extends BasicInterface {
	
	/**
	 * Lays the passed-in {@code testResult} out and returns a new lay-outed test
	 * result.
	 * 
	 * @param testResult the test result to lay-out
	 * @return the lay-outed test result
	 */
	public function layOut(testResult:TestSuiteResult):TestSuiteResult;
	
}