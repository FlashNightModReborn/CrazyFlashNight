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
import org.as2lib.env.except.IllegalStateException;

/**
 * {@code Stopwatch} stops the time.
 * 
 * <p>Instantiate this class as follows:
 * <code>
 *   import org.as2lib.util.StopWatch;
 *   var stopWatch:StopWatch = new StopWatch();
 * </code>
 * 
 * <p>This will create a still standing stopwatch. You can start and stop the 
 * stopwatch to record time as you please.
 * 
 * <code>
 *   stopWatch.start();
 *   // Do something
 *   stopWatch.stop();
 * </code>
 * 
 * <p>The recored time is available in milliseconds and seconds.
 * 
 * <code>
 *   trace(stopWatch.getTimeInMilliSeconds() + " ms");
 *   trace(stopWatch.getTimeInSeconds() + " s");
 * </code>
 * 
 * @author Martin Heidegger
 */
class org.as2lib.util.StopWatch extends BasicClass {
	
	/** Starttime of the last start */
	private var started:Boolean = false;
	
	/** Holder for all start-time-keys */
	private var startTimeKeys:Array;
	
	/** Holder for all stop-time-keys */
	private var stopTimeKeys:Array;
	
	/** Total recored run time. */
	private var runTime:Number = 0;
	
	/** 
	 * Constructs a new {@code StopWatch} instance.
	 */
	public function StopWatch(Void) {
		reset();
	}
	
	/**
	 * Starts the time recording process.
	 * 
	 * @throws IllegalStateException if the stopwatch has already been started
	 */
	public function start(Void):Void {
		if(hasStarted()) {
			throw new IllegalStateException("Stopwatch is already started.", this, arguments);
		}
		started = true;
		startTimeKeys.push(getTimer());
	}
	
	/**
	 * Stops the time recording process if the process has been started before.
	 * 
	 * @throws IllegalStateException if the stopwatch has not been already started
	 */
	public function stop(Void):Void {
		if (!hasStarted()) {
			throw new IllegalStateException("Stopwatch isn't started yet.", this, arguments);
		}
		var stopTime:Number = getTimer();
		stopTimeKeys[startTimeKeys.length-1] = stopTime;
		started = false;
	}
	
	/**
	 * Returns whether this stopwatch has been started.
	 * 
	 * @return {@code true} if this stopwatch has been started else {@code false}
	 */
	public function hasStarted(Void):Boolean {
		return started;
	}
	
	/**
	 * Resets the stopwatch total running time.
	 */
	public function reset(Void):Void {
		startTimeKeys = new Array();
		stopTimeKeys = new Array();
		started = false;
	}
	
	/**
	 * Calculates and returns the elapsed time in milliseconds.
	 * 
	 * <p>This stopwatch will not be stopped by calling this method. If this stopwatch
	 * is still running it takes the current time as stoptime for the result.
	 * 
	 * @return the elapsed time in milliseconds
	 * @see #getTimeInSeconds
	 */
	public function getTimeInMilliSeconds(Void):Number {
		if (hasStarted()) {
			stopTimeKeys[startTimeKeys.length-1] = getTimer();
		}
		var result:Number = 0;
		for (var i:Number = 0; i < startTimeKeys.length; i++) {
			result += (stopTimeKeys[i] - startTimeKeys[i]);
		}
		return result;		
	}
	
	/**
	 * Calculates and returns the elapsed time in seconds.
	 * 
	 * <p>This stopwatch will not be stopped by calling this method. If this stopwatch
	 * is still running it takes the current time as stoptime for the result.
	 * 
	 * @return the elapsed time in seconds
	 * @see #getTimeInMilliSeconds.
	 */
	public function getTimeInSeconds(Void):Number {
		return getTimeInMilliSeconds()/1000;
	}
	
	/**
	 * Generates a string representation of this stopwatch that includes all start and
	 * stop times in milliseconds.
	 * 
	 * @return the string representation of this stopwatch
	 */
	public function toString():String {
		var result:String;
		result = "\n------- [STOPWATCH] -------";
		var i:Number;
		for(i=0; i<startTimeKeys.length; i++) {
			result += "\n started["+startTimeKeys[i]+"ms] stopped["+stopTimeKeys[i]+"ms]";
		}
		if(i==0) {
			result += "\n never started.";
		} else {
			result += "\n\n total runnning time: "+getTimeInMilliSeconds()+"ms";
		}
		result += "\n---------------------------\n";
		return result;
	}
	
}