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

import org.as2lib.app.exec.Call;
import org.as2lib.env.event.impulse.AbstractImpulse;
import org.as2lib.env.event.impulse.Impulse;
import org.as2lib.env.event.impulse.FrameImpulseListener;
import org.as2lib.env.except.FatalException;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ReflectUtil;
import org.as2lib.util.ArrayUtil;

/**
 * {@code FrameImpulse} is a implementation of {@link Impulse} for a impulse
 * that gets executed at a the Frame {@code onEnterFrame} event.
 * 
 * <p>{@code FrameImpulse} supports static methods for easy connecting to a
 * FrameImpulse.
 * 
 * Note: Those methods can not be named in the same way as the public methods
 * are named because of a restriction in Macromedias compiler.
 * 
 * Example:
 * <code>
 *   import org.as2lib.app.exec.Executable;
 *   import org.as2lib.env.event.impulse.FrameImpulseListener;
 *   import org.as2lib.app.exec.FrameImpulse;
 *   
 *   class com.domain.FrameTracer implements FrameImpulseListener {
 *   
 *      private var prefix:String;
 *      
 *      private var postfix:String;
 *      
 *      public function FrameTracer(prefix:String, postfix:String) {
 *      	this.prefix = prefix;
 *      	this.postfix = postfix;
 *      	FrameImpulse.getInstance().addFrameImpulseListener(this);
 *      }
 *      
 *      public function onFrameImpulse(impulse:FrameImpulse):Void {
 *      	trace(prefix+_root._currentframe+postfix);
 *      }
 *   }
 *   
 * </code>
 * 
 * @author Martin Heidegger
 * @version 1.5 */
class org.as2lib.env.event.impulse.FrameImpulse extends AbstractImpulse implements Impulse {
	
	/** Holder for the static instance */
	private static var instance:FrameImpulse;
	
	/**
	 * Getter for a instance of a FrameImpulse.
	 * 
	 * <p>Generates a new FrameImpulse if no FrameImpulse has been set.
	 * 
	 * @return {@code FrameImpulse} instance.	 */
	public static function getInstance(Void):FrameImpulse {
		if(!instance) instance = new FrameImpulse();
		return instance;
	}
	
	/** Holder for the timeline to the FrameImpulse */
	private var timeline:MovieClip;
	
	/** 
	 * Flag if the timeline is generated and should be destroyed after
	 * replacement.	 */
	private var timelineIsGenerated:Boolean;
	
	/** Broadcaster for connected FrameImpulseListener's */
	private var frameImpulseBroadcaster:Object;
	
	/**
	 * Creates a new FrameImpulse instance.
	 * 
	 * @param timeline Timeline to be used - see: {@link #setTimeline}	 */
	private function FrameImpulse(timeline:MovieClip) {
		frameImpulseBroadcaster = new Object();
		AsBroadcaster.initialize(frameImpulseBroadcaster);
		setTimeline(timeline);
	}
		
	/**
	 * Sets a new Timeline as main timeline for the MovieClip.
	 * 
	 * @param timeline Timeline to be used for the frame event.
	 * @throws IllegalArgumentException if onEnterFrame has already been used in the timeline.	 */
	public function setTimeline(timeline:MovieClip):Void {
		var e:Object = execBroadcaster;
		var i:Object = impulseBroadcaster;
		var f:Object = frameImpulseBroadcaster;
		var that:Impulse = this;
		if (timeline != null) {
			if (timeline.onEnterFrame === undefined) {
				
				if (this.timeline) {
					if(timelineIsGenerated) {
						this.timeline.removeMovieClip();
					}
					delete this.timeline.onEnterFrame;
					timelineIsGenerated = false;
				}
				
				this.timeline = timeline;
				timeline.onEnterFrame = function() {
					e.broadcastMessage("execute", that);
					i.broadcastMessage("onImpulse", that);
					f.broadcastMessage("onFrameImpulse", that);
				};
			} else {
				throw new IllegalArgumentException("onEnterFrame method in "
												   +timeline
												   +" has already been overwritten, its not possible to use it as Timeline for a FrameImpulse",
												   this,
												   arguments);
			}
		} else {
			timeline = null;
			getTimeline();
		}
	}
	
