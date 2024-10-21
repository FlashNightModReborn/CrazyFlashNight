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

class org.actionstep.NSNumber extends NSObject {
  
  private var m_number:Number;
  
  public static function numberWithDouble(number:Number):NSNumber {
    return (new NSNumber()).initWithDouble(number);
  }
  public static function numberWithFloat(number:Number):NSNumber {
    return (new NSNumber()).initWithFloat(number);
  }
  public static function numberWithInt(number:Number):NSNumber {
    return (new NSNumber()).initWithInt(number);
  }
  
  public function initWithDouble(number:Number):NSNumber {
    m_number = number;
    return this;
  }
  public function initWithFloat(number:Number):NSNumber {
    m_number = number;
    return this;
  }
  public function initWithInt(number:Number):NSNumber {
    m_number = number;
    return this;
  }
  
  public function doubleValue():Number {
    return m_number;
  }
  public function floatValue():Number {
    return m_number;
  }
  public function intValue():Number {
    return m_number;
  }
  
}