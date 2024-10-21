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

import org.as2lib.aop.Matcher;
import org.as2lib.core.BasicClass;
import org.as2lib.regexp.Pattern;

/**
 * {@code RegexpMatcher} matches a join point with a regular expression pattern.
 * 
 * <p>Note that this matcher is less performant than the {@link WildcardMatcher} and
 * also a little harder to use if you are not familiar with regular expressions. I thus
 * encourage you to use the wildcard matcher if the supported wildcards fit all your
 * needs.
 * 
 * @author Simon Wacker
 * @see org.as2lib.regexp.Pattern
 */
class org.as2lib.aop.matcher.RegexpMatcher extends BasicClass implements Matcher {
	
	/**
	 * Constructs a new {@code RegexpMatcher} instance.
	 */
	public function RegexpMatcher(Void) {
	}
	
	/**
	 * Checks whether the given join point matches the given regular expression pattern.
	 * 
	 * <p>The join point string normally looks something like this:
	 * <code>static org.as2lib.env.log.Logger.info</code>
	 * 
	 * <p>And the regular expression pattern may look like this:
	 * <code>.* org\\.as2lib\\..*\\.log\\.Logger\\.info</code>
	 * 
	 * <p>For more information on what keywords can be used in the pattern take a look
	 * at the {@link org.as2lib.regexp.Pattern} class.
	 * 
	 * @param joinPoint the join point to check whether it matches the given
	 * {@code regexpPattern}
	 * @param regexpPattern the regular expression pattern to check whether it matches
	 * the given {@code joinPoint}
	 * @return {@code true} if the {@code joinPoint} matches the given {@code regexpPattern}
	 * else {@code false}
	 */
	public function match(joinPoint:String, regexpPattern:String):Boolean {
		return Pattern.matches(regexpPattern, joinPoint);
	}
	
}