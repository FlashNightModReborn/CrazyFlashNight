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

import org.as2lib.env.except.AbstractOperationException;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.app.exec.Process;
import org.as2lib.app.exec.Executable;
import org.as2lib.app.exec.ProcessErrorListener;
import org.as2lib.app.exec.ProcessFinishListener;
import org.as2lib.app.exec.ProcessStartListener;
import org.as2lib.app.exec.ProcessPauseListener;
import org.as2lib.app.exec.ProcessResumeListener;
import org.as2lib.app.exec.ProcessUpdateListener;
import org.as2lib.app.exec.AbstractTimeConsumer;
import org.as2lib.data.holder.Map;
import org.as2lib.data.holder.map.HashMap;
import org.as2lib.util.MethodUtil;
import org.as2lib.env.event.distributor.CompositeEventDistributorControl;

/**
 * {@code AbstractProcess} is a abstract helper class to implement processes.
 * 
 * <p>Most of the functionalities of {@link Process} are served well within 
 * {@code AbstractProcess}. Because of the situation that most processes are 
 * simple executions {@code AbstractProcess} allows easy implementations of 
 * {@link Process}.
 * 
 * <p>To use the advantage of {@code AbstractProcess} simple extend it and
 * implement the {@link #run} method.
 * 
 * <p>It executes {@link #run} at {@link #start} and handles the exeuction of
 * events and the correct states. If you wan't to stop your process
 * {@link #pause} and {@link #resume} offer direct support.
 * 
 * <p>Example for a process that can not be finished by return:
 * <code>
 *   class MyProcess extends AbstractProcess {
 *   
 *     public function run() {
 *        // Xml that has to work
 *        var xml:Xml = new Xml();
 *        
 *        // helper for the call back.
 *        var inst = this;
 *        
 *        // Mtasc compatible return from loading
 *        xml.onLoad = function() {
 *          inst["finish"]();
 *        }
 *        
 *        // Flag to not finish automatically
 *        working = true;
 *        
 *        // Start of loading the xml file.
 *        xml.load("test.xml");
 *     }
 *   }
 * </code>
 * 
 * @author Martin Heidegger
 * @version 1.0
 * @see Process
 * @see ProcessStartListener
 * @see ProcessFinishListener
 * @see ProcessErrorListener
 * @see ProcessPauseListener
 * @see ProcessResumeListener
 * @see ProcessUpdateListener
 */
