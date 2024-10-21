class LuminicBox.Utils.Delay {
	
	private var _tId:Number;
	
	public function Delay() {
		var delay:Number = Number(arguments.shift());
		_tId = setInterval(this, "onTimeout", delay, arguments);
	}
	
	public function cancel() {
		clear();
	}
	
	private function onTimeout(args) {
		clear();
		var scope:Object = args.shift();
		var func:Function = Function(args.shift());
		func.apply(scope, args);
	}
	
	private function clear() {
		clearInterval(_tId);
		delete _tId;
	}
	
}