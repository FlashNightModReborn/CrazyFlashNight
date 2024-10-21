/*
 * Copyright the original author or authors.
 * 
 * Licensed under the MOZILLA PUBLIC LICENSE, Version 1.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.mozilla.org/MPL/MPL-1.1.html
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.core.BasicClass;
import org.as2lib.util.MathUtil;

/**
 * {@code Time} is a holder for a time difference.
 * 
 * <p>{@code Time} splits a time difference (distance between two dates) into
 * days, hours, minutes, seconds and milliseconds to offers methods to access
 * the time difference value.
 * 
 * <p>There are two ways to access the {@code Time} instance:
 * 
 * <p>The first way is by {@code in*()}({@code inHours()}, {@code inMinutes()},...).
 * Those methods are coversions to the different time units. You can recieve the
 * complete value in a different unit.
 * 
 * Example:
 * <code>
 *   var time:Time = new Time(1.5, "d");
 *   trace(time.inDays()); // 1.5
 *   trace(time.inHours()); // 36
 *   trace(time.inMinutes()); // 2160
 * </code>
 * 
 * <p>The second way is by {@code get*()}({@code getHours()}, {@code getMinutes()},...).
 * Those methods contain only the part of each unit that is contained within the
 * value.
 * 
 * Example:
 * <code>
 *   var time:Time = new Time(1.5, "d");
 *   trace(time.getDays()); // 1.5
 *   trace(time.getHours()); // 12
 *   trace(time.getMinutes(); // 0
 * </code>
 * 
 * <p>Its possible to pass-in a number in to round the value to the next lower case:
 * 
 * Example:
 * <code>
 *   var time:Time = new Time(1.5, "d");
 *   trace(time.getDays(0)); // 1
 * </code>
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.data.type.Time extends BasicClass {
	
	/** Factor from ms to second. */ 
	private static var SECOND:Number = 1000;
	
	/** Factor from ms to minute. */
	private static var MINUTE:Number = SECOND*60;
	
	/** Factor from ms to hour. */
	private static var HOUR:Number = MINUTE*60;
	
	/** Factor from ms to day. */
	private static var DAY:Number = HOUR*24;
	
	/** Time difference in ms. */
	private var ms:Number;
	
	/** Amount of days. */
	private var days:Number;
	
	/** Amount of hours. */
	private var hours:Number;
	
	/** Amount of minutes. */
	private var minutes:Number;
	
	/** Amount of seconds. */
	private var seconds:Number;
	
	/** Amount of milliseconds. */
	private var milliSeconds:Number;
	
	/** Flag if the instance need to be evaluated by {@link #evaluate}. */
	private var doEval:Boolean = true;
	
	/**
	 * Constructs a new {@code Time} instance.
	 * 
	 * <p>Uses "ms" if no format or a wrong format was passed-in.
	 * 
	 * <p>Uses {@code Number.MAX_VALUE} if {@code Infinity} was passed-in.
	 * 
	 * 
     * @param time size of the time difference for the passed-in {@code format}
     * @param format (optional) "d"/"h"/"m"/"s"/"ms" for the unit of the amout,
     * 	      default case is "ms"
	 */
	public function Time(timeDifference:Number, format:String) {
		setValue(timeDifference, format);
	}
	
	/** 
	 * Sets the time of the instance.
	 * 
	 * <p>Uses "ms" if no format or a wrong format was passed-in.
	 * 
	 * <p>Uses {@code Number.MAX_VALUE} if {@code Infinity} was passed-in.
	 * 
     * @param time size of the time difference for the passed-in {@code format}
     * @param format (optional) "d"/"h"/"m"/"s"/"ms" for the unit of the amout.
     * 		  Default value is ms.
	 */
	public function setValue(timeDifference:Number, format:String):Time {
		if (timeDifference == Infinity) {
			timeDifference = Number.MAX_VALUE;
		}
		switch (format) {
			case "d":
				ms = timeDifference*DAY;
				break;
			case "h":
				ms = timeDifference*HOUR;
				break;
			case "m":
				ms = timeDifference*MINUTE;
				break;
			case "s":
				ms = timeDifference*SECOND;
				break;
			default:
				ms = timeDifference;
		}
		doEval = true;
		return this;
	}
	
	/**
	 * Adds the passed-in {@code timedistance} to the current time.
	 *  
	 * @param timeDifference time difference to be added to the current time
	 * @return new instance with the resulting amount of time
	 */
	public function plus(timeDifference:Time):Time {
		return new Time(ms+timeDifference.valueOf());
	}
	
	/**
	 * Adds the passed-in {@code timeDifference} from the current time.
	 *  
	 * @param timeDifference time difference to be removed from the current time
	 * @return new instance with the resulting amount of time
	 */
	public function minus(timeDifference:Time):Time {
		return new Time(ms-timeDifference.valueOf());
	}
	
	/**
	 * Getter for the amount of milliseconds are contained within the time.
	 * 
	 * <p>It will not round the result if you pass-in nothing.
	 * 
	 * @param round (optional) the number of decimal spaces
	 * @return time difference in milliseconds
	 */
	public function getMilliSeconds(round:Number):Number {
		if (doEval) evaluate();
		if (round == null) {
			return milliSeconds;
		} else {
			return MathUtil.floor(milliSeconds, round);
		}
	}
	
	/**
	 * Getter for the time distance in milliseconds.
	 * 
	 * @return time difference in milliseconds
	 */
	public function inMilliSeconds(Void):Number {
		return ms;
	}
	
	/**
	 * Getter for the amount of seconds are contained within the time.
	 * 
	 * <p>It will not round the result if you pass-in nothing.
	 * 
	 * @param round (optional) the number of decimal spaces
	 * @return time difference in seconds
	 */
	public function getSeconds(round:Number):Number {
		if (doEval) evaluate();
		if (round == null) {
			return seconds;
		} else {
			return MathUtil.floor(seconds, round);
		}
	}
	
	/**
	 * Getter for the time distance in seconds.
	 * 
	 * @return time difference in seconds
	 */
	public function inSeconds(Void):Number {
		return ms/SECOND;
	}
	
	/**
	 * Getter for the amount of minutes are contained within the time.
	 * 
	 * <p>It will not round the result if you pass-in nothing.
	 * 
	 * @param round (optional) the number of decimal spaces
	 * @return time difference in minutes
	 */
	public function getMinutes(round:Number):Number {
		if (doEval) evaluate();
		if (round == null) {
			return minutes;
		} else {
			return MathUtil.floor(minutes, round);
		}
	}
	
	/**
	 * Getter for the time distance in minutes.
	 * 
	 * @return time difference in minutes
	 */
	public function inMinutes(Void):Number {
		return ms/MINUTE;
	}
	
	/**
	 * Getter for the amount of hours are contained within the time.
	 * 
	 * <p>It will not round the result if you pass-in nothing.
	 * 
	 * @param round (optional) the number of decimal spaces
	 * @return time difference in hours
	 */
	public function getHours(round:Number):Number {
		if (doEval) evaluate();
		if (round == null) {
			return hours;
		} else {
			return MathUtil.floor(hours, round);
		}
	}
	
	/**
	 * Getter for the time distance in hours.
	 * 
	 * @return  time difference in hours
	 */
	public function inHours(Void):Number {
		return ms/HOUR;
	}
	
	/**
	 * Getter for the amount of days are contained within the time.
	 * 
	 * <p>It will not round the result if you pass-in nothing.
	 * 
	 * @param round (optional) the number of decimal spaces
	 * @return time difference in days
	 */
	public function getDays(round:Number):Number {
		if (doEval) evaluate();
		if (round == null) {
			return days;
		} else {
			return MathUtil.floor(days, round);
		}
	}
	
	/**
	 * Getter for the time distance in days.
	 * 
	 * @return  time difference in days
	 */
	public function inDays(Void):Number {
		return ms/DAY;
	}
	
	/**
	 * Generates String representation of the time.
	 * 
	 * @return time difference as string
	 */
	public function toString():String {
		return getDays(0)+"d "+getHours(0)+":"+getMinutes(0)+":"+getSeconds(0)+"."+getMilliSeconds(0);
	}
	
	/**
	 * Splits the time distance from ms (source value) into the different units.
	 */
	private function evaluate(Void):Void {
		var negative = (ms >= 0) ? 1 : -1;
		var rest:Number = ms;
		
		days = rest/DAY;
		rest -= negative*Math.floor(days)*DAY;
		
		hours = rest/HOUR;
		rest -= negative*Math.floor(hours)*HOUR;
		
		minutes = rest/MINUTE;
		rest -= negative*Math.floor(minutes)*MINUTE;
		
		seconds = rest/SECOND;
		rest -= negative*Math.floor(seconds)*SECOND;
		
		milliSeconds = rest;
		
		doEval = false;
	}
	
	/**
	 * Returns the value of the time distance (in ms).
	 * 
	 * @return value in ms
	 */
	public function valueOf():Number {
		return ms;
	}
}