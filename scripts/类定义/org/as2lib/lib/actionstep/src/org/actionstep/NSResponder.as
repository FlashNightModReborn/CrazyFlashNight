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
import org.actionstep.NSMenu;
import org.actionstep.NSEvent;
import org.actionstep.NSUndoManager;
import org.actionstep.NSBeep;

import org.actionstep.constants.NSInterfaceStyle;

class org.actionstep.NSResponder extends NSObject {
  
  private var m_nextResponder:NSResponder;
  private var m_menu:NSMenu;
  private var m_interfaceStyle:NSInterfaceStyle;
  
  private function beep() {
    NSBeep.beep();
  }
  
  //Changing the first responder
  
  function acceptsFirstResponder():Boolean {
    return false;
  }
  function becomeFirstResponder():Boolean {
    return true;
  }
  function resignFirstResponder():Boolean {
    return true;
  }
  
  //Setting the next responder

  function setNextResponder(responder:NSResponder) {
    m_nextResponder = responder;
  }
  
  function nextResponder():NSResponder {
    return m_nextResponder;
  }
  
  //Event methods

  function mouseDown(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.mouseDown(event);
    } else {
      noResponderFor("mouseDown");
    }
  }
  function mouseDragged(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.mouseDragged(event);
    } else {
      noResponderFor("mouseDragged");
    }
  }
  function mouseUp(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.mouseUp(event);
    } else {
      noResponderFor("mouseUp");
    }
  }
  function mouseMoved(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.mouseMoved(event);
    } else {
      noResponderFor("mouseMoved");
    }
  }
  function mouseEntered(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.mouseEntered(event);
    } else {
      noResponderFor("mouseEntered");
    }
  }
  function mouseExited(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.mouseExited(event);
    } else {
      noResponderFor("mouseExited");
    }
  }
  function rightMouseDown(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.rightMouseDown(event);
    } else {
      noResponderFor("rightMouseDown");
    }
  }
  function rightMouseDragged(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.rightMouseDragged(event);
    } else {
      noResponderFor("rightMouseDragged");
    }
  }
  function rightMouseUp(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.rightMouseUp(event);
    } else {
      noResponderFor("rightMouseUp");
    }
  }
  function otherMouseDown(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.otherMouseDown(event);
    } else {
      noResponderFor("otherMouseDown");
    }
  }
  function otherMouseDragged(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.otherMouseDragged(event);
    } else {
      noResponderFor("otherMouseDragged");
    }
  }
  function otherMouseUp(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.otherMouseUp(event);
    } else {
      noResponderFor("otherMouseUp");
    }
  }
  function scrollWheel(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.scrollWheel(event);
    } else {
      noResponderFor("scrollWheel");
    }
  }
  function keyDown(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.keyDown(event);
    } else {
      noResponderFor("keyDown");
    }
  }
  function keyUp(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.keyUp(event);
    } else {
      noResponderFor("keyUp");
    }
  }
  function flagsChanged(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.flagsChanged(event);
    } else {
      noResponderFor("flagsChanged");
    }
  }
  function helpRequested(event:NSEvent):Void {
    if(m_nextResponder!=undefined) {
      m_nextResponder.helpRequested(event);
    } else {
      noResponderFor("helpRequested");
    }
  }
  
  // Special key event methods
  
  function interpretKeyEvents(eventArray:Array):Void {
  }
  function performKeyEquivalent(event:NSEvent):Boolean {
    return false;
  }
  function performMneumonic(string:String):Boolean {
    return false;
  }
  
  // Clearing key events
  
  function flushBufferedKeyEvent():Void { }
  
  // Action methods
  
  function cancelOperation(sender:Object):Void { }
  function capitalizeWord(sender:Object):Void { }
  function centerSelectionInVisibleArea(sender:Object):Void { }
  function changeCaseOfLetter(sender:Object):Void { }
  function complete(sender:Object):Void { }
  function deleteBackward(sender:Object):Void { }
  function deleteBackwardByDecomposingPreviousCharacter(sender:Object):Void { }
  function deleteForward(sender:Object):Void { }
  function deleteToBeginningOfLine(sender:Object):Void { }
  function deleteToBeginningOfParagraph(sender:Object):Void { }
  function deleteToEndOfLine(sender:Object):Void { }
  function deleteToEndOfParagraph(sender:Object):Void { }
  function deleteToMark(sender:Object):Void { }
  function deleteWordBackward(sender:Object):Void { }
  function deleteWordForward(sender:Object):Void { }
  function indent(sender:Object):Void { }
  function insertBacktab(sender:Object):Void { }
  function insertNewline(sender:Object):Void { }
  function insertNewlineIgnoringFieldEditor(sender:Object):Void { }
  function insertParagraphSeparator(sender:Object):Void { }
  function insertTab(sender:Object):Void { }
  function insertTabIgnoringFieldEditor(sender:Object):Void { }
  function insertText(sender:Object):Void { 
    if (m_nextResponder != undefined) {
      m_nextResponder.insertText(sender);
    }
    else { 
      beep(); 
    }
  }
  function lowercaseWord(sender:Object):Void { }
  function moveBackward(sender:Object):Void { }
  function moveBackwardAndModifySelection(sender:Object):Void { }
  function moveDown(sender:Object):Void { }
  function moveDownAndModifySelection(sender:Object):Void { }
  function moveForward(sender:Object):Void { }
  function moveForwardAndModifySelection(sender:Object):Void { }
  function moveLeft(sender:Object):Void { }
  function moveLeftAndModifySelection(sender:Object):Void { }
  function moveRight(sender:Object):Void { }
  function moveRightAndModifySelection(sender:Object):Void { }
  function moveToBeginningOfDocument(sender:Object):Void { }
  function moveToBeginningOfLine(sender:Object):Void { }
  function moveToBeginningOfParagraph(sender:Object):Void { }
  function moveToEndOfDocument(sender:Object):Void { }
  function moveToEndOfLine(sender:Object):Void { }
  function moveToEndOfParagraph(sender:Object):Void { }
  function moveUp(sender:Object):Void { }
  function moveUpAndModifySelection(sender:Object):Void { }
  function moveWordBackward(sender:Object):Void { }
  function moveWordBackwardAndModifySelection(sender:Object):Void { }
  function moveWordForward(sender:Object):Void { }
  function moveWordForwardAndModifySelection(sender:Object):Void { }
  function moveWordLeft(sender:Object):Void { }
  function moveWordRight(sender:Object):Void { }
  function moveWordRightAndModifySelection(sender:Object):Void { }
  function moveWordLeftAndModifySelection(sender:Object):Void { }
  function pageDown(sender:Object):Void { }
  function pageUp(sender:Object):Void { }
  function scrollLineDown(sender:Object):Void { }
  function scrollLineUp(sender:Object):Void { }
  function scrollPageDown(sender:Object):Void { }
  function scrollPageUp(sender:Object):Void { }
  function selectAll(sender:Object):Void { }
  function selectLine(sender:Object):Void { }
  function selectParagraph(sender:Object):Void { }
  function selectToMark(sender:Object):Void { }
  function selectWord(sender:Object):Void { }
  function setMark(sender:Object):Void { }
  function showContextHelp(sender:Object):Void { }
  function swapWithMark(sender:Object):Void { }
  function transpose(sender:Object):Void { }
  function transposeWords(sender:Object):Void { }
  function uppercaseWord(sender:Object):Void { }
  function yank(sender:Object):Void { }
  
  // Dispatch methods
  
  function doCommandBySelector(selector:String):Void {
    var result:Boolean = tryToPerformWith(selector, null);
    if (!result) {
      beep();
    }
  }
  
  function tryToPerformWith(selector:String, anObject:Object):Boolean {
    if(typeof(this[selector]) == "function") {
      this[selector].call(this, anObject);
      return true;
    } else {
      if(m_nextResponder!=undefined) {
        return m_nextResponder.tryToPerformWith(selector, anObject);
      } else {
        return false;
      }
    }
  }
  
  // Terminating the responder chain
  
  function noResponderFor(selector:String):Void {
    if(selector=="keyDown") {
      beep();
    }
  }
  
  // Setting the menu
  
  function setMenu(menu:NSMenu):Void {
    m_menu = menu;
  }
  
  function menu():NSMenu {
    return m_menu;
  }
  
  // Setting the interface style
  
  function setInterfaceStyle(style:NSInterfaceStyle):Void {
    m_interfaceStyle = style;
  }
  
  function interfaceStyle():NSInterfaceStyle {
    return m_interfaceStyle;
  }
  
  // Undo manager
  
  function undoManager():NSUndoManager {
    if(m_nextResponder!=undefined) {
      return m_nextResponder.undoManager();
    }
    return null;
  }
}