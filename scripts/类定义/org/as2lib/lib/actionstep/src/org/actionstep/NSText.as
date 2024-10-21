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
 
import org.actionstep.NSView;
import org.actionstep.NSColor;
import org.actionstep.NSRange;
import org.actionstep.NSFont;
import org.actionstep.NSSize;
import org.actionstep.NSException;

import org.actionstep.constants.NSTextAlignment;
import org.actionstep.constants.NSWritingDirection;

class org.actionstep.NSText extends NSView {


  private function makeException():NSException {
    return NSException.exceptionWithNameReasonUserInfo("SubclassResponsibility", "Subclass must implement", null);
  }
  
  // Getting the characters

  public function string():String {
    var e:NSException = makeException(); trace(e); e.raise();
    return null;
  }

  // Setting graphics attributes

  public function setBackgroundColor(value:NSColor) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function backgroundColor():NSColor {
    var e:NSException = makeException(); trace(e); e.raise();
    return null;
  }

  public function setDrawsBackground(value:Boolean) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function drawsBackground():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }

  // Setting behavioral attributes

  public function setEditable(value:Boolean) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function isEditable():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }

  public function setSelectable(value:Boolean) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function isSelectable():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }

  public function setFieldEditor(value:Boolean) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function isFieldEditor():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }

  public function setRichText(value:Boolean) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function isRichText():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }
  
  public function setImportsGraphics(value:Boolean) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function importsGraphics():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }
  
  // Using the Font panel and menu
  
  public function setUsesFontPanel(value:Boolean) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function usesFontPanel():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }
  
  // Using the ruler
  
  public function toggleRuler(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function isRulerVisible():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }
  
  // Changing the selection
  
  public function setSelectedRange(value:NSRange) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  public function selectedRange():NSRange {
    var e:NSException = makeException(); trace(e); e.raise();
    return NSRange.NotFoundRange;
  }
  
  // Replacing text
  
  public function replaceCharactersInRangeWithString(range:NSRange, string:String) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  public function setString(string:String) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  // Action methods for editing
  
  public function selectAll(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function copy(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function cut(sender:Object) {
    copy(sender);
    clear(sender);
  }
  
  public function paste(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function copyFont(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function pasteFont(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function copyRuler(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function pasteRuler(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  /**
  * Remove all text from the text editor but do not place it on the clipboard
  * NOTE: Changed from the Cocoa delete method because delete is a keyword in ActionScript
  *
  */
  public function clear(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  // Changing the font
  public function changeFont(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function setFont(value:NSFont) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  public function font():NSFont {
    var e:NSException = makeException(); trace(e); e.raise();
    return null;
  }

  public function setFontRange(value:NSFont, range:NSRange) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  // Setting text alignment
  
  public function setAlignment(value:NSTextAlignment) {
    var e:NSException = makeException(); trace(e); e.raise();
    
  }
  
  public function alignCenter(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function alignLeft(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  public function alignRight(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  public function alignment():NSTextAlignment {
    var e:NSException = makeException(); trace(e); e.raise();
    return NSTextAlignment.NSLeftTextAlignment;
  }
  
  // Setting text color
  
  public function setTextColor(value:NSColor) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function setTextColorRange(value:NSColor, range:NSRange) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  public function textColor():NSColor {
    var e:NSException = makeException(); trace(e); e.raise();
    return null;
  }

  // Writing direction
  
  public function writingDirection():NSWritingDirection {
    var e:NSException = makeException(); trace(e); e.raise();
    return NSWritingDirection.NSWritingDirectionNatural;
  }

  public function setWritingDirection(direction:NSWritingDirection) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  // Setting superscripting and subscripting
  
  public function superscript(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function subscript(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function unscript(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  // Underlining text

  public function underline(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  // Constraining size
  
  public function setMaxSize(size:NSSize) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  public function maxSize():NSSize {
    var e:NSException = makeException(); trace(e); e.raise();
    return NSSize.ZeroSize;
  }

  public function setMinSize(size:NSSize) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function minSize():NSSize {
    var e:NSException = makeException(); trace(e); e.raise();
    return NSSize.ZeroSize;
  }

  public function setVerticallyResizable(value:Boolean) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function isVerticallyResizable():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }  

  public function setHorizontallyResizable(value:Boolean) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function isHorizontallyResizable():Boolean {
    var e:NSException = makeException(); trace(e); e.raise();
    return false;
  }  

  public function sizeToFit() {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  // Checking spelling
  
  public function checkSpelling(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }

  public function showGuessPanel(sender:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  // Scrolling
  
  public function scrollRangeToVisible(range:NSRange) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  // Setting the delegate
  
  public function setDelegate(delegate:Object) {
    var e:NSException = makeException(); trace(e); e.raise();
  }
  
  public function delegate():Object {
    var e:NSException = makeException(); trace(e); e.raise();
    return null;
  }
}