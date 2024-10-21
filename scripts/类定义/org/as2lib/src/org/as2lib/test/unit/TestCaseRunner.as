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
 
import org.as2lib.app.exec.AbstractProcess;
import org.as2lib.app.exec.Processor;
import org.as2lib.app.exec.StepByStepProcess;
import org.as2lib.data.holder.Queue;
import org.as2lib.data.holder.queue.LinearQueue;
import org.as2lib.test.unit.ExecutionInfo;
import org.as2lib.test.unit.TestCase;
import org.as2lib.test.unit.TestCaseMethodInfo;
import org.as2lib.test.unit.TestCaseResult;
import org.as2lib.test.unit.TestRunner;
import org.as2lib.test.unit.TestResult;
import org.as2lib.test.unit.info.InstantiationError;
import org.as2lib.test.unit.info.ExecutionError;
import org.as2lib.test.unit.info.SetUpError;
import org.as2lib.test.unit.info.TearDownError;
import org.as2lib.util.ClassUtil;
import org.as2lib.util.StopWatch;
import org.as2lib.util.StringUtil;

/**
 * {@code TestCaseRunner} is the implementation for the execution of {@link TestCase}s.
 * 
 * <p>It executes and handles all operations to process the certain {@code TestCase}.
 * 
 * <p>Usually you do not get in touch with the {@code TestCaseRunner} because any
 * {@code TestCase} handles it automatically.
 * 
 * <p>As its a implementation of {@link TestRunner} it is possible to add any
 * {@link org.as2lib.app.exec.ProcessListener} as listener to the execution of
 * the {@code TestCaseRunner}.
 * 
 * @author HeideggerMartin
 * @version 1.0
 */
