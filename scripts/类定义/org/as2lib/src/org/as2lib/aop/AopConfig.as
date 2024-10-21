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
import org.as2lib.aop.pointcut.PointcutFactory;
import org.as2lib.aop.pointcut.DynamicPointcutFactory;
import org.as2lib.aop.advice.DynamicAdviceFactory;
import org.as2lib.aop.advice.SimpleDynamicAdviceFactory;
import org.as2lib.aop.Matcher;
import org.as2lib.aop.matcher.WildcardMatcher;

/**
 * {@code AopConfig} declares methods to configure core parts of the AOP framework.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.AopConfig extends BasicClass {
	
	/** The pointcut factory. */
	private static var pointcutFactory:PointcutFactory;
	
	/** The dynamic advice factory. */
	private static var dynamicAdviceFactory:DynamicAdviceFactory;
	
	/** The matcher. */
	private static var matcher:Matcher;
	
	/**
	 * Sets a new dynamic advice factory.
	 *
	 * @param factory the new dynamic advice factory
	 */
	public static function setDynamicAdviceFactory(factory:DynamicAdviceFactory):Void {
		dynamicAdviceFactory = factory;
	}
	
	/**
	 * Returns the set or the default dynamic advice factory. The defult factory is
	 * an instance of the {@link SimpleDynamicAdviceFactory} class.
	 *
	 * @return the set or the default dynamic advice factory
	 */
	public static function getDynamicAdviceFactory(Void):DynamicAdviceFactory {
		if (!dynamicAdviceFactory) dynamicAdviceFactory = new SimpleDynamicAdviceFactory();
		return dynamicAdviceFactory;
	}
	
	/**
	 * Sets a new pointcut factory.
	 *
	 * @param factory the new pointcut factory
	 */
	public static function setPointcutFactory(factory:PointcutFactory):Void {
		pointcutFactory = factory;
	}
	
	/**
	 * Returns the set pointcut factory or the default one. The default one is an
	 * instance of the {@link DynamicPointcutFactory} class.
	 *
	 * @return the set or default pointcut factory
	 */
	public static function getPointcutFactory(Void):PointcutFactory {
		if (!pointcutFactory) pointcutFactory = new DynamicPointcutFactory();
		return pointcutFactory;
	}
	
	/**
	 * Sets a new matcher.
	 * 
	 * @param newMatcher the new matcher	 */
	public static function setMatcher(newMatcher:Matcher):Void {
		matcher = newMatcher;
	}
	
	/**
	 * Returns either the set or the default matcher. The default matcher is an
	 * instance of the {@link WildcardMatcher} class.
	 * 
	 * @return the set or default matcher	 */
	public static function getMatcher(Void):Matcher {
		if (!matcher) matcher = new WildcardMatcher();
		return matcher;
	}
	
	/**
	 * Constructs a new {@code AopConfig} instance.
	 */
	private function AopConfig(Void) {
	}
	
}