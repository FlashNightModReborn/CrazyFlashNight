/*
 * Alcon (Actionscript Logging Console) v1.0.5 2005/6/16
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * Sascha Balkau <sascha@hiddenresource.corewatch.net>
 */

import mx.controls.TextArea;
import mx.utils.Delegate;


/**
 * Console Class
 * @version		1.0.5 2005/07/04
 * @author			Sascha Balkau
 */
class Console
{
	// App information:
	private var APP_NAME:String		= "Alcon";
	private var APP_VERSION:String	= "1.0.5";
	private var APP_YEAR:String		= "2005";
	private var APP_WEBSITE:String	= "hiddenresource.corewatch.net";
	private var APP_AUTHOR:String		= "Sascha Balkau";
	
	// Config filename:
	private var CFG_FILE:String		= "Alcon.cfg";
	
	// Default settings:
	private var FONT_FACE:String		= "Courier New";
	private var FONT_SIZE:String		= "11";
	private var BUFFER_LENGTH:String	= "6000";
	private var BUFFER_INFO:String	= "true";
	private var WIN_XPOS:String		= "20";
	private var WIN_YPOS:String		= "20";
	private var WIN_WIDTH:String		= "300";
	private var WIN_HEIGHT:String		= "600";
	private var USE_COLORS:String		= "true";
	private var BG_COLOR:String		= "f2f2f2";
	private var LEVEL_0_COLOR:String	= "0055aa";
	private var LEVEL_1_COLOR:String	= "000000";
	private var LEVEL_2_COLOR:String	= "ff8800";
	private var LEVEL_3_COLOR:String	= "ff3300";
	private var LEVEL_4_COLOR:String	= "bb0000";
	private var DELIMITER:String		= "--------------------------------";

	// Object for context menu:
	private var ctMenu:ContextMenu;
	
	// Keeps message if settings load succeeded or not:
	private var lsuccess:String = "";

	// Determines paused mode:
	private var paused:Boolean = true;

	// Textarea object:
	private var output_area:TextArea;
	
	// LocalConnection object:
	private var alcon_lc:LocalConnection;
	
	// A reference to the mask clip:
	private var mask_mc:MovieClip;
	
	
	
	/**
	* Constructor
	*/
	public function Console()
	{
		createContextMenu();
		loadSettings();
		Key.addListener(this);
	}
	
	
	
	/**
	* main()
	* Program entry point.
	*/
	public static function main():Void
	{
		var newConsole:Console = new Console();
	}
	
	
	
	/**
	 * initScreen()
	 * @description				Sets up screen and mask behavior.
	 * @param lColors:Array		An array that contains the level color values.	 */
	private function initScreen(lColors:Array):Void
	{
		// Set stage to noScale and align to top left corner:
		Stage.scaleMode = "noScale";
		Stage.align = "TL";
		
		// Place Text Area:
		output_area = _root.createClassObject(TextArea, "output_area", 0);
		output_area.setStyle("backgroundColor", parseInt("0x" + BG_COLOR));
		output_area.setStyle("fontFamily", FONT_FACE);
		output_area.setStyle("fontSize", FONT_SIZE);
		output_area.setStyle("color", parseInt("0x" + lColors[1]));
		output_area.move(-2, -2);
		output_area.setSize((Stage.width + 4), (Stage.height + 4));
		output_area.editable = false;
		output_area.wordWrap = true;
		output_area.vScrollPolicy = "on";
		
		// Adding a mask which is used to indicate pause mode:
		mask_mc = _root.attachMovie("mask_mc", "mask_mc", 1);
		mask_mc._x = 0;
		mask_mc._y = 0;
		mask_mc._width = Stage.width;
		mask_mc._height = Stage.height;
		mask_mc._visible = false;
		
		// Set resize functionality for output area:
		var stageListener:Object = new Object();
		stageListener.onResize = Delegate.create(this, function():Void
		{
			this.output_area.move(-2, -2);
			this.output_area.setSize((Stage.width + 4), (Stage.height + 4));
			this.mask_mc._x = 0;
			this.mask_mc._y = 0;
			this.mask_mc._width = Stage.width;
			this.mask_mc._height = Stage.height;
		});
		Stage.addListener(stageListener);
	}
	
	
	
