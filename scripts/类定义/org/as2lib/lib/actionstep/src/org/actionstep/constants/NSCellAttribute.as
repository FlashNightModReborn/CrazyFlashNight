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
 
class org.actionstep.constants.NSCellAttribute {
  
  static var NSCellAllowsMixedState:NSCellAttribute = new NSCellAttribute(0);
  static var NSChangeBackgroundCell:NSCellAttribute = new NSCellAttribute(1);
  static var NSCellChangesContents:NSCellAttribute = new NSCellAttribute(2);
  static var NSChangeGrayCell:NSCellAttribute = new NSCellAttribute(3);
  static var NSCellDisabled:NSCellAttribute = new NSCellAttribute(4);
  static var NSCellEditable:NSCellAttribute = new NSCellAttribute(5);
  static var NSCellHasImageHorizontal:NSCellAttribute = new NSCellAttribute(6);
  static var NSCellHasImageOnLeftOrBottom:NSCellAttribute = new NSCellAttribute(7);
  static var NSCellHasOverlappingImage:NSCellAttribute = new NSCellAttribute(8);
  static var NSCellHighlighted:NSCellAttribute = new NSCellAttribute(9);
  static var NSCellIsBordered:NSCellAttribute = new NSCellAttribute(10);
  static var NSCellIsInsetButton:NSCellAttribute = new NSCellAttribute(11);
  static var NSCellLightsByBackground:NSCellAttribute = new NSCellAttribute(12);
  static var NSCellLightsByContents:NSCellAttribute = new NSCellAttribute(13);
  static var NSCellLightsByGray:NSCellAttribute = new NSCellAttribute(14);
  static var NSPushInCell:NSCellAttribute = new NSCellAttribute(15);
  static var NSCellState:NSCellAttribute = new NSCellAttribute(16);
  
  public var value:Number;
  
  private function NSCellAttribute(num:Number) {
    value = num;
  }
}
