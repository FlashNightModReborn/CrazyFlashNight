/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 *
 * Copyright (c) 2005, Affinity Systems
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

import org.actionstep.NSActionCell;
import org.actionstep.NSRect;
import org.actionstep.NSView;

import org.actionstep.NSTextFieldCell;
import org.actionstep.NSFont;
import org.actionstep.ASFieldEditor;
import org.actionstep.ASFieldEditingProtocol;

import org.actionstep.constants.NSTextAlignment;
import org.actionstep.constants.NSWritingDirection;

/**
 * The NSFormCell class is used to implement text entry fields in a form. The
 * left part of an NSFormCell is a title. The right part is an editable text
 * entry field.
 *
 * NSFormCell implements the user interface of NSForm.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSFormCell extends NSActionCell 
	implements ASFieldEditingProtocol
{	
	public static var TITLE_PADDING:Number = 4;
	
	private var m_titlecell:NSTextFieldCell;
	private var m_inputcell:NSTextFieldCell;
	private var m_titlewidth:Number;
	
	/**
	 * Creates a new instance of NSFormCell.
	 */
	public function NSFormCell()
	{
		m_selectable = true;
		m_editable = true;
		
		m_titlecell = (new NSTextFieldCell()).initTextCell("Field:");
		m_titlecell.setEditable(false);
		m_titlecell.setDrawsBackground(false);
		m_titlecell.setAlignment(NSTextAlignment.NSRightTextAlignment);
		m_titlecell.setFont(NSFont.systemFontOfSize(12));
		calculateTitleWidth();
		
		m_inputcell = (new NSTextFieldCell()).initTextCell("");
		m_inputcell.setEditable(true);
		m_inputcell.setDrawsBackground(true);
		m_inputcell.setBezeled(true);
		m_inputcell.setFont(NSFont.systemFontOfSize(12));
	}
	
	
	/**
	 * Initializes a newly allocated NSFormCell. Its title is set to aString.
	 * The contents of its text entry field are set to the empty string (@“”).
	 * The font for both title and text is the user’s chosen system font in 12.0
	 * point, and the text area is drawn with a bezel. This method is the
	 * designated initializer for NSFormCell.
	 *
	 * Returns an initialized object.
	 */
	public function initTextCell(aString:String):NSFormCell
	{
		setTitle(aString);
		
		return this;
	}
	
	//******************************************************															 
	//*					  Properties					   *
	//******************************************************
	
	public function description():String
	{
		return "NSFormCell(title=" + title() + ", isBezeled=" + isBezeled() +
			", isBordered=" + isBordered() + ", titleFont=" + titleFont() + ")";
	}
	
	
	/**
	 * @see org.actionstep.NSCell#setBezeled()
	 */
	public function setBezeled(flag:Boolean) 
	{
		m_inputcell.isBezeled(flag);
	}
  
  
	/**
	 * @see org.actionstep.NSCell#isBezeled()
	 */
	public function isBezeled():Boolean 
	{
		return m_inputcell.isBezeled();
	}
  
  
	/**
	 * @see org.actionstep.NSCell#setBordered()
	 */
	public function setBordered(flag:Boolean) 
	{
		m_inputcell.setBordered(flag);
	}
  
  
	/**
	 * @see org.actionstep.NSCell#isBordered()
	 */
	public function isBordered():Boolean 
	{
		return m_inputcell.isBordered();
	}
	
	
	/**
	 * @see org.actionstep.NSCell#setObjectValue()
	 */
	public function setObjectValue(value:Object):Void
	{
		super.setObjectValue(value);
		m_inputcell.setObjectValue(value);
	}
	
	
	/**
	 * @see org.actionstep.NSCell#objectValue()
	 */
	public function objectValue():Object
	{
		return m_inputcell.objectValue();
	}
	
	
	/**
	 * Returns TRUE if the title is empty and an opaque bezel is set, otherwise
	 * FALSE is returned.
	 */
	public function isOpaque():Boolean
	{
		return title().length == 0; //! && opaque bezel
	}
	
	
	/**
	 * Returns the receiver’s title. The default title is “Field:”.
	 */
	public function title():String
	{
		return m_titlecell.stringValue();
	}
	
	
	/**
	 * Sets the receiver’s title to aString.
	 */
	public function setTitle(aString:String):Void
	{
		m_titlecell.setStringValue(aString);
		
		calculateTitleWidth();
	}
	
	
	/**
	 * Returns the alignment of the title. The alignment can be one of the
	 * following: NSLeftTextAlignment, NSCenterTextAlignment, or
	 * NSRightTextAlignment (the default).
	 */
	public function titleAlignment():NSTextAlignment
	{
		return m_titlecell.alignment();
	}
	
	
	/**
	 * Sets the alignment of the title. alignment can be one of three
	 * constants: NSLeftTextAlignment, NSRightTextAlignment, or
	 * NSCenterTextAlignment.
	 */
	public function setTitleAlignment(alignment:NSTextAlignment):Void
	{
		m_titlecell.setAlignment(alignment);
	}
	
	
	/**
	 * Returns the default writing direction used to render the form cell’s
	 * title.
	 */
	public function titleBaseWritingDirection():NSWritingDirection
	{
		//! what should I do here?
		
		return null;
	}
	
	
	/**
	 * Sets the default writing direction used to render the form cell’s title.
	 */
	public function setTitleBaseWritingDirection(
		writingDirection:NSWritingDirection):Void
	{
		//! What should I do here?
	}
	
	
	/**
	 * Returns the font used to draw the receiver’s title.
	 */
	public function titleFont():NSFont
	{
		return m_titlecell.font();
	}
	
	
	/**
	 * Sets the title’s font to font.
	 */
	public function setTitleFont(font:NSFont):Void
	{
		m_titlecell.setFont(font);
	}
	
	
	/**
	 * Returns the width (in pixels) of the title field. If you specified the
	 * width using setTitleWidth:, this method returns the value you chose.
	 * Otherwise, it returns the width calculated automatically by the
	 * Application Kit.
	 *
	 * If the optional aSize is provided, the width is calculated constrained
	 * to aSize.
	 */
	public function titleWidth():Number
	{
		return m_titlewidth;
	}
	
	
	/**
	 * Sets the width in pixels. You usually won’t need to invoke this method,
	 * because the Application Kit automatically sets the title width whenever
	 * the title changes. If, however, the automatic width doesn’t suit your
	 * needs, you can use setTitleWidth: to set the width explicitly.
	 *
	 * Once you have set the width this way, the Application Kit stops setting
	 * the width automatically; you will need to invoke setTitleWidth: every
	 * time the title changes. If you want the Application Kit to resume
	 * automatic width assignments, invoke setTitleWidth: with a negative
	 * width value.
	 */
	public function setTitleWidth(width:Number):Void
	{
		m_titlewidth = width;
	}
	
	
	/**
	 * Sets the cell title and a single mnemonic character. 
	 */ 
	public function setTitleWithMnemonic(titleWithAmpersand:String):Void
	{
		//
		// Extract mnemonic character
		//
		var mnem:String = titleWithAmpersand.substr(titleWithAmpersand.indexOf("&") + 1, 1);
		
		//! do something here to register mnemonic
		
		//
		// Remove mnemonic character
		//
		titleWithAmpersand = titleWithAmpersand.split("&").join("");
		
		setTitle(titleWithAmpersand);
	}
	
	//******************************************************															 
	//*					 Public Methods					   *
	//******************************************************
	
	/**
	 * Draws the cell in the view given the frame which defines
	 * the area in which to draw.
	 */
	public function drawWithFrameInView(cellFrame:NSRect, inView:NSView):Void
	{
		trace("frame: " + cellFrame);
		trace("title width: " + m_titlewidth);
		var titleFrame:NSRect = cellFrame.clone();
		titleFrame.size.width = m_titlewidth;
		
		trace("title frame: " + titleFrame);
		
		var inputFrame:NSRect = cellFrame.clone();
		inputFrame.size.width -= (m_titlewidth + 1);
		inputFrame.origin.x += m_titlewidth;
		
		trace("input frame: " + inputFrame);
		
		//
		// Tell the cells to draw in their respective areas
		//
		m_titlecell.drawWithFrameInView(titleFrame, inView);
		m_inputcell.drawWithFrameInView(inputFrame, inView);
	}
	
	
	/**
	 * @see org.actionstep.NSCell#release()
	 */
	public function release():Void
	{
		m_inputcell.release();
		m_titlecell.release();
	}
	
	//******************************************************															 
	//*					    Events						   *
	//******************************************************
	//******************************************************															 
	//*				    Protected Methods				   *
	//******************************************************

	/**
	 * @see org.actionstep.ASFieldEditingProtocol#beginEditingWithDelegate()
	 */	
	public function beginEditingWithDelegate(delegate:Object):ASFieldEditor 
	{
		trace("begin editing");
		
		if (!isSelectable()) 
		{
			return null;
		}
		
		if (m_inputcell["m_textField"] != null && m_inputcell["m_textField"]._parent != undefined) 
		{
			m_inputcell["m_textField"].text = stringValue();
			var editor:ASFieldEditor = ASFieldEditor.startEditing(this, delegate, m_inputcell["m_textField"]);
			return editor;
		}
		
		return null;
	}
	
	
	/**
	 * @see org.actionstep.ASFieldEditingProtocol#endEditingWithDelegate()
	 */
	public function endEditingWithDelegate(delegate:Object):Void 
	{
		ASFieldEditor.endEditing(delegate);
	}
  
	//******************************************************															 
	//*					 Private Methods				   *
	//******************************************************
	
	
	/**
	 * Calculates and sets the title width based on the current
	 * title string.
	 */
	private function calculateTitleWidth():Void
	{
		m_titlewidth = m_titlecell.font().getTextExtent(title()).width + TITLE_PADDING;
	}
	
	
	//******************************************************															 
	//*			   Public Static Properties				   *
	//******************************************************
	//******************************************************															 
	//*				 Public Static Methods				   *
	//******************************************************	
}
