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

import org.as2lib.aop.Pointcut;

/**
 * {@code CompositePointcut} is a composition of multiple pointcuts. In common
 * implementations it combines the {@code captures} methods of multiple pointcuts in a
 * specific logic, like AND or OR logic.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.aop.pointcut.CompositePointcut extends Pointcut {
	
	/**
	 * Adds a new pointcut to the list of pointcuts.
	 *
	 * @param pointcut the pointcut to add
	 */
	public function addPointcut(pointcut:Pointcut):Void;
	
	/**
	 * Returns all added pointcuts.
	 * 
	 * @return all added pointcuts
	 */
	public function getPointcuts(Void):Array;
	
}