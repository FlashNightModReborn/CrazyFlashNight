﻿/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.env.event.broadcaster.EventInfo;

/**
 * {@code ConsumableEventInfo} allows for consuming events.
 *
 * <p>You can consume an event using the {@link #consume} method. The method
 * {@link #isConsumed} checks whether this event info is already consumed.
 * 
 * @author Martin Heidegger
 * @author Simon Wacker
 */
interface org.as2lib.env.event.broadcaster.ConsumableEventInfo extends EventInfo {
	
	/**
	 * Marks this event as consumed.
	 */
	public function consume(Void):Void;
	
	/**
	 * Returns whether this event is consumed.
	 *
	 * @return {@code true} is this event is consumed else {@code false}
	 */
	public function isConsumed(Void):Boolean;
	
}