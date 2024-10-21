/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 *
 * Copyright (c) 2005, Affinity Systems
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 * are permitted provided that the following conditions are met:
 * 
 * 1) Redistributions of source code must retain the above copyright notice, 
 *    this list of conditions and the following disclaimer.
 *  
 * 2) Redistributions in binary form must reproduce the above copyright notice, 
 *    this list of conditions and the following disclaimer in the documentation 
 *    and/or other materials provided with the distribution. 
 * 
 * 3) The name InfoEther, Inc. and Affinity Systems may not be used to endorse or promote products  
 *    derived from this software without specific prior written permission. 
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


/**
 * Class used to communicate with the FlashDebugTool, which can be found at
 * http://www.sourceforge.net/projects/flashdebugtool/
 *
 * The trace method is made for use the the MTASC compilers -trace argument.
 *
 * @author Scott Hyndman
 */
class org.actionstep.FDTDebugger 
{
	//
	// Configuration properties.
	// 
	static var SERVER_URL:String 	= "127.0.0.1";
	static var SERVER_PORT:Number 	= 4500;
					
	//
	// Debug levels
	// 
	static var DEBUG:Number 	= 2;
	static var INFO:Number 		= 3;
	static var WARNING:Number 	= 4;
	static var ERROR:Number		= 5;
	static var FATAL:Number 	= 6;
	
	/** True if the socket is connected. */
	static var g_connected:Boolean = false;
	
	/** The socket used to connect to the debugger. */
	static var g_socket:XMLSocket;
	
	//******************************************************															 
	//*					  Properties					   *
	//******************************************************
	//******************************************************															 
	//*					 Public Methods					   *
	//******************************************************
	//******************************************************															 
	//*					    Events						   *
	//******************************************************

	/**
	 * Fired when the socket connects.
	 *
	 * Scoped to the socket.
	 */	
	private static function socket_onConnect():Void
	{
		FDTDebugger.onConnect(); // scoped call
	}


	/**
	 * Fired when the socket connects.
	 *
	 * Scoped to FDTDebugger.
	 */	
	private static function onConnect():Void
	{
		g_connected = true;
	}


	/**
	 * Fired when the socket closes.
	 *
	 * Scoped to the socket.
	 */	
	private static function socket_onClose():Void
	{
		FDTDebugger.onClose(); // scoped call
	}
	
	
	/**
	 * Fired when the socket closes.
	 */
	private static function onClose():Void
	{
		g_connected = false;
	}
	
	
	/**
	 * Fired when the socket recieves data.
	 *
	 * Scoped to the socket.
	 */
	private static function socket_xmlRecieved(data:XML):Void
	{					
		FDTDebugger.onXmlRecieved(data.firstChild);
	}
	
	
	/**
	 * Fired when the socket recieves data.
	 *
	 * Scoped to FDTDebugger.
	 */
	private static function onXmlRecieved(data:XMLNode):Void
	{
		var response:XML = null;
		
		//! Extend here to add functionality, ie, remote method calls
		switch (data.attributes.type)
		{
			case "objectproperties":
				response = getObjectProperties(data.attributes.path);
				break;
		}
		
		//
		// Only send response if there is one.
		//
		if (response != null)
			g_socket.send(response.toString());
	}
	
	//******************************************************															 
	//*				    Protected Methods				   *
	//******************************************************
	//******************************************************															 
	//*					 Private Methods				   *
	//******************************************************
	//******************************************************															 
	//*			   Public Static Properties				   *
	//******************************************************
	//******************************************************															 
	//*				 Private Static Methods				   *
	//******************************************************
	
