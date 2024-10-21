//****************************************************************************
//*																			 *
//*					  COPYRIGHT 2004 Scott Hyndman							 *
//*						 ALL RIGHTS RESERVED					   			 *
//*																			 *
//****************************************************************************


/**
 *
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSDebugger 
{			
	static var DEBUG:Number 	= 2;
	static var INFO:Number 		= 3;
	static var WARNING:Number 	= 4;
	static var ERROR:Number		= 5;
	static var FATAL:Number 	= 6;
	
	static var SERVER_URL:String 	= "127.0.0.1";
	static var SERVER_PORT:Number 	= 4500;
	
	static var g_connected:Boolean = false;
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
	
	private static function socket_onConnect():Void
	{
		NSDebugger.onConnect();
	}
	
	private static function onConnect():Void
	{
		
	}
	
	private static function socket_onClose():Void
	{
		NSDebugger.onClose();
	}
	
	private static function onClose():Void
	{
		
	}
	
	private static function socket_xmlRecieved(data:XML):Void
	{			
		TRACE("XML Recieved");
		
		NSDebugger.onXmlRecieved(data.firstChild);
	}
	
	private static function onXmlRecieved(data:XMLNode):Void
	{
		var response:XML = null;
		
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
		
		
		
		TRACE("hit");
		
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
	
	private static function getObjectType(obj:Object):String
	{
		if (obj instanceof Date)
			return "date";
		
		return typeof(obj);
	}
	
	//******************************************************															 
	//*				 Public Static Methods				   *
	//******************************************************
	
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
			level = NSDebugger.INFO;
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
		
		if (!g_connected)
			g_socket.connect(SERVER_URL, SERVER_PORT);
			
		g_socket.send(obj.toString());
	}
		
	public static function resetConnection():Void
	{
		g_socket = new XMLSocket();
		g_socket.onClose = NSDebugger.socket_onClose;
		g_socket.onConnect = NSDebugger.socket_onConnect;
		g_socket.onXML = NSDebugger.socket_xmlRecieved;
		g_socket.connect(SERVER_URL, SERVER_PORT);
		g_connected = true;
	}
	
	//******************************************************															 
	//*				  Static Constructor				   *
	//******************************************************
	private static function classConstruct():Boolean
	{
		if (classConstructed)
			return true;
			
		resetConnection();
		return true;
	}
	
	private static var classConstructed:Boolean = classConstruct();
}
