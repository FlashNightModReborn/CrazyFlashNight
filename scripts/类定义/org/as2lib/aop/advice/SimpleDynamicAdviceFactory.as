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
import org.as2lib.aop.advice.DynamicAdviceFactory;
import org.as2lib.env.overload.Overload;
import org.as2lib.app.exec.Call;
import org.as2lib.aop.Advice;
import org.as2lib.aop.Pointcut;
import org.as2lib.aop.advice.AbstractAdvice;
import org.as2lib.aop.advice.AdviceFactory;
import org.as2lib.aop.advice.SimpleAdviceFactory;
import org.as2lib.aop.advice.DynamicBeforeAdvice;
import org.as2lib.aop.advice.DynamicAroundAdvice;
import org.as2lib.aop.advice.DynamicAfterAdvice;
import org.as2lib.aop.advice.DynamicAfterReturningAdvice;
import org.as2lib.aop.advice.DynamicAfterThrowingAdvice;
import org.as2lib.env.except.IllegalArgumentException;

/**
 * {@code SimpleDynamicAdviceFactory} manages the creation of advices for different
 * advice types in a simple manner.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.advice.SimpleDynamicAdviceFactory extends BasicClass implements DynamicAdviceFactory {
	
	/** All registered advices. */
	private var registry:Array;
	
	/**
	 * Constructs a new {@code SimpleDynamicAdviceFactory} instance.
	 */
	public function SimpleDynamicAdviceFactory(Void) {
		registry = new Array();
		bindAdviceFactoryByAdviceClass(AbstractAdvice.BEFORE, DynamicBeforeAdvice);
		bindAdviceFactoryByAdviceClass(AbstractAdvice.AROUND, DynamicAroundAdvice);
		bindAdviceFactoryByAdviceClass(AbstractAdvice.AFTER, DynamicAfterAdvice);
		bindAdviceFactoryByAdviceClass(AbstractAdvice.AFTER_RETURNING, DynamicAfterReturningAdvice);
		bindAdviceFactoryByAdviceClass(AbstractAdvice.AFTER_THROWING, DynamicAfterThrowingAdvice);
	}
	
	/**
	 * @overload #bindAdviceFactoryByAdviceFactory
	 * @overload #bindAdviceFactoryByAdviceClass
	 */
	public function bindAdviceFactory() {
		var o:Overload = new Overload(this);
		o.addHandler(bindAdviceFactoryByAdviceFactory, [Number, AdviceFactory]);
		o.addHandler(bindAdviceFactoryByAdviceClass, [Number, Function]);
		return o.forward(arguments);
	}
	
	/**
	 * Binds the given {@code adviceFactory} to the {@code adviceType}. If a request is
	 * made with the given {@code adviceType} as type, the bound {@code adviceFactory}
	 * will be used to create the advice that gets returned.
	 * 
	 * <p>If there is already an advice factory bound to the given {@code adviceType}
	 * the old binding gets overwritten.
	 * 
	 * <p>If you want to remove a binding pass an {@code adviceFactory} of value
	 * {@code null} or {@code undefined}
	 * 
	 * @param adviceType the type to bind the {@code adviceFactory} to
	 * @param adviceFactory the advice factory to bind to the given {@code adviceType}
	 * @throws IllegalArgumentException if argument {@code adviceType} is {@code null}
	 * or {@code undefined}
	 */
	public function bindAdviceFactoryByAdviceFactory(adviceType:Number, adviceFactory:AdviceFactory):Void {
		if (adviceType == null) throw new IllegalArgumentException("Argument 'adviceType' must not be 'null' nor 'undefined'.", this, arguments);
		registry[adviceType] = adviceFactory;
	}
	
	/**
	 * Creates a new {@link SimpleAdviceFactory} instance for the given
	 * {@code adviceClass}, binds the created advice factory to the given
	 * {@code adviceType} and returns the factory.
	 * 
	 * <p>If there is already an advice factory bound to the given {@code adviceType}
	 * the old binding gets overwritten.
	 * 
	 * @param adviceType the type to bind the {@code adviceFactory} to
	 * @param adviceClass the class of the advice to create instances of if a advice
	 * request for the given {@code adviceType} is made
	 * @return an advice factory configured for the given {@code adviceClass}
	 * @throws IllegalArgumentException if argument {@code adviceType} is {@code null}
	 * or {@code undefined}
	 * @throws IllegalArgumentException if argument {@code adviceClass} is {@code null}
	 * or {@code undefined}
	 */
	public function bindAdviceFactoryByAdviceClass(adviceType:Number, adviceClass:Function):AdviceFactory {
		var factory:AdviceFactory = new SimpleAdviceFactory(adviceClass);
		bindAdviceFactoryByAdviceFactory(adviceType, factory);
		return factory;
	}
	
	/**
	 * @overload #getAdviceByTypeAndStringAndCall
	 * @overload #getAdviceByTypeAndPointcutAndCall
	 */
	public function getAdvice():Advice {
		var o:Overload = new Overload(this);
		o.addHandler([Number, String, Call], getAdviceByTypeAndStringAndCall);
		o.addHandler([Number, Pointcut, Call], getAdviceByTypeAndPointcutAndCall);
		return o.forward(arguments);
	}
	
	/**
	 * Returns the advice corresponding to the given {@code type}. The returned advice
	 * uses the passed-in {@code pointcut} and {@code callback}.
	 * 
	 * <p>The {@code callback} is invoked if the {@code execute} method of the returned
	 * advice is executed.
	 * 
	 * <p>Commonly supported types are defined as constants in the
	 * {@link AbstractAdvice} class.
	 * 
	 * @param type the type of the advice to return
	 * @param pointcut the string representation of a pointcut used by the returned advice
	 * @param callback the callback that is executed if you invoke the {@code execute}
	 * method on the returned advice
	 * @return the advice corresponding to the type and configured with the given
	 * {@code pointcut} and {@code callback}
	 * @throws IllegalArgumentException if argument {@code type} is {@code null} or
	 * {@code undefined}
	 */
	public function getAdviceByTypeAndStringAndCall(type:Number, pointcut:String, callback:Call):Advice {
		if (type == null) throw new IllegalArgumentException("Argument 'type' must not be 'null' nor 'undefined'.", this, arguments);
		return AdviceFactory(registry[type]).getAdvice(pointcut, callback);
	}
	
	/**
	 * Returns the advice corresponding to the given {@code type}. The returned advice
	 * uses the passed-in {@code pointcut} and {@code callback}.
	 * 
	 * <p>The {@code callback} is invoked if the {@code execute} method of the returned
	 * advice is executed.
	 * 
	 * <p>Commonly supported types are defined as constants in the
	 * {@link AbstractAdvice} class.
	 *
	 * @param type the type of the advice to return
	 * @param pointcut the pointcut used by the returned advice
	 * @param callback the callback that is executed if you invoke the {@code execute}
	 * method on the returned advice
	 * @return the advice corresponding to the type and configured with the given
	 * {@code pointcut} and {@code callback}
	 * @throws IllegalArgumentException if argument {@code type} is {@code null} or
	 * {@code undefined}
	 */
	public function getAdviceByTypeAndPointcutAndCall(type:Number, pointcut:Pointcut, callback:Call):Advice {
		if (type == null) throw new IllegalArgumentException("Argument 'type' must not be 'null' nor 'undefined'.", this, arguments);
		return AdviceFactory(registry[type]).getAdvice(pointcut, callback);
	}
	
}