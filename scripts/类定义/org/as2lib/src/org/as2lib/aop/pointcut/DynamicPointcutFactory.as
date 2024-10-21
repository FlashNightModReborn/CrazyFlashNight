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
import org.as2lib.util.StringUtil;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.data.holder.Map;
import org.as2lib.data.holder.map.HashMap;
import org.as2lib.aop.AopConfig;
import org.as2lib.aop.Pointcut;
import org.as2lib.aop.pointcut.OrPointcut;
import org.as2lib.aop.pointcut.AndPointcut;
import org.as2lib.aop.pointcut.NotPointcut;
import org.as2lib.aop.pointcut.KindedPointcut;
import org.as2lib.aop.pointcut.WithinPointcut;
import org.as2lib.aop.pointcut.PointcutFactory;
import org.as2lib.aop.pointcut.PointcutRule;
import org.as2lib.aop.joinpoint.AbstractJoinPoint;

/**
 * {@code DynamicPointcutFactory} is a pointcut factory that can be dynamically expanded
 * with new pointcut types at run-time. You can do so by adding a new pointcut factory.
 * This pointcut factory is mapped to a pointcut rule that determines whether the given
 * pointcut factory is used to create the pointcut to return based on a given pointcut
 * pattern.
 * 
 * <p>This pointcut factory allows for execution, within, set and get access join points
 * and for composite pointcuts combined with AND or OR logic.
 * <code>execution(org.as2lib.env.Logger.debug)</code>
 * <code>set(org.as2lib.MyClass.myProperty)</code>
 * <code>get(org.as2lib.MyClass.myProperty)</code>
 * <code>within(org.as2lib.MyClass)</code>
 * <code>execution(org.as2lib.env.Logger.debug) || set(org.as2lib.MyClass.myProperty)</code>
 * 
 * <p>Negation is also supported for every kind of pointcut:
 * <code>execution(org.as2lib..*.*) && !within(org.as2lib.MyAspect)</code>
 * 
 * <p>You may of course enhance the list of supported pointcuts by binding new ones with
 * the {@link #bindPointcutFactory} method.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.pointcut.DynamicPointcutFactory extends BasicClass implements PointcutFactory {
	
	/** All bound factories. */
	private var factoryMap:Map;
	
	/**
	 * Constructs a new {@code DynamicPointcutFactory} instance.
	 */
	public function DynamicPointcutFactory(Void) {
		factoryMap = new HashMap();
		bindOrPointcut();
		bindAndPointcut();
		bindNotPointcut();
		bindExecutionPointcut();
		bindSetPropertyPointcut();
		bindGetPropertyPointcut();
		bindWithinPointcut();
	}
	
	/**
	 * Returns a blank pointcut rule. This is a rule with no initialized methods.
	 * 
	 * @return a blank pointcut rule
	 */
	private function getBlankPointcutRule(Void):PointcutRule {
		var result = new Object();
		result.__proto__ = PointcutRule["prototype"];
		result.__constructor__ = PointcutRule;
		return result;
	}
	
	/**
	 * Returns a blank pointcut factory. That is a factory with no initialized methods.
	 *
	 * @return a blank pointcut factory
	 */
	private function getBlankPointcutFactory(Void):PointcutFactory {
		var result = new Object();
		result.__proto__ = PointcutFactory["prototype"];
		result.__constructor__ = PointcutFactory;
		return result;
	}
	
	/**
	 * TODO: Documentation
	 */
	private function bindOrPointcut(Void):Void {
		var rule:PointcutRule = getBlankPointcutRule();
		rule.execute = function(pattern:String):Boolean {
			return (pattern.indexOf("||") != -1);
		};
		var factory:PointcutFactory = getBlankPointcutFactory();
		factory.getPointcut = function(pattern:String):Pointcut {
			return (new OrPointcut(pattern));
		};
		bindPointcutFactory(rule, factory);
	}
	
	/**
	 * TODO: Documentation
	 */
	private function bindAndPointcut(Void):Void {
		var rule:PointcutRule = getBlankPointcutRule();
		rule.execute = function(pattern:String):Boolean {
			return (pattern.indexOf("&&") != -1);
		};
		var factory:PointcutFactory = getBlankPointcutFactory();
		factory.getPointcut = function(pattern:String):Pointcut {
			return (new AndPointcut(pattern));
		};
		bindPointcutFactory(rule, factory);
	}
	
	/**
	 * TODO: Documentation
	 */
	private function bindNotPointcut(Void):Void {
		var rule:PointcutRule = getBlankPointcutRule();
		rule.execute = function(pattern:String):Boolean {
			return (pattern.indexOf("!") == 0);
		};
		var factory:PointcutFactory = getBlankPointcutFactory();
		factory.getPointcut = function(pattern:String):Pointcut {
			pattern = pattern.substring(1, pattern.length);
			return (new NotPointcut(AopConfig.getPointcutFactory().getPointcut(pattern)));
		};
		bindPointcutFactory(rule, factory);
	}
	
	/**
	 * TODO: Documentation
	 */
	private function bindExecutionPointcut(Void):Void {
		var rule:PointcutRule = getBlankPointcutRule();
		rule.execute = function(pattern:String):Boolean {
			return (pattern.indexOf("execution") == 0);
		};
		var factory:PointcutFactory = getBlankPointcutFactory();
		factory.getPointcut = function(pattern:String):Pointcut {
			if (pattern.indexOf("()") != -1) {
				pattern = pattern.substring(10, pattern.length - 3);
			} else {
				pattern = pattern.substring(10, pattern.length - 1);
			}
			return (new KindedPointcut(pattern, AbstractJoinPoint.METHOD | AbstractJoinPoint.CONSTRUCTOR));
		};
		bindPointcutFactory(rule, factory);
	}
	
	/**
	 * TODO: Documentation
	 */
	private function bindSetPropertyPointcut(Void):Void {
		var rule:PointcutRule = getBlankPointcutRule();
		rule.execute = function(pattern:String):Boolean {
			return (pattern.indexOf("set") == 0);
		};
		var factory:PointcutFactory = getBlankPointcutFactory();
		factory.getPointcut = function(pattern:String):Pointcut {
			pattern = pattern.substring(4, pattern.length - 1);
			return (new KindedPointcut(pattern, AbstractJoinPoint.SET_PROPERTY));
		};
		bindPointcutFactory(rule, factory);
	}
	
	/**
	 * TODO: Documentation
	 */
	private function bindGetPropertyPointcut(Void):Void {
		var rule:PointcutRule = getBlankPointcutRule();
		rule.execute = function(pattern:String):Boolean {
			return (pattern.indexOf("get") == 0);
		};
		var factory:PointcutFactory = getBlankPointcutFactory();
		factory.getPointcut = function(pattern:String):Pointcut {
			pattern = pattern.substring(4, pattern.length - 1);
			return (new KindedPointcut(pattern, AbstractJoinPoint.GET_PROPERTY));
		};
		bindPointcutFactory(rule, factory);
	}
	
	/**
	 * TODO: Documentation
	 */
	private function bindWithinPointcut(Void):Void {
		var rule:PointcutRule = getBlankPointcutRule();
		rule.execute = function(pattern:String):Boolean {
			return (pattern.indexOf("within") == 0);
		};
		var factory:PointcutFactory = getBlankPointcutFactory();
		factory.getPointcut = function(pattern:String):Pointcut {
			pattern = pattern.substring(7, pattern.length - 1);
			return (new WithinPointcut(pattern));
		};
		bindPointcutFactory(rule, factory);
	}
	
	/**
	 * Returns a pointcut based on the passed-in {@code pattern} representation.
	 * 
	 * <p>The pointcut to return is determined by the rules of the added pointcut
	 * factories. The pointcut factory whose rule applies first to the given
	 * {@code pattern} is used to get the pointcut to return. This means that order
	 * matters.
	 *
	 * @param pattern the string representation of the pointcut
	 * @return the object-oriented view of the passed-in pointcut {@code pattern}
	 */
	public function getPointcut(pattern:String):Pointcut {
		if (!pattern) return null;
		// this should be refactored, it is not a perfect solution, but it works for now
		if (pattern.indexOf(" ") != -1) {
			pattern = StringUtil.trim(pattern);
			while (pattern.indexOf("  ") != -1) {
				pattern = StringUtil.replace(pattern, "  ", " ");
			}
			pattern = StringUtil.replace(pattern, "( ", "(");
			pattern = StringUtil.replace(pattern, " )", ")");
			pattern = StringUtil.replace(pattern, " (", "(");
			pattern = StringUtil.replace(pattern, "! ", "!");
			pattern = StringUtil.replace(pattern, " &&", "&&");
			pattern = StringUtil.replace(pattern, " ||", "||");
			pattern = StringUtil.replace(pattern, "&& ", "&&");
			pattern = StringUtil.replace(pattern, "|| ", "||");
		}
		var rules:Array = factoryMap.getKeys();
		var factories:Array = factoryMap.getValues();
		for (var i:Number = 0; i < rules.length; i++) {
			var rule:PointcutRule = rules[i];
			if (rule.execute(pattern)) {
				return PointcutFactory(factories[i]).getPointcut(pattern);
			}
		}
		return null;
	}
	
	/**
	 * Binds a new {@code factory} to the given {@code rule}.
	 *
	 * @param rule the rule that must evaluate to {@code true} to indicate that the
	 * {@code factory} shall be used for a given pointcut pattern
	 * @param factory the factory to add
	 * @throws IllegalArgumentException if rule is {@code null} or {@code undefined}
	 * @throws IllegalArgumentException if factory is {@code null} or {@code undefined}
	 */
	public function bindPointcutFactory(rule:PointcutRule, factory:PointcutFactory):Void {
		if (!rule || !factory) throw new IllegalArgumentException("Neither argument 'rule' nor argument 'factory' must be {@code null} nor {@code undefined}.", this, arguments);
		factoryMap.put(rule, factory);
	}
	
}