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

import org.actionstep.NSArray;
import org.actionstep.NSDictionary;
import org.actionstep.NSRect;
import org.actionstep.NSMenu;

/**
 * Implements a defaults system for formatting information and localization.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSUserDefaults extends org.actionstep.NSObject
{	
	//******************************************************															 
	//*                    Constants
	//******************************************************
	
	/**
	 * An array that specifies how morning and afternoon times are outputted. 
	 * Defaults are AM and PM.
	 */
	public static var NSAMPMDesignation:String 				= "NSAMPMDesignation";
	
	/**
	 * A string that specifies currency. The default is $.
	 */
	public static var NSCurrencySymbol:String 				= "NSCurrencySymbol";
	
	/**
	 * A format string that specifies how default dates (%x) are printed.
	 * Default is "%A, %B %d, %Y".
	 */
	public static var NSDateFormatString:String 			= "NSDateFormatString";
	
	public static var NSDateTimeOrdering:String 			= "NSDateTimeOrdering";
	public static var NSDecimalDigits:String 				= "NSDecimalDigits";
	
	/**
	 * String specifying the decimal character. The decimal character
	 * separates the ones digit from the tenths digit.
	 *
	 * The default is ".".
	 */
	public static var NSDecimalSeparator:String 			= "NSDecimalSeparator";
	
	/**
	 * An array of strings that denote a time in the past. These are adjectives
	 * that modify values from NSYearMonthWeekDesignations. The defaults are
	 * Sprior,⬝ Slast,⬝ Spast,⬝ and Sago.⬝
	 */
	public static var NSEarlierTimeDesignations:String 		= "NSEarlierTimeDesignations";
	
	/**
	 * Strings that identify the time of day. These strings should be bound to
	 * an hour. The default is this array of arrays: (0, midnight),
	 * (10, morning), (12, noon, lunch), (14, afternoon), (19, dinner).
	 */
	public static var NSHourNameDesignations:String 		= "NSHourNameDesignations";
	
	/**
	 * String of the 3-letter currency abbreviation.
	 */
	public static var NSInternationalCurrencyString:String 	= "NSInternationalCurrencyString";
	
	/**
	 * An array of strings that denotes a time in the future. This array is an
	 * adjective that modifies a value from NSYearMonthWeekDesignations. The
	 * default is (next).
	 */
	public static var NSLaterTimeDesignations:String		= "NSLaterTimeDesignations";
	
	/**
	 * An array containing month names.
	 */
	public static var NSMonthNameArray:String 				= "NSMonthNameArray";
	
	/**
	 * A format string that specifies how negative numbers are printed when
	 * representing a currency value.
	 */
	public static var NSNegativeCurrencyFormatString:String	= "NSNegativeCurrencyFormatString"; //! SET DEFAULT
	
	/**
	 * A string that identifies the day after today. The default is (tomorrow).
	 */
	public static var NSNextDayDesignations:String			= "NSNextDayDesignations";
	
	/**
	 * A string that identifies the day after tomorrow. The default is (nextday).
	 */
	public static var NSNextNextDayDesignations:String		= "NSNextNextDayDesignations";
	
	/**
	 * A format string that specifies how positive numbers are printed when
	 * representing a currency value.
	 */
	public static var NSPositiveCurrencyFormatString:String	= "NSPositiveCurrencyFormatString";
	
	/**
	 * A string that identifies the day before today. The default is (yesterday).
	 */
	public static var NSPriorDayDesignations:String			= "NSPriorDayDesignations";
	
	/**
	 * A format string that specifies how dates are abbreviated. The default is
	 * "%d/%m/%y".
	 */
	public static var NSShortDateFormatString:String		= "NSShortDateFormatString";
	
	/**
	 * An array of abbreviated month names.
	 */
	public static var NSShortMonthNameArray:String 			= "NSShortMonthNameArray";
	
	/**
	 * A format string specifying how datetimes are abbreviated. The default
	 * is "%e-%b-%y %I:%M %p".
	 */
	public static var NSShortTimeDateFormatString:String	= "NSShortTimeDateFormatString";
	
	/**
	 * An array of abbreviated week day names. Sunday is the first day of the week.
	 */
	public static var NSShortWeekDayNameArray:String 		= "NSShortWeekDayNameArray";
	
	/**
	 * A string representing today. The default is "today".
	 */
	public static var NSThisDayDesignations:String			= "NSThisDayDesignations";
	
	/**
	 * A string to seperate thousands in numeric strings. The default is a
	 * space.
	 */
	public static var NSThousandsSeparator:String			= "NSThousandsSeparator";
	
	/**
	 * A datetime format string (longer than NSShortTimeDateFormatString).
	 * The default is S%A, %B %d, %Y %H:%M:%S %Z⬝.
	 */
	public static var NSTimeDateFormatString:String			= "NSTimeDateFormatString";
	
	/**
	 * A format that specifies how times are printed. The default is
	 * "%I:%M %p".
	 */
	public static var NSTimeFormatString:String				= "NSTimeFormatString";
	
	/**
	 * An array of full weekday names (eg. Sunday, Monday, ...). The week
	 * begins on a Sunday.
	 */
	public static var NSWeekDayNameArray:String 			= "NSWeekDayNameArray";
	
	/**
	 * An array of strings that represent the year, month, and day
	 * respectively in the current locale. The defaults are "year","month","day".
	 */
	public static var NSYearMonthWeekDesignations:String	= "NSYearMonthWeekDesignations";	
	
	
	private static var ASDomainStatePersistent:Number = 0;
	private static var ASDomainStateVolitile:Number = 1;
	
	//******************************************************															 
	//*                     Members
	//******************************************************
	
	/** The list of domains that are used to generate user defaults. */
	private static var g_searchList:NSArray;
	
	/** Defaults for any user without preferences. */
	private static var g_defaults:NSDictionary;
	
	/** TRUE if the defaults exist. */
	private static var g_registered:Boolean = false;
	
	/** The standard defaults for this user. */
	private static var g_standardDefaults:NSUserDefaults;
	
	//******************************************************															 
	//*                    Construction
	//******************************************************
	
	/**
	 * Creates a new instance of the NSUserDefaults class.
	 */
	public function NSUserDefaults()
	{
	}
	
	
	/**
	 * Initializes defaults for the current user account and returns an
	 * NSUserDefaults instance with the argument and registration domains set
	 * up. 
	 */
	public function init():NSUserDefaults
	{
		//! consider using a SharedObject to store defaults
		return this;
	}
	
	
	/**
	 * This method initializes defaults for the user with userName.
	 *
	 * This method should not ordinarily be invoked. It is used by a user
	 * who wishes to access the application from many different user prespectives.
	 */
	public function initWithUser(userName:String):NSUserDefaults
	{
		//! how should this be used
		return this;
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSUserDefaults()";
	}
	
	
	/**
	 * Returns a dictionary containing all user defaults as generated by
	 * enumerating the domain search list in order. A lower domain will 
	 * overwrite any keys stored in higher domains.
	 *
	 * The returned dictionary contains no information about the origin domain
	 * of each entry.
	 */
	public function dictionaryRepresentation():NSDictionary
	{
		return g_defaults;
	}
	
	//******************************************************															 
	//*                Getting Defaults
	//******************************************************
	
	/**
	 * Returns the NSArray corresponding to the key defaultKey, or null
	 * if it doesn't exist. This searches the domain list.
	 */	
	public function arrayForKey(defaultName:String):NSArray
	{
		return NSArray(objectForKey(defaultName));
	}
	

	/**
	 * Returns the Boolean corresponding to the key defaultKey, or null
	 * if it doesn't exist. This searches the domain list.
	 */	
	public function boolForKey(defaultName:String):Boolean
	{
		return Boolean(objectForKey(defaultName));
	}
	
	
	/**
	 * Returns the NSDictionary corresponding to the key defaultKey, or null
	 * if it doesn't exist. This searches the domain list.
	 */
	public function dictionaryForKey(defaultName:String):NSDictionary
	{
		return NSDictionary(objectForKey(defaultName));
	}
	

	/**
	 * Returns the Number corresponding to the key defaultKey, or null
	 * if it doesn't exist. This searches the domain list.
	 *
	 * Replaces integerForKey and floatForKey in Cocoa.
	 */
	public function numberForKey(defaultName:String):Number
	{
		return Number(objectForKey(defaultName));
	}
	
	
	/**
	 * Returns the Object corresponding to the key defaultKey, or null
	 * if it doesn't exist. This searches the domain list.
	 */
	public function objectForKey(defaultName:String):Object
	{
		return null; //!
	}
	

	/**
	 * Returns the String corresponding to the key defaultKey, or null
	 * if it doesn't exist. This searches the domain list.
	 */
	public function stringArrayForKey(defaultName:String):NSArray
	{
		var arr:NSArray = NSArray(objectForKey(defaultName));
		
		if (arr != null && 
			org.actionstep.ASUtils.chkElem(arr.internalList(), String) === true)
		{
			return arr;
		}
		
		return null;
	}
		
	
	/**
	 * Returns the String corresponding to the key defaultKey, or null
	 * if it doesn't exist. This searches the domain list.
	 */
	public function stringForKey(defaultName:String):String
	{
		return String(objectForKey(defaultName));
	}
		
	
	//******************************************************															 
	//*                Setting Defaults
	//******************************************************
	
	/**
	 * Calls setObjectForKey(value, defaultName).
	 */
	public function setBoolForKey(value:Boolean, defaultName:String):Void
	{
		setObjectForKey(value, defaultName);
	}


	/**
	 * Calls setObjectForKey(value, defaultName).
	 *
	 * Replaces setIntegerForKey and setFloatForKey in Cocoa.
	 */
	public function setNumberForKey(value:Number, defaultName:String):Void
	{
		setObjectForKey(value, defaultName);
	}
	
		
	/**
	 * Sets the value of the default with the key defaultName to value in
	 * the default application domain. This method will not affect objectForKey()
	 * calls if a domain preceding the application domain contains an entry for
	 * the key defaultName.
	 */
	public function setObjectForKey(value:Object, defaultName:String):Void
	{
		//!
	}
	
	public function removeObjectForKey():Void {
		//!
	}
	
	public function synchronize():Boolean {
		//!
		return true;
	}
	
	
	//******************************************************															 
	//*                   Domains
	//******************************************************
	
	/**
	 * Inserts a new domain, suiteName, into the receiver"s search list. The
	 * suite domain is inserted after the application domain.
	 */
	public function addSuiteNamed(suiteName:String):Void
	{
		//!
	}
	
	
	/**
	 * Removes the suite domain with the name suiteName.
	 */
	public function removeSuiteNamed(suiteName:String):Void
	{
		//!
	}
	
	public function persistentDomainForName(dom:String):NSDictionary {
		//!
		return null;
	}
	
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	/**
	 * Cleans up the object before destruction.
	 */
	public function release():Void
	{
		//!
	}
	
	
	public function registerDefaults():Void
	{
		g_defaults = new NSDictionary();
		
		//
		// Numbers and currency
		//			
		g_defaults.setObjectForKey("$", NSCurrencySymbol);
		g_defaults.setObjectForKey(".", NSDecimalSeparator);
		g_defaults.setObjectForKey(" ", NSDecimalSeparator); // that's right, haha
		g_defaults.setObjectForKey("USD", NSInternationalCurrencyString);		
			
		//
		// Time designations
		//
		g_defaults.setObjectForKey(
			NSArray.arrayWithObject("prior", "last", "past", "ago"), 
			NSEarlierTimeDesignations);
		g_defaults.setObjectForKey(NSArray.arrayWithObject(
			NSArray.arrayWithObjects(0, "midnight"), 
			NSArray.arrayWithObjects(10, "morning"), 
			NSArray.arrayWithObjects(12, "noon", "lunch"), 
			NSArray.arrayWithObjects(14, "midnight"), 
			NSArray.arrayWithObjects(19, "dinner") 
			), NSHourNameDesignations);
		g_defaults.setObjectForKey(NSArray.arrayWithObjects(
			"year", "month", "day"), NSYearMonthWeekDesignations);
		g_defaults.setObjectForKey(NSArray.arrayWithObjects("next"), 
			NSLaterTimeDesignations);			
		g_defaults.setObjectForKey("tomorrow", NSNextDayDesignations);
		g_defaults.setObjectForKey("nextday", NSNextNextDayDesignations);
		g_defaults.setObjectForKey("yesterday", NSPriorDayDesignations);
		g_defaults.setObjectForKey("today", NSThisDayDesignations);
		
		//
		// Dates and Times (for formatting)
		//
		g_defaults.setObjectForKey("%A, %B %d, %Y", NSDateFormatString);
		g_defaults.setObjectForKey("%d/%m/%y", NSShortDateFormatString);
		g_defaults.setObjectForKey("%e-%b-%y %I:%M %p", 
			NSShortTimeDateFormatString);
		g_defaults.setObjectForKey("%A, %B %d, %Y %H:%M:%S %Z", 
			NSTimeDateFormatString);
		g_defaults.setObjectForKey("%I:%M %p", NSTimeFormatString);
		
		g_defaults.setObjectForKey(NSArray.arrayWithObjects(
			"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept",
			"Oct", "Nov", "Dec"),
			NSShortMonthNameArray);
		g_defaults.setObjectForKey(NSArray.arrayWithObjects(
			"January", "February", "March", "April", "May", "June", "July",
			"August", "September", "October", "November", "December"
			), NSMonthNameArray);
		g_defaults.setObjectForKey(NSArray.arrayWithObjects(
			"Sun", "Mon", "Tues", "Wed", "Thurs", "Fri", "Sat"),
			NSShortWeekDayNameArray);
		g_defaults.setObjectForKey(NSArray.arrayWithObjects(
			"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"),
			NSWeekDayNameArray);
		g_defaults.setObjectForKey(NSArray.arrayWithObjects("AM", "PM"), 
			NSAMPMDesignation);
			
		//menu
		g_defaults.setObjectForKey(NSRect.ZeroRect, NSMenu.NSMenuLocationsKey);
	}
	
	//******************************************************															 
	//*                     Events
	//******************************************************
	//******************************************************															 
	//*                 Protected Methods
	//******************************************************
	//******************************************************															 
	//*                  Private Methods
	//******************************************************
	//******************************************************															 
	//*             Public Static Properties
	//******************************************************
	
	/**
	 * Syncs changes from the standardUserDefaults and recreates it.
	 */
	public static function resetStandardUserDefaults():Void
	{
		//! sync changes
		g_standardDefaults.release();
		g_standardDefaults = null;
		
		standardUserDefaults();
	}
	
	
	/**
	 * Returns the standard user defaults for this application.
	 */
	public static function standardUserDefaults():NSUserDefaults
	{
		if (g_searchList == undefined)
		{
			g_searchList = NSArray.array();
			
			//! fill in with search list
		}
		
		if (g_standardDefaults == undefined)
		{
			g_standardDefaults = (new NSUserDefaults()).init();
			g_standardDefaults.registerDefaults();
			trace(g_standardDefaults.objectForKey(NSMenu.NSMenuLocationsKey));
		}
		
		return g_standardDefaults;
	}
	
	//******************************************************															 
	//*             Private Static Methods
	//******************************************************
	
	private function createDomain(name:String, state:Number):NSDictionary
	{
		return NSDictionary.dictionaryWithObjectsAndKeys(
			name, "name",
			state, "state",
			NSDictionary.dictionary(), "defaults");
	}
	
	//******************************************************															 
	//*              Public Static Methods
	//******************************************************
	

	
	//******************************************************															 
	//*               Static Constructor
	//******************************************************
	
	/**
	 * Runs when the application begins.
	 */
	private static function classConstruct():Boolean
	{
		if (classConstructed)
			return true;
				
		return true;
	}
	
	private static var classConstructed:Boolean = classConstruct();
}
