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

import org.as2lib.util.Stringifier;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.log.LogHandler;
import org.as2lib.env.log.LogMessage;
import org.as2lib.env.log.handler.AbstractLogHandler;

/**
 * {@code XmlSocketHandler} uses the {@code XMLSocket} to log the message.
 * 
 * <p>It was originally designed to work with the POWERFLASHER's SOS
 * XML-Socket-Server but you can use it for any output device that is accessible
 * over the XML socket.
 * 
 * @author Simon Wacker
 * @see SosSocketHandler
 * @see <a href="http://sos.powerflasher.com">SOS - SocketOutputServer</a>
 */
class org.as2lib.env.log.handler.XmlSocketHandler extends AbstractLogHandler implements LogHandler {
	
	/** Socket to connect to the specified host. */
	private var socket:XMLSocket;
	
	/**
	 * Constructs a new {@code XmlSocketHandler} instance.
	 * 
	 * @param host a fully qualified DNS domain name
	 * @param port the TCP port number on the host used to establish a connection
	 * @param messageStringifier (optional) the log message stringifier to use
	 * @throws IllegalArgumentException if the passed-in {@code port} is {@code null}
	 * or less than 1024
	 * @todo throw exception when unable to connect
	 */
	public function XmlSocketHandler(host:String, port:Number, messageStringifier:Stringifier) {
		if (port == null || port < 1024) {
			throw new IllegalArgumentException("Argument 'port' [" + port + "] must not be 'null' nor less than 1024.", this, arguments);
		}
		this.socket = new XMLSocket();
		this.socket.connect(host, port);
		this.messageStringifier = messageStringifier;
	}
	
	/**
	 * Uses the xml socket connection to log the passed-in message.
	 *
	 * <p>The string representation of the {@code message} to log is obtained via
	 * the {@code convertMessage} method.
	 *
	 * @param message the message to log
	 */
	public function write(message:LogMessage):Void {
		this.socket.send(convertMessage(message) + "\n");
	}
	
}