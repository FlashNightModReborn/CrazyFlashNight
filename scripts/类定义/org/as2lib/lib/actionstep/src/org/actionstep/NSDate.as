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

import org.actionstep.NSCopying;
import org.actionstep.NSDateFormatter;
import org.actionstep.NSDictionary;
import org.actionstep.NSObject;
import org.actionstep.NSUserDefaults;

import org.actionstep.constants.NSComparisonResult;

/**
 * Class used for representing dates.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSDate extends NSObject
	implements NSCopying
{	
	/**
	 * Seconds between Jan 1st, 1970 to Jan 1st, 2001. 
	 */
	public static var NSTimeIntervalSince1970:Number;
	
	/** String format used by initWithString() */
	private static var DEF_STRING_FORMAT:String;
	
	/** January 1st, 2001, 00:00:00:0000 */
	private static var g_refDate:Date;
	
	/** A date formatter that uses to format all dates. */
	private static var g_dtFormatter:NSDateFormatter;
	
	/** The internal date. */
	private var m_dt:Date;
		
		
	//******************************************************															 
	//*                   Construction
	//******************************************************
		
	/**
	 * Constructs a new instance of the NSDate class.
	 */
	public function NSDate()
	{
		if (g_dtFormatter == undefined)
		{
			g_dtFormatter = 
				(new NSDateFormatter()).initWithDateFormatAllowNaturalLanguage(
				DEF_STRING_FORMAT, false);
			g_dtFormatter.generatesCalendarDates(true); // for subclasses
		}
	}
	
	
	/**
	 * Initializes an NSDate to the current date and time.
	 */
	public function init():NSDate
	{
		m_dt = new Date();
		return this;
	}
	
	
	/**
	 * Initializes an NSDate to the date and time specified by a string
	 * conforming to the international string representation format 
	 * YYYY-MM-DD HH:MM:SS ±HHMM. All fields must be specified.
	 */
	public function initWithString(description:String):NSDate
	{
		var genDt:NSDate;
		var old:String; 
		
		//
		// Since ActionScript is single-threaded, this is okay to do.
		//
		old = g_dtFormatter.dateFormat();
		g_dtFormatter.setDateFormat(DEF_STRING_FORMAT);
		genDt = g_dtFormatter.dateFromString(description);
		g_dtFormatter.setDateFormat(old); // reset
		
		this.m_dt.setTime(genDt.internalDate().getTime());
		//! deal with timezone
		
		return this;
	}
	
	
	/**
	 * Initializes an NSDate to the current date and time, offset by seconds
	 * seconds.
	 */
	public function initWithTimeIntervalSinceNow(seconds:Number):NSDate
	{
		m_dt = new Date();
		m_dt.setTime(m_dt.getTime() + seconds * 1000);
		
		return this;
	}
	
	
	/**
	 * Initializes an NSDate to the date and time of refDate, offset by 
	 * seconds seconds.
	 */
	public function initWithTimeIntervalSinceDate(seconds:Number, 
		refDate:NSDate):NSDate
	{
		m_dt = new Date();
		m_dt.setTime(refDate.m_dt.getTime() + seconds * 1000);
		
		return this;
	}
	
	
	/**
	 * Initializes an NSDate to the date and time of the absolute reference
	 * date, offset by seconds seconds.
	 */
	public function initWithTimeIntervalSinceReferenceDate(seconds:Number):NSDate
	{
		return initWithTimeIntervalSinceDate(seconds, NSDate.dateWithDate(g_refDate));
	}
	
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * Uses the international date formatting style.
	 *
	 * Calls descriptionWithCalendarFormatTimeZoneLocale().
	 */
	public function description():String 
	{
		return descriptionWithCalendarFormatTimeZoneLocale(NSDate.DEF_STRING_FORMAT,
			null, null);
	}
	
	
	/**
	 * Returns a string representation of this NSDate using the date format
	 * string format, the time zone timeZone and the locale locale. If null
	 * is provided for any of the arguments, the default is assumed.
	 */
	public function descriptionWithCalendarFormatTimeZoneLocale(
		format:String, timeZone:Number, locale:NSDictionary):String //! timeZone should be NSTimeZone
	{		
		if (format == null)
		{
			format = NSDate.DEF_STRING_FORMAT;
		}
		
		if (timeZone == null)
		{
			//! use locale timezone
		}
		
		var dtf:NSDateFormatter = (new NSDateFormatter()
			).initWithDateFormatAllowNaturalLanguage(format, true);
		return dtf.stringFromDate(this); //! locale
	}
	
	
	/**
	 * Uses the international date formatting style.
	 *
	 * Calls descriptionWithCalendarFormatTimeZoneLocale()
	 */
	public function descriptionWithLocale(locale:NSDictionary):String
	{
		return descriptionWithCalendarFormatTimeZoneLocale(NSDate.DEF_STRING_FORMAT,
			null, locale);
	}
	
	
	/**
	 * Returns the internal date representation. Should only be used when
	 * absolutely necessary.
	 */
	public function internalDate():Date
	{
		return m_dt;
	}
	
	//******************************************************															 
	//*                   Time Intervals
	//******************************************************
	
	/**
	 * Returns the interval (seconds) between this date and Jan 1st, 1970.
	 * If this date is earlier than now a negative value is returned.
	 *
	 * Cocoa specs have this returning an NSTimeInterval. Number is fine for
	 * our purposes.
	 */	
	public function timeIntervalSince1970():Number
	{
		return (this.m_dt.getTime() / 1000);
	}
	
	
	/**
	 * Returns the interval (seconds) between this date and anotherDate. If 
	 * this date is earlier than anotherDate a negative value is returned.
	 *
	 * Cocoa specs have this returning an NSTimeInterval. Number is fine for
	 * our purposes.
	 */
	public function timeIntervalSinceDate(anotherDate:NSDate):Number
	{
		return timeIntervalSinceIntrinsicDate(anotherDate.m_dt);
	}


	/**
	 * Returns the interval (seconds) between this date and the current date 
	 * and time. If this date is earlier than now a negative value is returned.
	 *
	 * Cocoa specs have this returning an NSTimeInterval. Number is fine for
	 * our purposes.
	 */	
	public function timeIntervalSinceNow():Number
	{
		return timeIntervalSinceIntrinsicDate(new Date());
	}
	
	
	/**
	 * Returns the interval (seconds) between this date and the reference date
	 * (Jan 1st, 2001). If this date is earlier than now a negative value is 
	 * returned.
	 *
	 * Cocoa specs have this returning an NSTimeInterval. Number is fine for
	 * our purposes.
	 */	
	public function timeIntervalSinceReferenceDate():Number
	{
		return timeIntervalSinceIntrinsicDate(g_refDate);
	}
	
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	/**
	 * Returns a new NSDate offset by seconds seconds from this date.
	 */
	public function addTimeInterval(seconds:Number):NSDate
	{
		return (new NSDate()).initWithTimeIntervalSinceDate(seconds, this);
	}
	
	
	/**
	 * Uses timeIntervalSinceDate to compare this date to anotherDate and 
	 * returns an NSComparisonResult.
	 *
	 * If the two dates are the same, NSOrderedSame is returned.
	 * If this date is later than anotherDate, NSOrderedDescending is returned.
	 * If this date is earlier, NSOrderedAscending is returned.
	 */
	public function compare(anotherDate:NSDate):NSComparisonResult
	{
		var delta:Number = timeIntervalSinceDate(anotherDate);
		
		if (delta == 0)
		{
			return NSComparisonResult.NSOrderedSame;
		}
		else if (delta > 0)
		{
			return NSComparisonResult.NSOrderedDescending;
		}
		else // delta < 0
		{
			return NSComparisonResult.NSOrderedAscending;
		}
	}
	
	
	/**
	 * Returns whatever is earlier, this date or anotherDate.
	 */
	public function earlierDate(anotherDate:NSDate):NSDate
	{
		return timeIntervalSinceDate(anotherDate) < 0 ? this : anotherDate;
	}
	
	
	/**
	 * Returns whatever is later, this date or anotherDate.
	 */
	public function laterDate(anotherDate:NSDate):NSDate
	{
		return timeIntervalSinceDate(anotherDate) < 0 ? anotherDate : this;
	}
	
	
	/**
	 * @see org.actionstep.NSObject#isEqual
	 */
	public function isEqual(anObject:NSObject):Boolean
	{
		if (!(anObject instanceof NSDate))
			return false;
			
		return isEqualToDate(NSDate(anObject));
	}
	
	
	/**
	 * Returns TRUE if this date is equal to anotherDate, and FALSE otherwise.
	 */
	public function isEqualToDate(anotherDate:NSDate):Boolean
	{
		//! Timezones
		return m_dt.getTime() == anotherDate.m_dt.getTime();
	}
	
	//******************************************************															 
	//*              NSCopying Implementation
	//******************************************************
	
	/**
	 * @see org.actionstep.NSCopying#copyWithZone
	 */
	public function copyWithZone():NSObject
	{
		return (new NSDate()).initWithTimeIntervalSinceDate(0, this);
	}
	
	//******************************************************															 
	//*                 Protected Methods
	//******************************************************
	//******************************************************															 
	//*                  Private Methods
	//******************************************************
	
	/**
	 * Returns the time in seconds between this date and the intrinsic Date
	 * argument.
	 */
	private function timeIntervalSinceIntrinsicDate(dt:Date):Number
	{
		return (this.m_dt.getTime() - dt.getTime()) / 1000;
	}
	
	
	//******************************************************															 
	//*             Public Static Properties
	//******************************************************
	
	/**
	 * Returns a date in the distant future (centuries distant).
	 */
	public function distantFuture():NSDate
	{
		return NSDate.dateWithDate(new Date(9999, 0, 1, 0, 0, 0, 0));
	}

	
	/**
	 * Returns a date in the distant past.
	 */
	public function distantPast():NSDate
	{
		return NSDate.dateWithDate(new Date(1, 0, 1, 0, 0, 0, 0));
	}	
	
	//******************************************************															 
	//*              Public Static Methods
	//******************************************************
	
	/**
	 * Constructs and returns a new date with the current date and time.
	 */
	public static function date():NSDate
	{
		return NSDate.dateWithDate(new Date());
	}
	
	
	/**
	 * Constructs and returns a new date set to the date and time of date.
	 */
	public static function dateWithDate(date:Date):NSDate
	{
		return (new NSDate()).initWithTimeIntervalSinceReferenceDate(date.getTime());
	}
	
	
	/**
	 * Constructs a new date based on the information contained in string.
	 * The date formatter uses date and time preferences stored in the user
	 * defaults table to parse the string.
	 */
	public static function dateWithNaturalLanguageString(string:String):NSDate
	{
		return dateWithNaturalLanguageStringLocale(string, 
			NSUserDefaults.standardUserDefaults().dictionaryRepresentation());
	}
	
	
	public static function dateWithNaturalLanguageStringLocale(string:String, 
		locale:NSDictionary):NSDate
	{
		return null;
	}
	
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
		
		//
		// Generate reference date (Jan 1st, 2001) and constant.
		//	
		g_refDate = new Date(2001, 0, 1, 0, 0, 0, 0);
		NSTimeIntervalSince1970 = Math.round(g_refDate.getTime() / 1000);
		
		// 
		// For formatting (YYYY-MM-DD HH:MM:SS ±HHMM)
		//
		DEF_STRING_FORMAT = "%Y-%m-%d %H:%M:%S %z";
		
		return true;
	}
	
	private static var classConstructed:Boolean = classConstruct();
}
