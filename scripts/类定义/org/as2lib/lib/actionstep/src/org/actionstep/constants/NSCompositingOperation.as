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
 
class org.actionstep.constants.NSCompositingOperation {
  
  static var NSCompositeClear:NSCompositingOperation           = new NSCompositingOperation(0 );
  static var NSCompositeCopy:NSCompositingOperation            = new NSCompositingOperation(1 );
  static var NSCompositeSourceOver:NSCompositingOperation      = new NSCompositingOperation(2 );
  static var NSCompositeSourceIn:NSCompositingOperation        = new NSCompositingOperation(3 );
  static var NSCompositeSourceOut:NSCompositingOperation       = new NSCompositingOperation(4 ); 
  static var NSCompositeSourceAtop:NSCompositingOperation      = new NSCompositingOperation(5 );
  static var NSCompositeDestinationOver:NSCompositingOperation = new NSCompositingOperation(6 );
  static var NSCompositeDestinationIn:NSCompositingOperation   = new NSCompositingOperation(7 );
  static var NSCompositeDestinationOut:NSCompositingOperation  = new NSCompositingOperation(8 );
  static var NSCompositeDestinationAtop:NSCompositingOperation = new NSCompositingOperation(9 );
  static var NSCompositeXOR:NSCompositingOperation             = new NSCompositingOperation(10);
  static var NSCompositePlusDarker:NSCompositingOperation      = new NSCompositingOperation(11);
  static var NSCompositeHighlight:NSCompositingOperation       = new NSCompositingOperation(12);
  static var NSCompositePlusLighter:NSCompositingOperation     = new NSCompositingOperation(13);
  
  public var value:Number;
  
  private function NSCompositingOperation(num:Number) {
    value = num;
  }

}