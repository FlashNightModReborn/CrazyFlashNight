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

import org.as2lib.env.reflect.ConstructorInfo;
import org.as2lib.aop.joinpoint.MethodJoinPoint;
import org.as2lib.aop.JoinPoint;

/**
 * {@code ConstructorJoinPoint} represents a constructor as join point.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.joinpoint.ConstructorJoinPoint extends MethodJoinPoint {
	
	/**
	 * Constructs a new {@code ConstructorJoinPoint} instance.
	 *
	 * @param info the info of the represented constructor
	 * @param thiz the logical this of the interception
	 * @throws IllegalArgumentException if argument {@code info} is {@code null} or
	 * {@code undefined}
	 * @see <a href="http://www.simonwacker.com/blog/archives/000068.php">Passing Context</a>
	 */
	public function ConstructorJoinPoint(info:ConstructorInfo, thiz) {
		super(info, thiz);
	}
	
	/**
	 * Returns the type of this join point.
	 * 
	 * @return {@link AbstractJoinPoint#CONSTRUCTOR}
	 */
	public function getType(Void):Number {
		return CONSTRUCTOR;
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
		return new ConstructorJoinPoint(ConstructorInfo(this.info), thiz);
	}
	
	/**
	 * Returns a copy of this join point that reflects its current state.
	 * 
	 * <p>It is common practice to create a new join point for a not-fixed constructor
	 * info. This is when the underlying concrete constructor this join point reflects
	 * may change. To make the concrete constructor and other parts that may change
	 * fixed you can use this method to get a new fixed join point, a snapshot.
	 * 
	 * @return a snapshot of this join point
	 */
	public function snapshot(Void):JoinPoint {
		return new ConstructorJoinPoint(ConstructorInfo(this.info.snapshot()), getThis());
	}

}