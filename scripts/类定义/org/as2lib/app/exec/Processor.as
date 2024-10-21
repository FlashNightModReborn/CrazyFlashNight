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

import org.as2lib.env.event.EventSupport;
import org.as2lib.env.event.impulse.FrameImpulse;
import org.as2lib.env.event.impulse.FrameImpulseListener;
import org.as2lib.util.ArrayUtil;
import org.as2lib.app.exec.StepByStepProcess;

/**
 * {@code Processor} executes any {@code StepByStepProcess} for step based code execution.
 * 
 * <p>MM Flash Player has got a time limit for the execution of code. {@code Processor}
 * allows to seperate code into steps.
 * 
 * <p>It executes every step of a added {@code StepByStepProcess}.
 * If the {@code StepByStepProcess} reaches the (@link #MAX_EXECUTION_TIME}
 * limit during the exeuction, the {@code Processor} pauses for one frame as
 * workaround for this time limitation.
 * 
 * <p>Within the pause, anything may happen. It may require a complex implemnetation
 * strategy within the {@code StepByStepProcess}.
 * 
 * <p>{@code Processor} observes {@link FrameImpulse} if any {@code StepByStepProcess}
 * has to be executed. It automatically removes itself as observer if all 
 * processes have finished.
 * 
 * <p>{@code Processor} is built as singleton. It is possible to access it by
 * {@code Processor.getInstance()}.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.app.exec.Processor extends EventSupport implements FrameImpulseListener {
	
	/** Time until pause of the execution. */
	public static var MAX_EXECUTION_TIME:Number = 1500;
	
	/** Instance of the used {@code Processor} in {@code getInstance}. */
	private static var instance:Processor;
	
	/**
	 * Singleton - returns the default instance of the {@code Processor}
	 * 
	 * @return instance of the {@code Processor}
	 */
	public static function getInstance(Void):Processor {
		if (!instance) {
			instance = new Processor();
		}
		return instance;
	}
	
	/** Flag if the processor is running (connected to the FrameImpulseListener) */
	private var running:Boolean = false;
	
	/** Current process to handle */
	private var current:Number;
	
	/** List of all processes currently executing */
	private var processList:Array;
	
	/**
	 * Constructs a new {@code Processor} instance.
	 */
	private function Processor(Void) {
		processList = new Array();
	}
	
	/**
	 * Adds a new {@code StepByStepProcess} to the execution list.
	 * 
	 * <p>It is possible that a {@code StepByStepProcess} can be added twice.
	 * 
	 * <p>The {@code Processor} will automatically awake from stand-by.
	 * 
	 * @param p {@code StepByStepProcess} to be added
	 */
	public function addStepByStepProcess(p:StepByStepProcess):Void {
		processList.push(p);
		awakeFromStandBy();
	}
	
	/**
	 * Removes all occurances of {@code StepByStepProcess}.
	 * 
	 * @param p {@code StepByStepProcess} to be removed
	 */
	public function removeStepByStepProcess(p:StepByStepProcess):Void {
		var formerLength = processList.length;
		var result:Array = ArrayUtil.removeElement(processList, p);
		var i:Number = result.length;
		// Shift the current cursor
		// Backward processing to ensure the correct size.
		while (--i-(-1)) {
			if (current > result[i]) {
				current --;
			}
		}
	}
	
	/**
	 * Restart listening to the {@code FrameImpulse}
	 */
	private function awakeFromStandBy(Void):Void {
		if (!running) {
			running = true;
			current = 0;
			FrameImpulse.getInstance().addFrameImpulseListener(this);
		}
	}
	
	/**
	 * Stop listening to the {@code FrameImpulse}.
	 */
	private function gotoStandBy(Void):Void {
		running = false;
		FrameImpulse.getInstance().removeFrameImpulseListener(this);
	}
	
	/**
	 * Handling of the event of {@link FrameImpulse}.
	 * 
	 * @param impulse {@code FrameImpulse} that executes the impulse
	 */
	public function onFrameImpulse(impulse:FrameImpulse):Void {
		var startTime:Number = getTimer();
		while (current < processList.length) {
			
			var currentProcessable:StepByStepProcess = processList[current];
			while (!currentProcessable.hasFinished()) {
				
				if (startTime+MAX_EXECUTION_TIME < getTimer() || currentProcessable.isPaused()) {
					return;
				}
				
				currentProcessable.nextStep();
			}
			current ++;
		}
		processList = new Array();
		gotoStandBy();
	}

}