	/**
	* createContextMenu()
	* Set up the context menu.
	*/
	private function createContextMenu():Void
	{
		// Nested functions:
		var ctPause:Function;
		ctPause = Delegate.create(this, function():Void
		{
			this.paused = true;
			this.mask_mc._visible = true;
			this.mask_mc._alpha = 30;
			_root.sendToStatusBar("Paused");
		});
		var ctContinue:Function;
		ctContinue = Delegate.create(this, function():Void
		{
			this.mask_mc._visible = false;
			this.mask_mc._alpha = 100;
			_root.sendToStatusBar("");
			this.paused = false;
		});
		var ctClearBuffer:Function;
		ctClearBuffer = Delegate.create(this, function():Void
		{
			this.paused = true;
			this.output_area.text = "";
			_root.sendToStatusBar("Buffer cleared");
			this.paused = false;
		});
		var ctReset:Function;
		ctReset = Delegate.create(this, function():Void
		{
			this.alcon_lc.close();
			_root.gotoAndPlay(1);
		});
		var ctGoToWebsite:Function;
		ctGoToWebsite = Delegate.create(this, function():Void
		{
			getURL("http://" + this.APP_WEBSITE + "/", "_top");
		});
		var ctAbout:Function;
		ctAbout = Delegate.create(this, function():Void
		{
			this.paused = true;
			var about_lc = new LocalConnection();
			var aboutMsg:String =	"********************************\n";
			aboutMsg +=	"* " + this.APP_NAME + " v" + this.APP_VERSION + "\n";
			aboutMsg +=	"* Actionscript Logging Console\n";
			aboutMsg +=	"* " + this.APP_YEAR + " by " + this.APP_AUTHOR + "\n";
			aboutMsg +=	"* " + this.APP_WEBSITE + "\n";
			aboutMsg +=	"********************************\n";
			about_lc.send("alcon_lc", "onMessage", aboutMsg, 1);
			delete about_lc;
			this.paused = false;
		});

		ctMenu = new ContextMenu();
		ctMenu.hideBuiltInItems();
		
		var ctm0:ContextMenuItem = new ContextMenuItem("Pause\t\tP", ctPause);
		var ctm1:ContextMenuItem = new ContextMenuItem("Continue", ctContinue);
		var ctm2:ContextMenuItem = new ContextMenuItem("Clear buffer\t\tC", ctClearBuffer);
		var ctm3:ContextMenuItem = new ContextMenuItem("Reset\t\tR", ctReset);
		var ctm4:ContextMenuItem = new ContextMenuItem("Visit Website", ctGoToWebsite);
		var ctm5:ContextMenuItem = new ContextMenuItem("About", ctAbout);
		
		ctm2.separatorBefore = true;
		ctm4.separatorBefore = true;
		
		ctMenu.customItems.push(ctm0, ctm1, ctm2, ctm3, ctm4, ctm5);
		
		_root.menu = ctMenu;
	}
	
	
	
	/**
	* loadSettings()
	* Tries to load the settings file.
	*/
	private function loadSettings():Void
	{
		var settingsVars:LoadVars = new LoadVars();
		settingsVars.onData = Delegate.create(this, parseSettings);
		settingsVars.load(CFG_FILE);
	}
	
	
	
	/**
	* parseSettings()
	*/
	private function parseSettings(settingsText:String):Void
	{
		if (settingsText != undefined)
		{
			lsuccess = "Settings loaded!";
			
			// Strip linefeeds:
			var tmpArray:Array = settingsText.split("\r\n");
			settingsText = tmpArray.join("\r");
			
			// Divide settings name and settings value
			// into two different arrays:
			var nameArray:Array = [];
			var valueArray:Array = [];
			for (var i:Number = 0; i < tmpArray.length; i++)
			{
				// Don't parse empty or comment lines:
				if ((tmpArray[i] != "") && (tmpArray[i].substring(0, 1) != "#"))
				{
					var subArray:Array = tmpArray[i].split(" = ");
					nameArray.push(subArray[0]);
					valueArray.push(subArray[1]);
				}
			}
			
			// Parse:
			for (var i:Number = 0; i < nameArray.length; i++)
			{
				var val:String = valueArray[i];
				//trace(i + ". [" + nameArray[i] + ": " + val + "]");
				if (nameArray[i] == "FONT_FACE") FONT_FACE = val;
				if (nameArray[i] == "FONT_SIZE") FONT_SIZE = val;
				if (nameArray[i] == "BUFFER_LENGTH") BUFFER_LENGTH = val;
				if (nameArray[i] == "BUFFER_INFO") BUFFER_INFO = val;
				if (nameArray[i] == "WIN_XPOS") WIN_XPOS = val;
				if (nameArray[i] == "WIN_YPOS") WIN_YPOS = val;
				if (nameArray[i] == "WIN_WIDTH") WIN_WIDTH = val;
				if (nameArray[i] == "WIN_HEIGHT") WIN_HEIGHT = val;
				if (nameArray[i] == "USE_COLORS") USE_COLORS = val.toLowerCase();
				if (nameArray[i] == "BG_COLOR") BG_COLOR = val;
				if (nameArray[i] == "LEVEL_0_COLOR") LEVEL_0_COLOR = val;
				if (nameArray[i] == "LEVEL_1_COLOR") LEVEL_1_COLOR = val;
				if (nameArray[i] == "LEVEL_2_COLOR") LEVEL_2_COLOR = val;
				if (nameArray[i] == "LEVEL_3_COLOR") LEVEL_3_COLOR = val;
				if (nameArray[i] == "LEVEL_4_COLOR") LEVEL_4_COLOR = val;
				if (nameArray[i] == "DELIMITER") DELIMITER = val;
			}
		}
		else
		{
			lsuccess = "Settings file not found,\nusing defaults!";
		}
		
		// Set position and size only once initially:
		if (_root.init == undefined)
		{
			_root.init = true;
			_root.win_xpos = WIN_XPOS;
			_root.win_ypos = WIN_YPOS;
			_root.win_width = WIN_WIDTH;
			_root.win_height = WIN_HEIGHT;
			_root.prepareWindow();
		}
		
		// start main part:
		runLogger();
	}
	
	
	
