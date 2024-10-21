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
import org.as2lib.aop.advice.AdviceFactory;
import org.as2lib.env.overload.Overload;
import org.as2lib.app.exec.Call;
import org.as2lib.aop.Advice;
import org.as2lib.aop.Pointcut;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.util.ClassUtil;

/**
 * {@code SimpleAdviceFactory} creates advices dynamically based on an advice class.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.advice.SimpleAdviceFactory extends BasicClass implements AdviceFactory {
	
	/** The advice class. */
	private var adviceClass:Function;
	
	/**
	 * Constructs a new {@code SimpleAdviceFactory} instance.
	 * 
	 * <p>The {@code adviceClass} is suspected to have a constructor that takes two
	 * arguments. The first argument is either a pointcut pattern or a {@link Pointcut}
	 * instance and the second argument is a callback of instance {@link Call}.
	 *
	 * @param advice the advice class to return instances of
	 * @throws IllegalArgumentException if argument {@code adviceClass} is {@code null}
	 * or {@code undefined}
	 * @throws IllegalArgumentException if the passed-in {@code adviceClass} is not an
	 * implementation of the {@link Advice} interface
	 */
	public function SimpleAdviceFactory(adviceClass:Function) {
		if (!adviceClass) throw new IllegalArgumentException("Argument 'adviceClass' must not be 'null' nor 'undefined'.", this, arguments);
		if (!ClassUtil.isImplementationOf(adviceClass, Advice)) {
			throw new IllegalArgumentException("Argument 'adviceClass' is not an implementation of interface 'Advice'.", this, arguments);
		}
		this.adviceClass = adviceClass;
	}
	
	/**
	 * @overload #getAdviceByStringAndCall
	 * @overload #getAdviceByPointcutAndCall
	 */
	public function getAdvice():Advice {
		var o:Overload = new Overload(this);
		o.addHandler([String, Call], getAdviceByStringAndCall);
		o.addHandler([Pointcut, Call], getAdviceByPointcutAndCall);
		return o.forward(arguments);
	}
	
	/**
	 * Returns an advice configured for the given {@code pointcut} string and
	 * {@code callback}.
	 *
	 * @param pointcut the string representation of a pointcut used by the returned advice
	 * @param callback the callback that is executed if you invoke the {@code execute}
	 * method on the returned advice
	 * @return an advice that is configured with the given {@code pointcut} and
	 * {@code callback}
	 */
	public function getAdviceByStringAndCall(pointcut:String, callback:Call):Advice {
		return Advice(new adviceClass(pointcut, callback));
	}
	
	/**
	 * Returns an advice configured for the given {@code pointcut} and {@code callback}.
	 *
	 * @param pointcut the pointcut used by the returned advice
	 * @param callback the callback that is executed if you invoke the {@code execute}
	 * method on the returned advice
	 * @return an advice that is configured with the given {@code pointcut} and
	 * {@code callback}
	 */
	public function getAdviceByPointcutAndCall(pointcut:Pointcut, callback:Call):Advice {
		return Advice(new adviceClass(pointcut, callback));
	}
	
}