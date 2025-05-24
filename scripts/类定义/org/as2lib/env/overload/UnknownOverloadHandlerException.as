﻿/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.env.overload.OverloadException;
import org.as2lib.env.reflect.ReflectUtil;

/**
 * {@code UnknownOverloadHandlerException} will be thrown if no appropriate overload
 * handler for a list of real arguments could be found.
 *
 * <p>Whether an overload handler matches a given list of real arguments is determined
 * by the {@link OverloadHandler#matches} method.
 *
 * @author Simon Wacker
 * @author Martin Heidegger
 */
class org.as2lib.env.overload.UnknownOverloadHandlerException extends OverloadException {
	
	/** Exception printed as string */
	private var asString:String;
	
	/** Arguments used by overloading */
	private var overloadArguments:Array;
	
	/** Handlers that where available by the unknown overloadHandler */
	private var overloadHandlers:Array;
	
	/** The object on which the overload should have taken place. */
	private var overloadTarget;
	
	/** The method that performs the overloading. */
	private var overloadedMethod:Function;
	
	/**
	 * Constructs a new {@code UnknownOverloadHandlerException} instance.
	 * 
	 * @param message the message of the exception
	 * @param thrower the object whose method threw the exception
	 * @param args the arguments of the method that threw the exception
	 * @param overloadTarget the target object the method should be invoked on / on
	 * which the overload is performed
	 * @param overloadedMethod the method that is overloaded
	 * @param overloadArguments the real arguments used to perform the overloading
	 * @param overloadHandlers an array containing all {@code OverloadHandler} instances
	 * that do not match the overload arguments
	 */
	public function UnknownOverloadHandlerException(message:String, thrower, args:Array, overloadTarget, overloadedMethod:Function, overloadArguments:Array, overloadHandlers:Array) {
		super (message, thrower, args);
		this.overloadTarget = overloadTarget;
		this.overloadedMethod = overloadedMethod;
		this.overloadArguments = overloadArguments;
		this.overloadHandlers = overloadHandlers;
	}
	
	/**
	 * Returns a well formatted informative string representation of this exception.
	 * 
	 * @return the string representation of this exception
	 */
	private function doToString(Void):String {
		// The resulting string gets constructed lazily and gets stored once it has been generated.
		// It would take unnecessary much time to generate the string representation if you'd catch
		// it and it would never get displayed.
		if (!asString) {
			asString = message;
			var info:Array = ReflectUtil.getTypeAndMethodInfo(overloadTarget, overloadedMethod);
			asString += "\n  Overloaded Method: ";
			asString += info[0] == null ? "[unknown]" : (info[0] ? "static " : "");
			asString += info[1] == null ? "[unknown]" : info[1];
			asString += "." + (info[2] == null ? "[unknown]" : info[2]);
			asString += "\n  Used Arguments["+overloadArguments.length+"]: ";
			for (var i:Number = 0; i < overloadArguments.length; i++) {
				if (i != 0) {
					asString += ", ";
				}
				asString += overloadArguments[i];
			}
			asString += "\n  Used Handlers: ";
			for(var i:Number = 0; i < overloadHandlers.length; i++) {
				asString += "\n    "+overloadHandlers[i].toString();
			}
		}
		return asString;
	}
	
}