	/**
	* runLogger()
	* Contains the loggers main guts.
	*/
	private function runLogger():Void
	{
		// Local vars:
		var premsg:String;
		var buffer:Number = parseInt(BUFFER_LENGTH);
		var bInfo:Boolean = (BUFFER_INFO == "true") ? true : false;
		var htmlTrue:Boolean = (USE_COLORS == "true") ? true : false;
		var lColors:Array = [LEVEL_0_COLOR, LEVEL_1_COLOR, LEVEL_2_COLOR, LEVEL_3_COLOR, LEVEL_4_COLOR];
		var dlt:String = DELIMITER;
		
		// Initialize the visual assets:
		initScreen(lColors);
		
		// In case color text (html) is used:
		if (htmlTrue)
		{
			output_area.html = true;
			premsg = "<font face='" + FONT_FACE + "' size='" + FONT_SIZE + "' ";
		}
		else
		{
			output_area.html = false;
			premsg = "";
		}
		
		// Initialize the receiver functionality:
		alcon_lc = new LocalConnection();
		alcon_lc.onMessage = Delegate.create(this, function(msg:String, lvl:Number):Void
		{
			if (!this.paused)
			{
				// Check for clear buffer signal:
				if (msg.substr(0, 7) == "[%CLR%]")
				{
					this.output_area.text = "";
					msg = msg.substr(7, msg.length);
				}
				// Check for delimiter signal:
				else if (msg.substr(0, 7) == "[%DLT%]")
				{
					msg = dlt + "\n" + msg.substr(7, msg.length);
				}
				
				var len:Number = this.output_area.length;
				if (len > buffer) this.output_area.text = "";
				if (bInfo) _root.sendToStatusBar("Buffer: " + len + "/" + buffer);
				
				if (htmlTrue) msg = premsg + "color='#" + lColors[lvl] + "'>" + this.convertTags(msg) + "</font>";
				
				this.output_area.text += msg + "\n";
				this.output_area.vPosition = this.output_area.maxVPosition;
			}
		});
		alcon_lc.connect("alcon_lc");
		
		// Send init message:
		initMessage(htmlTrue);
	}
	
	
	
	/**
	 * convertTags()
	 * Replaces all occurances of HTML braces in a string with &lt; and &gt;.	 */
	private function convertTags(msg:String):String
	{
		return (msg.split("<").join("&lt;")).split(">").join("&gt;");
	}

	
	
	/**
	 * initMessage()
	 * @description					Sends an initial message to the console output.
	 * @param htmlTrue:Boolean		True if html text should be used for init message.	 */
	private function initMessage(htmlTrue:Boolean):Void
	{
		// Send an init message with a short delay because local connection needs a moment:
		var delayInterval:Number;
		delayInterval = setInterval(Delegate.create(this, function():Void
		{
			var init_lc = new LocalConnection();
			init_lc.send("alcon_lc", "onMessage", "*** " + this.APP_NAME + " v" + this.APP_VERSION + " ***\n" + this.lsuccess + "\n--------------------------------\n\n", 1);
			delete init_lc;
			this.paused = false;
			clearInterval(delayInterval);
		}), 100);
	}
	
	
	
	/**
	* onKeyDown()
	*/
	private function onKeyDown():Void
	{
		// Check for pause key (p):
		if (Key.getCode() == 80)
		{
			if (!paused)
			{
				paused = true;
				mask_mc._visible = true;
				mask_mc._alpha = 30;
				_root.sendToStatusBar("Paused");
			}
			else
			{
				mask_mc._visible = false;
				mask_mc._alpha = 100;
				_root.sendToStatusBar("");
				paused = false;
			}
		}
		
		// Check for clear buffer key (c):
		else if (Key.getCode() == 67)
		{
			paused = true;
			output_area.text = "";
			_root.sendToStatusBar("Buffer cleared");
			paused = false;
		}
		
		// Check for reset key (r):
		else if (Key.getCode() == 82)
		{
			alcon_lc.close();
			_root.gotoAndPlay(1);
		}
	}
}