	/**
	 * Getter for the currently listening timeline.
	 * 
	 * <p>This method creates a new timeline in root and listenes to it if no
	 * timeline has been set.
	 * 
	 * @return Timeline that is currently used
	 * @throws FatalExeception if a Timeline could not be generated on the fly.	 */
	public function getTimeline(Void):MovieClip {
		if (!timeline) {
			var name:String = ReflectUtil.getUnusedMemberName(_root);
			if (!name) {
				throw new FatalException("Could not get a free instance name with"
				                        +" ObjectUtil.getUnusedChildName(_root),"
				                        +" to create a listenercontainer.",
				                        this,
				                        arguments);
			}
			var mc:MovieClip = _root.createEmptyMovieClip(name,
														  _root.getNextHighestDepth());
			if (mc) {
				setTimeline(mc);
			} else {
				throw new FatalException("Could not generate a timeline for "
										 +"impulse generation", this, arguments);
			}
			var timelineIsGenerated = true;
		}
		return timeline;
	}
	
	/**
	 * Method to add any supported listener to the FrameImpulse.
	 * 
	 * <p>Adds a listener to the FrameImpulse. The listener will be informed on
	 * each frame change.
	 * 
	 * <p>Example:
	 * <code>
	 *   import org.as2lib.env.event.impulse.Impulse;
	 *   import org.as2lib.env.event.impulse.FrameImpulse;
	 *  
	 *   function test(impulse:Impulse) {
	 *     trace("Test called: "+impulse+" at "+getTimer()+"ms");
	 *   }
	 * 
	 *   var impulse:Impulse = FrameImpulse.getInstance();
	 *   impulse.addListener(new Call(this, test));
	 * </code>	 * 
	 * <p>Note: If a certain listener implements more than one supported event it
	 * will listen to all of them at one execution (execute, onFrameImpulse,
	 * onImpulse).
	 * 
	 * @param listener to be added.
	 * @throws IllegalArgumentException if the listener doesn't match any type.	 */
	public function addListener(listener):Void {
		var added:Boolean = true;
		try {
			super.addListener(listener);
		} catch(e:org.as2lib.env.except.IllegalArgumentException) {
			added = false;
		}
		if (listener instanceof FrameImpulseListener) {
			frameImpulseBroadcaster.addListener(listener);
			added = true;
		}
		if (!added) {
			throw new IllegalArgumentException("Passed listener "+listener+" does not match type 'Executable', 'ImpulseListener' or 'FrameImpuseListener'", this, arguments);
		}
	}
	
	/**
	 * Methode to add a {@link FrameImpulseListener} as listener to the FrameImpulse. 
	 * 
	 * <p>Some parts of the code get better readable if you use a complete
	 * clear name like "onFrameImpulse" to define your code. With
	 * {@code .addFrameImpulseListener} you can add a listener that specially
	 * listens only to this naming of the same event that will be executed as
	 * "onImpulse" or "execute".
	 * 
	 * <p>Example:
	 * 
	 * <p>Listener:
	 * <code>
	 *   import org.as2lib.env.event.impulse.FrameImpulseListener;
	 *   import org.as2lib.env.event.impulse.FrameImpulse;
	 *   
	 *   class TraceTimeImpulseListener implements FrameImpulseListener {
	 *     public function onFrameImpulse(impulse:FrameImpulse):Void {
	 *       trace("Frameimpulse executed at "+getTimer());
	 *     }
	 *   }
	 * </code>
	 * 
	 * <p>Usage:
	 * <code>
	 *   import org.as2lib.env.event.impulse.FrameImpulse;
	 *   
	 *   var impulse:FrameImpulse = FrameImpulse.getInstance();
	 *   impulse.addFrameImpulseListener(new TraceTimeImpulseListener());
	 * </code>
	 * 
	 * @param listener Listener to be added.
	 */
	public function addFrameImpulseListener(listener:FrameImpulseListener):Void {
		addListener(listener);
	}
	