class org.as2lib.app.exec.AbstractProcess extends AbstractTimeConsumer
	implements Process,
		ProcessErrorListener,
		ProcessFinishListener {
	
	/** Flag if execution was paused. */
	private var paused:Boolean;
	
	/** Flag if execution is just not working (case if a event is not finished within .start). */
	private var working:Boolean;
	
	/** List of all errors that occur during execution. */
	private var errors:Array;
	
	/** All subprocesses (Key) and its mapped callBacks (Value).  */
	private var subProcesses:Map;
	
	/** Contains the possible parent. */
	private var parent:Process;
	
	/** Shorter name for the concrete distributorControl. */
	private var dC:CompositeEventDistributorControl;
	
	/**
	 * Constructs a new {@code AbstractProcess}.
	 */
	private function AbstractProcess(Void) {
		dC = distributorControl;
		acceptListenerType(ProcessStartListener);
		acceptListenerType(ProcessErrorListener);
		acceptListenerType(ProcessUpdateListener);
		acceptListenerType(ProcessPauseListener);
		acceptListenerType(ProcessResumeListener);
		acceptListenerType(ProcessFinishListener);
		errors = new Array();
		subProcesses = new HashMap();
		paused = false;
		working = false;
	}
	
	/**
	 * Setter for a parent process.
	 *
	 * <p>Validates if the passed-in {@code Process} is this instance or has
	 * this instance in its parent hierarchy (to prevent recursions).
	 * 
	 * @param p {@code Process} to act as parent
	 * @throws IllegalArgumentException if the applied process has the current 
	 *         instance in its parent hierarchy or it is the current instance
	 */
	public function setParentProcess(p:Process):Void {
		do {
			if(p == this) {
				throw new IllegalArgumentException("You can not start a process with itself as super process.", this, arguments);
			}
		} while (p = p.getParentProcess());
		parent = p;
	}
	
	/**
	 * Returns the {@code Process} that acts as parent for this process.
	 * 
	 * @return parent {@code Process} if set, else {@code null}
	 */
	public function getParentProcess(Void):Process {
		return parent;
	}
	
	/**
	 * Starts a sub-process.
	 * 
	 * <p>This method allows to start a {@code Process}. It registers itself as
	 * parent of the passed-in {@code process} and starts the {@code process}
	 * if necessary.
	 * 
	 * <p>If you add a sub-process it will be started immediately. This is important
	 * if you start more than one sub-process, because they won't get executed in
	 * a row like its handled within a {@link org.as2lib.app.exec.Batch}.
	 * 
	 * <p>This process will not be finished until all subprocesses have finished.
	 * 
	 * <p>On finish of the {@code process} to start it will execute the passed-in
	 * {@code callBack}. 
	 * 
     * @param process process to be used as sub-process
     * @param args arguments for the process start
     * @param callBack call back to be executed if the process finishes
	 */
	public function startSubProcess(process:Process, args:Array, callBack:Executable):Void {
		// Don't do anything if the the process is already registered as sub-process.
		if (!subProcesses.containsKey(process)) {
			process.addListener(this);
			process.setParentProcess(this);
			subProcesses.put(process, callBack);
			if (!isPaused()) {
				pause();
			}
			// Start if not started.
			// Re-start if finished.
			// Do nothing if started but not finished.
			if(!process.hasStarted() || process.hasFinished()) {
				process["start"].apply(process, args);
			}
		}
	}
	
	/**
	 * Pauses the process.
	 */
	public function pause(Void):Void {
		paused = true;
		sendPauseEvent();
	}
	
	/**
	 * Resumes the process.
	 */
	public function resume(Void):Void {
		paused = false;
		sendResumeEvent();
	}
	
	/**
	 * Prepares the start of the process.
	 */
	private function prepare(Void):Void {
		started = false;
		paused = false;
		finished = false;
		working = false;
		totalTime.setValue(0);
		restTime.setValue(0);
		sendStartEvent();
		started = true;
	}
	
	/**
	 * Starts the process.
	 * 
	 * <p>Any applied parameter will be passed to the {@link #run} implementation.
	 * 
	 * @return (optional) result of {@code run()}
	 */
    public function start() {
    	prepare();
    	var result;
    	try {
    		delete endTime;
    		startTime = getTimer();
			result = MethodUtil.invoke("run", this, arguments);
    	} catch(e) {
    		sendErrorEvent(e);
    	}
		if(!isPaused() && !isWorking()) {
			finish();
		}
		return result;
	}
	
	/**
	 * Flag if the current implementation is working.
	 * 
	 * <p>Important for {@link #start} this method indicates that the just starting
	 * process is not finished by return.
	 * 
	 * @return {@code true} if the implementation is working
	 */
	private function isWorking(Void):Boolean {
		return working;
	}
	
	/**
	 * Template method for running the process.
	 * 
	 * @throws AbstractOperationException if the method was not extended
	 */
	private function run(Void):Void {
		throw new AbstractOperationException(".run is abstract and has to be implemented.", this, arguments);
	}
	
	/**
	 * Returns {@code true} if the process is paused.
	 * 
	 * @return {@code true} if the process is paused
	 */
	public function isPaused(Void):Boolean {
		return paused;
	}
	
	
	/**
	 * Returns {@code true} if the process is running.
	 * 
	 * @return {@code true} if the process is running
	 */
	public function isRunning(Void):Boolean {
		return(!isPaused() && hasStarted());
	}
	
	/**
	 * Method to be executed if a process finishes its execution.
	 * 
	 * @param process {@link Process} that finished with execution
	 */
	public function onProcessFinish(process:Process):Void {
		if (subProcesses.containsKey(process)) {
			// removes current as listener
			process.removeListener(this);
			// Remove the process and executes the registered callback.
			subProcesses.remove(process).execute();
			// Resume exeuction
			resume();
		}
	}
	
    /**
     * Method to be executed if a exception was thrown during the execution.
     * 
     * @param process {@link Process} where a error occured
     * @param error error that occured
     * @return {@code true} if error was consumed
     */
	public function onProcessError(process:Process, error):Boolean {
		return sendErrorEvent(error);
	}
	
	/**
	 * Internal Method to finish the execution.
	 */
	private function finish(Void):Void {
		if (subProcesses.isEmpty() && isRunning()) {
			finished = true;
			started = false;
			working = false;
			endTime = getTimer();
			sendFinishEvent();
		}
	}
	
	/**
	 * Returns {@code true} if a error occured.
	 *  
	 * @return {@code true} if a error occured
	 */
	public function hasError(Void):Boolean {
		return (getErrors().length != 0);
	}
	
	/**
	 * Returns the list with all occured errors.
	 * 
	 * @return list that contains all occured errors
	 */
	public function getErrors(Void):Array {
		return errors;
	}
	
	/**
	 * Stores the {@code error} in the list of occured errors and finishes the process.
	 * 
	 * <p>It will set the error to -1 if you interrupt without a error.
	 * 
	 * @param error error that occured to interrupt
	 */
	private function interrupt(error):Void {
		publishError(error);
		finish();
	}
	
	/**
	 * Publishes the error event and stores the error in the error list.
	 * 
	 * @param error error to be published
	 * @return {@code true} if event was consumed
	 */
	private function publishError(error):Boolean {
		if (!error) error = -1;
		this.errors.push(error);
		return sendErrorEvent(error);
	}
	
	/**
	 * Internal method to send update events for {@link ProcessUpdateListener}.
	 */
	private function sendUpdateEvent(Void):Void {
		var updateDistributor:ProcessUpdateListener
			= dC.getDistributor(ProcessUpdateListener);
		updateDistributor.onProcessUpdate(this);
	}
	
	/**
	 * Internal method to send pause events for {@link ProcessPauseListener}.
	 */
	private function sendPauseEvent(Void):Void {
		var pauseDistributor:ProcessPauseListener
			= dC.getDistributor(ProcessPauseListener);
		pauseDistributor.onProcessPause(this);
	}
	
	/**
	 * Internal method to send resume events for {@link ProcessResumeListener}.
	 */
	private function sendResumeEvent(Void):Void {
		var resumeDistributor:ProcessResumeListener
			= dC.getDistributor(ProcessResumeListener);
		resumeDistributor.onProcessResume(this);
	}
	
	/**
	 * Internal method to send start events for {@link ProcessStartListener}.
	 */
	private function sendStartEvent(Void):Void {
		var startDistributor:ProcessStartListener
			= dC.getDistributor(ProcessStartListener);
		startDistributor.onProcessStart(this);
	}
	
	/**
	 * Internal method to send error events for {@link ProcessErrorListener}.
	 */
	private function sendErrorEvent(error):Boolean {
		var errorDistributor:ProcessErrorListener
			= dC.getDistributor(ProcessErrorListener);
		return errorDistributor.onProcessError(this, error);
	}
	
	/**
	 * Internal method to send finish events for {@link ProcessFinishListener}.
	 */
	private function sendFinishEvent(Void):Void {
		var finishDistributor:ProcessFinishListener
			= dC.getDistributor(ProcessFinishListener);
		finishDistributor.onProcessFinish(this);
	}

}