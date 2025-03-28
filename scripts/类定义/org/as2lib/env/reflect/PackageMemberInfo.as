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

import org.as2lib.env.reflect.MemberInfo;

/**
 * {@code PackageMemberInfo} is the super interface for members of packages.
 * 
 * <p>Members of packages are classes, interfaces and packages themselves.
 * 
 * <p>Accoring to this classes and interfaces can be seen as leafs in a compositional
 * structure and packages as composites. This design pattern is known under the name
 * Composite.
 *
 * @author Simon Wacker
 */
interface org.as2lib.env.reflect.PackageMemberInfo extends MemberInfo {
	
	/**
	 * Returns the fully qualified name of this package member.
	 * 
	 * <p>A fully qualified name is a name that consists of the member's name as well
	 * as its preceding package structure.
	 *
	 * @return the fully qualified name of this package member
	 */
	public function getFullName(Void):String;
	
}