import LuminicBox.Log.Level;

class LuminicBox.FlashInspector.LogEventCollection extends Array {
	
	public function getByLevel(level:Level):LogEventCollection {
		if(level == Level.ALL) return this;
		var levelValue:Number = level.getValue();
		var events:LogEventCollection = new LogEventCollection();
		var count:Number = this.length;
		for(var i:Number=0; i<count; i++) {
			if(this[i].level.getValue() >= levelValue) events.push(this[i]);
		}
		return events;
	}
	
	public function clear() {
		this.splice(0);
	}
	
}