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
import org.as2lib.env.log.LogHandler;
import org.as2lib.env.log.LogMessage;

/**
 * {@code Bit101Handler} logs messages to the Bit-101 Debug Panel.
 *
 * <p>The {@code Debug} class is needed.
 *
 * @author Simon Wacker
 * @see org.as2lib.env.log.logger.Bit101Logger
 * @see <a href="www.bit-101.com/DebugPanel">Flash Debug Panel Source</a>
 * @see <a href="http://www.bit-101.com/blog/archives/000119.html">Flash Debug Panel Article</a>
 */
class org.as2lib.env.log.handler.Bit101Handler extends BasicClass implements LogHandler {
	
	/** Holds a bit-101 handler. */
	private static var bit101Handler:Bit101Handler;
	
	/**
	 * Returns an instance of this class.
	 *
	 * <p>This method always returns the same instance.
	 *
	 * <p>Note that the arguments are only recognized on first call of this method and
	 * are in this case used for construction of the {@code Bit101Handler} instance.
	 *
	 * @param decorateMessage (optional) determines whether to log the string returned
	 * by the {@code LogMessage.toString} method or just the message returned by
	 * {@code LogMessage.getMessage}
	 * @param recursionDepth (optional) determines the count of recursions for
	 * recursively traced objects
	 * @param indentation (optional) determines the indentation number for recursively
	 * traced objects
	 * @return a bit-101 handler
	 */
	public static function getInstance(decorateMessage:Boolean, recursionDepth:Number, indentation:Number):Bit101Handler {
		if (!bit101Handler) bit101Handler = new Bit101Handler(decorateMessage, recursionDepth, indentation);
		return bit101Handler;
	}
	
	/** Determines whether to decorate messages. */
	private var decorateMessage:Boolean;
	
	/** The number of recursions when tracing an object recursively. */
	private var recursionDepth:Number;
	
	/** The indentation number for recursively traced objects. */
	private var indentation:Number;
	
	/**	
	 * Constructs a new {@code Bit101Handler} instance.
	 *
	 * <p>You can use one and the same instance for multiple loggers. So think about
	 * using the handler returned by the static {@link #getInstance} method. Using
	 * this instance prevents the instantiation of unnecessary bit-101 handlers and
	 * saves storage.
	 *
	 * <p>{@code decorateMessage} is by default {@code true}. Refer to the
	 * {@code Debug} class for information on the default {@code recursionDepth} and
	 * {@code indentation}.
	 *
	 * <p>Note that messages are only logged recursively if {@code decorateMessage} is
	 * set to {@code false}.
	 *
	 * @param decorateMessage (optional) determines whether to log the string returned
	 * by the {@code LogMessage.toString} method or just the message returned by
	 * {@code LogMessage.getMessage}
	 * @param recursionDepth (optional) determines the count of recursions for
	 * recursively traced objects
	 * @param indentation (optional) determines the indentation number for recursively
	 * traced objects
	 */
	public function Bit101Handler(decorateMessage:Boolean, recursionDepth:Number, indentation:Number) {
		this.decorateMessage = decorateMessage == null ? true : decorateMessage;
		this.recursionDepth = recursionDepth;
		this.indentation = indentation;
	}
	
	/**
	 * Writes log messages to the Bit-101 Debug Panel.
	 *
	 * <p>Uses the {@link LogMessage#toString} method to obtain the string that is
	 * logged if {@code decorateMessage} is turned on. Otherwise the string returned
	 * by the original message's {@code toString} method is logged if it is of type
	 * {@code 'string'}, {@code 'number'}, {@code 'boolean'}, {@code 'undefined'} or
	 * {@code 'null'} or the original method is logged recursively if it is not of one
	 * of the above types.
	 *
	 * @param message the message to log
	 */
	public function write(message:LogMessage):Void {
		if (this.decorateMessage) {
			Debug.trace(message.toString());
		} else {
			var type:String = typeof(message.getMessage());
			if (type == "string" || type == "number" || type == "boolean" || type == "undefined" || type == "null") {
				Debug.trace(message.getMessage().toString());
			} else {
				Debug.traceObject(message.getMessage(), this.recursionDepth, this.indentation);
			}
		}
	}
	
}