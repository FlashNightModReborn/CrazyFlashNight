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
 
class org.actionstep.constants.NSTextAlignment {
  
  static var NSLeftTextAlignment:NSTextAlignment = new NSTextAlignment(0);
  static var NSRightTextAlignment:NSTextAlignment = new NSTextAlignment(1);
  static var NSCenterTextAlignment:NSTextAlignment = new NSTextAlignment(2);
  static var NSJustifiedTextAlignment:NSTextAlignment = new NSTextAlignment(3);
  static var NSNaturalTextAlignment:NSTextAlignment = new NSTextAlignment(4);
  
  private static var STRINGS:Array = ["left", "right", "center", "left", "left"];
  
  public var value:Number;
  public var string:String;
  
  private function NSTextAlignment(num:Number) {
    value = num;
    string = STRINGS[value];
  }

}