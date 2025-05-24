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


/**
 * {@code BasicInterface} is the basic interface for each class in the As2lib
 * Framework.
 * 
 * <p>It is recommended to always implement this interface in the classes of your
 * own project but it is not a necessity. You can use all functionalities of the
 * As2lib Framework without implementing it.
 * 
 * <p>It enables you to call the {@link #toString} method on instances that have
 * been casted to interfaces.
 * 
 * <p>The default implementation {@code BasicClass} offers an enhanced {@code toString}
 * method implementation that returns a better string representation than the default
 * {@code Object#toString} method of Flash.
 *
 * @author Simon Wacker
 * @author Martin Heidegger
 * @author Michael Hermann
 * @see org.as2lib.core.BasicClass
 */
interface org.as2lib.core.BasicInterface {
	 
	/**
	 * Returns the string representation of this instance.
	 *
	 * @return the string representation of this instance
	 */
	public function toString():String;
	
}