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
import org.as2lib.env.event.broadcaster.EventInfo;

/**
 * {@code EventBroadcaster} dispatches events to all added listeners with the help
 * of an {@link EventInfo}.
 * 
 * @author Martin Heidegger
 * @author Simon Wacker
 */
interface org.as2lib.env.event.broadcaster.EventBroadcaster extends EventListenerSource {
	
	/**
	 * Dispatches the passed-in {@code event} to all added listeners.
	 * 
	 * <p>The name returned by the {@link EventInfo#getName} method of the passed-in
	 * {@code event} is used as event method name to invoke on the listeners.
	 *
	 * <p>The passed-in {@code event} is also passed as parameter to the listeners'
	 * event methods.
	 * 
	 * @param event the event to dispatch to all listeners
	 * @throws EventExecutionException if a listener threw an exception during
	 * dispatching
	 */
	public function dispatch(event:EventInfo):Void;
	
}