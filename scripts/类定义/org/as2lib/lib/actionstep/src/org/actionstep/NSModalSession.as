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

import org.actionstep.NSObject;
import org.actionstep.NSWindow;

import org.actionstep.constants.NSRunResponse;

class org.actionstep.NSModalSession extends NSObject {
  public var runState:NSRunResponse;
  public var entryLevel:Number;  //not supported (yet)
  public var window:NSWindow;
  public var previous:NSModalSession;
  //not part of Openstep/Cocoa
  public var docWin:NSWindow;
  public var isSheet:Boolean;
  
  //additional, AS specific stuff
  public var callback:Object;
  public var selector:String;
  
  public function NSModalSession(run:NSRunResponse, entry:Number, win:NSWindow, prev:NSModalSession, call:Object, sel:String, sheet:NSWindow) {
    runState = run;
    entryLevel = entry;
    window = win;
    previous = prev;
    
    callback = call;
    selector = sel;
    
    docWin = sheet;
    isSheet = (sheet==null) ? false : true;
  }
  
  public function description():String {
    return "NSModalSession(" +
    	"callback=" + callback + ", " +
    	"selector=" + selector + ", " +
    	"isSheet=" + isSheet + 
    	")";
  }
}