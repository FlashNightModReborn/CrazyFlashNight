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
 
class org.actionstep.constants.NSBezelStyle {
  
  public static var NSRoundedBezelStyle:NSBezelStyle = new NSBezelStyle(0);
  public static var NSRegularSquareBezelStyle:NSBezelStyle = new NSBezelStyle(1);
  public static var NSThickSquareBezelStyle:NSBezelStyle = new NSBezelStyle(2);
  public static var NSThickerSquareBezelStyle:NSBezelStyle = new NSBezelStyle(3);
  public static var NSDisclosureBezelStyle:NSBezelStyle = new NSBezelStyle(4);
  public static var NSShadowlessSquareBezelStyle:NSBezelStyle = new NSBezelStyle(5);
  public static var NSCircularBezelStyle:NSBezelStyle = new NSBezelStyle(6);
  public static var NSTexturedSquareBezelStyle:NSBezelStyle = new NSBezelStyle(7);
  public static var NSHelpButtonBezelStyle:NSBezelStyle = new NSBezelStyle(8);

  public var value:Number;
  
  private function NSBezelStyle(num:Number) {
    value = num;
  }
}