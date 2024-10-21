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
import org.as2lib.env.event.broadcaster.ConsumableEventBroadcaster;
import org.as2lib.env.event.broadcaster.EventInfo;
import org.as2lib.env.event.broadcaster.ConsumableEventInfo;

/**
 * {@code SimpleConsumableEventBroadcaster} broadcasts an event to listeners until
 * the event has been consumed.
 *
 * <p>The dispatching of the event will be stopped as soon as the event is consumed.
 * The event can be consumed by calling the appropriate method on the
 * {@code ConsumableEventInfo} instance passed to the {@code dispatch} method and
 * from there to the appropriate event method on the listeners.
 * 
 * @author Simon Wacker
 * @author Martin Heidegger
 */
class org.as2lib.env.event.broadcaster.SimpleConsumableEventBroadcaster extends SimpleEventListenerSource implements ConsumableEventBroadcaster {
	
	/**
	 * Constructs a new {@code SimpleConsumableEventBroadcaster} instance.
	 *
	 * @param listeners (optional) an array of listeners to populate this broadcaster
	 * with
	 */
	public function SimpleConsumableEventBroadcaster(listeners:Array) {
		if (listeners) {
			addAllListeners(listeners);
		}
	}
	
	/**
	 * Dispatches the passed-in {@code eventInfo} to all listeners until the event has
	 * been consumed.
	 * 
	 * <p>The name returned by the {@link EventInfo#getName} method of the passed-in
	 * {@code eventInfo} is used as event method name to invoke on the listeners.
	 *
	 * <p>The passed-in {@code eventInfo} is also passed as parameter to the listeners'
	 * event methods.
	 *
	 * <p>The event dispatching will be stopped as soon as the event is consumed. An
	 * event can be consumed by calling the appropriate method on the passed-in
	 * {@code eventInfo} that must be, if the consumption of events shall be enabled,
	 * an instance of type {@link ConsumableEventInfo}.
	 * 
	 * @param eventInfo the event to dispatch to all listeners
	 * @throws EventExecutionException if a listener threw an exception during
	 * dispatching
	 */
	public function dispatch(eventInfo:EventInfo):Void {
		if (eventInfo) {
			var s:Number = this.l.length;
			if (s > 0) {
				var n:String = eventInfo.getName();
				if (n) {
					var i:Number;
					try {
						if (eventInfo instanceof ConsumableEventInfo) {
							var c:ConsumableEventInfo = ConsumableEventInfo(eventInfo);
							for (i = 0; i < s && !c.isConsumed(); i++) {
								this.l[i][n](eventInfo);
							}
						} else {
							for (i = 0; i < s; i++) {
								this.l[i][n](eventInfo);
							}
						}
					} catch(e) {
						// "new EventExecutionException" without braces is not MTASC compatible because of the following method call to "initCause"
						throw (new EventExecutionException("Unexpected exception was thrown during dispatch of event [" + n + "] on listener [" + this.l[i] + "] with event info [" + eventInfo + "].", this, arguments)).initCause(e);
					}
				}
			}
		}
	}
	
}