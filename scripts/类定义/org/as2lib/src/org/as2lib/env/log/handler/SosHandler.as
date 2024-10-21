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

import org.as2lib.env.log.handler.XmlSocketHandler;
import org.as2lib.util.Stringifier;
import org.as2lib.env.log.stringifier.SosMessageStringifier;

/**
 * {@code SosHandler} uses the {@code XMLSocket} to log the message to
 * POWERFLASHER's SOS XML-Socket-Server.
 * 
 * <p>It logs colorized and formatted debug information to POWERFLASHER's SOS
 * XML-Socket-Server
 * 
 * @author Christoph Atteneder
 * @see <a href="http://sos.powerflasher.com">SOS - SocketOutputServer</a>
 */
class org.as2lib.env.log.handler.SosHandler extends XmlSocketHandler {
	
	/** Color of debug messages. */
	private static var DEBUG:Number = 0xFFFFFF;
	
	/** Key of debug messages. */
	public static var DEBUG_KEY:String = "DEBUG";
	
	/** Color of info messages. */
	private static var INFO:Number = 0xD9D9FF;
	
	/** Key of info messages. */
	public static var INFO_KEY:String = "INFO";
	
	/** Color of warning messages. */
	private static var WARNING:Number = 0xFFFFCE;
	
	/** Key of warning messages. */
	public static var WARNING_KEY:String = "WARNING";
	
	/** Color of error messages. */
	private static var ERROR:Number = 0xFFBBBB;
	
	/** Key of error messages. */
	public static var ERROR_KEY:String = "ERROR";
	
	/** Color of fatal messages. */
	private static var FATAL:Number = 0xCC99CC;
	
	/** Key of fatal messages. */
	public static var FATAL_KEY:String = "FATAL";
	
	/**
	 * Constructs a new {@code SosHandler} instance.
	 * 
	 * <p>If {@code messageStringifier} is not specified an instance of class
	 * {@link SosMessageStringifier} will be used.
	 * 
	 * @param messageStringifier (optional) the log message stringifier to use
	 */
	public function SosHandler(messageStringifier:Stringifier) {
		super("localhost", 4445, (!messageStringifier ? new SosMessageStringifier() : messageStringifier));
		socket.send("<setKey><name>" + DEBUG_KEY + "</name><color>" + DEBUG + "</color></setKey>");		socket.send("<setKey><name>" + INFO_KEY + "</name><color>" + INFO + "</color></setKey>");		socket.send("<setKey><name>" + WARNING_KEY + "</name><color>" + WARNING + "</color></setKey>");		socket.send("<setKey><name>" + ERROR_KEY + "</name><color>" + ERROR + "</color></setKey>");		socket.send("<setKey><name>" + FATAL_KEY + "</name><color>" + FATAL + "</color></setKey>");
	}
	
}