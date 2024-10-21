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

import org.as2lib.env.overload.Overload;
import org.as2lib.app.exec.AbstractProcess;
import org.as2lib.app.exec.Call;
import org.as2lib.app.exec.Executable;
import org.as2lib.app.exec.ForEachExecutable;
import org.as2lib.env.event.impulse.FrameImpulse;

/**
 * {@code Timeout} works as delayed execution of a executable.
 * 
 * <p>As {@code Timeout} implements {@link Executable} it works like a usual
 * executable and can be started with {@link #execute}. 
 * 
 * <p>As {@code Timeout} implements {@link Process} its possible to handle it
 * as process.
 * 
 * <p>{@code Timeout} works framebased, that means you have to define the delay 
 * in number of frames.
 * 
 * <p>Due to the definition of Call all arguments passed-in in {@link #execute}
 * will be passed to the connected executable
 * 
 * Example for a direct execution:
 * <code>
 *   import org.as2lib.app.exec.Timeout;
 *   import org.as2lib.app.exec.Call;
 * 
 *   Timeout.timeout(new Call(myObj, myMethod), 20, ["1", "2"]); 
 * </code>
 * 
 * Example for a controlable usage:
 * <code>
 *   import org.as2lib.app.exec.Timeout;
 *   import org.as2lib.app.exec.Call;
 * 
 *   var call:Call = new Call(myObj, myMethod);
 *   var frames:Number = 20;
 *   var t:Timeout = new Timeout(call, frames);
 *   t.execute("argument 1", "argument 2");
 * </code>
 * 
 * @author Martin Heidegger
 * @version 1.0
 * @see Executable#execute */
class org.as2lib.app.exec.Timeout extends AbstractProcess implements ForEachExecutable {
	
	/** Connected Executable */
	private var exe:Executable;
	
	/** Amount of frames until execution (delay) */
	private var frames:Number;
	
	/** Amount of listened frames */
	private var executed:Number;
	
	/**
	 * List of the targets (arguments) for the execution.
	 * used in {@link #forEach}.
	 */
	private var target:Array;
	
	/** Call to the onEnterFrame listener */
	private var timeCall:Call;
	
	/**
	 * Simplyfier for the execution of a timeout.
	 * 
	 * <p>Allows creation and execution of a {@code Timeout} with one call.
	 * 
	 * @param exe Executable to excute after a delay
	 * @param frames Amout of frames during the end of the execution
	 * @param args Arguments to be passed at execution	 */
	public static function setTimeout(exe:Executable, frames:Number, args:Array) {
		var t:Function = eval("th"+"is");
		var o = new t(exe, frames).execute(args);
	}
	
	/**
	 * Creates a new {@code Timeout} instance.
	 * 
	 * @overload #setExecutable
	 * @overload #setExecutableByObjectAndFunction	 */
	public function Timeout() {
		timeCall = new Call(this, onEnterFrame);
		var o:Overload = new Overload(this);
		o.addHandler([Executable, Number], setExecutable);
		o.addHandler([Object, Function, Number], setExecutableByObjectAndFunction);
		o.forward(arguments);
	}
	
	/**
	 * Sets the connected executable.
	 * 
	 * @param exe Executable to be executed after the delay
	 * @param frames Delay in frames until execution.	 */
	public function setExecutable(exe:Executable, frames:Number):Void {
		this.exe = exe;
		this.frames = frames;
	}
	
	/**
	 * Sets the connected executable with a generated call.
	 * 
	 * @param inObject Scope of the execution
	 * @param func Method to execute
	 * @param frames Delay in frames until execution.	 */
	public function setExecutableByObjectAndFunction(inObject:Object, func:Function, frames:Number):Void {
		setExecutable(new Call(inObject, func), frames);
	}
	
	/**
	 * Starts the delay until the execution of the connected Executable.
	 * 
	 * @see #setExecutable
	 * @see #setExecutableByObjectAndFunction
	 * @see Executable#execute	 */
	public function execute() {
		executed = 1;
		if (!target) target = new Array();
		target.push(arguments);
		working = true;
		FrameImpulse.getInstance().connectExecutable(timeCall);
		return null;
	}
	
	/**
	 * Referes to execute.
	 * 
	 * <p>Implementation of {@link AbstractProcess#run} for using it as a
	 * process.	 */
	public function run(Void):Void {
		execute.apply(this, arguments);
	}
	
	/**
	 * Executed the Timeout for all iterable objects.
	 * 
	 * <p>If you execute .forEach to Timeout it will redirect content, name and
	 * the object to each execution of the connected call. 
	 * 
	 * Example:
	 * <code>
	 *   import org.as2lib.app.exec.Timeout;
	 * 
	 *   function display(content, name, inObject) {
	 *     trace("Executed: "+content+", "+name+", "+inObject+";");
	 *   }
	 *   
	 *   var t:Timeout = new Timeout(this, display, 40);
	 *   t.forEach({a:"1", b:"2", c:"3"});
	 * </code>
	 * 
	 * Delays for 40 frames:
	 * <pre>
	 * Executed: 1, a, [Object object];
	 * Executed: 2, b, [Object object];
	 * Executed: 3, c, [Object object];
	 * </pre>
	 * 
	 * @param object Object to be iterated
	 * @return null as the result isn't available yet.	 */
	public function forEach(object):Array {
		executed = 0;
		if (!target) target = new Array();
		var i:String;
		for (i in object) {
			target.push([object[i], i, object]);
		}
		execute();
		FrameImpulse.getInstance().connectExecutable(timeCall);
		return null;
	}

	/**
	 * Executed on each interval execution.	 */
	private function onEnterFrame(Void):Void {
		if (executed++ > frames) {
			finalExecution();
		}
	}
	
	/**
	 * Internal method to finish the execution.	 */
	private function finalExecution(impulse:FrameImpulse):Void {
		executed = 1;
		var i:Number;
		impulse.disconnectExecutable(timeCall);
		var oldTarget = target.concat();
		target = new Array();
		
		// Applying the execution to multiple targets (foreach)
		try {
			for (i=0; i<oldTarget.length; i++) {
				exe["execute"].apply(exe, oldTarget[i]);
			}
			finish();
		} catch(e) {
			interrupt(e);
		}
	}
}