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

import org.as2lib.env.event.EventListenerSource;
import org.as2lib.data.type.Time;

/**
 * {@code Process} represents the access to a lacy execution.
 * 
 * <p>{@code Process} can be used as access to application code that executes with
 * a time delay. This can be eighter file requests or time consuming algorithms
 * that have to be delayed to prevent player timeouts.
 * 
 * <p>Any {@code Process} implementation can be started with {@link #start}.
 *
 * <p>Any {@code Process} can send events defined in following interfaces:
 * {@link ProcessStartListener}, {@link ProcessErrorListener},
 * {@link ProcessFinishListener}, {@link ProcessPauseListener},
 * {@link ProcessResumeListener}, {@link ProcessUpdateListener}
 * 
 * <p>To listen to the events implement one or more of the above interfaces and
 * add the listener with {@code addListener} as listener to the {@code Process}.
 * 
 * @author Martin Heidegger
 * @version 1.0
 * @see org.as2lib.app.exec.AbstractProcess
 */
interface org.as2lib.app.exec.Process extends EventListenerSource {
	
	/**
	 * Starts the execution of this process.
	 * 
	 * <p>It is possible that the process finishes execution before returning the
	 * from this method, but it is also possible that it finishes after returning
	 * from this method. This rule exists to not loose unnecessary performance by
	 * simple accepting that every process has to be finished after this execution.
	 * 
	 * <p>Problematic example:
	 * <code>
	 * 
	 *   class MyClass implements ProcessFinishListener {
	 *     private var processStarted:Boolean
	 *     
	 *     public function MyClass(Void) {
	 *     	 processStarted = false;
	 *     }
	 *   
	 *     public function doSomething(Void):Void {
	 *       var process:Process = new MyProcess();
	 *       process.start();
	 *       process.addListener(this);
	 *       processStarted = true;
	 *     }
	 *     
	 *     public function onFinishProcess(process:Process):Void {
	 *       if (processStarted) {
	 *         // do something
	 *         processStarted = false;
	 *       } else {
	 *         // throw an error (will be called if the process finishes immediatly.
	 *       }
	 *     }
	 *   }
	 * </code>
	 * 
	 * <p>Any {@code Process} is allowed to take arguments for its execution or
	 * return a result of its execution.
	 * 
	 * @return (optiona) result for the start (implementation specific).
	 */
    public function start();
	
	/**
	 * Flag if the process has been started.
	 * 
	 * @return true if the process has been started and isn't finish yet else false.
	 */
    public function hasStarted(Void):Boolean;
    
    /**
     * Returns {@code true} if the process has been finished else {@code false}.
     * 
     * <p>A {@code Process} can only be finished if it has been started with 
     * {@code start()}
     * 
     * @return {@code true} if the process has been finished else {@code false}
     */
    public function hasFinished(Void):Boolean;
    
    /**
     * Returns {@code true} if the process has been started and has been paused.
     * 
     * <p>A {@code Process} is allowed to be paused, this indicates that the process
     * is actually waiting for something.
     * 
     * @return {@code true} if the process has been started and has been paused
     */
    public function isPaused(Void):Boolean;
    
    /**
     * Returns {@code true} if the process has been started and is not paused.
     * 
     * <p>A {@code Process} is allowed to be paused, this indicates that the process
     * is actually not waiting for something.
     * 
     * @return {@code true} if the process has been started and is not paused
     */
    public function isRunning(Void):Boolean;
    
    /**
     * Returns the percentage of execution
     * 
     * <p>There are several possibilies of return values:
     * 
     * <p>If the execution has not been started and the percentage will be
     * evaluateable for sure it will return {@code 0}.
     * 
     * <p>If the execution has been started and the percentage is evaluateable,
     * it returns the current amount of percentage from {@code 0}-{@code 100}.
     * 
     * <p>If the execution has finished and the percentage was evaluateable, it
     * returns {@code 100}.
     * 
     * <p>In any other case it will return {@code null}.
     * 
     * @return current percentage of execution
     */
    public function getPercentage(Void):Number;
    
    /**
     * Allows the integration and access to a process hierarchy.
     * 
     * @param process {@code Process} that started the current process.
     * @throws org.as2lib.env.except.IllegalArgumentException if the passed-in
     * 		   process has the current process within the parent process list or
     * 		   if the passed-in process is the same process as the current
     * 		   process.
     */
    public function setParentProcess(process:Process):Void;
    
    /**
     * Returns the parent {@code Process} set with {@code setParentProcess}.
     * 
     * @return parent process if available, else {@code null}.
     */
    public function getParentProcess(Void):Process;
    
    /**
     * Returns the occured errors published with {@code onProcessError} during
     * exeuction of the {@code Process} in an array.
     *
     * @return all occured errors during the execution of the event
     */
    public function getErrors(Void):Array;
	
	/**
	 * Checks if an error occured during execution of the {@code Process}.
	 *  
	 * @return {@code true} if an error occured, else {@code false}
	 */
	public function hasError(Void):Boolean;
	
	/**
	 * By using {@code start()} it saves the start time of the execution of the process.
	 * 
	 * <p>This method allows access to the total execution time of the process. The total
	 * execution time get evaluated by comparing start time with end time or (if the
	 * process has not finished yet) with the current time.
	 * 
	 * @return time difference between start time and finish time or current point
	 */
	public function getDuration(Void):Time;
	
	/**
	 * Evaluates the expected total time of execution.
	 * 
	 * <p>If the {@code Process} has been finished it returns the final total time
	 * of the execution.
	 * 
	 * <p>If the {@code Process} has not been started it returns a estimated total
	 * time of {@code 0}.
	 * 
	 * @return estimated time difference between start and finish time
	 */
	public function getEstimatedTotalTime(Void):Time;
	
	/**
	 * Evaluates the expected rest time until the execution finishes.
	 * 
	 * <p>If the {@code Process} has been finished it returns {@code 0}. If it
	 * has not been started it returns {@code null}.
	 * 
	 * @return estimated rest time of the execution of the process.
	 */
	public function getEstimatedRestTime(Void):Time;
}