
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

/**
 * {@code EventDistributorControl} controls a distributor to distribute events to
 * listeners in a compiler-safe manner.
 * 
 * <p>You can get a distributor via the {@link #getDistributor} method that can be
 * casted to your listener type. This enables you to distribute events in a
 * compiler-safe manner.
 * 
 * @author Simon Wacker
 * @author Martin Heidegger
 */
interface org.as2lib.env.event.distributor.EventDistributorControl extends EventListenerSource {
	
	/**
	 * Returns the typed distributor to distribute the event to all added listeners.
	 * 
	 * <p>The returned distributor can be casted to the type all added listeners have.
	 * You can then invoke the event method on it to distribute it to all added
	 * listeners. This event distribution approach has the advantage of proper
	 * compile-time checking.
	 *
	 * <p>Note that the type of the returned distributor depends on the concrete
	 * implementation of this interface. Most implementations will probably expect the
	 * listener type to be passed-in on construction.
	 * 
	 * @return the distributor to distribute the event
	 */
	public function getDistributor(Void);
	
	/**
	 * Returns the type of listeners this distributor expects. This is also the type of
	 * the distributor returned by the {@link #getDistributor} method.
	 * 
	 * @return the type of the distributor and listeners	 */
	public function getType(Void):Function;
	
}