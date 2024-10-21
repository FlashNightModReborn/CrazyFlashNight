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

import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.aop.joinpoint.AbstractJoinPoint;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.env.reflect.TypeMemberInfo;
import org.as2lib.aop.JoinPoint;

/**
 * {@code MethodJoinPoint} represents a method as join point.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.joinpoint.MethodJoinPoint extends AbstractJoinPoint implements JoinPoint {
	
	/** The info of the represented method. */
	private var info:MethodInfo;
	
	/**
	 * Constructs a new {@code MethodJoinPoint} instance.
	 *
	 * @param info the info of the represented method
	 * @param thiz the logical this of the interception
	 * @throws IllegalArgumentException if argument {@code info} is {@code null} or
	 * {@code undefined}
	 * @see <a href="http://www.simonwacker.com/blog/archives/000068.php">Passing Context</a>
	 */
	public function MethodJoinPoint(info:MethodInfo, thiz) {
		super(thiz);
		if (!info) throw new IllegalArgumentException("Argument 'info' must not be 'null' nor 'undefined'.", this, arguments);
		this.info = info;
	}
	
	/**
	 * Returns the info of the represented method. This is a {@link MethodInfo}
	 * instance.
	 * 
	 * @return the info of the represented method
	 */
	public function getInfo(Void):TypeMemberInfo {
		return this.info;
	}
	
	/**
	 * Proceeds this join point by executing the represented method passing the given
	 * arguments and returning the result of the execution.
	 * 
	 * @param args the arguments to use for the execution
	 * @return the result of the execution
	 */
	public function proceed(args:Array) {
		return proceedMethod(this.info, args);
	}
	
	/**
	 * Returns the type of this join point.
	 * 
	 * @return {@link AbstractJoinPoint#METHOD}
	 */
	public function getType(Void):Number {
		return METHOD;
	}
	
	/**
	 * Returns a copy of this join point with an updated logical this. This join point
	 * is left unchanged.
	 * 
	 * @param thiz the new logical this
	 * @return a copy of this join point with an updated logical this
	 * @see #getThis
	 */
	public function update(thiz):JoinPoint {
		return new MethodJoinPoint(this.info, thiz);
	}
	
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
	public function snapshot(Void):JoinPoint {
		return new MethodJoinPoint(this.info.snapshot(), getThis());
	}
	
}