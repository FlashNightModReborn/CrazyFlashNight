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
import org.as2lib.env.event.EventListenerSource;
import org.as2lib.env.event.impulse.ImpulseListener;

/**
 * {@code Impulse} is a definition for events that gets executed periodically.
 * 
 * <p>Periodical events could be frame executions, seconds, hours or dates.
 * {@code Impulse} allows to seperate the certain kind of Impulse from the
 * execution code.
 * 
 * <p>The {@code Impulse} executes {@link Executable#execute} on each impulse to
 * the connected executables.
 * 
 * Example:
 * <code>
 *   import org.as2lib.env.event.impulse.Impulse;
 *   import org.as2lib.env.event.impulse.FrameImpulse;
 *   import org.as2lib.app.exec.Call;
 * 
 *   function test(impulse:Impulse) {
 *     trace(impulse+" executed at "+getTimer()+"ms");
 *   }
 * 
 *   var impulse:Impulse = FrameImpulse.getInstance();
 *   impulse.connectExecutable(new Call(this, test));
 * </code>
 * 
 * <p>Additionally its possible to work with the impulse as EventListenerSource.
 * With you can add {@link ImpulseListener} implementations
 * as listener to the code.
 * 
 * Listener:
 * <code>
 *   import org.as2lib.env.event.impulse.ImpulseListener;
 *   import org.as2lib.env.event.impulse.Impulse;
 *   
 *   class TraceImpulseListener implements ImpulseListener {
 *      public function onImpulse(impulse:Impulse):Void {
 *      	trace(impulse+" executed at "+getTimer()+"ms");
 *      }
 *   }
 * </code>
 * 
 * Test:
 * <code>
 *   import org.as2lib.env.event.impulse.Impulse;
 *   import org.as2lib.env.event.impulse.FrameImpulse;
 *   
 *   var impulse:Impulse = FrameImpulse.getInstance();
 *   impulse.addImpulseListener(new TraceImpulseListener());
 * </code>
 * 
 * <p>The {@link #addListener} referes to eighter {@connectExecutable} or to 
 * {@addImpulseListener} depending to what kind of listener you pass. If you 
 * pass a not-matching impulse it will throw a
 * {@link org.as2lib.env.except.IllegalArgumentException}.
 * 
 * @author Martin Heidegger
 * @version 1.1
 */
interface org.as2lib.env.event.impulse.Impulse extends EventListenerSource {
	
	/**
	 * Adds a {@link ImpulseListener} for listening to the onImpulse event to
	 * the Impulse.
	 * 
	 * @param listener Listener to be added.	 */
	public function addImpulseListener(listener:ImpulseListener):Void;
	
	/**
	 * Removes a added {@link ImpulseListener} from listening to the onImpulse
	 * event.
	 * 
	 * <p>If the certain listener also implements other event types it will also
	 * be remove from listening to those events.
	 * 
	 * @param listener Listener to be added.	 */
	public function removeImpulseListener(listener:ImpulseListener):Void;
	
	/**
	 * Adds a list of {@link ImpulseListener}s as listener to the events.
	 * 
	 * @param listeners List of all listener to add.
	 * @throws IllegalArgumentException if one listener didn't match to any listener type.
	 * @see #addListener
	 */
	public function addAllImpulseListeners(listener:Array):Void;
	
	/**
	 * Getter for the list of all added {@link ImpulseListener}s.
	 * 
	 * @return List that contains all added listeners.
	 */
	public function getAllImpulseListeners(Void):Array;
	
	/**
	 * Checks if the {@code listener} has been added.
	 * 
	 * @param listener Listener to be checked if it has been added.
	 * @return True if the certain listener has been added.
	 */
	public function hasImpulseListener(listener:ImpulseListener):Boolean;
	
	/**
	 * Removes all added {@link ImpulseListener}s from listening to any event.
	 */
	public function removeAllImpulseListeners(Void):Void;
	
	/**
	 * Connect a certain executable to listen to the continous event.
	 * 
	 * @param executable {@link Executable} that should be connected	 */
	public function connectExecutable(executable:Executable):Void;
	
	/**
	 * Connects a list of {@link Executable}s to be executed on the continous event.
	 * 
	 * @param executables List of {@link Executable}s to be added.
	 */
	public function connectAllExecutables(executables:Array):Void;
	
	/**
	 * Getter for the list of all connected {@link Executable}s.
	 * 
	 * @return List that contains all connected executables.
	 */
	public function getAllConnectedExecutables(Void):Array;
	
	/**
	 * Disconnect a certain executable from listening to the {@code Impulse}.
	 * 
	 * @param executable Executable that should be disconnected	 */
	public function disconnectExecutable(executable:Executable):Void;
	
	/**
	 * Checks if a certain {@link Executable} has been added as listener.
	 * 
	 * @param executable {@link Executable} to be checked if it has been added.
	 * @return True if the certain listener has been added.
	 */
	public function isExecutableConnected(executable:Executable):Boolean;
	
	/**
	 * Method to disconnect all connected Executables
	 */
	public function disconnectAllExecutables(Void):Void;
	
}