	/**
	 * Removes a listener of any type that might be added.
	 * 
	 * @param listener Listener to be removed.
	 * @throws IllegalArgumentException if you pass a listener that is of a
	 *         illegal type.	 */
	public function removeListener(listener):Void {
		var notRemoved:Boolean = false;
		try {
			super.removeListener(listener);
		} catch (e:org.as2lib.env.except.IllegalArgumentException) {
			notRemoved = true;
		}
		if (listener instanceof FrameImpulseListener) {
			frameImpulseBroadcaster.removeListener(listener);
			notRemoved = false;
		}
		if (notRemoved) {
			throw new IllegalArgumentException("Passed listener "+listener+" does not match type 'Executable', 'ImpulseListener' or 'FrameImpuseListener'", this, arguments);
		}
	}
	
	/**
 	 * Removes a {@link FrameImpulseListener} from listening to the events.
	 * 
	 * <p>The passed listener will be removed from listening to any event
	 * (not only to from listening to {@code onFrameImpulse}).
	 * 
	 * @param listener Listener to be removed.	 */
	public function removeFrameImpulseListener(listener:FrameImpulseListener):Void {
		removeListener(listener);
	}
	
	/**
	 * Getter for the list of all added listeners.
	 * 
	 * <p>This method returns a list of all listeners added with eighter
	 * {@link #connectExecutable}, {@link #addListener}
	 * {@link #addImpulseListener} or {@link #addFrameImpulseListener}
	 * 
	 * @return List that contains all added listeners.	 */
	public function getAllListeners(Void):Array {
		return super.getAllListeners().concat(getAllFrameImpulseListeners());
	}
	
	/**
	 * Getter for the list of all added {@link FrameImpulseListener}s.
	 * 
	 * @return List that contains all added {@link FrameImpulseListener}s.	 */
	public function getAllFrameImpulseListeners(Void):Array {
		return frameImpulseBroadcaster._listeners.concat();
	}
	
	/**
	 * Removes all added listeners from listening to the FrameImpulse.
	 * 
	 * @throws IllegalArgumentException if the 	 */
	public function removeAllListeners(Void):Void {
		super.removeAllListeners();
		removeAllFrameImpulseListeners();
	}
	
	/**
	 * Returns {@code true} if passed-in {@code listener} has been added.
	 * 
	 * @param listener the listener to check whether it has been added
	 * @return {@code true} if the {@code listener} has been added
	 */
	public function hasListener(listener):Boolean {
		if (hasFrameImpulseListener(listener)
			|| super.hasListener(listener)) {
			return true;
		}
		return false;
	}
	
	/**
	 * Adds a list of {@link FrameImpulseListener}s as listener to the events.
	 * 
	 * @param listeners List of all listeners to add.
	 * @throws IllegalArgumentException if one listener didn't match to any listener type.
	 * @see #addListener	 */
	public function addAllFrameImpulseListeners(listeners:Array):Void {
		for (var i:Number=0; i<listeners.length; i++) {
			addListener(listeners[i]);
		}
	}
	
	/**
	 * Removes all added {@link FrameImpulseListener}s from listening to any event.	 */
	public function removeAllFrameImpulseListeners(Void):Void {
		// As its possible that a frameimpulselistener was added as executable
		// listener they have to be removed one by one.
		var c:Call = new Call(this, removeListener);
		c.forEach(frameImpulseBroadcaster._listeners);
	}
	
	/**
	 * Checks if a certain {@link FrameImpulseListener} has been added as
	 * listener.
	 * 
	 * @param listener Listener to be checked if it has been added.
	 * @return {@code true} if the certain listener has been added.	 */
	public function hasFrameImpulseListener(listener:FrameImpulseListener):Boolean {
		return ArrayUtil.contains(frameImpulseBroadcaster._listeners, listener); 
	}
	
}