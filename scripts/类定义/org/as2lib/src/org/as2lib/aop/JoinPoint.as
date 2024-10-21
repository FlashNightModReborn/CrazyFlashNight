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
import org.as2lib.env.reflect.TypeMemberInfo;

/**
 * {@code JoinPoint} represents an identifiable point in a program. Although this
 * points could by theory also be try..catch blocks, the join points offered by this
 * framework are limited to members of classes or interfaces, these are methods and
 * properties.
 * 
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000041.php">Terms and AspectJ</a>
 */
interface org.as2lib.aop.JoinPoint extends BasicInterface {
	
	/**
	 * Returns the info of the represented type member; this information is also known
	 * as the join point's static part. Note that the type of this join point is also
	 * part of this join point's static part.
	 * 
	 * @return the info representing the static part of this join point
	 */
	public function getInfo(Void):TypeMemberInfo;
	
	/**
	 * Executes the type member represented by this join point passing the given
	 * {@code args} and returns the result.
	 *
	 * @param args the arguments to use for the execution
	 * @return the result of the type member execution
	 */
	public function proceed(args:Array);
	
	/**
	 * Returns the logical this of the interception. This means if this join point is
	 * part of a call-pointcut the result will refer to the object where the call was
	 * made from. If this join point is part of an execution-, set- or get-pointcut the
	 * result will refer to the object that represented method or property resides in.
	 * 
	 * @return the logical this of this join point depending on the used pointcut
	 * @see <a href="http://www.simonwacker.com/blog/archives/000068.php">Passing Context</a>
	 */
	public function getThis(Void);
	
	/**
	 * Returns the type of the join point.
	 * 
	 * <p>Supported types are declared as constants in the {@link AbstractJoinPoint}
	 * class.
	 *
	 * @return the type of this join point
	 */
	public function getType(Void):Number;
	
	/**
	 * Checks if this join point matches the given {@code pattern}. Depending on the
	 * used matcher the pattern may contain wildcards like {@code "*"} and {@code ".."}.
	 * A pattern could for example be {@code "org..BasicClass.*"}.
	 * 
	 * @param pattern the pattern to match against this join point
	 * @return {@code true} if the given {@code pattern} matches this join point else
	 * {@code false}
	 * @see WildcardMatcher
	 * @see <a href="http://www.simonwacker.com/blog/archives/000053">Wildcards</a>
	 */
	public function matches(pattern:String):Boolean;
	
	/**
	 * Returns a copy of this join point with an updated logical this. This join point
	 * is left unchanged.
	 * 
	 * @param thiz the new logical this
	 * @return a copy of this join point with an updated logical this
	 * @see #getThis
	 */
	public function update(thiz):JoinPoint;
	
	/**
	 * Returns a copy of this join point that reflects its current state.
	 * 
	 * <p>It is common practice to create a new join point for a not-fixed method info.
	 * This is when the underlying concrete method this join point reflects may change.
	 * To make the concrete method and other parts that may change fixed you can use
	 * this method to get a new fixed join point, a snapshot.
	 * 
	 * @return a snapshot of this join point
	 */
	public function snapshot(Void):JoinPoint;
	
}