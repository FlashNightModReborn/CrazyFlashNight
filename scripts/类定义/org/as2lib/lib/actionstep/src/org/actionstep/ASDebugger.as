/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1) Redistributions of source code must retain the above copyright notice,
 *		this list of conditions and the following disclaimer.
 *
 * 2) Redistributions in binary form must reproduce the above copyright notice,
 *		this list of conditions and the following disclaimer in the documentation
 *		and/or other materials provided with the distribution.
 *
 * 3) The name InfoEther, Inc. may not be used to endorse or promote products
 *		derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

 import org.actionstep.NSException;

 class org.actionstep.ASDebugger {

	static var ALL:Number = 5;
	static var DEBUG:Number = 4;
	static var INFO:Number = 3;
	static var WARNING:Number = 2;
	static var ERROR:Number = 1;
	static var FATAL:Number = 0;
	static var NONE:Number = -1;
	static var LEVELS:Array = ["[FATAL] ", "[ERROR] ", "[WARNING] ", "[INFO] ", "[DEBUG] "];

	static var DEFAULT_HOSTNAME:String = "127.0.0.1";
	static var DEFAULT_PORT:Number = 4500;
	static var handlers:Array = [];
	static var instance:ASDebugger;
	static var block:Object;

	public static function error(object:Object):Object {
		return {ASDebuggerObject:object, ASDebuggerLevel:ERROR};
	}

	public static function fatal(object:Object):Object {
		return {ASDebuggerObject:object, ASDebuggerLevel:FATAL};
	}

	public static function info(object:Object):Object {
		return {ASDebuggerObject:object, ASDebuggerLevel:INFO};
	}

	public static function warning(object:Object):Object {
		return {ASDebuggerObject:object, ASDebuggerLevel:WARNING};
	}

	public static function debug(object:Object):Object {
		return {ASDebuggerObject:object, ASDebuggerLevel:DEBUG};
	}

	var m_hostname:String;
	var m_connected:Boolean;
	var m_identifier:String;
	var m_connection:XMLSocket;
	var m_port:Number;
	static var g_level:Number;

	/*
	 * Outputs a message at the supplied level.	Level defaults to
	 * INFO if not supplied.	This method is used by the MTASC compiler
	 * through using the -trace org.actionstep.ASDebugger.trace method.
	 *
	 * @param object The object to output (via toString)
	 * @param level The level (DEBUG, INFO, WARNING, ERROR, FATAL)
	 * @param className The class the trace is in
	 * @param file The file the trace is in
	 * @param line The line number that trace is on
	 *
	 */
	public static function trace(object:Object, level:Number, className:String, file:String, line:Number) {
		if (ASDebugger.instance == undefined) {
			ASDebugger.start(g_level);
		}
		// We need to shift all the params if the level is not provided
		if (line == undefined) {
			line = Number(file);
			file = className;
			className = String(level);
			level = g_level;
		}
		if (object instanceof NSException) {
			NSException(object).setReference(className, file, line);
			return;
		}
		if (object.ASDebuggerObject != undefined) {
			level = object.ASDebuggerLevel;
			object = object.ASDebuggerObject;
		}
		if (level > 4) {
			level = 4;
		}
		if (level < 0) {
			level = 0;
		}

		notifyHandlers(object, level, className, file, line);

		 //don't show abs path
		var x:Array = file.split("/");
		file = x[x.length-1];

		//don't display for some classes
		var arr:Array=className.split("::");
		var klass:String = arr[0];
		if(block[klass])	
			return;
			
		var func:String = arr[1];

		if (ASDebugger.instance.level() >= level) {
			ASDebugger.instance.send(LEVELS[level]+object.toString()+" -- "+klass+":"+line+" ("+func+")");
		}
	}

	public static function SWFConsoleTrace(object:Object, level:Number, className:String, file:String, line:Number) {
		// We need to shift all the params if the level is not provided
		if (line == undefined) {
			line = Number(file);
			file = className;
			className = String(level);
			level = g_level;
		}
		if (object instanceof NSException) {
			NSException(object).setReference(className, file, line);
			return;
		}
		if (object.ASDebuggerObject != undefined) {
			level = object.ASDebuggerLevel;
			object = object.ASDebuggerObject;
		}
		if (level > 4) {
			level = 4;
		}
		if (level < 0) {
			level = 0;
		}

		 //don't show abs path
		var x:Array = file.split("/");
		file = x[x.length-1];

		//don't display for some classes
		var arr:Array=className.split("::");
		var klass:String = arr[0];
		if(block[klass])	
			return;
		var func:String = arr[1];

		getURL("javascript:showText('" + LEVELS[level]+object.toString()+" -- "+klass+":"+line+" ("+className.split("::")[1]+")')");
	}

	/**
	* Prints the source ot flash var
	*/
	public static function dump(obj:Object):Object {
		if(obj == null) return null;

		switch( obj.constructor ){

			case Number:
				return obj;

			case String:
				return	"String(" + obj + ")";

				case Array:
				var els:Array = [];
				for(var key:Object in obj){
					els[els.length] = ""
					+ key
					+ ":"
					+ dump(obj[key]);
				}
				return "Array("+els.join(", ")+")";
			case Object:
			case TextField:	//default + dom
				var els:Array = [];
				for(var key:Object in obj){
					els[els.length] = ""
					+ key
					+ ":"
					+ dump(obj[key]);
				}
				return "Object("+els.join(", ")+")";

			default :
				return obj.toString();
		}
	}

	public static function addHandler(obj:Object, sel:String):Void {
		handlers.push({obj: obj, sel: sel});
	}

	public static function notifyHandlers(object:Object, level:Number, className:String, file:String, line:Number) {
		var len:Number = handlers.length;
		for (var i:Number = 0; i < len; i++) {
			var obj:Object = handlers[i].obj;
			var sel:String = handlers[i].sel;

			obj[sel].call(obj, object, level, className, file, line);
		}
	}

	function ASDebugger(hostname:String, given_port:Number) {
		if (hostname != undefined) {
			this.m_hostname = hostname;
		} else {
			this.m_hostname = DEFAULT_HOSTNAME;
		}

		if (given_port != undefined) {
			m_port = given_port;
		} else {
			m_port = DEFAULT_PORT;
		}

		g_level = DEBUG;
	}



	/*
	 * Sets the level of the debugger
	 *
	 * @param level The level (DEBUG, INFO, WARNING, ERROR, FATAL)
	 *
	 */
	public static function setLevel(level:Number) {
		if (ASDebugger.instance == undefined) {
			ASDebugger.start(level);
		} else {
			ASDebugger.instance.setCurrentLevel(level);
		}
	}

	public static function start(level:Number, hostname:String, given_port:Number):ASDebugger {
		ASDebugger.instance = new ASDebugger(hostname, given_port);
		if (level != undefined) {
			ASDebugger.instance.setCurrentLevel(level);
		}
		ASDebugger.instance.begin();
		return ASDebugger.instance;
	}

	function begin() {
		m_connection = new XMLSocket();
		var self:ASDebugger = this;
		m_connection.onConnect = function(success) {
			self.onConnect(success);
		};
		m_connection.onData = function(data) {
			self.onMessage(data);
		};
		m_connection.connect(m_hostname, m_port);
	}

	function setCurrentLevel(value:Number) {
		g_level = value;
	}

	/**
	 * Returns the level of the debugger.
	 */
	function level():Number {
		return g_level;
	}

	public function onClose():Void {
	}

	public function onConnect(isConnected:Boolean):Void {
		m_connected = isConnected;
		if(isConnected) {
			block ={	};
			//eg:
			//block["org/actionstep/test/ASTestSheet.as"] = true;
			var x:String = "";
			for(var i:Object in block) {
				x+="\n\t"+i+"";
			}
			if(x!="") {
				send(">>Blocked classes:"+x);
			}
		}
	}

	public function onMessage(message:String):Void {
		//Ignore
	}

	public function send(message:String) {
		m_connection.send(message);
	}
}
