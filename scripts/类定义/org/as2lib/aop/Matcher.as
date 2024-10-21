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

import org.as2lib.core.BasicInterface;

/**
 * {@code Matcher} matches the string representation of a join point against a pattern.
 * Depending on the implementation the pattern may consist of various wildcards and
 * logical operators. Common wildcards and operators that are also supported by AspectJ
 * are:
 * 
 * <ul>
 *   <li>'*' indicates any number of characters excluding the period.</li>
 *   <li>'..' indicates any number of charecters including all periods.</li>
 *   <li>'+' indicates all subclasses or subinterfaces of a given type.</li>
 *   <li>'!' negates the match.</li>
 * </ul>
 * 
 * @author Simon Wacker
 */
interface org.as2lib.aop.Matcher extends BasicInterface {
	
	/**
	 * Checks if the passed-in {@code joinPoint} represented by a string matches the
	 * given {@code pattern}.
	 *
	 * @param joinPoint the join point represented as a string
	 * @param pattern the pattern that may match the given {@code joinPoint} string
	 * @return {@code true} if the given {@code joinPoint} matches the given
	 * {@code pattern} else {@code false}
	 */
	public function match(joinPoint:String, pattern:String):Boolean;
	
}