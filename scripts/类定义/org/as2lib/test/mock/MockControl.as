/**
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
import org.as2lib.env.overload.Overload;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ProxyFactory;
import org.as2lib.env.reflect.TypeProxyFactory;
import org.as2lib.env.reflect.InvocationHandler;
import org.as2lib.test.mock.ArgumentsMatcher;
import org.as2lib.test.mock.support.DefaultArgumentsMatcher;
import org.as2lib.test.mock.support.TypeArgumentsMatcher;
import org.as2lib.test.mock.Behavior;
import org.as2lib.test.mock.MethodCall;
import org.as2lib.test.mock.MethodCallRange;
import org.as2lib.test.mock.MethodResponse;
import org.as2lib.test.mock.support.DefaultBehavior;
import org.as2lib.test.mock.MockControlState;
import org.as2lib.test.mock.support.RecordState;
import org.as2lib.test.mock.support.ReplayState;
import org.as2lib.test.mock.MockControlStateFactory;
import org.as2lib.env.reflect.ReflectUtil;

/**
 * {@code MockControl} is the central class of the mock object framework. You use
 * it to create your mock object, set expectations and verify whether these
 * expectations have been met.
 *
 * <p>The normal workflow is creating a mock control for a specific class or
 * interface, receiving the mock object from it, setting expectations, setting the
 * behavior of the mock object, switching to replay state, using the mock object as
 * if it were a normal instance of a class and verifying that all expectations have
 * been met.
 * 
 * <code>
 *   import org.as2lib.test.mock.MockControl;
 *
 *   // create mock control for class MyClass
 *   var myMockControl:MockControl = new MockControl(MyClass);
 *   // receive the mock object (it is in record state)
 *   var myMock:MyClass = myMockControl.getMock();
 *   // expect a call to the setStringProperty-method with argument 'myString'.
 *   myMock.setStringProperty("myString");
 *   // expect calls to the getStringProperty-method
 *   myMock.getStringProperty();
 *   // return 'myString' for the first two calls
 *   myMockControl.setReturnValue("myString", 2);
 *   // throw MyException for any further call
 *   myMockControl.setDefaultThrowable(new MyException());
 *   // switch to replay state
 *   myMockControl.replay();
 *
 *   // the class under test calls these methods on the mock
 *   myMock.setStringProperty("myString");
 *   myMock.getStringProperty();
 *   myMock.getStringProperty();
 *
 *   // verify that all expectations have been met
 *   myMockControl.verify();
 * </code>
 *
 * <p>If an expectation has not been met an {@link AssertionFailedError} will be
 * thrown. If an expectation violation is discovered during execution an
 * {@code AssertionFailedError} will be thrown immediately.
 * 
 * <p>If you had called the {@code setStringProperty} method in the above example
 * with another string like {@code "unexpectedString"} an {@code AssertFailedError}
 * would have been thrown immediately. If you had called the {@code setStringProperty}
 * method a second time, what has not been expected, an {@code AssertionFailedError}
 * would also have been thrown immediately. If you had not called the
 * {@code setStringProperty} method at all, an {@code AssertionFailedError} would
 * have been thrown on verification.
 *
 * @author Simon Wacker
 */
class org.as2lib.test.mock.MockControl extends BasicClass {
	
	/**
	 * Returns a new default arguments matcher.
	 *
	 * @return a new default arguments matcher
	 */
	public static function getDefaultArgumentsMatcher(Void):DefaultArgumentsMatcher {
		return new DefaultArgumentsMatcher();
	}
	
	/**
	 * Returns a new type arguments matcher that is configured with the passed-in
	 * {@code expectedType}.
	 * 
	 * <p>Type arguments matcher matches arguments by type and not by value.
	 *
	 * @return a type arguments matcher
	 */
	public static function getTypeArgumentsMatcher(expectedTypes:Array):TypeArgumentsMatcher {
		return new TypeArgumentsMatcher(expectedTypes);
	}
	
	/** The type of the mock proxy. */
	private var type:Function;
	
	/** Used to create a new mock proxy. */
	private var proxyFactory:ProxyFactory;
	
