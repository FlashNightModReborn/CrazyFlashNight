/*
 * Copyright (c) 2005, InfoEther, Inc.
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
 * 3) The name InfoEther, Inc. may not be used to endorse or promote products 
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
 
import org.actionstep.NSDictionary;
import org.actionstep.NSException;
 
class org.actionstep.ASUtils {
  private static var g_internedObject:Object = new Object();
  private static var g_internedIndex:Number = 0;
  
  public static function intern(string:String):Number {
    var intern:Number = g_internedObject[string];
    if(intern == undefined) {
      intern = g_internedIndex++;
      g_internedObject[string] = intern;
    }
    return intern;
  }
  
  public static function extern(number:Number):String {
    for(var x:Object in g_internedObject) {
      if (g_internedObject[x] == number) {
        return x;
      }
    }
    return null;
  }
  
  
  /**
   * Creates an instance of the supplied class.
   *
   * From as2lib.
   */
  public static function createInstanceOf(klass:Function, args:Array):Object
  {
    if (!klass) 
      return null;
      
    var result:Object = new Object();
    result.__proto__ = klass.prototype;
    result.__constructor__ = klass;
    klass.apply(result, args);
    return result;
  }
  
  
	/**
	 * Strict type-checking of elements.
	 * Might be slow, so use for debug.
	 */
	public static function chkElem (list:Object, type:Function):Object {
		for(var i:Object in list) {
			if(!(list[i] instanceof type))	return {who: i};
		}
		return true;
	}
	
	/**
	 * Multi-purpose function.
	 * eg. ASUtils.findMatch([NSCell, NSControl], arguments.caller, "prototype");
	 * eg. ASUtils.findMatch([NSApplication, result);
	 */
	public static function findMatch (suspects:Array, caller:Object, ext:String):NSDictionary {
		var i:String, x:Object, j:String;
		var f:Boolean = false;	//flag
		var aspf:Function = _global.ASSetPropFlags;	//shortcut
		
		for(i in suspects) {
			x = suspects[i];
			if(ext!=null)	x=x[ext];
			aspf(x, null, 6, true);
			for(j in x) {
				if(x[j]==caller) {
					f=true;
					break;
				}
			}
			aspf(x, null, 7);
			if(f)	break;
		}
		
		try {
			if(!f) {
				return NSDictionary.dictionaryWithObjectsAndKeys
				(f, "found");
			} else {
				return NSDictionary.dictionaryWithObjectsAndKeys
				(f, "found", j, "prop", suspects[i].prototype.toString(), "obj", ext, "ext");
			}
		} catch (e:NSException) {
			trace(e);
			throw e;
		}
	}
	
	
	/**
	 * Returns the number of occurences of token in str.
	 */
	public static function countIndicesOf(str:String, token:String):Number
	{
		return ASUtils.indicesOfString(str, token).length;
	}
	
	
	/**
	 * Returns the indicies of one sting in another.
	 */
	public static function indicesOfString(str:String, token:String):Array
	{
		var result:Array = new Array();
		var curpos:Number = 0;
		
		while (curpos != -1 && curpos < str.length)
		{
			curpos = str.indexOf(token, curpos);
			
			if (curpos != -1)
			{
				result.push(curpos);
				++curpos;
			}
		}
		
		return result;
	}
	
	/**
	 * Removes whitespace from the beginning and end of a string.
	 */
	public static function trimString(str:String):String
	{
		var end:Number = str.length;
		var start:Number = 0;
		var white:Object = new Object();
		white["_"+" ".charCodeAt(0)] = 1;
		white["_"+"\n".charCodeAt(0)] = 1;
		white["_"+"\r".charCodeAt(0)] = 1;
		white["_"+"\t".charCodeAt(0)] = 1;
		while(white["_"+str.charCodeAt(--end)]);
		while(white["_"+str.charCodeAt(start++)]);
		return str.slice(start-1,end+1);
	}
	
	
	/**
	 * Capitalizes each word in the provided string and returns the result.
	 */
	public static function capitalizeWords(words:String):String
	{
		var arrWords:Array = words.split(" ");
		
		var len:Number = arrWords.length; // apparently faster according to MM
		for (var i:Number = 0; i < len; i++)
		{
			var word:String = arrWords[i];
			arrWords[i] = word.charAt(0).toUpperCase() + word.substring(1);
		}
		
		return arrWords.join(" ");
	}
	
}