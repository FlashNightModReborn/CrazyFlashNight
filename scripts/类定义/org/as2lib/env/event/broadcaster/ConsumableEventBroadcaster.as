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

import org.as2lib.env.event.broadcaster.EventBroadcaster;

/**
 * {@code ConsumableEventBroadcaster} dispatches events to all listeners with the
 * help of an {@link EventInfo} or {@link ConsumableEventInfo} until the event has
 * been consumed.
 *
 * <p>The dispatching of the event will be stopped as soon as the event is consumed.
 * The event can be consumed by calling the appropriate method on the
 * {@code ConsumableEventInfo} instance passed to the {@code dispatch} method and
 * from there to the appropriate event method on the listeners.
 * 
 * @author Martin Heidegger
 * @author Simon Wacker
 */
interface org.as2lib.env.event.broadcaster.ConsumableEventBroadcaster extends EventBroadcaster {
	
}