	/**
	 * Gets an XML document containing an object's properties
	 * from the object at path.
	 */
	private static function getObjectProperties(path:String):XML
	{
		//
		// Build initial xml object.
		//
		var xml:XML = new XML();
		xml.nodeName = "node";
		xml.attributes.type = "objectproperties";
		
		//
		// Find object
		//
		var obj:Object = getObjectFromPath(path);
		xml.attributes.path = path;
		
		//
		// Object doesn't exist
		//
		if (obj == null && typeof(obj) != "object")
		{
			xml.attributes.objecttype = "null";
			xml.attributes.value = "null";
			return xml;
		}
		
		//
		// Define object type
		//
		xml.attributes.objecttype = getObjectType(obj);
		
		//
		// Define object value and account for objects that for some reason
		// return undefined as their value.
		//
		if (obj.toString() == null)
		{
			xml.attributes.value = "object";
		}
		else
		{
			xml.attributes.value = obj.toString();
		}
				
		//
		// Fill object with property definitions
		//
		var prop:XMLNode;
		for (var p:String in obj)
		{			
			prop = xml.createElement("property");
			prop.attributes.value = obj[p];
			prop.attributes.path = path + "." + p;
			prop.attributes.objecttype = getObjectType(obj[p]);
			
			xml.appendChild(prop);
		}		
		
		return xml;
	}
	
	
	/**
	 * Returns the object that can be found at path.
	 *
	 * @param path A dot seperated path.
	 */
	private static function getObjectFromPath(path:String):Object
	{
		var parts:Array = path.split(".");
		
		var obj:Object;
		
		//
		// Determine the root object (_root or _global)
		//
		switch (parts[0])
		{
			case "_root":
				obj = _root;
				parts.shift();
				
				break;
				
			case "_global": // global variable
				parts.shift();
				obj = _global;
				break;
				
			default: // static class probably
				obj = _global;
				break;
				
		}
		
		//
		// Follow path to object.
		//
		for (var i:Number = 0; i < parts.length; i++)
		{
			obj = obj[parts[i]];
			
			//
			// Check if object exists
			//
			if (obj == null)
				return null;
		}
		
		return obj;
	}
	
	
	/**
	 * Gets the type of an object as a string.
	 */
	private static function getObjectType(obj:Object):String
	{
		if (obj instanceof Date)
			return "date";
		
		return typeof(obj);
	}
	
	//******************************************************															 
	//*				 Public Static Methods				   *
	//******************************************************
	
	/**
	 * Sends a trace message to the server.
	 * 
	 * This is intended for use with the MTASC -trace argument.
	 */
	public static function trace(msg:Object, level:Number, className:String, 
		file:String, line:Number) 
	{
		//
		// shift parameters if no level specified
		//
		if (line == undefined)
		{
			line = Number(file);
			file = className;
			className = String(level);
			level = FDTDebugger.DEBUG;
		}
		
		var clsParts = className.split("::");
		
		msg = msg.toString().split('"').join('\"');
		msg = msg.split("\n").join("");
		msg = msg.split("<").join("&lt;");
		msg = msg.split(">").join("&gt;");
		
		var obj:XML = new XML();
		obj.nodeName = "node";
		obj.attributes.type = "trace";
		obj.attributes.level = level;
		obj.attributes.cls = clsParts[0];
		obj.attributes.method = clsParts[1];
		obj.attributes.file = file;
		obj.attributes.line = line;
		obj.attributes.message = msg;
		
	//	if (!g_connected)
		//	g_socket.connect(SERVER_URL, SERVER_PORT);
			
		g_socket.send(obj.toString());
	}
		
		
	/**
	 * Creates a new connection.
	 */
	public static function resetConnection():Void
	{
		g_socket = new XMLSocket();
		g_socket.onClose = FDTDebugger.socket_onClose;
		g_socket.onConnect = FDTDebugger.socket_onConnect;
		g_socket.onXML = FDTDebugger.socket_xmlRecieved;
		g_socket.connect(SERVER_URL, SERVER_PORT);
	}
	
	//******************************************************															 
	//*				  Static Constructor				   *
	//******************************************************
	
	/**
	 * Resets the connection.
	 */
	private static function classConstruct():Boolean
	{
		if (classConstructed)
			return true;
			
		resetConnection();
		return true;
	}
	
	private static var classConstructed:Boolean = classConstruct();
}
