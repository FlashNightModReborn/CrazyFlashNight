/*
    Debug class for use with bit-101 Flash Debug Panel
    See www.bit-101.com/DebugPanel
*/
class Debug
{
    private static var lc:LocalConnection;
    
    private function Debug()
    {
        // can't make an instance
    }
    
    public static function trace():Void
    {
        var msg:String = "";
        for(var i=0;i<arguments.length;i++)
        {
            msg += arguments[i];
            if(i<arguments.length-1)
            {
                msg += ", ";
            }
        }
        lc = new LocalConnection();
        lc.send("trace", "trace", msg);
    }

	public static function traceObject(o:Object, recurseDepth:Number, indent:Number):Void {
		if(recurseDepth == undefined){
			var recurseDepth:Number = 0;
		}
		if(indent == undefined){
			var indent:Number = 0;
		}
		for(var prop in o){
			var lead:String = "";
			for(var i=0;i<indent;i++){
				lead += "    ";
			}
			var obj:String = o[prop].toString();
			if(o[prop] instanceof Array)
			{
			    obj = "[Array]";
			}
			if(obj == "[object Object]")
			{
    			obj = "[Object]";
    		}
			Debug.trace(lead + prop + ": " + obj);// + " (" + typeof o[prop] + ")");
			if(recurseDepth > 0){
				traceObject(o[prop], recurseDepth-1, indent+1);
			}
		}
	}
	
	public static function clear(Void):Void
	{
        lc = new LocalConnection();
        lc.send("trace", "clear");
    }
}