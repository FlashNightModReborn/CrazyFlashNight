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

import org.as2lib.core.BasicInterface;

/**
 * {@code Aspect} represents an aspect in an Aspect-Oriented Programming language. An
 * aspect's sole responsibility is to group varies advices in a logical sense.
 * Convenient implementations of this interface also offer support to easily add
 * advices.
 *
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000041.php">Terms and AspectJ</a>
 */
interface org.as2lib.aop.Aspect extends BasicInterface {
	
	/**
	 * Returns the advices that were added externally or internally to this aspect.
	 * These advices will be used for the weaving process.
	 * 
	 * @returns the advices used by the weaver
	 */
	public function getAdvices(Void):Array;
	
}