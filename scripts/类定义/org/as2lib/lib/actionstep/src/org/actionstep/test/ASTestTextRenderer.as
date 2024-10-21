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
 * 3) The name InfoEther, Inc. and Affinity Systems may not be used to endorse or promote products  
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

import org.actionstep.*;

class org.actionstep.test.ASTestTextRenderer
{	
	public static function test():Void
	{
	  
	  var styleSheet:TextField.StyleSheet = new TextField.StyleSheet();
	  styleSheet.parseCSS( " contact {
            font-family: Verdana,Ariel;
            color: #000000;
            display: block;
          }
          name {
            font-weight: bold;
            font-size: 18;
          }
          label {
            color: #555555;
            font-weight: bold;
            font-size: 12;
            display: inline;
          }
          item {
            font-size: 12;
            display: block;
          }");
          
    var htmlText:String = "
      <contact>
        <name>Richard Kilmer</name>
        <item> President & CEO</item>
        <item> InfoEther, Inc.</item>
        <br><textformat tabstops='[60,200]'>
        <label> home \t</label> <item>555.555.1212</item>
        <label> work \t</label> <item>555.555.1313</item>
        </textformat>
      </contact>
      ";
	  
		var app:NSApplication = NSApplication.sharedApplication();
		var window:NSWindow = (new NSWindow()).initWithContentRect(new NSRect(0,0,500,500));
		var view:NSView = (new NSView()).initWithFrame(new NSRect(0,0,500,500));
		var textRenderer:ASTextRenderer = (new ASTextRenderer()).initWithFrame(new NSRect(10, 10, 300, 300));
		textRenderer.setStyleSheet(styleSheet);
		textRenderer.setText(htmlText);
		view.addSubview(textRenderer);
		window.setContentView(view);
		app.run();
	}
}
