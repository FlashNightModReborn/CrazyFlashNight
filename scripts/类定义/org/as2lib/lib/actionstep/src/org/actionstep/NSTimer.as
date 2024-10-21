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

class org.actionstep.NSTimer extends NSObject {
  
  public static function scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
    seconds:Number, target:Object, selector:String, userInfo:Object, repeats:Boolean):NSTimer {
    return (new NSTimer()).initWithFireDateIntervalTargetSelectorUserInfoRepeats(new Date(), seconds, target, selector, userInfo, repeats);
  }
  
  // Intervals (setInterval/clearInterval)
  private var m_initialFireInterval:Number;
  private var m_interval:Number;

  private var m_seconds:Number;
  private var m_userInfo:Object;
  private var m_target:Object;
  private var m_selector:String;
  private var m_repeats:Boolean;
  private var m_fireDate:Date;
  private var m_lastFireDate:Date;
  
  public function initWithFireDateIntervalTargetSelectorUserInfoRepeats(
    date:Date, seconds:Number, target:Object, selector:String, userInfo:Object, repeats:Boolean):NSTimer {
    m_seconds = seconds;
    m_fireDate = date;
    m_target = target;
    m_selector = selector;
    m_userInfo = userInfo;
    m_repeats = repeats;
    scheduleToFire();
    return this;
  }
  
  public function invalidate() {
    if (m_initialFireInterval != null) {
      clearInterval(m_initialFireInterval);
      m_initialFireInterval = null;
    }
    if (m_interval != null) {
      clearInterval(m_interval);
      m_interval = null;
    }
  }
  
  public function isValid():Boolean {
    return (m_interval != null);
  }
  
  public function fire() {
    if (isValid()) {
      m_target[m_selector].call(m_target, this);
      if (!m_repeats) {
        invalidate();
      }
    }
  }
  
  public function fireDate():Date {
    var date:Date = m_lastFireDate;
    if (date==null) {
      date = m_fireDate;
    }
    var result:Date = new Date();
    result.setTime(date.getTime()+m_seconds*1000);
    return result;
  }
  
  public function setFireDate(date:Date) {
    invalidate();
    m_fireDate = date;
    scheduleToFire();
  }
  
  public function timeInterval():Number {
    return m_seconds;
  }
  
  public function userInfo():Object {
    return m_userInfo;
  }
  
  // PRIVATE
  
  private function scheduleToFire() {
    var startTime:Number = m_fireDate.getTime();
    var currentTime:Number = (new Date()).getTime();
    if (startTime < currentTime) {
      start();
      return;
    }
    m_initialFireInterval = setInterval(this, "start", startTime - currentTime, this);
  }
  
  private function start() {
    if (m_initialFireInterval != null) {
      clearInterval(m_initialFireInterval);
      m_initialFireInterval = null;
    }
    m_interval = setInterval(this, "fire", m_seconds*1000, this);
  }
}