	/** The created mock proxy. */
	private var mock;
	
	/** The mock behavior. */
	private var behavior:Behavior;
	
	/** The current state. */
	private var state:MockControlState;
	
	/** Factory used to obtain the record state. */
	private var recordStateFactory:MockControlStateFactory;
	
	/** Factory used to obtain the replay state. */
	private var replayStateFactory:MockControlStateFactory;
	
	/** Determines whether to handle {@code toString} method invocations. */
	private var handleToStringInvocations:Boolean;
	
	/**
	 * @overload #MockControlByType
	 * @overload #MockControlByTypeAndBehavior
	 */
	public function MockControl() {
		var o:Overload = new Overload(this);
		o.addHandler([Function], MockControlByType);
		o.addHandler([Function, Behavior], MockControlByTypeAndBehavior);
		o.forward(arguments);
	}
	
	/**
	 * Constrcuts a new {@code MockControl} instance using the default behavior.
	 *
	 * <p>The default behavior is an instance of class {@link org.as2lib.test.mock.support.DefaultBehaviour}.
	 *
	 * <p>This instance is in reset state after creation. That means it is ready to
	 * receive expectations and to record them.
	 *
	 * <p>When you have finished recording you must switch to replay state using the
	 * {@link #replay} method.
	 *
	 * @param type the interface or class to create a mock object for
	 * @throws IllegalArgumentException if the passed-in {@code type} is {@code null}
	 */
	private function MockControlByType(type:Function):Void {
		MockControlByTypeAndBehavior(type, null);
	}
	
	/**
	 * Constructs a new {@code MockControl} instance using the passed-in
	 * {@code bahvior}.
	 *
	 * <p>If the passed-in {@code behavior} is {@code null} the default behavior that
	 * is of type {@link DefaultBehavior} is used instead.
	 *
	 * <p>This instance is in reset state after creation. That means it is ready to
	 * to receive expectations and to record them.
	 *
	 * <p>When you have finished recording you must switch to replay state using the
	 * {@link #replay} method.
	 *
	 * <p>{@code toString} invocations on the mock are by default not handled.
	 *
	 * @param type the interface or class to create a mock object for
	 * @param behavior the instance to store the behavior of the mock
	 * @throws IllegalArgumentException if the passed-in {@code type} is {@code null}
	 * @see #setHandleToStringInvocations
	 */
	private function MockControlByTypeAndBehavior(type:Function, behavior:Behavior):Void {
		if (!type) throw new IllegalArgumentException("The argument type '" + type + "' is not allowed to be null or undefined.");
		this.type = type;
		this.behavior = behavior ? behavior : new DefaultBehavior();
		this.handleToStringInvocations = false;
		reset();
	}
	
	/**
	 * Sets whether to handle {@code toString} invocations on mocks or not.
	 *
	 * <p>Handling {@code toString} invocations means that these invocations are
	 * added to the expected or actual behavior. This means if you set
	 * {@code handleToStringInvocations} to {@code true} calling this method on the
	 * mock in replay state results in an added expection and in record state in a
	 * verification whether the call was expected. If you set it to {@code false} the
	 * result of an invocation of the mock's {@code toString} method is returned.
	 * 
	 * <p>If {@code handleToStringInvocations} is {@code null}, it is interpreted as
	 * {@code false}.
	 *
	 * @param handleToStringInvocations determines whether to handle {@code toStirng}
	 * method invocations
	 */
	public function setHandleToStringInvocations(handleToStringInvocations:Boolean):Void {
		this.handleToStringInvocations = !handleToStringInvocations ? false : true;
	}
	
	/**
	 * Returns whether {@code toString} invocations on the mock are handled.
	 *
	 * <p>Handling {@code toString} invocations means that these invocations are
	 * added to the expected or actual behavior. This means if they are handled,
	 * calling the {@code toString} method on the mock in replay state results in an
	 * added expection and in record state in a verification whether the call was
	 * expected. If they are not handled, the result of an invocation of the mock's
	 * {@code toString} method is returned.
	 *
	 * @return {@code true} if {@code toString} invocations are handled else
	 * {@code false}
	 * @see #setHandleToStringInvocations
	 */
	public function areToStringInvocationsHandled(Void):Boolean {
		return this.handleToStringInvocations;
	}
	
