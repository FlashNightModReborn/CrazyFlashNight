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
 
import org.actionstep.ASUtils;
import org.actionstep.NSNotification;
import org.actionstep.NSNotificationCenter;

class org.actionstep.test.ASTestNotificationCenter {
  
  public var name:String;
  
  public function ASTestNotificationCenter(theName:String) {
    this.name = theName;
  }
  
  public function processEvent(notification:NSNotification) {
    trace(name+ " sees "+notification.object.name+" message "+notification.nameAsString());
  }

  public static function test() {
    var as:ASTestNotificationCenter = new ASTestNotificationCenter("one");
    var as2:ASTestNotificationCenter = new ASTestNotificationCenter("two");
    var as3:ASTestNotificationCenter = new ASTestNotificationCenter("three");
    var nc:NSNotificationCenter = NSNotificationCenter.defaultCenter();
    nc.addObserverSelectorNameObject(as, "processEvent", ASUtils.intern("NSTestMessage"), as2);
    nc.addObserverSelectorNameObject(as, "processEvent", ASUtils.intern("NSTestMessage2"), as2);
    nc.addObserverSelectorNameObject(as2, "processEvent", ASUtils.intern("NSTestMessage"));
    nc.postNotificationWithNameObject(ASUtils.intern("NSTestMessage"), as2);
    nc.postNotificationWithNameObject(ASUtils.intern("NSTestMessage2"), as2);
    nc.postNotificationWithNameObject(ASUtils.intern("NSTestMessage"), as3);
    trace("removing observer");
    nc.removeObserverNameObject(as, null, as2);
    nc.postNotificationWithNameObject(ASUtils.intern("NSTestMessage"), as2);
    nc.postNotificationWithNameObject(ASUtils.intern("NSTestMessage2"), as2);
    nc.postNotificationWithNameObject(ASUtils.intern("NSTestMessage"), as3);
  }
}