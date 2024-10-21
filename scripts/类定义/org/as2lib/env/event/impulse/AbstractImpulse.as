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

import org.as2lib.app.exec.Executable;
import org.as2lib.app.exec.Call;
import org.as2lib.core.BasicClass;
import org.as2lib.env.event.impulse.ImpulseListener;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.util.ArrayUtil;

/**
 * {@code AbstractImpulse} is a helper class that contains shared API to be used
 * by different {@link org.as2lib.env.event.impulse.Impulse} Implementations.
 * 
 * @author Martin Heidegger
 * @version 1.0 */
class org.as2lib.env.event.impulse.AbstractImpulse extends BasicClass {
	
	/** Broadcaster for connected executables */
	private var execBroadcaster:Object;
	
	/** Broadcaster for connected impulselisteners */
	private var impulseBroadcaster:Object;
	
	/**
	 * Constructs a new impulse.	 */
	public function AbstractImpulse() {
		// Creation of ASBroadcasters for the events.
		execBroadcaster = new Object();
		AsBroadcaster.initialize(execBroadcaster);
		impulseBroadcaster = new Object();
		AsBroadcaster.initialize(impulseBroadcaster);
	}	
	
	/**
	 * Connects a executable as listener to the frame execution.
	 * 
	 * @param exe Executable to be added as listener
	 */
	public function connectExecutable(exe:Executable):Void {
		addListener(exe);
	}
	
	/**
	 * Adds a list of listeners to listen to the impulse events.
	 * 
	 * @param listeners List of listeners to be added.
	 * @throws IllegalArgumentException if a listener could not be added.	 */
	public function addAllListeners(listeners:Array):Void {
		for(var i=0; i<listeners.length; i++) {
			addListener(listeners[i]);
		}
	}
	
	/**
	 * Method to add any supported listener to the FrameImpulse.
	 * 
	 * <p>Adds a listener to the Impulse. The listener will be informed on
	 * each frame change.
	 * 
	 * <p>Note: If a certain listener implements more than one supported event it
	 * will listen to all of them at one execution (execute, onFrameImpulse,
	 * onImpulse).
	 * 
	 * @param listener to be added.
	 * @throws IllegalArgumentException if the listener doesn't match any type.
	 */
	public function addListener(listener):Void {
		var notAdded:Boolean = true;
		if(listener instanceof Executable) {
			execBroadcaster.addListener(listener);
			notAdded = false;
		}
		if(listener instanceof ImpulseListener) {
			impulseBroadcaster.addListener(listener);
			notAdded = false;
		}
		if(notAdded) {
			throw new IllegalArgumentException("Passed listener doesn't match"
				+" any possible listener type.", this
				, arguments);
		}
	}
	
	/**
	 * Methode to add a {@link ImpulseListener} as listener to the Impulse. 
	 * 
	 * <p>Some parts of the code get better readable if you use a complete
	 * clear name like "onImpulse" to define your code. With
	 * {@code .addImpulseListener} you can add a listener that specially
	 * listens only to this naming of the same event that will be executed as
	 * "execute".
	 * 
	 * <p>Example:
	 * 
	 * <p>Listener:
	 * <code>
	 *   import org.as2lib.env.event.impulse.ImpulseListener;
	 *   import org.as2lib.env.event.impulse.Impulse;
	 *   
	 *   class TraceTimeImpulseListener implements ImpulseListener {
	 *     public function onImpulse(impulse:Impulse):Void {
	 *       trace("Impulse executed at "+getTimer());
	 *     }
	 *   }
	 * </code>
	 * 
	 * <p>Usage:
	 * <code>
	 *   import org.as2lib.env.event.impulse.FrameImpulse;
	 *   
	 *   var impulse:FrameImpulse = FrameImpulse.getInstance();
	 *   impulse.addImpulseListener(new TraceTimeImpulseListener());
	 * </code>
	 * 
	 * @param listener Listener to be added.
	 */
	public function addImpulseListener(listener:ImpulseListener):Void {
		addListener(listener);
	}
	
	/**
	 * Removes a listener of any type that might be added.
	 * 
	 * @param listener Listener to be removed.
	 * @throws IllegalArgumentException if you pass a listener that is of a
	 *         illegal type.
	 */
	public function removeListener(listener):Void {
		var notRemoved:Boolean = true;
		if(listener instanceof Executable) {
			execBroadcaster.removeListener(listener);
			notRemoved = false;
		}
		if(listener instanceof ImpulseListener) {
			impulseBroadcaster.removeListener(listener);
			notRemoved = false;
		}
		if(notRemoved) {
			throw new IllegalArgumentException("Passed listener doesn't match"
				+" any possible listener type.", this
				, arguments);
		}
	}
	