	/**
	 * Returns the currently used mock proxy factory.
	 *
	 * <p>This proxy factoy is either the default {@link TypeProxyFactory} or the one
	 * set via {@code setMockProxyFactory}.
	 *
	 * @return the currently used proxy factory
	 * @see #setMockProxyFactory
	 */
	public function getMockProxyFactory(Void):ProxyFactory {
		if (!proxyFactory) proxyFactory = new TypeProxyFactory();
		return proxyFactory;
	}
	
	/**
	 * Sets the proxy factory used to obtain the mock proxis / mocks.
	 *
	 * <p>If {@code proxyFactory} is {@code null} the {@code getMockProxyFactory}
	 * method will use the default factory.
	 *
	 * @param proxyFactory factory to obtain mock proxies / mocks
	 * @see #getMockProxyFactory
	 */
	public function setMockProxyFactory(proxyFactory:ProxyFactory):Void {
		this.proxyFactory = proxyFactory;
	}
	
	/**
	 * Returns the currently used record state factory.
	 *
	 * <p>This is either the factory set via {@code setRecordStateFactory} or the
	 * default one, which returns instances of the {@link RecordState} class.
	 *
	 * @return the currently used record state factory
	 * @see #setRecordStateFactory
	 */
	public function getRecordStateFactory(Void):MockControlStateFactory {
		if (!recordStateFactory) recordStateFactory = getDefaultRecordStateFactory();
		return recordStateFactory;
	}
	
	/**
	 * Returns the default record state factory.
	 *
	 * <p>The default record state factory returns instances of class
	 * {@link RecordState}.
	 *
	 * @return the default record state factory
	 */
	private function getDefaultRecordStateFactory(Void):MockControlStateFactory {
		var result:MockControlStateFactory = getBlankMockControlStateFactory();
		result.getMockControlState = function(behavior:Behavior):MockControlState {
			return new RecordState(behavior);
		};
		return result;
	}
	
	/**
	 * Sets the new record state factory.
	 *
	 * <p>If {@code recordStateFactory} is {@code null} the default record state
	 * factory gets returned by the {@code getRecordStateFactory} method.
	 *
	 * @param recordStateFactory the new record state factory
	 * @see #getRecordStateFactory
	 */
	public function setRecordStateFactory(recordStateFactory:MockControlStateFactory):Void {
		this.recordStateFactory = recordStateFactory;
	}
	
	/**
	 * Returns the currently used replay state factory.
	 *
	 * <p>This is either the factory set via {@code setReplayStateFactory} or the
	 * default one, which returns instances of the {@link ReplayState} class.
	 *
	 * @return the currently used replay state factory
	 * @see #setReplayStateFactory
	 */
	public function getReplayStateFactory(Void):MockControlStateFactory {
		if (!replayStateFactory) replayStateFactory = getDefaultReplayStateFactory();
		return replayStateFactory;
	}
	
	/**
	 * Returns the default replay state factory.
	 *
	 * <p>The default replay state factory returns instances of class
	 * {@link ReplayState}.
	 *
	 * @return the default replay state factory
	 */
	private function getDefaultReplayStateFactory(Void):MockControlStateFactory {
		var result:MockControlStateFactory = getBlankMockControlStateFactory();
		result.getMockControlState = function(behavior:Behavior):MockControlState {
			return new ReplayState(behavior);
		};
		return result;
	}
	
	/**
	 * Sets the new replay state factory.
	 *
	 * <p>If {@code replayStateFactory} is {@code null} the
	 * {@code getReplayStateFactory} method will return the default replay state
	 * factory.
	 *
	 * @param replayStateFactory the new replay state factory
	 * @see #getReplayStateFactory
	 */
	public function setReplayStateFactory(replayStateFactory:MockControlStateFactory):Void {
		this.replayStateFactory = replayStateFactory;
	}
	
