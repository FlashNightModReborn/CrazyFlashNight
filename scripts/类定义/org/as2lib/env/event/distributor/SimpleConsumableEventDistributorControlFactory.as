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

import org.as2lib.core.BasicClass;
import org.as2lib.env.event.distributor.EventDistributorControlFactory;
import org.as2lib.env.event.distributor.EventDistributorControl;
import org.as2lib.env.event.distributor.SimpleConsumableEventDistributorControl;

/**
 * {@code SimpleConsumableEventDistributorControlFactory} creates instances of class
 * {@link SimpleConsumableEventDistributorControl}.
 * 
 * @author Martin Heidegger
 */
class org.as2lib.env.event.distributor.SimpleConsumableEventDistributorControlFactory extends BasicClass implements EventDistributorControlFactory {
	
	/**
	 * Creates a new instance of class {@link SimpleConsumableEventDistributorControl}.
	 * 
	 * @param type the distributor and listener type for the new event distributor
	 * control
	 * @return an instance of class {@code SimpleConsumableEventDistributorControl} that
	 * is configured with the given {@code type}
	 */
	public function createEventDistributorControl(type:Function):EventDistributorControl {
		return new SimpleConsumableEventDistributorControl(type);
	}
	
}