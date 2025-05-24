﻿
/*
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

import org.as2lib.core.BasicInterface;
import org.as2lib.env.event.distributor.EventDistributorControl;

/**
 * {@code EventDistributorControlFactory} creates instances of type
 * {@link EventDistributorControl}
 * 
 * @author Martin Heidegger
 */
interface org.as2lib.env.event.distributor.EventDistributorControlFactory extends BasicInterface {
	
	/**
	 * Creates a new instance of type {@code EventDistributorControl}
	 * 
	 * @param type the distributor and listener type of the created event distributor
	 * control
	 * @return an event distributor control that is configured with the given
	 * {@code type}
	 */
	public function createEventDistributorControl(type:Function):EventDistributorControl;
	
}