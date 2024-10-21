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
import org.log4f.logging.Level;
import org.log4f.logging.Logger;
import org.log4f.logging.LogManager;
import org.log4f.logging.PropertyHandler;
import org.log4f.logging.DefaultPublisher;
import org.log4f.logging.AlertPublisher;

import org.log4f.logging.console.DebugModelPublisher;
import org.log4f.logging.console.DebugConsole;
import org.log4f.logging.console.DebugTitleWindow;

import mx.core.Application;
import mx.core.UIObject;

import mx.utils.Delegate;

import mx.managers.PopUpManager;

/**
 * The purpose of this class is to simplify the setup of common loggers and
 * publishers, so that projects which use Log4F can stay as decoupled from it
 * as possible.  The use of this class is entirely optional; projects which
 * want to manage all their loggers themselves can do so, copying and pasting
 * code from here where appropriate.
 */
class org.log4f.logging.LoggingConfig {
	//these exist as a hack to get the names into the app so _global works
	private static var ___hackPublisher1:DefaultPublisher;
	private static var ___hackPublisher2:AlertPublisher;
	private static var ___hackPublisher3:DebugModelPublisher;
	
	public var alertLogger:Logger;

	public var defaultLogger:Logger;

	public var debugModelLogger:Logger;

	public function LoggingConfig(loggingConfigModel) {
		var propHandler:PropertyHandler = new PropertyHandler();
//		if (loggingConfig.logging.enabled == "false") {
//			LogManager.getInstance().disableLogging();
//		}		
		var loggerObj = loggingConfigModel.logging.logger;
		if (loggerObj instanceof Array) {
			//if there is more than one, the <mx:Model> makes an array
			for (var i = 0; i < loggerObj.length; i++) {
				initLogger(loggerObj[i], propHandler);
			}
		} else {
			//if there is only one, the <mx:Model> just makes the object
			initLogger(loggerObj, propHandler);
		}
		alertLogger = Logger.getLogger("AlertLogger");
		defaultLogger = Logger.getLogger("DefaultLogger");
		debugModelLogger = Logger.getLogger("DebugModelLogger");
		
		//add the debug console context menu item to the Flash context menu
		var showDebugConsoleMenuItem:ContextMenuItem =
			new ContextMenuItem(
				"Show Log4F Debug Console",
				Delegate.create(this, showDebugConsole));
		var theCM = new ContextMenu();
		theCM.hideBuiltInItems();
		theCM.customItems.push(showDebugConsoleMenuItem);
		_root.menu = theCM;		
	}

	private function initLogger(
		logger:Object,
		propHandler:PropertyHandler)
	{
		propHandler.handleLoggerProperties(
			logger.name, logger.level, logger.filter);
		var pubsObj = logger.publisher;
		if (pubsObj instanceof Array) {
			//if there is more than one, the <mx:Model> makes an array
			for (var i = 0; i < pubsObj.length; i++) {
				initPublisher(pubsObj[i], logger, propHandler);
			}
		} else {
			//if there is only one, the <mx:Model> just makes the object
			initPublisher(pubsObj, logger, propHandler);
		}
	}	
	
	private function initPublisher(
		pub:Object,
		logger:Object,
		propHandler:PropertyHandler)
	{
		propHandler.handlePublisherProperties(
			logger.name, pub.name, pub.formatter, pub.level);
	}
	
	/**
	 * Show the debug console.
	 */
	private function showDebugConsole(obj, menu) {
		var appUI:UIObject = UIObject(Application.application);
		var w = .9 * appUI.width;
		PopUpManager.createPopUp(
			appUI,
			DebugTitleWindow,
			false,
			{width:w,
			 x:((appUI.width - w) / 2),
			 y:(appUI.height - DebugTitleWindow.HEIGHT)});
	}
}