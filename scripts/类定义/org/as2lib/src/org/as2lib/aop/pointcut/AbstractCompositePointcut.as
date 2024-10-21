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

import org.as2lib.core.BasicClass;
import org.as2lib.aop.Pointcut;

/**
 * {@code AbstractCompositePointcut} provides implementations of methods commonly
 * needed by {@link CompositePointcut} implementation classes.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.pointcut.AbstractCompositePointcut extends BasicClass {
	
	/** All added pointcuts. */
	private var pointcuts:Array;
	
	/**
	 * Constructs a new {@code AbstractCompositePointcut} instance.
	 */
	private function AbstractCompositePointcut(Void) {
		this.pointcuts = new Array();
	}
	
	/**
	 * Adds a new pointcut to the list of pointcuts.
	 *
	 * <p>The {@code pointcut} is not added if it is {@code null} or {@code undefined}.
	 *
	 * @param pointcut the pointcut to add
	 */
	public function addPointcut(pointcut:Pointcut):Void {
		if (pointcut) this.pointcuts.push(pointcut);
	}
	
	/**
	 * Returns all added pointcuts.
	 * 
	 * @return all added pointcuts	 */
	public function getPointcuts(Void):Array {
		return this.pointcuts.concat();
	}
	
}