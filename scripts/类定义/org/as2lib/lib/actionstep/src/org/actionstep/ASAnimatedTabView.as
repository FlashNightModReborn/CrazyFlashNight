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
 
import org.actionstep.NSTabView;
import org.actionstep.NSView;
import org.actionstep.NSRect;
import org.actionstep.NSPoint;
import org.actionstep.NSTimer;
import org.actionstep.ASDraw;
import org.actionstep.NSTabViewItem;
import org.actionstep.constants.NSTabState;

/*
 * This class overrides the selectTabViewItem method of NSTabView and
 * animates the switching of tab views by sliding the existing tab view 
 * item out (to the left) and then sliding the new tab view item in (from
 * the left).  This class also demonstrates how to use the NSTimer class
 * to achieve animation.
 *
 */ 
 
class org.actionstep.ASAnimatedTabView extends NSTabView {
  
  private var m_tabOutEasingFunction:Function;
  private var m_tabInEasingFunction:Function;
  private var m_tabOutDuration:Number;
  private var m_tabInDuration:Number;
  
  public function ASAnimatedTabView() {
    m_tabOutEasingFunction = ASDraw.easeOutQuad;
    m_tabInEasingFunction = ASDraw.easeInQuad;
    m_tabInDuration = m_tabOutDuration = 500;
  }
  
  public function selectTabViewItem(item:NSTabViewItem) {
    if (m_delegate != null) {
      if(typeof(m_delegate["tabViewShouldSelectTabViewItem"]) == "function") {
        if (!m_delegate["tabViewShouldSelectTabViewItem"].call(m_delegate, this, item)) {
          return;
        }
      }
    }
    _removeOldItem(item);
  }
  
  public function tabOutDuration():Number {
    return m_tabOutDuration;
  }

  public function tabInDuration():Number {
    return m_tabInDuration;
  }
  
  public function setTabOutDuration(dur:Number) {
    m_tabOutDuration = dur;
  }
  
  public function setTabInDuration(dur:Number) {
    m_tabInDuration = dur;
  }

  public function tabOutEasingFunction():Function {
    return m_tabOutEasingFunction;
  }

  public function setTabOutEasingFunction(func:Function) {
    m_tabOutEasingFunction = func;
  }
  
  public function tabInEasingFunction():Function {
    return m_tabInEasingFunction;
  }

  public function setInOutEasingFunction(func:Function) {
    m_tabInEasingFunction = func;
  }

  private function _removeOldItem(item:NSTabViewItem) {
    if (m_selected != null) {
      m_selected.setTabState(NSTabState.NSBackgroundTab);
      setNeedsDisplay(true);
      NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
        .005, this, "_animateOldItem", 
        { item:item, 
          startX:m_selected.view().frame().origin.x, 
          y:m_selected.view().frame().origin.y, 
          width:m_selected.view().frame().size.width,
          startTime:getTimer()
        }, 
        true);      
    } else {
      _addNewItem(item);
    }
  }
  
  private function _animateOldItem(timer:NSTimer) {
    var info:Object = timer.userInfo();
    var currentTime:Number = getTimer()-info.startTime;
    if (currentTime > m_tabOutDuration) currentTime = m_tabOutDuration;
    var currentX:Number = Number(m_tabOutEasingFunction.call(null, currentTime, info.startX, info.startX-info.width, m_tabOutDuration));
    if (currentTime == m_tabOutDuration) {
      currentX = info.startX-info.width;
      m_selected.view().removeFromSuperview();
      timer.invalidate();
      _addNewItem(timer.userInfo().item);
    }
    m_selected.view().setFrameOrigin(new NSPoint(currentX, info.y));
  }
  
  private function _addNewItem(item:NSTabViewItem) {
    m_selected = item;
    if (m_selected != null) {
      m_selectedItem = m_items.indexOfObject(m_selected);
      m_selected.setTabState(NSTabState.NSSelectedTab);
      if(typeof(m_delegate["tabViewWillSelectTabViewItem"]) == "function") {
        m_delegate["tabViewWillSelectTabViewItem"].call(m_delegate, this, m_selected);
      }
      var selectedView:NSView = m_selected.view();
      if (selectedView != null) {
        addSubview(selectedView);
        window().makeFirstResponder(m_selected.initialFirstResponder());
        var rect:NSRect = contentRect();
        rect.origin.x -= rect.size.width;
        selectedView.setFrame(rect);
        setNeedsDisplay(true);
        NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
          .005, this, "_animateNewItem", {
            startX:rect.origin.x, 
            y:rect.origin.y, 
            width:rect.size.width,
            startTime:getTimer()
          }, 
          true);
      
      } else {
        _finish();
      }
    } else {
      m_selectedItem = -1;
      _finish();
    }
  }
  
  private function _animateNewItem(timer:NSTimer) {
    var info:Object = timer.userInfo();
    var currentTime:Number = getTimer()-info.startTime;
    if (currentTime > m_tabInDuration) currentTime = m_tabInDuration;
    var currentX:Number = Number(m_tabInEasingFunction.call(null, currentTime, info.startX, info.width, m_tabInDuration));
    if (currentTime == m_tabInDuration) {
      currentX = 0;
      timer.invalidate();
      _finish();
    }
    m_selected.view().setFrameOrigin(new NSPoint(currentX, info.y));
  }
  
  private function _finish() {
    setNeedsDisplay(true);
    //window().displayIfNeeded();
    if(typeof(m_delegate["tabViewDidSelectTabViewItem"]) == "function") {
      m_delegate["tabViewDidSelectTabViewItem"].call(m_delegate, this, m_selected);
    }
  }
}