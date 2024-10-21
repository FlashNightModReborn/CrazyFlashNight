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
import org.as2lib.data.type.*;

/**
 * {@code MathUtil} contains fundamental math operations.
 *
 * @author Christophe Herreman
 * @author Martin Heidegger
 * @author Simon Wacker
 */
class org.as2lib.util.MathUtil extends BasicClass {
	
	/**
	 * Checks if the passed-in integer {@code n} is odd.
	 * 
	 * @param n the integer to check
	 * @return {@code true} if {@code n} is odd else {@code false}
	 */
	public static function isOdd(n:Integer):Boolean {
		return Boolean(n%2);
	}
	
	/**
	 * Checks if the passed-in integer {@code n} is even.
	 *
	 * @param n the integer to check
	 * @return {@code true} if {@code n} is even else {@code false}
	 */	
	public static function isEven(n:Integer):Boolean {
		return (n%2 == 0);
	}
	
	/**
	 * Checks if the passed-in number {@code n} is an integer.
	 *
	 * @param n the number to check
	 * @return {@code true} if {@code n} is an integer else {@code false}
	 */	
	public static function isInteger(n:Number):Boolean {
		return (n%1 == 0);
	}

	/**
	 * Checks if the passed-in number {@code n} is natural.
	 *
	 * @param n the number to check
	 * @return {@code true} if {@code n} is natural else {@code false}
	 */	
	public static function isNatural(n:Number):Boolean {
		return (n >= 0 && n%1 == 0);
	} 
	
	/**
	 * Checks if the passed-in number {@code n} is a prime.
	 * 
	 * <p>A prime number is a positive integer that has no positive integer divisors
	 * other than 1 and itself.
	 * 
	 * @param n the number to check
	 * @return {@code true} if {@code n} is a prime else {@code false}
	 */	
	public static function isPrime(n:NaturalNumber):Boolean {
		if (n == 1) return false;
		if (n == 2) return true;
		if (n % 2 == 0) return false;
		for (var i:Number = 3, e:Number = Math.sqrt(n); i <= e; i += 2) {
			if (n % i == 0){
				return false;
			}
		}
		return true;
	}
		
	/**
	 * Calculates the factorial of the passed-in number {@code n}.
	 *
	 * @param n the number to calculate the factorial of
	 * @return the factorial of {@code n}
	 */
	public static function factorial(n:NaturalNumberIncludingZero):Number {
		if (n == 0) {
			return 1;
		}
		var d:Number = n.valueOf(); // Performance Speed up (this way the instance will not be used anymore
		var i:Number = d-1;
		while (i) {
			d = d*i;
			i--;
		}
		return d;
	}
		
	/**
	 * Returns an array with all divisors of the passed-in number {@code n}
	 * 
	 * @param n the number to return the divisors of
	 * @return an array that contains the divisors of {@code n}
	 */
	public static function getDivisors(n:NaturalNumberIncludingZero):Array {
		var r:Array = new Array();
		for (var i:Number = 1, e:Number = n/2; i <= e; i++) {
			if (n % i == 0){
				r.push(i);
			}
		}
		if (n != 0) r.push(n.valueOf());
		return r;
	}
	
	/**
	 * Rounds the passed-in number {@code n} to the nearest value.
	 * 
	 * <p>It works basically the same as the {@code Math.round} method, but it adds a
	 * new argument to specify the number of decimal spaces.
	 * 
	 * @param n the number to round
	 * @param c the number of decimal spaces
	 * @returns the rounded number
	 */
	public static function round(n:Number, c:Number):Number {
		var r:Number = Math.pow(10,c);
		return Math.round(n*r)/r;
	}
	
	/**
	 * Floors the passed-in number {@code n}.
	 * 
	 * <p>It works basically the same as the {@code Math.floor} method, but it adds a
	 * new argument to specify the number of decimal spaces.
	 * 
	 * @param n the number to round
	 * @param c the number of decimal spaces
	 * @returns the rounded number
	 */
	public static function floor(n:Number, c:Number):Number {
		var r:Number = Math.pow(10,c);
		return Math.floor(n*r)/r;
	}  
	
	/**
	 * Private constructor.
	 */
	private function MathUtil() {
	}
	
}