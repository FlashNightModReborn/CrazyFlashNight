/*
   Copyright 2004 Peter Armstrong

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
import org.log4f.logging.LogRecord;
import mx.events.EventDispatcher;

/**
 * A DebugModel is a Singleton which has the error messages for the application.
 * @author Peter Armstrong
 */
[Event("modelChanged")]
class org.log4f.logging.console.DebugModel {
	//begin mixin stuff
	private static var EventDispatcherDependency = EventDispatcher;
	public var addEventListener:Function;
	public var removeEventListener:Function;
	private var dispatchEvent:Function;
	private static function staticConstructor(Void):Boolean {
		EventDispatcher.initialize(DebugModel.prototype);
		return true;
	}
	private static var staticConstructed:Boolean = staticConstructor();
	//end mixin stuff

	private static var _instance:DebugModel;
	
	public var messages:Array;
	
	private function DebugModel(Void) {
		messages = new Array();
	}
	
	public static function getSharedInstance():DebugModel {
		if (_instance == null) {
			_instance = new DebugModel();
		}
		return _instance;
	}
	
	public function clearMessages() {
		messages = new Array();
		dispatchEvent({type:"modelChanged"});
	}
	
	public function addMessage(msg:LogRecord) {
		messages.push(msg);
		dispatchEvent({type:"modelChanged"});
	}
}