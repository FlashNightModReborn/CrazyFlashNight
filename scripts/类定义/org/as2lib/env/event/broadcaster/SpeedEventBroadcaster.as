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

import org.as2lib.env.event.SimpleEventListenerSource;
import org.as2lib.env.event.EventExecutionException;
import org.as2lib.env.event.broadcaster.EventBroadcaster;
import org.as2lib.env.event.broadcaster.EventInfo;

/**
 * {@code SpeedEventBroadcaster} broadcasts events to listeners in the fastest way
 * possible. It does therefore not support any kind of special functionalities like
 * consuming events.
 * 
 * @author Martin Heidegger
 * @author Simon Wacker
 */
class org.as2lib.env.event.broadcaster.SpeedEventBroadcaster extends SimpleEventListenerSource implements EventBroadcaster {	

	/** The wrapped {@code AsBroadcaster} needed for actual distribution. */
	private var b:Object;
	
	/**
	 * Constructs a new {@code SpeedEventBroadcaster} instance.
	 * 
	 * @param listeners (optional) an array of listeners to populate this broadcaster
	 * with
	 */
	public function SpeedEventBroadcaster(listeners:Array) {
		this.b = new Object();
		AsBroadcaster.initialize(this.b);
		this.b._listeners = this.l;
		if (listeners) {
			addAllListeners(listeners);
		}
	}
	
	/**
	 * Removes all added listeners.
	 */
	public function removeAllListeners(Void):Void {
		super.removeAllListeners();
		this.b._listeners = this.l;
	}
	
	/**
	 * Dispatches the passed-in {@code eventInfo} to all added listeners.
	 * 
	 * <p>The name returned by the {@link EventInfo#getName} method of the passed-in
	 * {@code eventInfo} is used as event method name to invoke on the listeners.
	 *
	 * <p>The passed-in {@code eventInfo} is also passed as parameter to the listeners'
	 * event methods.
	 * 
	 * @param eventInfo the event to dispatch to all listeners
	 * @throws EventExecutionException if a listener threw an exception during
	 * dispatching
	 */
	public function dispatch(eventInfo:EventInfo):Void {
		if (eventInfo) {
			if (this.l.length > 0) {
				var n:String = eventInfo.getName();
				try {
					if (n) this.b.broadcastMessage(n, eventInfo);
				} catch (e) {
					// braces are around "new EventExecutionException..." because otherwise it wouldn't be MTASC compatible
					throw (new EventExecutionException("Unexpected exception was thrown during dispatch of event [" + n + "] with event info [" + eventInfo + "].", this, arguments)).initCause(e);
				}
			}
		}
	}
	
}