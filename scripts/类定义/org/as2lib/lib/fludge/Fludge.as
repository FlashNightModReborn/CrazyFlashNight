class Fludge {
	static private var _idCnt:Number = 0;
	static private var _observed:Object = {};
	
	static function trace( message:String, debug:String ):Void {
		switch( debug ) {
			case "warn":
				fscommand( "warning", message );
				break;
			case "error":
				fscommand( "error", message );
				break;
			case "exception":
				fscommand( "exception", message );
				break;
			default:
				fscommand( "info", message );
		}
	}
	
	static function display ( label:String, value:Object ):Void {
		if( !((Fludge._observed)[ label ]) ) {
			(Fludge._observed)[ label ] = true;
			fscommand( "watchProperty", label + "|$|" + label + "|$|" + value );
		} else {
			fscommand( "updateProperty", label + "|$|" + value );
		}
	}
	
	static function remove ( label:String ) {
		delete (Fludge._observed)[ label ];
		fscommand( "unwatchProperty", label );
	}
}
