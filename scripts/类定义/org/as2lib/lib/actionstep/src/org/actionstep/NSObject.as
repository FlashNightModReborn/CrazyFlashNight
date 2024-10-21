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
 
import org.actionstep.NSDictionary;
import org.actionstep.NSEnumerator;
import org.actionstep.ASDebugger;

class org.actionstep.NSObject {
  
  public static var NSNotFound:Number = -1;
  public static var NSTabCharacter:Number = 9;
  public static var NSNewlineCharacter:Number = 13;
  public static var NSEnterCharacter:Number = 13;
  public static var NSEscapeCharacter:Number = 27;
  public static var NSCarriageReturnCharacter:Number = 13;
  public static var NSLeftArrowFunctionKey:Number = 37;
  public static var NSUpArrowFunctionKey:Number = 38;
  public static var NSRightArrowFunctionKey:Number = 39;
  public static var NSDownArrowFunctionKey:Number = 40;
  
    
  public function init():NSObject {
    return this;
  }
  
  public function description():String {
    return "NSObject";
  }
  
  public function asError(object:Object):Object {
    return ASDebugger.error(object);
  }

  public function asFatal(object:Object):Object {
    return ASDebugger.fatal(object);
  }

  public function asWarning(object:Object):Object {
    return ASDebugger.warning(object);
  }

  public function asDebug(object:Object):Object {
    return ASDebugger.debug(object);
  }

  public function toString():String {
    return description();
  }
  
  public function getClass():Function {
    return Object(this).__constructor__;
  }
  
  
  /**
   * Returns TRUE if this is equal to anObject, and FALSE otherwise.
   *
   * To be overridden by subclasses as desired.
   *
   * The default implementation is reference comparison.
   */
  public function isEqual(anObject:NSObject):Boolean {
    return this == anObject;
  }
  
  
  /**
   * Cycles through the variables dictionary applying 
   * this[key] = dict[key] for each entry.
   */
  public function updateMemberVariables(variables:NSDictionary):Void {
    var itr:NSEnumerator = variables.keyEnumerator();
    var key:String;
    
    while (null != (key = String(itr.nextObject())))
    {
      this[key] = variables.objectForKey(key);
    }
  }
  
  
  /**
   * Creates a shallow copy of the object.
   *
   * A shallow copy of an Object is a copy of the Object only. If the Object
   * contains references to other objects, the shallow copy will not create
   * copies of the referred objects. It will refer to the original objects
   * instead.
   */
  public function memberwiseClone():NSObject {
    var res:Object = new Object();
    
    //
    // Object prototype chain and constructor stuff (important so that further 
    // calls to clone will succeed, as well as getClass() use).
    //
    var constructor:Function = getClass();
    res.__proto__ = constructor.prototype;
    res.__constructor__ = constructor;
    
    //
    // Fire the constructor
    // 
    // NOTE:
    // We are not currently storing the arguments as originally passed
    // to the constructor, and this might pose a problem. In any case, it
    // should be fairly easy to do if necessary.
    //
    constructor.apply(res);
    
    //
    // Copy all the properties
    //
    for (var p:String in this) {
      res[p] = this[p];
    }
        
    return NSObject(res);
  }
  
  public function copy():NSObject {
    var f:Object = this["copyWithZone"];
    if(f instanceof Function) {
      return f.call(this);
    } else {
      throw new Error("Class doesn't implement NSCopying");
    }
  }
  
  public function respondsToSelector(sel:String):Boolean {
    return (this[sel] != undefined) && (this[sel] instanceof Function);
  }
}