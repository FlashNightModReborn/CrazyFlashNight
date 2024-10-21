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
import org.as2lib.test.unit.TestRunner;
import org.as2lib.test.unit.TestCaseResult;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.log.LogSupport;
import org.as2lib.test.unit.TestCaseMethodInfo;
import org.as2lib.app.exec.ProcessStartListener;
import org.as2lib.app.exec.ProcessErrorListener;
import org.as2lib.app.exec.ProcessFinishListener;
import org.as2lib.app.exec.ProcessPauseListener;
import org.as2lib.app.exec.ProcessResumeListener;
import org.as2lib.app.exec.ProcessUpdateListener;

/**
 * {@code LoggerTestListener} is the default listener for Tests.
 * Listener as default logger for the Testrunner. To be used as standard outwriter for the TestRunner.
 *
 * @author Martin Heidegger
 * @see LogManager#getLoggerRepository
 * @see Logger
 */
class org.as2lib.test.unit.LoggerTestListener extends LogSupport
	implements ProcessStartListener,
		ProcessErrorListener,
		ProcessFinishListener,
		ProcessPauseListener,
		ProcessResumeListener,
		ProcessUpdateListener {
	
	/* Instance holfer of the default LoggerTestListener */
	private static var instance:LoggerTestListener;
	
	/**
	 * Returns a instance of {@code LoggerTestListener}
	 * 
	 * @return Instance of {@code LoggerTestListener}
	 */
	public static function getInstance(Void):LoggerTestListener {
		if (!instance) {
			instance = new LoggerTestListener();
		}
		return instance;
	}
	
	/** Stores former displayed TestCase. */
	private var formerTest:TestCaseResult;
	
	/**
	 * Private constructor, use {@link #getInstance} to create a instance.
	 */
	private function LoggerTestListener() {}
	
	
	/**
	 * Start event, fired by start of a TestRunner.
	 * 
	 * @param startInfo Informations about the TestRunner that started.
	 */
	public function onProcessStart(process:Process):Void {
		logger.info("TestRunner started execution.");
	}
	
	/**
	 * Progress event, fired after each executed method within a TestRunner.
	 * 
	 * @param progressInfo Extended informations the current progress.
	 */
	public function onProcessUpdate(process:Process):Void {
		var testRunner:TestRunner = TestRunner(process);
		if (testRunner) {
			var methodInfo:TestCaseMethodInfo = testRunner.getCurrentTestCaseMethodInfo();
			if (methodInfo) {
				logger.info("executing ... "+testRunner.getCurrentTestCase().getName()+"."+methodInfo.getMethodInfo().getName());
			}
		}
	}
	
	/**
	 * Redirects the string representation of the testrunner to the logger
	 * 
	 * @param finishInfo Informations about the TestRunner that finished.
	 */
	public function onProcessFinish(process:Process):Void {
		var testRunner:TestRunner = TestRunner(process);
		if(testRunner) {
			logger.info("TestRunner finished with the result: \n"+testRunner.getTestResult().toString());
		} else {
			throw new IllegalArgumentException("LoggerTestListener added to a different Process", this, arguments);
		}
	}
	
	/**
	 * Pause event, fired after by pausing the execution of a TestRunner.
	 * 
	 * @param pauseInfo Informations about the TestRunner that paused.
	 */
	public function onProcessPause(process:Process):Void {
		var test:TestRunner = TestRunner(process);
		logger.info("TestRunner paused execution at "+test.getCurrentTestCaseMethodInfo().getName());
	}
	
	/**
	 * Pause event, fired after by resuming the execution of a TestRunner.
	 * 
	 * @param resumeInfo Informations about the TestRunner that resumed working.
	 */
	public function onProcessResume(process:Process):Void {
		var test:TestRunner = TestRunner(process);
		logger.info("TestRunner resumed execution at "+test.getCurrentTestCaseMethodInfo().getName());
	}
	
	/**
	 * Executed if a Exeception was thrown during the execution
	 * 
	 * @param process where the execution paused.
	 * @param error Error that occured.
	 */
	public function onProcessError(process:Process, error):Boolean {
		logger.error("Exception was thrown during the execution of the TestRunner: " + error + ".");
		return true;
	}
	
}