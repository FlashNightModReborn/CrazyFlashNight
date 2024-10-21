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

import org.as2lib.env.event.EventListener;
import org.as2lib.env.event.impulse.Impulse;

/**
 * Interface for listening to a Impulse.
 * 
 * <p>{@link Impulse} allows two ways of listening to a certain impulse. {@link
 * Executable} with {@link Impulse#connectExecutable} allows in some cases only
 * bad readable usages.
 * 
 * <p>With {@link Impulse#addListener} its possible to add a listener typed as
 * {@code ImpulseListener}. The method {@link #onImpulse} will be called on each
 * impulse.
 *
 * @author Martin Heidegger
 * @version 1.0
 */
interface org.as2lib.env.event.impulse.ImpulseListener extends EventListener {
	
	/**
	 * Method to be executed on a impulse.
	 * 
	 * @param impulse {@link Impulse] where the listener was added.	 */
	public function onImpulse(impulse:Impulse):Void;
}