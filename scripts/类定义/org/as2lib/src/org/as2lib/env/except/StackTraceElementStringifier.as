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
import org.as2lib.util.Stringifier;
import org.as2lib.env.except.StackTraceElement;
import org.as2lib.env.reflect.ReflectUtil;
import org.as2lib.util.StringUtil;

/**
 * {@code StackTraceElementStringifier} stringifies {@link StackTraceElement}
 * instances.
 *
 * @author Simon Wacker
 * @author Martin Heidegger
 */
class org.as2lib.env.except.StackTraceElementStringifier extends BasicClass implements Stringifier {
	
	/** Default name if an information is unknown. */
	public static var UNKNOWN:String = "[unknown]";
	
	/** Show the real arguments. */
	private var showArgumentsValues:Boolean;
	
	/**
	 * Constructs a new {@code StackTraceElementStringifier} instance.
	 *
	 * <p>By default the types of the arguments are shown and not their value.
	 *
	 * @param showArgumentsValues determines whether to show a string representation
	 * of the arguments' values, that is the string that is returned by their
	 * {@code toString} methods ({@code true}) or only the types of the arguments
	 * ({@code false}).
	 */
	public function StackTraceElementStringifier(showArgumentsValues:Boolean) {
		this.showArgumentsValues = showArgumentsValues;
	}
	
	/**
	 * Returns the string representation of the passed-in {@link StackTraceElement}
	 * instance.
	 *
	 * <p>The string representation is composed as follows:
	 * <pre>
	 *   static theFullQualifiedNameOfTheThrower.theMethodName(theFirstArgument, ..)
	 * </pre>
	 *
	 * <p>Depending on the settings arguments are either represented by their types of
	 * by the result of their {@code toString} methods.
	 *
	 * <p>A real string representation could look like this:
	 * <pre>org.as2lib.data.holder.MyDataHolder.setMaximumLength(Number)</pre>
	 * 
	 * <p>Or this:
	 * <pre>org.as2lib.data.holder.MyDataHolder.setMaximumLength(-2)</pre>
	 *
	 * <p>If an element is {@code null} or its string representation could not been
	 * obtained the string '[unknown]' is used.
	 *
	 * <p>If the method of the stack trace element is the constructor of the thrower
	 * the string {@code "new"} is used.
	 *
	 * @param target the {@code StackTraceElement} instance to stringify
	 * @return the string representation of the passed-in {@code target} element
	 */
	public function execute(target):String {
		var element:StackTraceElement = target;
		var result:String;
		try {
			var info:Array = ReflectUtil.getTypeAndMethodInfo(element.getThrower(), element.getMethod());
			result = info[0] == null ? UNKNOWN + " " : (info[0] ? "static " : "");
			result += info[1] == null ? UNKNOWN : info[1];
			result += "." + (info[2] == null ? UNKNOWN : info[2]);
			result += "(";
			if (showArgumentsValues) {
				result += element.getArguments().toString() ? element.getArguments().toString() : UNKNOWN;
			} else {
				var args:Array = element.getArguments();
				for (var i:Number = 0; i < args.length; i++) {
					var argType:String = ReflectUtil.getTypeName(args[i]);
					if (argType == null) argType = UNKNOWN;
					result += argType;
					if (i < args.length-1) result += ", ";
				}
			}
			result += ")";
		} catch(e) {
			result = "Exception was thrown during generation of string representation of stack trace element: \n" + StringUtil.addSpaceIndent(e.toString(), 2);
		}
		return result;
	}
	
}