class org.as2lib.test.unit.TestCaseRunner
			extends AbstractProcess
			implements TestRunner, StepByStepProcess {

	/** State if no method has been started. */
	private var STATE_NOT_STARTED:Number = 1;
	
	/** State if the instance has been created. */
	private var STATE_TEST_CREATED:Number = 2;
	
	/** State if setUp has been executed. */
	private var STATE_SET_UP_FINISHED:Number = 3;
	
	/** State if the method has been executed. */
	private var STATE_EXECUTION_FINISHED:Number = 4;
	
	/** State if tearDown has been executed. */
	private var STATE_TEAR_DOWN_FINISHED:Number = 5;

	/** Result to the execution. */
	private var testResult:TestCaseResult;
	
	/** Queue that contains the methods to execute. */
	private var openTestCaseMethods:Queue;
	
	/**
	 * Information for the current executing method.
	 * Since its possible to pause/resume the process its necessary to safe it
	 * in instance scope.
	 */
	private var methodInfo:TestCaseMethodInfo;
	
	/**
	 * State of the execution of the method.
	 * Since its possible to pause/resume the process its necessary to safe at
	 * what point of execution it had paused.
	 */
	private var methodState:Number;
	
	/** Instance for the execution of the method. */
	private var testCaseInstance:TestCase;
	
	/** StopWatch related to the test (saved in instance scope because of performance). */
	private var sW:StopWatch;
	
	/**
	 * Constructs a new {@code TestCaseRunner}.
	 * 
	 * @param testCase {@code TestCase} that should be executed.
	 */
	function TestCaseRunner(testCase:TestCase) {
		testResult = new TestCaseResult(testCase);
		methodState = STATE_NOT_STARTED;
		openTestCaseMethods = new LinearQueue(testResult.getMethodInfos());
	}
	
	/** 
	 * Returns the {@code TestCaseResult} to the executed {@code TestCase}.
	 * 
	 * <p>The result contains all informations about the connected {@code TestCase}.
	 * Since it is available even if the {@code TestCaseRunner} has not been started
	 * or finished the execution it is possible that the result is not complete at
	 * the request. But it contains all informations about the methods that will
	 * be executed.
	 * 
	 * @return {@link TestResult} for the {@code TestCase} that contains all informations
	 */
	public function getTestResult(Void):TestResult {
		return testResult;
	}
	
	/**
	 * Returns the current executing {@code TestCaseResult}.
	 * 
	 * <p>It is necessary to get the {@code TestCaseResult} for the {@code TestCase}
	 * that just gets executed because there can be more than one {@code TestCase}
	 * available within a {@code TestResult}. 
	 * 
	 * @return {@code TestCaseResult} related to the {@code TestCase}
	 */
	public function getCurrentTestCase(Void):TestCaseResult {
		return testResult;
	}

	/**
	 * Returns the current executing {@code TestCaseMethodInfo}.
	 * 
	 * <p>It is necessary to get the {@code TestCaseMethodInfo} for the method
	 * that just gets executed because there can be more than one methods available
	 * within a {@code TestCaseResult}.
	 * 
	 * @return informations about the current executing method
	 * @see #getCurrentTestCase
	 */
	public function getCurrentTestCaseMethodInfo(Void):TestCaseMethodInfo {
		return methodInfo;
	}

	/**
	 * Adds a information about the current executing method.
	 * 
	 * @param info {@code ExecutionInfo} to be added
	 */
	public function addInfo(info:ExecutionInfo):Void {
		methodInfo.addInfo(info);
	}
	
	/**
	 * Implementation of {@link AbstractProcess#run} for the start of the {@code Process}.
	 */
	private function run(Void):Void {
		working = true;
		// Processor to manage the concrete processing of the TestCase
		Processor.getInstance().addStepByStepProcess(this);
	}
	
	/**
	 * Executes the next step of the {@code Process}
	 * 
	 * <p>Implementation of {@link StepByStepProcess#nextStep}.
	 */
	public function nextStep(Void):Void {
		if (openTestCaseMethods.isEmpty()) {
			finish();
		} else {
			if (methodState == STATE_NOT_STARTED) {
				methodInfo = openTestCaseMethods.dequeue();
				sW = methodInfo.getStopWatch();
				sendUpdateEvent();
			}
			while (processMethod());
		}
	}
	
	/**
	 * Returns the percentage of execution of the {@code TestCase}.
	 */
	public function getPercentage(Void):Number {
		return (100-(100/testResult.getMethodInfos().length*openTestCaseMethods.size()));
	}
	
	/**
	 * Executes the current method.
	 * 
	 * <p>Handles all possible executions states and continues to the next
	 * execution.
	 * 
	 * @return {@code true} if the execution has finished and {@code false} if it has to be continued.
	 */
	private function processMethod(Void):Boolean {
		// Execution depending to the current state.
		switch (methodState) {
			case STATE_NOT_STARTED:
				
			    // create instance and set state for next loop.
				methodState = STATE_TEST_CREATED;
				
			    try {
				    testCaseInstance = ClassUtil.createInstance(
							testResult.getTestCase()["__constructor__"]
					);
			    } catch(e) {
					fatal(new InstantiationError("IMPORTANT: Testcase threw "
						+ "an error by instanciation.\n"
						+ StringUtil.addSpaceIndent(e.toString(), 2), this, arguments));
				}
				break;
				
			case STATE_TEST_CREATED:
			
				// set up the instance and set state for next loop.
				methodState = STATE_SET_UP_FINISHED;
				
				testCaseInstance.getTestRunner();

				// Prepare the execution of the method by setUp
				if (!methodInfo.hasErrors()) {
					try {
						testCaseInstance.setUp();
					} catch (e) {
						fatal(new SetUpError("IMPORTANT: Error occured during"
							+ " set up(Testcase wasn't executed):\n"+StringUtil.addSpaceIndent(e.toString(), 2), testCaseInstance, arguments));
					}
				}
				break;
				
			case STATE_SET_UP_FINISHED:
			
				// execute the method and set the state for the next loop
				methodState = STATE_EXECUTION_FINISHED;
				
				if (!methodInfo.hasErrors()) {	
					// Execute the method
					sW.start();
					try {
						methodInfo.getMethodInfo().invoke(testCaseInstance, null);
					} catch (e) {
						fatal(new ExecutionError("Unexpected exception thrown"
							+ " during execution:\n"
							+ StringUtil.addSpaceIndent(e.toString(), 2),
							testCaseInstance, arguments));
					}
				}
				break;
				
			case STATE_EXECUTION_FINISHED:
			
				// tear down the instance and set the state for the next loop
				methodState = STATE_TEAR_DOWN_FINISHED;
				if (sW.hasStarted()) {
					sW.stop();
				}
				
				if (!methodInfo.hasErrors()) {	
					try {
						testCaseInstance.tearDown();
					} catch(e) {
						fatal(new TearDownError("IMPORTANT: Error occured during"
							+ " tear down:\n"+StringUtil.addSpaceIndent(e.toString(), 2),
							testCaseInstance, arguments));
					}
				}
				break;
				
			case STATE_TEAR_DOWN_FINISHED:
				methodState = STATE_NOT_STARTED;
				methodInfo.setExecuted(true);
				return false; // next method
				
		}
		// next state execution
		return true;
	}
	
	/**
	 * Internal helper to stop the execution if a fatal error occurs.
	 * 
	 * <p>It will add the passed-in {@code error} to the list of informations
	 * with {@code addInfo}.
	 * 
	 * @param error error that occured
	 */
	private function fatal(error:ExecutionInfo):Void {
		addInfo(error);
		methodState = STATE_TEAR_DOWN_FINISHED;
	}
}