	/**
	 * Disconnects a {@link Executable} from listening to the impulse.
	 * 
	 * @param exe {@link Executable} to disconnect.
	 */
	public function disconnectExecutable(exe:Executable):Void {
		removeListener(exe);
	}
		
	/**
	 * Removes a {@link ImpulseListener} from listening to the impulse.
	 * 
	 * @param listener {@link ImpulseListener} to remove from listening.
	 */
	public function removeImpulseListener(listener:ImpulseListener):Void {
		removeListener(listener);
	}
	
	/**
	 * Removes all added Listeners from listening to the impulse.	 */
	public function removeAllListeners(Void):Void {
		removeAllImpulseListeners();
		disconnectAllExecutables();
	}
	
	/**
	 * Removes all added {@link ImpulseListener}s from listening to the impulse.	 */
	public function removeAllImpulseListeners(Void):Void {
		var c:Call = new Call(this, removeListener);
		c.forEach(impulseBroadcaster._listeners);
	}
	
	/**
	 * Disconnects all connected {@link Executable}s from the impulse.
	 */
	public function disconnectAllExecutables(Void):Void {
		var c:Call = new Call(this, removeListener);
		c.forEach(execBroadcaster._listeners);
	}
	
	
	/**
	 * Getter for the list of all added listeners.
	 * 
	 * <p>This method returns a list of all listeners added with eihter
	 * {@link #connectExecutable}, {@link #addListener} or
	 * {@link #addImpulseListener}
	 * 
	 * @return List that contains all added listeners.
	 */
	public function getAllListeners(Void):Array {
		var result:Array = new Array();
		result = result.concat(getAllConnectedExecutables());
		result = result.concat(getAllImpulseListeners());
		return result;
	}
	
	/**
	 * Getter for the list of all connected {@link Executable}s.
	 * 
	 * @return List that contains all connected {@link Executable}s.
	 */
	public function getAllConnectedExecutables(Void):Array {
		return execBroadcaster._listeners.concat();
	}
	
	/**
	 * Getter for the list of all added {@link ImpulseListener}s.
	 * 
	 * @return List that contains all added {@link ImpulseListener}s.
	 */
	public function getAllImpulseListeners(Void):Array {
		return impulseBroadcaster._listeners.concat();
	}
	
	/**
	 * Adds a list of {@link ImpulseListener}s as listener to the events.
	 * 
	 * @param listeners List of all listeners to add.
	 * @throws IllegalArgumentException if one listener didn't match to any listener type.
	 * @see #addListener
	 */
	public function addAllImpulseListeners(listeners:Array):Void {
		for(var i=0; i<listeners.length; i++) {
			addListener(listeners[i]);
		}
	}
	
	/**
	 * Connects a list of {@link Executables}s to the impulse.
	 * 
	 * @param listeners List of all listeners to add.
	 * @throws IllegalArgumentException if one listener didn't match to any listener type.
	 * @see #addListener
	 */
	public function connectAllExecutables(executables:Array):Void {
		for(var i=0; i<executables.length; i++) {
			addListener(executables[i]);
		}
	}
	
	/**
	 * Validates if a certain listener of any type is currently added to the
	 * impulse.
	 * 
	 * @param listener Listener to be validated.
	 * @return {@code true} if the certain executable is connected.
	 * @see #addListener
	 */
	public function hasListener(listener):Boolean {
		if (hasImpulseListener(listener)) {
			return true;
		}
		if (isExecutableConnected(listener)) {
			return true;
		}
		return false;
	}	
	
	/**
	 * Validates if a certain {@link ImpulseListener} is currently added to the
	 * impulse.
	 * 
	 * @param listener {@link ImpulseListener} to be validated.
	 * @return {@code true} if the certain executable is connected.
	 */
	public function hasImpulseListener(listener:ImpulseListener):Boolean {
		return ArrayUtil.contains(impulseBroadcaster._listeners, listener);
	}
	
	/**
	 * Validates if a certain {@link Executable} is currently connected to the
	 * impulse.
	 * 
	 * @param exe {@link Executable} to be validated.
	 * @return {@code true} if the certain executable is connected.
	 */
	public function isExecutableConnected(exe:Executable):Boolean {
		return ArrayUtil.contains(execBroadcaster._listeners, exe);
	}
	
}