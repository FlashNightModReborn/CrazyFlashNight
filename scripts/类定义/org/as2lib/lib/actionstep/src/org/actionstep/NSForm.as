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

import org.actionstep.NSMatrix;
import org.actionstep.NSFormCell;
import org.actionstep.NSFont;
import org.actionstep.NSCell;
import org.actionstep.NSArray;
import org.actionstep.NSSize;
import org.actionstep.NSRect;
import org.actionstep.NSEvent;
import org.actionstep.NSEnumerator;
import org.actionstep.NSColor;
import org.actionstep.NSException;

import org.actionstep.constants.NSTextAlignment;
import org.actionstep.constants.NSWritingDirection;

/**
 * An NSForm is a vertical NSMatrix of NSFormCells.
 *
 * NSForm uses NSFormCell to implement its user interface.
 * 
 * @see org.actionstep.NSFormCell
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSForm extends NSMatrix
{		
	private var m_largesttitlewidth:Number;
	private var m_cellwritingdirection:NSWritingDirection;
	private var m_celltextwritingdirection:NSWritingDirection;
	private var m_cellfont:NSFont;
	private var m_celltextalignment:NSTextAlignment;
	private var m_cellalignment:NSTextAlignment;
	private var m_celltextfont:NSFont;
	private var m_bordered:Boolean;
	private var m_bezeled:Boolean;
	
	/**
	 * Creates a new instance of NSForm.
	 */	
	public function NSForm()
	{
		m_cellclass = NSFormCell;
		m_cellsize = new NSSize(100, 22);
		m_largesttitlewidth = 0;
		m_bgcolor = new NSColor(0xE3E3E3);
		m_cellspacing = new NSSize(1, 1);
	}
	
	
	/**
	 * Initializes the form with the frame as specified by frameRect.
	 *
	 * Entry width is set to the frame's width.
	 */
	public function initWithFrame(frameRect:NSRect):NSForm
	{
		m_cellsize.width = frameRect.size.width;
		super.initWithFrame(frameRect);
				
		return this;
	}
	
	//******************************************************															 
	//*					  Properties					   *
	//******************************************************
	
	/**
	 * Returns the index of the selected entry. If no entry is selected,
	 * indexOfSelectedItem returns –1.
	 */ 
	public function indexOfFirstSelectedItem():Number
	{
		if (m_sel.count() == 0)
			return -1;
		else
			return m_sel.lastObject().row;
	}
	
	
	/**
	 * If flag is TRUE, sets all the entries in the receiver to show a bezel
	 * around their editable text; if flag is FALSE, sets all the entries to show
	 * no bezel.
	 */
	public function setBezeled(flag:Boolean):Void
	{
		m_bezeled = flag;
		
		var cells:NSArray = m_cells;
		
		//
		// Loop through the cells, setting the flag.
		//
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSFormCell;
		
		while (null != (cell = NSFormCell(itr.nextObject())))
		{
			cell.setBezeled(flag);
		}
	}
	
	
	/** 
	 * Sets whether the entries in the receiver display a border—that is, a
	 * thin line—around their editable text fields. If flag is YES, they
	 * display a border; otherwise, they don’t. An entry can have a border or a
	 * bezel, but not both.
	 */
	public function setBordered(flag:Boolean):Void
	{
		m_bordered = flag;
		
		var cells:NSArray = m_cells;
		
		//
		// Loop through the cells, setting the flag.
		//
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSFormCell;
		
		while (null != (cell = NSFormCell(itr.nextObject())))
		{
			cell.setBordered(flag);
		}
	}
	
	
	/**
	 * Sets the width (in pixels) of all the entries in the receiver. This
	 * width includes both the title and the text field. 
	 */
	public function setEntryWidth(width:Number):Void
	{
		m_cellsize.width = width;
	}
	
	
	/**
	 * Sets the receiver’s frame size to be newSize. The width of NSFormCells
	 * always match the width of the NSForm. The cell width is always changed
	 * to match the view regardless of the value returned by autosizesCells.
	 */
	public function setFrameSize(newSize:NSSize):Void
	{
		m_cellsize.width = newSize.width;
		super.setFrameSize(newSize);
	}
	
	
	/**
	 * Sets the number of pixels between entries in the receiver to spacing.
	 */
	public function setInterlineSpacing(spacing:Number):Void
	{
		setIntercellSpacing(new NSSize(0, spacing));
	}
	
	
	/**
	 * Sets the alignment for all of the receiver’s editable text. alignment
	 * can be one of three constants: NSRightTextAlignment,
	 * NSCenterTextAlignment, or NSLeftTextAlignment (the default).
	 */
	public function setTextAlignment(alignment:NSTextAlignment):Void
	{
		//
		// Not valid arguments
		//
		if (alignment == NSTextAlignment.NSJustifiedTextAlignment ||
			alignment == NSTextAlignment.NSNaturalTextAlignment)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"InvalidArgumentException",
				"setTextAlignment can only take alignment " +
				"values of NSRightTextAlignment, NSCenterTextAlignment, or " +
				"NSLeftTextAlignment", null);
			trace(e); // annotate the exception
			throw e;
		}
			
		m_celltextalignment = alignment;
			
		//
		// Loop through the cells, setting the alignment.
		//
		var cells:NSArray = m_cells;
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSFormCell;
		
		while (null != (cell = NSFormCell(itr.nextObject())))
		{
			cell.setAlignment(alignment);
		}
	}
	
	
	/**
	 * Sets the writing direction for the text content of every control
	 * embedded in the form.
	 */
	public function setTextBaseWritingDirection(
		writingDirection:NSWritingDirection):Void
	{
		m_celltextwritingdirection = writingDirection;
		
		//
		// Loop through the cells, setting the title font.
		//
		var cells:NSArray = m_cells;
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSFormCell;
		
		while (null != (cell = NSFormCell(itr.nextObject())))
		{
			//! cell.setBaseWritingDirection(writingDirection);
		}
	}
	
	
	/**
	 * Sets the font for all of the receiver’s editable text fields to font.
	 */
	public function setTextFont(font:NSFont):Void
	{
		m_celltextfont = font;
		
		//
		// Loop through the cells, setting the title font.
		//
		var cells:NSArray = m_cells;
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSFormCell;
		
		while (null != (cell = NSFormCell(itr.nextObject())))
		{
			cell.setFont(font);
		}
	}
	
	
	/**
	 * Sets the alignment for all of the entry titles. alignment can be one of
	 * three constants: NSRightTextAlignment, NSCenterTextAlignment, or the
	 * default, NSLeftTextAlignment.
	 */
	public function setTitleDirection(alignment:NSTextAlignment):Void
	{
		//
		// Not valid arguments
		//
		if (alignment == NSTextAlignment.NSJustifiedTextAlignment ||
			alignment == NSTextAlignment.NSNaturalTextAlignment)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"InvalidArgumentException",
				"NSForm::setTextAlignment can only take alignment " +
				"values of NSRightTextAlignment, NSCenterTextAlignment, or " +
				"NSLeftTextAlignment");
			trace(e);
			throw e;
		}
		
		m_cellalignment = alignment;
		
		//
		// Loop through the cells, setting the title alignment.
		//
		var cells:NSArray = m_cells;
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSFormCell;
		
		while (null != (cell = NSFormCell(itr.nextObject())))
		{
			cell.setTitleAlignment(alignment);
		}
	}
	
	
	/**
	 * Sets the writing direction for the title of every control embedded in
	 * the form.
	 */
	public function setTitleBaseWritingDirection(
		writingDirection:NSWritingDirection):Void
	{
		m_cellwritingdirection = writingDirection;
		
		//
		// Loop through the cells, setting the writing direction.
		//
		var cells:NSArray = m_cells;
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSFormCell;
		
		while (null != (cell = NSFormCell(itr.nextObject())))
		{
			cell.setTitleBaseWritingDirection(writingDirection);
		}
	}
	
	
	/**
	 * Sets the font for all of the entry titles to font.
	 */
	public function setTitleFont(font:NSFont):Void
	{
		m_cellfont = font;
		
		//
		// Loop through the cells, setting the title font.
		//
		var cells:NSArray = m_cells;
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSFormCell;
		
		while (null != (cell = NSFormCell(itr.nextObject())))
		{
			cell.setTitleFont(font);
		}
	}
	
	//******************************************************															 
	//*					 Public Methods					   *
	//******************************************************
	
	/**
	 * Adds a new entry to the end of the receiver and gives it the title
	 * title. The new entry has no tag, target, or action, but is enabled
	 * and editable.
	 */
	public function addEntry(title:String):NSFormCell
	{
		var cell:NSFormCell = (new NSFormCell()).initTextCell(title);
		prepareCell(cell); // assign the cell the properties of the Form
		recalcTitleWidthWithNewWidth(cell.titleWidth());
		cell.setTitleWidth(m_largesttitlewidth);
		
		super.addRowWithCells(NSArray.arrayWithObject(cell));
		
		
		return cell;
	}
	
	
	/**
	 * Returns the entry specified by entryIndex.
	 */
	public function cellAtIndex(entryIndex:Number):NSFormCell
	{
		return NSFormCell(
			m_cells.objectAtIndex(entryIndex).objectAtIndex(0));
	}
	
	
	/**
	 * Displays the entry specified by entryIndex. Because this method is
	 * called automatically whenever a cell needs drawing, you never need to
	 * invoke it explicitly. It is included in the API so you can override it
	 * if you subclass NSFormCell.
	 */
	public function drawCellAtIndex(entryIndex:Number):Void
	{
		super.drawCellAtRowColumn(entryIndex, 0);
	}
	
	
	/**
	 * Returns the index of the entry whose tag is tag.
	 */
	public function indexOfCellWithTag(anInt:Number):Number
	{
		//
		// Loop through the cells, setting the title font.
		//
		var cells:NSArray = m_cells;
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSFormCell;
		var cnt:Number = 0;
		
		while (null != (cell = NSFormCell(itr.nextObject())))
		{
			if (cell.tag() == anInt)
				return cnt;
				
			cnt++;
		}
		
		return null;
	}
	
	
	/**
	 * Inserts an entry with the title title at the position in the receiver
	 * specified by entryIndex. The new entry has no tag, target, or action,
	 * and, as explained in the class description, it won’t appear on the
	 * screen automatically.
	 *
	 * Returns the newly inserted NSFormCell.
	 */
	public function insertEntryAtIndex(title:String, 
		entryIndex:Number):NSFormCell
	{
		var cell:NSFormCell = (new NSFormCell()).initTextCell(title);
		prepareCell(cell);
		recalcTitleWidthWithNewWidth(cell.titleWidth());
		cell.setTitleWidth(m_largesttitlewidth);
		
		super.insertRowWithCells(entryIndex, NSArray.arrayWithObject(cell));		
		
		return cell;
	}
	
	
	/**
	 * Removes the entry at entryIndex and frees it. If entryIndex is not a
	 * valid position in the receiver, does nothing.
	 */
	public function removeEntryAtIndex(entryIndex:Number):Void
	{
		removeRow(entryIndex);
		recalcTitleWidth();
	}
	
	
	/**
	 * Selects the entry at entryIndex. If entryIndex is not a valid position
	 * in the receiver, does nothing.
	 */
	public function selectTextAtIndex(entryIndex:Number):Void
	{
		selectTextAtRowColumn(entryIndex, 0);
	}
	
	//******************************************************															 
	//*					    Events						   *
	//******************************************************
	
	public function mouseDown(event:NSEvent):Void 
	{
		super.mouseDown(event);
		
		var sel:NSCell = selectedCell();
		if (sel != null)
			super.selectText();
			
			
	}
	
	//******************************************************															 
	//*				    Protected Methods				   *
	//******************************************************
	//******************************************************															 
	//*					 Private Methods				   *
	//******************************************************
	
	private function prepareCell(aCell:NSFormCell):Void
	{
		if (m_cellwritingdirection != undefined)
			aCell.setTitleBaseWritingDirection(m_cellwritingdirection);
					
		if (m_cellfont != undefined)
			aCell.setTitleFont(m_cellfont);
		
		if (m_cellalignment != undefined)
			aCell.setTitleAlignment(m_cellalignment);
			
		if (m_bordered != undefined)
			aCell.setBordered(m_bordered);
			
		if (m_bezeled != undefined)
			aCell.setBezeled(m_bezeled);
		
		if (m_celltextalignment != undefined)
			aCell.setAlignment(m_celltextalignment);
		
		if (m_celltextfont != undefined)
			aCell.setFont(m_celltextfont);
		
		//! if (m_celltextwritingdirection != undefined)
		
	}
	
	
	private function recalcTitleWidth():Void
	{
		var cells:Array = m_cells.internalList();
		var len:Number = cells.length;
		var wdth:Number = 0;
		var cell:NSFormCell;
		var cellwdth:Number;
		
		for (var i:Number = 0; i < len; i++)
		{
			cell = NSFormCell(cells[i]);
			cellwdth = cell.titleWidth();
			
			if (cellwdth > wdth)
				wdth = cellwdth;
		}
		
		setTitleWidth(wdth);
	}
	
	
	private function recalcTitleWidthWithNewWidth(newWidth:Number):Void
	{
		if (newWidth <= m_largesttitlewidth)
			return;
			
		setTitleWidth(newWidth);
	}
	
	
	private function setTitleWidth(newWidth:Number):Void
	{
		var cells:Array = m_cells.internalList();
		var len:Number = cells.length;
		var cell:NSFormCell;
		
		for (var i:Number = 0; i < len; i++)
		{
			cell = NSFormCell(cells[i]);
			cell.setTitleWidth(newWidth);
		}
		
		m_largesttitlewidth = newWidth;
	}
	
	//******************************************************															 
	//*			   Public Static Properties				   *
	//******************************************************
	//******************************************************															 
	//*				 Public Static Methods				   *
	//******************************************************
}
