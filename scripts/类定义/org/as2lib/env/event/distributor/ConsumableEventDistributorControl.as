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

import org.as2lib.env.event.distributor.EventDistributorControl;

/**
 * {@code ConsumableEventDistributorControl} marks the {@code EventDistributorControl}
 * interface as consumable.
 * 
 * <p>A distributor that implements this interface allows for consumable events.
 * This means that the event distribution is stopped as soon as an event is
 * consumed.
 * 
 * <p>An event is consumed if a listener's event method returns {@code true}. If it
 * returns nothing, {@code null} or {@code undefined} or {@code false} the event
 * will further be distributed.
 *
 * @author Simon Wacker
 * @author Martin Heidegger
 */
interface org.as2lib.env.event.distributor.ConsumableEventDistributorControl extends EventDistributorControl {
	
}