	/**
	 * Returns a blank mock control state factory. That is a factory with no
	 * implemented methods.
	 *
	 * @return a blank mock control state factory
	 */
	private function getBlankMockControlStateFactory(Void):MockControlStateFactory {
		var result = new Object();
		result.__proto__ = MockControlStateFactory["prototype"];
		result.__constructor__ = MockControlStateFactory;
		return result;
	}
	
	/**
	 * Returns the mock object.
	 *
	 * <p>The mock can be casted and typed to the interface or class specified
	 * on instantiation.
	 *
	 * <p>The mock is created using the mock proxy factory returned by the
	 * {@link #getMockProxyFactory} method.
	 *
	 * <p>Once the mock object has been created it is cached. That means this method
	 * always returns the same mock object for this mock control.
	 *
	 * @return the mock object
	 */
	public function getMock(Void) {
		if (!mock) mock = getMockProxyFactory().createProxy(type, createDelegator());
		return mock;
	}
	
	/**
	 * Creates a new invocation handler instance that handles method invocations on
	 * the mock proxy.
	 *
	 * @return a delegator that handles proxy method invocations
	 */
	private function createDelegator(Void):InvocationHandler {
		var result:InvocationHandler = getBlankInvocationHandler();
		var owner:MockControl = this;
		result.invoke = function(proxy, method:String, args:Array) {
			// 'toString' must be excluded because it is used everytime output is made.
			// For example in the success and failure messages of the unit testing api.
			if (method == "toString" && !owner.areToStringInvocationsHandled()) {
				// TODO: Source out into own stringifier class (MockStringifier)
				return "[mock " + ReflectUtil.getTypeNameForInstance(owner.getMock()) + "]";
				//return owner.getMock().__proto__.toString.apply(owner.getMock());
			}
			// calling private methods from an inner anonymous method is not allowed by MTASC
			return owner["invokeMethod"](method, args);
		};
		return result;
	}
	
	/**
	 * Returns a blank invocation handler. That is a handler with no implemented
	 * methods.
	 *
	 * @return a blank invocation handler
	 */
	private function getBlankInvocationHandler(Void):InvocationHandler {
		var result = new Object();
		result.__proto__ = InvocationHandler["prototype"];
		result.__constructor__ = InvocationHandler;
		return result;
	}
	
	/**
	 * Is called when a method is invoked on the proxy.
	 *
	 * @param methodName the name of the invoked method
	 * @param args the arguments passed to the invoked method
	 */
	private function invokeMethod(methodName:String, args:Array) {
		// resolves bug with algorithms that check the existence of a method before
		// they proceed; this is for example with the AsBroadcaster
		var r:Function = mock.__resolve;
		mock.__resolve = null;
		if (!mock[methodName]) {
			if (state instanceof RecordState) {
				var owner:MockControl = this;
				mock[methodName] = function() {
					if (methodName == "toString" && !owner.areToStringInvocationsHandled()) {
						return owner.getMock().__proto__.toString.apply(owner.getMock());
					}
					// calling private methods out of inner anonymous methods is not allowed with MTASC
					return owner["invokeMethod"](methodName, arguments);
				};
			}
		}
		mock.__resolve = r;
		var result;
		try {
			result = state.invokeMethod(new MethodCall(methodName, args));
		} catch(error:org.as2lib.test.mock.MethodCallRangeError) {
			error.setType(type);
			throw error;
		}
		return result;
	}
	
	/**
	 * Switches the mock object from record state to replay state.
	 *
	 * <p>The mock object is in record state as soon as it gets returned by the
	 * {@link #getMock} method.
	 *
	 * <p>You cannot record expectations in replay state. In replay state you verify
	 * that all your expectations have been met, by using the mock as it were a real
	 * instance.
	 *
	 * <p>If an expectations is not met an {@link AssertionFailedError} is thrown.
	 * This is either done during execution of your test or on verification. Take a
	 * look at the example provided in the class documentation to see when what
	 * {@code AssertFailedError} is thrown.
	 */
	public function replay(Void):Void {
		state = getReplayStateFactory().getMockControlState(behavior);
	}
	
	/**
	 * Resets the mock control and the mock object to the state directly after
	 * creation.
	 *
	 * <p>That means that all previously made expectations will be removed and that
	 * the mock object will be again in record state.
	 */
	public function reset(Void):Void {
		behavior.removeAllBehaviors();
		state = getRecordStateFactory().getMockControlState(behavior);
	}
	
	/**
	 * Sets the arguments matcher that will be used for the last method specified by
	 * a method call.
	 *
	 * @param argumentsMatcher the arguments matcher to use for the specific method
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setArgumentsMatcher(argumentsMatcher:ArgumentsMatcher):Void {
		state.setArgumentsMatcher(argumentsMatcher);
	}
	
	/**
	 * Records that the mock object will by default allow the last method specified
	 * by a method call and will react by returning the provided return value.
	 *
	 * <p>Default means that the method can be called 0 to infinite times without
	 * expectation errors.
	 *
	 * @param value the return value to return
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setDefaultReturnValue(value):Void {
		var response:MethodResponse = new MethodResponse();
		response.setReturnValue(value);
		state.setMethodResponse(response, new MethodCallRange());
	}
	
	/**
	 * Records that the mock object will by default allow the last method specified
	 * by a method call, and will react by throwing the provided throwable.
	 *
	 * <p>Default means that the method can be called zero to infinite times without
	 * expectation errors.
	 *
	 * @param throwable the throwable to throw
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setDefaultThrowable(throwable):Void {
		var response:MethodResponse = new MethodResponse();
		response.setThrowable(throwable);
		state.setMethodResponse(response, new MethodCallRange());
	}
	
	/**
	 * Recards that the mock object will by default allow the last method specified
	 * by a method call.
	 *
	 * <p>Default means that the method can be called zero to infinite times without
	 * expectation errors.
	 *
	 * <p>Calling this method is not necessary. The mock control expects the last
	 * method specified by a method call as soon as this method call occured.
	 *
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setDefaultVoidCallable(Void):Void {
		state.setMethodResponse(new MethodResponse(), new MethodCallRange());
	}
	
	/**
	 * @overload #setReturnValueByValue
	 * @overload #setReturnValueByValueAndQuantity
	 * @overload #setReturnValueByValueAndMinimumAndMaximumQuantity
	 */
	public function setReturnValue():Void {
		var o:Overload = new Overload(this);
		o.addHandler([Object], setReturnValueByValue);
		o.addHandler([Object, Number], setReturnValueByValueAndQuantity);
		o.addHandler([Object, Number, Number], setReturnValueByValueAndMinimumAndMaximumQuantity);
		o.forward(arguments);
	}
	
	/**
	 * Records that the mock object will expect the last method call once and will
	 * react by returning the provided return value.
	 *
	 * @param value the return value to return
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setReturnValueByValue(value):Void {
		setReturnValueByValueAndQuantity(value, 1);
	}
	
	/**
	 * Records that the mock object will expect the last method call a fixed number
	 * of times and will react by returning the provided return value.
	 *
	 * @param value the return value to return
	 * @param quantity the number of times the method is allowed to be invoked
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setReturnValueByValueAndQuantity(value, quantity:Number):Void {
		var response:MethodResponse = new MethodResponse();
		response.setReturnValue(value);
		state.setMethodResponse(response, new MethodCallRange(quantity));
	}
	
	/**
	 * Records that the mock object will expect the last method call between
	 * {@code minimumQuantity} and {@code maximumQuantity} times and will react by
	 * returning the provided return value.
	 *
	 * @param value the return value to return
	 * @param minimumQuantity the minimum number of times the method must be called
	 * @param maximumQuantity the maximum number of times the method can be called
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setReturnValueByValueAndMinimumAndMaximumQuantity(value, minimumQuantity:Number, maximumQuantity:Number):Void {
		var response:MethodResponse = new MethodResponse();
		response.setReturnValue(value);
		state.setMethodResponse(response, new MethodCallRange(minimumQuantity, maximumQuantity));
	}
	
	/**
	 * @overload #setThrowableByThrowable
	 * @overload #setThrowableByThrowableAndQuantity
	 * @overload #setThrowableByThrowableAndMinimumAndMaximumQuantity
	 */
	public function setThrowable():Void {
		var o:Overload = new Overload(this);
		o.addHandler([Object], setThrowableByThrowable);
		o.addHandler([Object, Number], setThrowableByThrowableAndQuantity);
		o.addHandler([Object, Number, Number], setThrowableByThrowableAndMinimumAndMaximumQuantity);
		o.forward(arguments);
	}
	
	/**
	 * Records that the mock object will expect the last method call once and will
	 * react by throwing the provided throwable.
	 *
	 * @param throwable the throwable to throw
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setThrowableByThrowable(throwable):Void {
		setThrowableByThrowableAndQuantity(throwable, 1);
	}
	
	/**
	 * Records that the mock object will expect the last method call a fixed number
	 * of times and will react by throwing the provided throwable.
	 *
	 * @param throwable the throwable to throw
	 * @param quantity the number of times the method is allowed to be invoked
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setThrowableByThrowableAndQuantity(throwable, quantity:Number):Void {
		var response:MethodResponse = new MethodResponse();
		response.setThrowable(throwable);
		state.setMethodResponse(response, new MethodCallRange(quantity));
	}
	
	/**
	 * Records that the mock object will expect the last method call between 
	 * {@code minimumQuantity} and {@code maximumQuantity times} and will react by
	 * throwing the provided throwable.
	 *
	 * @param throwable the throwable to throw
	 * @param minimumQuantity the minimum number of times the method must be called
	 * @param maximumQuantity the maximum number of times the method can be called
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setThrowableByThrowableAndMinimumAndMaximumQuantity(throwable, minimumQuantity:Number, maximumQuantity:Number):Void {
		var response:MethodResponse = new MethodResponse();
		response.setThrowable(throwable);
		state.setMethodResponse(response, new MethodCallRange(minimumQuantity, maximumQuantity));
	}
	
	/**
	 * @overload #setVoidCallableByVoid
	 * @overload #setVoidCallableByQuantity
	 * @overload #setVoidCallableByMinimumAndMaximumQuantity
	 */
	public function setVoidCallable():Void {
		var o:Overload = new Overload(this);
		o.addHandler([], setVoidCallableByVoid);
		o.addHandler([Number], setVoidCallableByQuantity);
		o.addHandler([Number, Number], setVoidCallableByMinimumAndMaximumQuantity);
		o.forward(arguments);
	}
	
	/**
	 * Records that the mock object will expect the last method call once and will
	 * react by returning silently.
	 *
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setVoidCallableByVoid(Void):Void {
		setVoidCallableByQuantity(1);
	}
	
	/**
	 * Records that the mock object will expect the last method call a fixed number
	 * of times and will react by returning silently.
	 *
	 * @param quantity the number of times the method is allowed to be invoked
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setVoidCallableByQuantity(quantity:Number):Void {
		state.setMethodResponse(new MethodResponse(), new MethodCallRange(quantity));
	}
	
	/**
	 * Records that the mock object will expect the last method call between 
	 * {@code minimumQuantity} and {@code maximumQuantity} times and will react by
	 * returning silently.
	 *
	 * @param minimumQuantity the minimum number of times the method must be called
	 * @param maximumQuantity the maximum number of times the method can be called
	 * @throws IllegalStateException if this mock control is in replay state
	 */
	public function setVoidCallableByMinimumAndMaximumQuantity(minimumQuantity:Number, maximumQuantity:Number):Void {
		state.setMethodResponse(new MethodResponse(), new MethodCallRange(minimumQuantity, maximumQuantity));
	}
	
	/**
	 * Verifies that all expectations have been met that could not been verified
	 * during execution.
	 *
	 * @throws IllegalStateException if this mock control is in record state
	 * @throws AssertionFailedError if an expectation has not been met
	 */
	public function verify(Void):Void {
		try {
			state.verify();
		} catch(error:org.as2lib.test.mock.MethodCallRangeError) {
			error.setType(type);
			throw error;
		}
	}
	
}