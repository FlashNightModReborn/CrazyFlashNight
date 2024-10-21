/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 *
 * Copyright (c) 2005, Scott Hyndman
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
 * 3) The name InfoEther, Inc. and Scott Hyndman may not be used to endorse or promote products  
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

import org.actionstep.ASFieldEditingProtocol;
import org.actionstep.ASFieldEditor;
import org.actionstep.ASTheme;
import org.actionstep.constants.NSCellType;
import org.actionstep.constants.NSMatrixMode;
import org.actionstep.constants.NSTextMovement;
import org.actionstep.NSActionCell;
import org.actionstep.NSApplication;
import org.actionstep.NSArray;
import org.actionstep.NSCell;
import org.actionstep.NSColor;
import org.actionstep.NSControl;
import org.actionstep.NSEnumerator;
import org.actionstep.NSEvent;
import org.actionstep.NSException;
import org.actionstep.NSNotification;
import org.actionstep.NSPoint;
import org.actionstep.NSRange;
import org.actionstep.NSRect;
import org.actionstep.NSSize;
//import org.actionstep.constants.NSCellAttribute;

//**************************************************************************
// NSMatrix TODO:
//**************************************************************************
// 
//**************************************************************************

/**
 * NSMatrix is a class used for creating groups of NSCells that work together 
 * in various ways.
 * 
 * The cells in an NSMatrix are numbered by row and column, each starting with
 * 0; for example, the top left NSCell would be at (0, 0), and the NSCell 
 * that’s second down and third across would be at (1, 2).
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSMatrix extends NSControl
{	
	private var m_cellclass:Function;
	private var m_prototype:NSCell;	
	private var m_cells:NSArray;
	private var m_numrows:Number;
	private var m_numcols:Number;
	private var m_maxrows:Number = 0;
	private var m_maxcols:Number = 0;
	private var m_mode:NSMatrixMode;
	private var m_allowsemptysel:Boolean;
	private var m_bgcolor:NSColor;
	private var m_cellbgcolor:NSColor;
	private var m_cellsize:NSSize;
	private var m_delegate:Object;
	private var m_doubleaction:String;
	private var m_drawsbg:Boolean;
	private var m_autosizecells:Boolean;
	private var m_cellspacing:NSSize;
	private var m_autoscroll:Boolean;
	private var m_isselbyrect:Boolean;
	private var m_keycell:NSCell;
	private var m_mousedownflags:Number;
	private var m_sel:NSArray;
	private var m_selcell:NSCell; // The selected cell.
	private var m_selcell_row:Number; // holds the row of m_selcell
	private var m_selcell_column:Number; // holds the column of m_selcell
	private var m_target:Object;
	private var m_action:String;
	private var m_usetabkey:Boolean;
	private var m_editor:ASFieldEditor;
	
	private var m_dottedrow:Number = -1; // the row in which the highlighted cell exists
	private var m_dottedcol:Number = -1; // the column in which the highlighted cell exists
	
	/** 
	 * The reason this is here, and not in a cell, is because a matrix can 
	 * exist with no cells, and we wouldn't have a cell to ask.
	 *
	 * @see org.actionstep.NSMatrix#drawsCellBackground()
	 * @see org.actionstep.NSMatrix#setDrawsCellBackground()
	 */
	private var m_drawscellbg:Boolean;
	
	/** 
	 * True if using copies of a cell instance to fill cells, and false 
	 * otherwise. The default is false.
	 */
	private var m_usingcellinstance:Boolean;
	
	
	/** Constructs a new instance of NSMatrix. */
	public function NSMatrix()
	{	
		m_cellclass = NSActionCell;
		m_sel = new NSArray();
		m_cells = new NSArray();
		m_numrows = 0;
		m_numcols = 0;
		m_drawsbg = true;
		m_drawscellbg = true;
		m_autosizecells = false;
		m_usingcellinstance = false;
		m_allowsemptysel = false;
		m_cellspacing = new NSSize(1, 1);
		m_cellsize = new NSSize(100, 17);
		m_autoscroll = false;
		m_isselbyrect = false;
		m_usetabkey = true;
	}
	
	
	/**
	 * Basic init.
	 */
	public function init():NSMatrix
	{
		initWithFrame(NSRect.ZeroRect);
		
		return this;
	}
	
	/**
	 * Initializes and returns the receiver, a newly allocated instance of 
	 * NSMatrix, with default parameters in the frame specified by frameRect.
	 * The new NSMatrix contains no rows or columns. The default mode is 
	 * NSRadioModeMatrix. The default cell class is NSActionCell.
	 */
	public function initWithFrame(frameRect:NSRect):NSMatrix
	{
		initWithFrameModeCellClassNumberOfRowsNumberOfColumns(frameRect, 
			NSMatrixMode.NSRadioModeMatrix, m_cellclass, 0, 0);
				
		return this;
	}
	
	
	/**
	 * Initializes and returns the receiver, a newly allocated instance of 
	 * NSMatrix, in the frame specified by frameRect. The new NSMatrix 
	 * contains numRows rows and numColumns columns. aMode is set as the 
	 * tracking mode for the NSMatrix and can be one of the modes described 
	 * in “Constants�?.
	 *
	 * The new NSMatrix creates and uses cells of class cellClass.
	 *
	 * This method is the designated initializer for matrices that add cells by
	 * creating instances of an NSCell subclass.
	 */
	public function initWithFrameModeCellClassNumberOfRowsNumberOfColumns
		(frameRect:NSRect, aMode:NSMatrixMode, cellClass:Function, 
		numRows:Number, numColumns:Number):NSMatrix
	{
		super.initWithFrame(frameRect);
	
		m_cellclass = cellClass;
  		renewRowsColumnsRowSpaceColSpace(numRows, numColumns, 0, 0);
  		m_mode = aMode;
		postInit();
		
		return this;
	}
	
	
	/**
	 * Initializes and returns the receiver, a newly allocated instance of 
	 * NSMatrix, in the frame specified by frameRect. The new NSMatrix 
	 * contains numRows rows and numColumns columns. aMode is set as the
	 * tracking mode for the NSMatrix and can be one of the modes described
	 * in “Constants�?.
	 *
	 * The new matrix creates cells by copying aCell, which should be an 
	 * instance of a subclass of NSCell.
	 *
	 * This method is the designated initializer for matrices that add cells
	 * by copying an instance of an NSCell subclass.
	 */
	public function initWithFrameModePrototypeNumberOfRowsNumberOfColumns
		(frameRect:NSRect, aMode:NSMatrixMode, aCell:NSCell, 
		numRows:Number, numColumns:Number):NSMatrix
	{
		super.initWithFrame(frameRect);
		
		m_prototype = aCell;
		m_usingcellinstance = true;
		renewRowsColumnsRowSpaceColSpace(numRows, numColumns, 0, 0);
		m_mode = aMode;
		
		postInit();
		
		return this;
	}
	
	
	/** A few common operations between the inits. */
	private function postInit():Void
	{
		//trace(m_frame);
		
  		//
  		// Set cell size if applicable.
  		//
  		if (m_numrows > 0 && m_numcols > 0)
  		{
 			recalcCellSize();	 		
 		}
  		
  		//
  		// Make initial selection.
  		//
		if (m_mode == NSMatrixMode.NSRadioModeMatrix && m_numrows > 0 
			&& m_numcols > 0)
		{
			this.selectCellAtRowColumn(0, 0);
		}
		else
		{
			m_selcell_row = m_selcell_column = -1;
			m_selcell = null;
		}
	}
		
	//******************************************************															 
	//*					  Properties					   *
	//******************************************************
	
	/**
	 * If flag is TRUE, then the receiver will allow one or zero cells to be
	 * selected. If flag is FALSE, then the receiver will allow one and only
	 * one cell (not zero cells) to be selected. This setting has effect only
	 * in the NSRadioModeMatrix selection mode.
	 */
	public function setAllowsEmptySelection(flag:Boolean):Void
	{
		m_allowsemptysel = flag;
	}
	
	 
	/**
	 * Returns whether it’s possible to have no cells selected in a radio-mode matrix.
	 */
	public function allowsEmptySelection():Boolean
	{	
		return m_allowsemptysel;
	}
	
	
	/**
	 * Returns TRUE if cells are resized proportionally to the receiver when 
	 * its size changes (and intercell spacing is kept constant). Returns FALSE
	 * if the cell size and intercell spacing remain constant.
	 */
	public function autosizesCells():Boolean
	{
		return m_autosizecells;
	}
	
	
	/**
	 * Returns the color used to draw the background of the receiver (the space between 
	 * the cells).
	 */
	public function backgroundColor():NSColor
	{
		return m_bgcolor;
	}
	
	
	/**
	 * Sets the background color for the receiver to aColor and redraws the
	 * receiver. This color is used to fill the space between cells or the
	 * space behind any nonopaque cells. The default background color is
	 * NSColor’s controlColor.
	 */
	public function setBackgroundColor(aColor:NSColor):Void
	{
		m_bgcolor = aColor;
		
		setNeedsDisplay(true);
	}

	
	/**
	 * Returns the color used to fill the background of the receiver’s cells.
	 */
	public function cellBackgroundColor():NSColor
	{
		return m_cellbgcolor;
	}


	/**
	 * Sets the background color for the cells in the receiver to aColor. This
	 * color is used to fill the space behind nonopaque cells. The default cell
	 * background color is NSColor’s controlColor.
	 */
	public function setCellBackgroundColor(aColor:NSColor):Void
	{
		m_cellbgcolor = aColor;
	}
		
	
	/**
	 * Returns the subclass of NSCell that the receiver uses when creating new 
	 * (empty) cells.
	 */
	public function defaultCellClass():Function
	{
		return m_cellclass;
	}
		
	
	/**
	 * Configures the receiver to use instances of aClass when creating new
	 * cells. aClass should be the id of a subclass of NSCell, which can be
	 * obtained by sending the class message to either the NSCell subclass
	 * object or to an instance of that subclass. The default cell class is
	 * that set with the class method setCellClass:, or NSActionCell if no
	 * other default cell class has been specified.
	 *
	 * You need to use this method only with matrices initialized with
	 * initWithFrame, because the other initializers allow you to specify an
	 * instance-specific cell class or cell prototype.
	 */
	public function setDefaultCellClass(aClass:Function):Void
	{
		m_cellclass = aClass;
		
		m_usingcellinstance = false;
	}
	
	
	/**
	 * Returns the width and the height of each cell in the receiver (all 
	 * cells in an NSMatrix are the same size).
	 */
	public function cellSize():NSSize
	{
		return m_cellsize;
	}
	
	
	/**
	 * Sets the width and height of each of the cells in the receiver to
	 * those in aSize. This method may change the size of the receiver.
	 * Does not redraw the receiver.
	 */
	public function setCellSize(aSize:NSSize):Void
	{
		m_cellsize = aSize;
	}
		
	/**
	 * Returns an NSArray that contains the receiver’s cells. The cells in the 
	 * array are row-ordered; that is, the first row of cells appears first in 
	 * the array, followed by the second row, and so forth.
	 */
	public function cells():NSArray
	{		
		return m_cells;
	}
	
	
	/**
	 * Returns the delegate for messages from the field editor.
	 */
	public function delegate():Object
	{
		return m_delegate;
	}
	
	
	/**
	 * Sets the delegate for messages from the field editor to anObject.
	 */
	public function setDelegate(anObject:Object):Void
	{
		m_delegate = anObject;
	}
	
	
	/**
	 * Returns whether the receiver draws its background (the space between the cells).
	 */
	public function drawsBackground():Boolean
	{
		return m_drawsbg;
	}
	
	
	/**
	 * Sets whether the receiver draws its background (the space between the cells) to flag.
	 */
	public function setDrawsBackground(flag:Boolean):Void
	{
		m_drawsbg = flag;
	}
	
	
	/**
	 * Returns whether the receiver draws the background within each of its cells.
	 */
	public function drawsCellBackground():Boolean
	{
		//
		// Should be member variable, and not dependant on cell instances,
		// because matrix can by 0x0.
		//
		return m_drawscellbg;
	}
	
	
	/**
	 * Sets whether the receiver draws the background within each of its cells to flag.
	 */
	public function setDrawsCellBackground(flag:Boolean):Void
	{
		m_drawscellbg = flag;
	}
	
	
	/**
	 * Returns the vertical and horizontal spacing between cells in the receiver.
	 */
	public function intercellSpacing():NSSize
	{
		return m_cellspacing;
	}
	
	
	/**
	 * Sets the vertical and horizontal spacing between cells in the receiver
	 * to aSize. By default, both values are 1.0 in the receiver’s coordinate
	 * system.
	 */
	public function setIntercellSpacing(aSize:NSSize):Void
	{
		m_cellspacing = aSize;
		recalcCellSize();
	}
	
		
	/**
	 * Returns whether the receiver will be automatically scrolled whenever the 
	 * cursor is dragged outside the receiver after a mouse-down event within 
	 * its bounds.
	 */
	public function isAutoscroll():Boolean
	{
		return m_autoscroll;
	}
	
	
	/**
	 * True if the receiver should scroll when the cursor is dragged outside
	 * the receiver after a mouse-down event within its bounds.
	 */
	public function setAutoscroll(flag:Boolean):Void
	{
		m_autoscroll = flag;
	}
	
	
	/**
	 * Returns TRUE if the user can select a rectangle of cells in the receiver
	 * by dragging the cursor, FALSE otherwise.
	 */
	public function isSelectionByRect():Boolean
	{
		return m_isselbyrect;
	}
	
	
	/**
	 * Returns the cell that will be clicked when the user presses the Space bar.
	 */
	public function keyCell():NSCell
	{
		return m_keycell;
	}
	

	/**
	 * Returns the selection mode of the receiver.
	 */
	public function mode():NSMatrixMode
	{
		return m_mode;
	}
	

	/**
	 * Returns the flags in effect at the mouse-down event that started the 
	 * current tracking session. NSMatrix’s mouseDown: method obtains these
	 * flags by sending a modifierFlags message to the event passed into
	 * mouseDown:. Use this method if you want to access these flags. This
	 * method is valid only during tracking; it isn’t useful if the target of
	 * the receiver initiates another tracking loop as part of its action
	 * method (as a cell that pops up a pop-up list does, for example).	
	 */
	public function mouseDownFlags():Number
	{
		return m_mousedownflags;
	}
	
	
	/**
	 * Returns the number of columns in the receiver.
	 */
	public function numberOfColumns():Number
	{
		return m_numcols;
	}
	
	
	/**
	 * Returns the number of rows in the receiver.
	 */
	public function numberOfRows():Number
	{
		return m_numrows;
	}
	
	
	/**
	 * Returns the prototype cell that’s copied whenever a new cell needs to be
	 * created, or null if there is none.
	 */
	public function prototype():NSCell
	{
		return m_prototype;
	}
		
	
	/**
	 * Returns the most recently selected cell, or nil if no cell is selected.
	 * If more than one cell is selected, this method returns the cell that is
	 * lowest and farthest to the right in the receiver.	
	 */
	public function selectedCell():NSCell
	{
		switch (m_sel.count())
		{
			case 0:
				return null;
				
			case 1:
				return m_selcell;
				
		}
		
		//
		// default case (selections > 1)
		//
		var selLoc:Number = getLowestRightmostSelectionLocation();
		return NSCell(m_cells.objectAtIndex(selLoc));
	}
	
	
	/**
	 * Returns an array containing all of the receiver’s highlighted cells.
	 */
	public function selectedCells():NSArray
	{
		var res:NSArray = new NSArray();
		
		//
		// Build the cell array from the selection locations.
		//
		var cellItr:NSEnumerator = m_sel.objectEnumerator();
		var selLoc:Number;
		
		while (null != (selLoc = Number(cellItr.nextObject())))
		{
			res.addObject(m_cells.objectAtIndex(selLoc));
		}
		
		return res;
	}
	
	
	/**
	 * Returns the column number of the selected cell, or –1 if no cells are
	 * selected. If cells in multiple columns are selected, this method returns
	 * the number of the last (rightmost) column containing a selected cell.
	 */
	public function selectedColumn():Number
	{
		if (m_sel.count() == 0)
			return -1;
			
		//
		// Radio mode
		//
		if (m_mode == NSMatrixMode.NSRadioModeMatrix)
			return m_selcell_column;
			
		//
		// Non-radio mode
		//
		var cellItr:NSEnumerator = m_sel.objectEnumerator();
		var selLoc:Object;
		var resLoc:Object;
		
		while (null != (selLoc = cellItr.nextObject()))
		{
			//
			// Set resLoc to the first item in the list.
			//
			if (resLoc == null)
			{
				resLoc = selLoc;
				continue;
			}
			
			resLoc = resLoc.column > selLoc.column ? resLoc : selLoc;
		}
		
		return resLoc.column;
	}
	
	
	/**
	 * Returns the row number of the selected cell, or –1 if no cells are
	 * selected. If cells in multiple rows are selected, this method returns
	 * the number of the last row containing a selected cell.
	 */
	public function selectedRow():Number
	{
		if (m_sel.count() == 0)
			return -1;
		
		//
		// Radio mode
		//
		if (m_mode == NSMatrixMode.NSRadioModeMatrix)
			return m_selcell_row;

		//
		// Non-radio mode
		//
		var loc:Object = getLowestRightmostSelectionLocation();
		return loc.row;
	}
		
	//******************************************************															 
	//*                Tab key behaviour
	//******************************************************
	
	/**
	 * Returns whether pressing the Tab key advances the key cell to the next
	 * selectable cell in the receiver.
	 */
	public function tabKeyTraversesCells():Boolean
	{
		return m_usetabkey;
	}
	
	
	/**
	 * Sets whether pressing tab will move focus to the next selectable cell.
	 * If flag is FALSE, or there are no more selectable cells, the window
	 * becomes key. Pressing shift and tab moves the advances the focus in the
	 * opposite direction.
	 */
	public function setTabKeyTraversesCells(flag:Boolean):Void
	{
		m_usetabkey = flag;
	}
	
	//******************************************************															 
	//*                Target and Action
	//******************************************************
	
	/**
	 * Returns the the method name that is called on this control's target
	 * when a double click occurs.
	 *
	 * @see org.actionstep.NSMatrix#setDoubleAction
	 * @see org.actionstep.NSMatrix#sendDoubleAction
	 */
	public function doubleAction():String
	{
		return m_doubleaction;
	}
	
		
	/**
	 * If the selected cell has a target and an action, a message is sent
	 * to the target.
	 *
	 * If the cell's target is null, this control's target is used.
	 *
	 * If there is no selected cell or the selected cell has no action, this
	 * control triggers its target's action.
	 *
	 * This method returns TRUE if a target responds to the message, and FALSE
	 * otherwise.
	 */
	public function sendAction():Boolean
	{
		var selcell:NSCell = selectedCell();
		
		if (selcell == null || selcell.action() == null)
		{
			//
			// No selection or selection has no action, so use this control's
			// target and action.
			//
			return sendActionTo(m_action, m_target);
		}
		else if (selcell.target() == null) 
		{
			//
			// Selection has no target, so use this control's target.
			//
			return sendActionTo(selcell.action(), m_target); //! is this right?
		}
		else
		{
			//
			// Selection has target and action, so send it.
			//
			return sendActionTo(selcell.action(), selcell.target()); //! is this right?
		}
	}
	
	
	/**
	 * Iterates through all cells if toAllCells is TRUE or selected cells if
	 * toAllCells is FALSE, calling aSelector on anObject for each cell
	 * passing the current cell as the only parameter.
	 *
	 * The return type for anObject::aSelector() must be boolean. When 
	 * anObject::aSelector returns TRUE, iteration continues to the next cell.
	 * When it returns FALSE, the iteration halts immediately.
	 */
	public function sendActionToForAllCells(aSelector:String, anObject:Object,
		toAllCells:Boolean):Void
	{
		var cells:NSArray = toAllCells ? cells() : selectedCells();
		var app:NSApplication = NSApplication.sharedApplication();
		var itr:NSEnumerator = cells.objectEnumerator();
		var cell:NSCell;
		var cont:Boolean = true;
		
		while ((null != (cell = NSCell(itr.nextObject()))) && cont)
		{
			cont = app.sendActionToFrom(aSelector, anObject, cell);
		}
	}
	
	
	/**
	 * This method does the following in the specified order, until
	 * success is reached:
	 *
	 * 	1. If doubleAction is set, a message will be sent to this control's
	 *	   target.
	 *  2. If the selected cell has an action set, that message will be sent
	 *	   to the cell's target.
	 *	3. A single-click action will be sent to this control's target.
	 *		
	 *
	 * If the selected cell is disabled, no action is sent. 
	 *
	 * This method should not be called directly (from the outside of this 
	 * object), but can be overridden by subclasses for specialized 
	 * behaviour.
	 */
	public function sendDoubleAction():Boolean
	{
		// Step 1.
		if (m_doubleaction != null)
			return sendActionTo(m_doubleaction, m_target);
			
		// Step 2.
		var selcell:NSCell = selectedCell();
		
		if (selcell != null)
		{
			if (!selcell.isEnabled())
				return false;
				
			if (selcell.action() != undefined)
				return sendActionTo(selcell.action(), selcell.target()); //! is this right?
		}
		
		// Step 3.
		//! How do I do this?
		
		return false;
	}
	
	
	/**
	 * @see org.actionstep.NSControl#setAction
	 */
	public function setAction(aSelector:String):Void
	{
		m_action = aSelector;
	}
	
	
	/**
	 * Makes aSelector the action sent to the target of the receiver when the
	 * user double-clicks a cell. A double-click action is always sent after
	 * the appropriate single-click action, which is the cell’s single-click
	 * action, if it has one, or the receiver single-click action, otherwise.
	 * If aSelector is a non-NULL selector, this method also sets the
	 * ignoresMultiClick flag to TRUE; otherwise, it leaves the flag unchanged.
	 * 
	 * If an NSMatrix has no double-click action set, then by default a double
	 * click is treated as a single click.
	 *
	 * For the method to have any effect, the receiver’s action and target must
	 * be set to the class in which the selector is declared.
	 */
	public function setDoubleAction(aSelector:String):Void
	{
		m_doubleaction = aSelector;
	}
	
	
	/**
	 * @see org.actionstep.NSControl#setTarget
	 */
	public function setTarget(target:Object):Void
	{
		m_target = target;
	}
	
	//******************************************************															 
	//*            Row / Column Manipulation
	//******************************************************
			
	/**
	 * Adds a new column of cells to the right of the last column, creating
	 * new cells as needed with makeCellAtRowColumn.
	 *
	 * This method raises an NSRangeException if there are 0 rows or 0 
	 * columns. Use renewRowsColumns to add new cells to an empty matrix.
	 *
	 * If the number of rows or columns in the receiver has been changed 
	 * with renewRowsColumns, new cells are created only if they are 
	 * needed. This fact allows you to grow and shrink an NSMatrix without 
	 * repeatedly creating and freeing the cells.
	 *
	 * This method redraws the receiver. Your code may need to send 
	 * sizeToCells after sending this method to resize the receiver 
	 * to fit the newly added cells.
	 */
	public function addColumn():Void
	{
		insertColumn(m_numcols);
	}
	
	
	/**
	 * Adds a new column of cells to the right of the last column. The 
	 * new column is filled with objects from newCells, starting with 
	 * the object at index 0. Each object in newCells should be an 
	 * instance of NSCell or one of its subclasses (usually 
	 * NSActionCell). newCells should have a sufficient number of 
	 * cells to fill the entire column. Extra cells are ignored, 
	 * unless the matrix is empty. In that case, a matrix is 
	 * created with one column and enough rows for all the elements 
	 * of newCells.
	 *
	 * This method redraws the receiver. Your code may need to send 
	 * sizeToCells after sending this method to resize the receiver 
	 * to fit the newly added cells.
	 */
	public function addColumnWithCells(newCells:NSArray):Void
	{
		insertColumnWithCells(m_numcols, newCells);
	}
	
	
	/**
	 * Adds a new row of cells below the last row, creating new cells as needed
	 * with makeCellAtRowColumn.
	 *
	 * This method raises an NSRangeException if there are 0 rows or 0 columns.
	 * Use renewRowsColumns: to add new cells to an empty matrix.
	 *
	 * If the number of rows or columns in the receiver has been changed with 
	 * renewRowsColumns, then new cells are created only if they are needed. 
	 * This fact allows you to grow and shrink an NSMatrix without repeatedly 
	 * creating and freeing the cells.
	 *
	 * This method redraws the receiver. Your code may need to send sizeToCells 
	 * after sending this method to resize the receiver to fit the newly added cells.
	 */
	public function addRow():Void
	{
		insertRow(m_numrows);
	}
	
	
	/**
	 * Adds a new row of cells below the last row. The new row is filled with 
	 * objects from newCells, starting with the object at index 0. Each object 
	 * in newCells should be an instance of NSCell or one of its subclasses 
	 * (usually NSActionCell). newCells should have a sufficient number of cells
	 * to fill the entire row. Extra cells are ignored, unless the matrix is 
	 * empty. In that case, a matrix is created with one row and enough 
	 * columns for all the elements of newCells.
	 *
	 * This method redraws the receiver. Your code may need to send sizeToCells 
	 * after sending this method to resize the receiver to fit the newly added cells.
	 */
	public function addRowWithCells(newCells:NSArray):Void
	{
		insertRowWithCells(m_numrows, newCells);
	}
	
	
	/**
	 * Inserts a new column of cells before column, creating new cells if needed
	 * with makeCellAtRowColumn. If column is greater than the number of columns
	 * in the receiver, enough columns are created to expand the receiver to be
	 * column columns wide. This method redraws the receiver. Your code may need
	 * to send sizeToCells after sending this method to resize the receiver to
	 * fit the newly added cells.
	 *
	 * If the number of rows or columns in the receiver has been changed with 
	 * renewRowsColumns, new cells are created only if they’re needed. This 
	 * fact allows you to grow and shrink an NSMatrix without repeatedly 
	 * creating and freeing the cells.
	 */
	public function insertColumn(column:Number):Void
	{
		insertColumnWithCells(column, null);
	}
	
	
	/**
	 * Inserts a new column of cells before column. The new column is filled 
	 * with objects from newCells, starting with the object at index 0. Each 
	 * object in newCells should be an instance of NSCell or one of its
	 * subclasses (usually NSActionCell). If column is greater than the number
	 * of columns in the receiver, enough columns are created to expand the
	 * receiver to be column columns wide. newCells should either be empty or
	 * contain a sufficient number of cells to fill each new column. If newCells
	 * is null or an array with no elements, the call is equivalent to calling
	 * insertColumn:. Extra cells are ignored, unless the matrix is empty. In
	 * that case, a matrix is created with one column and enough rows for all
	 * the elements of newCells.
	 *
	 * This method redraws the receiver. Your code may need to send sizeToCells
	 * after sending this method to resize the receiver to fit the newly added cells.
	 */
	public function insertColumnWithCells(column:Number, newCells:NSArray):Void
	{
		var cnt:Number = newCells.count();
		var i:Number = m_numcols + 1;
		
		if (cnt == undefined)
		{
			cnt = 0;
		}
		
  		//
  		// Check for illegal argument (negative column).
  		//  
		if (column < 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSRangeException",
				"NSMatrix::insertColumnWithCells - " + column + 
				" was specified as the column parameter. Negative indices are " +
				"not allowed.");
			trace(e);
			throw e;
		}
		
		//
		// If column is more than the number of columns, then increase i.
		//
		if (column >= i)
		{
			i = column + 1;
		}
		
		//
		// Use renewRowsColumnsRowSpaceColSpace to grow the matrix as necessary.
		// The docs say that if the matrix is empty, we make it have one column
		// and enough rows for all the elements.
		//
		if (cnt > 0 && (m_numrows == 0 || m_numcols == 0))
		{
			//trace("cnt > 0 && (m_numrows == 0 || m_numcols == 0)");
			renewRowsColumnsRowSpaceColSpace(cnt, 1, 0, cnt);
		}
		else
		{
			//trace("num rows: " + m_numrows + ", column: " + i);
			renewRowsColumnsRowSpaceColSpace(m_numrows == 0 ? 1 : m_numrows,
				i, 0, cnt);
		}
		
		//
		// Push all the existing cells one column forward.
		//
		
		if (m_numcols != column)
		{
			for (i = 0; i < m_numrows; i++)
			{
				var j:Number = m_numcols;
				var old:NSCell = cellAtRowColumn(i, j-1);
			
				while (--j > column)
				{
					assignCell(cellAtRowColumn(i, j-1), i, j, false);
				}
				
				assignCell(old, i, column, false);
			}
			
			if (m_selcell && (m_selcell_column >= column))
			{
				m_selcell_column++;
			}
			if (m_dottedcol >= column)
			{
				m_dottedcol++;
			}
		}
		
		//
		// Since a new column is added, the current selections who's column's
		// are higher than column must be incremented.
		//
		updateSelWithColumnAdded(column);
		
		//
		// Put the new cells into the matrix (if there are any).
		//
		if (cnt > 0)
		{			
			for (i = 0; i < m_numrows && i < cnt; i++)
			{
				//
				// Use this call so the old cell is property released.
				//
				assignCell(NSCell(newCells.objectAtIndex(i)), i, column);
			}
		}
		
		//
		// If we are in radio matrix mode without allowed empty cell 
		// selection and there is no current selection, then we select
		// the first cell.
		//
		if (m_mode == NSMatrixMode.NSRadioModeMatrix && 
			m_allowsemptysel == false && 
			selectedCell() == null)
		{
			selectCellAtRowColumn(0, 0);
		}
		
		setNeedsDisplay(true);
	}
	
	
	/**
	 * Inserts a new row of cells before row, creating new cells if needed with
	 * makeCellAtRowColumn. If row is greater than the number of rows in the
	 * receiver, enough rows are created to expand the receiver to be row rows
	 * high. This method redraws the receiver. Your code may need to send
	 * sizeToCells after sending this method to resize the receiver to fit
	 * the newly added cells.
	 *
	 * If the number of rows or columns in the receiver has been changed with
	 * renewRowsColumns, then new cells are created only if they’re needed. 
	 * This fact allows you to grow and shrink an NSMatrix without repeatedly
	 * creating and freeing the cells.
	 */
	public function insertRow(row:Number):Void
	{
		insertRowWithCells(row, null);
	}
	
	
	/**
	 * Inserts a new row of cells before row. The new row is filled with
	 * objects from newCells, starting with the object at index 0. Each
	 * object in newCells should be an instance of NSCell or one of its
	 * subclasses (usually NSActionCell). If row is greater than the
	 * number of rows in the receiver, enough rows are created to expand
	 * the receiver to be row rows high. newCells should either be empty
	 * or contain a sufficient number of cells to fill each new row. If
	 * newCells is null or an array with no elements, the call is equivalent
	 * to calling insertRow. Extra cells are ignored, unless the matrix is
	 * empty. In that case, a matrix is created with one row and enough
	 * columns for all the elements of newCells.
	 *
	 * This method redraws the receiver. Your code may need to send sizeToCells
	 * after sending this method to resize the receiver to fit the newly added
	 * cells.
	 */
	public function insertRowWithCells(row:Number, newCells:NSArray):Void
	{
		var cnt:Number = newCells.count();
		var i:Number = m_numrows + 1;
		
		if (cnt == undefined)
		{
			cnt = 0;
		}

		if (row < 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSRangeException",
				"NSMatrix::insertRowWithCells - " + row + 
				" was specified as the row parameter. Negative indices are " +
				"not allowed.");
			trace(e);
			throw e;
		}
		
		if (row >= i)
		{
			i = row + 1;
		}
				
		//
		// Use renewRowsColumnsRowSpaceColSpace to grow the matrix as necessary.
		// The docs say that if the matrix is empty, we make it have one column
		// and enough rows for all the elements.
		//
		if (cnt > 0 && (m_numrows == 0 || m_numcols == 0))
		{
			renewRowsColumnsRowSpaceColSpace(1, cnt, cnt, 0);
		}
		else
		{
			renewRowsColumnsRowSpaceColSpace(i,
				m_numcols == 0 ? 1 : m_numcols, cnt, 0);
		}

		//
		// Push all currently existing rows downwards
		//
		if (m_numrows != row)
		{
			for (i = 0; i < m_numcols; i++)
			{
				var j:Number = m_numrows;
				var old:NSCell = cellAtRowColumn(j - 1, i);
			
				while (--j > row)
				{
					assignCell(cellAtRowColumn(j - 1, i), j, i, false);
				}
				
				assignCell(old, row, i, false);
			}
			
			if (m_selcell && (m_selcell_row >= row))
			{
				m_selcell_row++;
			}
			if (m_dottedrow >= row)
			{
				m_dottedrow++;
			}
		}
		
		//
		// Update selection
		//
		updateSelWithRowAdded(row);
		
		//
		// Put the new cells into the matrix (if there are any).
		//
		if (cnt > 0)
		{			
			for (var j:Number = 0; j < cnt; j++)
			{
				//
				// Use this call so the old cell is property released.
				//
				assignCell(NSCell(newCells.objectAtIndex(j)), row, j);				
			}
		}
		
		//
		// If we are in radio matrix mode without allowed empty cell 
		// selection and there is no current selection, then we select
		// the first cell.
		//
		if (m_mode == NSMatrixMode.NSRadioModeMatrix && 
			m_allowsemptysel == false && 
			selectedCell() == null)
		{
			selectCellAtRowColumn(0, 0);
		}
		
		setNeedsDisplay(true);
	}

	
	/**
	 * Creates a new cell at the location specified by row and column in the
	 * receiver. If the receiver has a prototype cell, it’s copied to create
	 * the new cell. If not, and if the receiver has a cell class set, it
	 * allocates and initializes (with init) an instance of that class. If
	 * the receiver hasn’t had either a prototype cell or a cell class set,
	 * makeCellAtRowColumn creates an NSActionCell. Returns the newly created cell.
	 *
	 * Your code should never invoke this method directly; it’s used by addRow
	 * and other methods when a cell must be created. It may be overridden to
	 * provide more specific initialization of cells.
	 */
	public function makeCellAtRowColumn(row:Number, column:Number):NSCell
	{		
		var cell:NSCell = makeCell();
				
		putCellAtRowColumn(cell, row, column);	
				
		return cell;	
	}
	
	
	/**
	 * Replaces the cell at the location specified by row and column with
	 * newCell and redraws the cell.
	 */
	public function putCellAtRowColumn(newCell:NSCell, row:Number, 
		column:Number):Void
	{
		var idx:Number;
		var cell:NSCell;
		
		//
		// Check if row and column are in bounds.
		//
		if (row >= m_numrows || row < 0 || column >= m_numcols || column < 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSOutOfRangeException",
				"NSMatrix::putCellAtRowColumn - row: " + row + 
				", column: " + column + " - Out of bounds.",
				null);
			trace(e);
			throw e;
		}
		
		//
		// Assign the cell
		//
		assignCell(newCell, row, column);
		
		//! What should we do about selection?
		
		//
		// Draw it.
		//
		drawCellAtRowColumn(row, column);
	}
	
		
	/**
	 * Removes the column at position column from the receiver and autoreleases
	 * the column’s cells. Redraws the receiver. Your code should normally send
	 * sizeToCells after invoking this method to resize the receiver so it fits
	 * the reduced cell count.
	 */
	public function removeColumn(column:Number):Void
	{
		//
		// Check if row and column are in bounds.
		//
		if (column >= m_numcols || column < 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSIndexOutOfRangeException",
				"NSMatrix::removeColumn - column: " + column + " - Out of bounds.",
				null);
			trace(e);
			throw e;
		}
		
		var i:Number;
		
		//
		// Shift cells
		//
		for (i = 0; i < m_maxrows; i++)
		{
			var j:Number;
			
			var cell:NSCell = NSCell(cellAtRowColumn(i, column));
			cell.release();
			
			
			for (j = column + 1; j < m_maxcols; j++)
			{
				assignCell(cellAtRowColumn(i, j), i, j-1, false);
			}
		}
		
		//
		// Update array (remove last column from each row)
		//
		for (i = m_maxrows - 1; i >= 0; i--)
		{
			m_cells.removeObjectAtIndex(indexFromRowColumn(i, m_numcols - 1));
		}
					
		updateSelWithColumnRemoved(column);
		m_numcols--;
		m_maxcols--;
		
		if (m_maxcols == 0)
		{
			m_numrows = m_maxrows = 0;
		}
		
		if (column == m_selcell_column)
		{
			m_selcell = null;
			selectCellAtRowColumn(m_selcell_row, 0);
		}
		
		if (column == m_dottedcol)
		{
			if (m_numcols != 0 && cellAtRowColumn(m_dottedrow, 0).acceptsFirstResponder())
			{
				m_dottedcol = 0;
			}
			else
			{
				m_dottedrow = m_dottedcol = -1;
			}
		}
		
		setNeedsDisplay(true);
	}
	
	
	/**
	 * Removes the row at position row from the receiver and autoreleases the
	 * row’s cells. Redraws the receiver. Your code should normally send
	 * sizeToCells after invoking this method to resize the receiver so it fits
	 * the reduced cell count.
	 */
	public function removeRow(row:Number):Void
	{
		//
		// Check if row and column are in bounds.
		//
		if (row >= m_numrows || row < 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSIndexOutOfRangeException",
				"NSMatrix::removeRow - row: " + row + " - Out of bounds.",
				null);
			trace(e);
			throw e;
		}
		
		var removalPoint:Number = row * m_numcols;
		var numToRemove:Number = m_numcols;
				
		while (numToRemove-- > 0)
		{
			var cell:NSCell = NSCell(m_cells.objectAtIndex(removalPoint));
			m_cells.removeObjectAtIndex(removalPoint);
			cell.release();
		}
		
		updateSelWithRowRemoved(row);
		m_numrows--;
		m_maxrows--;
		
		if (m_maxrows == 0)
		{
			m_numcols = m_maxcols = 0;
		}
		
		if (row == m_selcell_row)
		{
			m_selcell = null;
			selectCellAtRowColumn(0, m_selcell_column);
		}
		
		if (row == m_dottedrow)
		{
			if (m_numrows != 0 && cellAtRowColumn(0, m_dottedcol).acceptsFirstResponder())
				m_dottedrow = 0;
			else
				m_dottedrow = m_dottedcol = -1;
		}
		
		setNeedsDisplay(true);
	}
	
	//******************************************************															 
	//*					 Public Methods					   *
	//******************************************************
	
	/**
	 * Returns the NSCell object at the location specified by row and column,
	 * or null if either row or column is outside the bounds of the receiver.
	 */
	public function cellAtRowColumn(row:Number, column:Number):NSCell
	{
		return NSCell(m_cells.objectAtIndex(indexFromRowColumn(row, column)));
	}
	

	/**
	 * Returns the frame rectangle of the cell that would be drawn at the 
	 * location specified by row and column (whether or not the specified 
	 * cell actually exists).	
	 */
	public function cellFrameAtRowColumn(row:Number, column:Number):NSRect
	{
		var iniX:Number = m_cellspacing.width;
		var iniY:Number = m_cellspacing.height;
		var incX:Number = m_cellspacing.width + m_cellsize.width;
		var incY:Number = m_cellspacing.height + m_cellsize.height;
		
		return new NSRect(iniX + column * incX, iniY + row * incY,
			m_cellsize.width, m_cellsize.height);
	}
	
	
	/**
	 * Searches the receiver and returns the last (when viewing the matrix 
	 * as a row-ordered array) NSCell object that has a tag matching anInt, 
	 * or null if no such cell exists.
	 */
	public function cellWithTag(anInt:Number):NSCell
	{
		//
		// Using a reverse enumerator, because this method returns the
		// 'last' NSCell that has the matching tag.
		//
		var itrRows:NSEnumerator = m_cells.reverseObjectEnumerator();
		
		//
		// Cycle through cells
		//
		var cell:NSCell;
		while (null != (cell = NSCell(itrRows.nextObject())))
		{			
			if (cell.tag() == anInt)
				return cell;
		}
		
		return null; // cell doesn't exist
	}
	
	
	/** 
	 * Deselects all cells in the receiver and, if necessary, redisplays the 
	 * receiver. If the selection mode is NSRadioModeMatrix and empty selection
	 * is not allowed, this method does nothing.
	 */
	public function deselectAllCells():Void
	{
		if (m_mode == NSMatrixMode.NSRadioModeMatrix && !m_allowsemptysel)
			return;

		//
		// If nothing is selected, return.
		//
		if (m_sel.count() == 0)
			return;
			
		//
		// Cycle through cells, deselecting as we go.
		//			
		var cellItr:NSEnumerator = m_sel.objectEnumerator();
		var cell:NSCell;
		var loc:Number;
		
		while (null != (loc = Number(cellItr.nextObject())))
		{			
			cell = NSCell(m_cells.objectAtIndex(loc));
			cell.setHighlighted(false);
		}
		
		m_sel.clear();
		setNeedsDisplay(true);
	}
	
	
	/**
	 * Deselects the selected cell or cells. If the selection mode is 
	 * NSRadioModeMatrix and empty selection is not allowed, or if nothing is 
	 * currently selected, this method does nothing. This method doesn’t 
	 * redisplay the receiver.
	 */
	public function deselectSelectedCell():Void
	{
		if (m_mode == NSMatrixMode.NSRadioModeMatrix && !m_allowsemptysel)
			return;

		//
		// Cycle through cells, deselecting as we go.
		//			
		var cellItr:NSEnumerator = m_sel.objectEnumerator();
		var cell:NSCell;
		var loc:Object;
		
		while (null != (loc = cellItr.nextObject()))
		{			
			cell = cellAtRowColumn(loc.row, loc.column);
			cell.setHighlighted(false);
		}
				
		m_sel.clear();
	}
	
	
	/**
	 * Displays the cell at the specified row and column, providing that row 
	 * and column reference a cell within the receiver.
	 */
	public function drawCellAtRowColumn(row:Number, column:Number):Void
	{
		if (m_mcBounds == null)
			return;
			
		var cell:NSCell = cellAtRowColumn(row, column);
				
		if (cell == null) // if cell doesn't exist, we can't draw it
			return;
			
		var frame:NSRect = cellFrameAtRowColumn(row, column);

		//
		// Draw the cell background.
		//
		if (m_drawscellbg)
		{
			ASTheme.current().drawFillWithRectColorInView(frame, m_cellbgcolor, this);
		}
		else
		{
			ASTheme.current().drawFillWithRectColorInView(frame, m_bgcolor, this);
		}
		
		if (m_dottedrow == row && m_dottedcol == column && 
			cell.acceptsFirstResponder())
		{
			cell.setShowsFirstResponder(m_window.isKeyWindow() && 
				m_window.firstResponder() == this);
		}
		else
		{
			cell.setShowsFirstResponder(false);
		}
		
		cell.drawWithFrameInView(frame, this);
		cell.setShowsFirstResponder(false);
	}
	
	
	/**
	 * Returns a simple object with a columnCount and rowCount properties
	 * which correspond to the number of columns and the number of rows
	 * respectively in the reciever.
	 *
	 * Note: This implementation is different than that specified by the
	 * Cocoa documentation, as ActionScript does not have the concept of
	 * pointers.
	 */
	public function getNumberOfRowsColumns():Object
	{
		return {rowCount:m_numrows, columnCount:m_numcols};
	}
	
	
	/**
	 * Returns a simple object with row and column properties if aPoint lies
	 * within one of the cells in the receiver, and sets row and column to 
	 * the row and column for the cell within which the specified point lies.
	 * If aPoint falls outside the bounds of the receiver or lies within an 
	 * intercell spacing, getRowColumnForPoint returns null.
	 *
	 * Make sure aPoint is in the coordinate system of the receiver.
	 *
	 * Note: This implementation is different than that specified by the
	 * Cocoa documentation, as ActionScript does not have the concept of
	 * pointers.
	 */
	public function getRowColumnForPoint(aPoint:NSPoint):Object
	{
		aPoint = convertPointFromView(aPoint, null);	
		var colWidth:Number = m_cellsize.width + m_cellspacing.width;
		var rowHeight:Number = m_cellsize.height + m_cellspacing.height;
		
		//
		// Build the location object.
		//
		var loc:Object = {};
		loc.column = Math.floor(aPoint.x / colWidth);
		loc.row = Math.floor(aPoint.y / rowHeight);
		
		//
		// If row or column is out of bounds, return null.
		//
		if (loc.row >= m_numrows || 
			loc.row < 0 || 
			loc.column >= m_numcols ||
			loc.column < 0)
		{
			return null;
		}
		
		//
		// Return the location if the cell if the point doesn't lie on
		// intercell spacing.
		//
		return ((aPoint.x % colWidth) > m_cellspacing.width &&
			(aPoint.y % rowHeight) > m_cellspacing.height) ? loc : null;
	}
	
	
	/**
	 * Searches the receiver and returns a simple object with row and column
	 * properties if aCell is one of the cells in the receiver, and sets row
	 * and column to the row and column of the cell. If aCell is not found 
	 * within the receiver, getRowColumnOfCell returns null.
	 *
	 * Note: This implementation is different than that specified by the
	 * Cocoa documentation, as ActionScript does not have the concept of
	 * pointers.
	 */
	public function getRowColumnOfCell(aCell:NSCell):Object
	{		
		//
		// Cycle through until we make a match
		//
		var len:Number = m_cells.count();
		
		for (var i:Number = 0; i < len; i++)
		{
			//
			// If match, calculate row and column from index, and return.
			//
			if (m_cells.objectAtIndex(i) == aCell)
			{
				return rowColumnFromIndex(i);
			}
		}
		
		return null;
	}
	
	
	/**
	 * Assuming that row and column indicate a valid cell within the receiver,
	 * this method highlights (if flag is YES) or unhighlights (if flag is NO)
	 * the specified cell.
	 */
	public function highlightCellAtRowColumn(flag:Boolean, row:Number, 
		column:Number):Void
	{
		var cell:NSCell = cellAtRowColumn(row, column);
		
		if (cell == null) // can't highlight it if it doesn't exist
			return;
			
		cell.setHighlighted(flag);
	}
	
	
	/**
	 * Changes the number of rows and columns in the receiver. This method uses
	 * the same cells as before, creating new cells only if the new size is
	 * larger; it never frees cells. Doesn’t redisplay the receiver. Your code
	 * should normally send sizeToCells after invoking this method to resize
	 * the receiver so it fits the changed cell arrangement. This method
	 * deselects all cells in the receiver.
	 */
	public function renewRowsColumns(newRows:Number, newColumns:Number):Void
	{	
		renewRowsColumnsRowSpaceColSpace(newRows, newColumns, 0, 0);
	}
	
	
	//! public function resetCursorRects
	
	
	//! public function scrollCellToVisibleAtRowColumn
	
	
	/**
	 * Selects and highlights all cells in the receiver, except for editable
	 * text cells and disabled cells. Redisplays the receiver. sender is ignored.
	 */
	public function selectAll():Void
	{
		//
		// Cycle through cells, selecting and highlighting as we go.
		//
		var cellItr:NSEnumerator = cells().objectEnumerator();
		var cell:NSCell;
		var cnt:Number = 0;
		
		while (null != (cell = NSCell(cellItr.nextObject())))
		{
			if ((cell.type() == NSCellType.NSTextCellType && cell.isEditable())
				|| !cell.isEnabled())
			{
				continue;
			}
			
			cell.setHighlighted(true);
			m_sel.addObject({row: Math.floor(cnt / m_numcols), column: cnt % m_numcols});
			
			cnt++;
		}
		
		setNeedsDisplay(true); // mark the reciever for redraw.
	}
	
	
	/**
	 * Selects the cell at the specified row and column within the receiver.
	 * If the specified cell is an editable text cell, its text is selected. If
	 * either row or column is –1, then the current selection is cleared
	 * (unless the receiver is an NSRadioModeMatrix and doesn’t allow empty
	 * selection). Redraws the affected cells.
	 */
	public function selectCellAtRowColumn(row:Number, column:Number):Void
	{
		if (row == -1 || column == -1)
		{
			//trace("Deselecting all cells");
			deselectAllCells();
			return;
		}
		
		//trace("Selecting cell at ("+row+", "+column+")");
		var cell:NSCell = cellAtRowColumn(row, column);
					
		if (cell != null)
		{
			var rect:NSRect;
			
			//
			// For NSRadioModeMatrix - Deselect the old selection if not the
			// same as the new one.
			//
			if (m_mode == NSMatrixMode.NSRadioModeMatrix &&
				m_selcell != null && cell != m_selcell)
			{
				clearCurrentRadioSelection(false);
			}
			
			if (m_selcell != null && cell != m_selcell)
			{	
				m_selcell.setShowsFirstResponder(false);
				//! setNeedsDisplayInRect
				drawCellAtRowColumn(m_selcell_row, m_selcell_column);
			}
			
			//
			// Record the new selection
			//
			m_selcell = cell;
			m_selcell_row = row;
			m_selcell_column = column;
			var idx:Number = indexFromRowColumn(row, column);
			
			m_sel.addObject(idx);

			//
			// Update visual representation
			// 
			m_selcell.setState(NSCell.NSOnState);
			
			if (m_mode == NSMatrixMode.NSListModeMatrix)
				m_selcell.setHighlighted(true);
				
			rect = cellFrameAtRowColumn(row, column);
			
			if (m_autoscroll)
			{				
				scrollRectToVisible(rect);
			}
			
			setKeyRowColumn(row, column);
			
			//
			// Draw.
			//
			setNeedsDisplay(true);
			//! setNeedsDisplayInRect
						
			//
			// Select text if we can
			//
			selectTextAtRowColumn(row, column);
		}
		else
		{
			m_selcell = null;
			m_selcell_row = m_selcell_column = -1;
		}
	}
	
	
	/**
	 * If the receiver has at least one cell whose tag is equal to anInt, the
	 * last cell (when viewing the matrix as a row-ordered array) is selected.
	 * If the specified cell is an editable text cell, its text is selected.
	 * Returns TRUE if the receiver contains a cell whose tag matches anInt,
	 * or FALSE if no such cell exists.
	 */
	public function selectCellWithTag(anInt:Number):Boolean
	{
		var cell:NSCell = cellWithTag(anInt);
		
		if (cell == null)
			return false;
			
		var loc:Object = getRowColumnOfCell(cell);
		
		cell.setHighlighted(true); // highlight the cell
		
		if (cell.type() == NSCellType.NSTextCellType &&
			cell.isEditable())
		{
			//! text selection
		}
				
		m_sel.addObject(loc); // add to the selection
		drawCellAtRowColumn(loc.row, loc.column); // draw the cell
	}
	
	
	/**
	 * If the currently selected cell is editable and enabled, its text is
	 * selected. Otherwise, the key cell is selected.
	 */
	public function selectText(sender:Object):Void //! What is sender?
	{
		selectTextWithCell(selectedCell());
	}
	
	
	/**
	 * If row and column indicate a valid cell within the receiver, and that
	 * cell is both editable and selectable, this method selects and then
	 * returns the specified cell. If the cell specified by row and column is
	 * either not editable or not selectable, this method does nothing, and
	 * returns nil. Finally, if row and column indicate a cell that is outside
	 * the receiver, this method does nothing and returns the receiver.
	 */
	public function selectTextAtRowColumn(row:Number, column:Number):NSCell
	{
		var cell:NSCell = cellAtRowColumn(row, column);
				
		if (!selectTextWithCell(cell))
			return null;
		
		return cell;
	}
			
	
	/** 
	 * Sets selection, counting from 0 (upper-left corner) in row order.
	 */	
	public function setSelectionFromToAnchorHighlight(startPos:Number, 
		endPos:Number, anchor:Number, lit:Boolean):Void
	{
		
	}
	
	
	/**
	 * Sizes the matrix to the exact size required to view all the cells.
	 */
	public function sizeToCells():Void
	{
		var frameSize:NSSize = NSSize.ZeroSize.clone();
		var cs:NSSize = m_cellsize;
		var ss:NSSize = m_cellspacing;
		
		frameSize.width += cs.width * m_numcols + ss.width * (m_numcols + 1);
		frameSize.height += cs.height * m_numrows + ss.height * (m_numrows + 1);
		
		this.setFrameSize(frameSize);
	}
	
	//******************************************************															 
	//*                 Moving Selection
	//******************************************************
	
	/**
	 * Moves the current focus up.
	 */
	public function moveUp(sender:Object):Void
	{
		moveFocusOrSel(NSUpArrowFunctionKey);
	}
	

	/**
	 * Moves the current focus down.
	 */	
	public function moveDown(sender:Object):Void
	{
		moveFocusOrSel(NSDownArrowFunctionKey);
	}
	
	
	/**
	 * Moves the current focus left.
	 */
	public function moveLeft(sender:Object):Void
	{
		moveFocusOrSel(NSLeftArrowFunctionKey);
	}
	
	
	/**
	 * Moves the current focus right.
	 */
	public function moveRight(sender:Object):Void
	{
		moveFocusOrSel(NSRightArrowFunctionKey);
	}
	

	//******************************************************															 
	//*                 Text Editing
	//******************************************************
	  
	public function abortEditing():Boolean 
	{
		if (m_editor) 
		{
			m_editor = null;
			ASFieldEditingProtocol(m_selcell).endEditingWithDelegate(this);
			return true;
		} 
		else 
		{
			return false;
		}
	}
	
	
	public function validateEditing() 
	{
		if (m_editor != null) 
		{
			trace(m_editor.string());
			m_selcell.setStringValue(m_editor.string());
		}
	} 
  
  
	public function textShouldBeginEditing(editor:Object):Boolean 
	{
		return true;
	}


	public function textDidBeginEditing(notification:NSNotification):Void
	{
		m_notificationCenter.postNotificationWithNameObjectUserInfo(
			NSControlTextDidBeginEditingNotification, 
			this, 
			{NSFieldEditor: notification.object});
	}

  
	public function textDidChange(notification:NSNotification):Void
	{
		m_notificationCenter.postNotificationWithNameObjectUserInfo(
			NSControlTextDidChangeNotification, 
			this, 
			{NSFieldEditor: notification.object}
			);
		//! what else to do here ?
	}
	
	
	public function textShouldEndEditing(editor:Object):Boolean 
	{
		//! need to validate that text is acceptable
		//if (m_cell.isEntryAcceptable(editor.text) {
		//}
		/*
		if (m_delegate != null) 
		{
			if(typeof(m_delegate["controlTextShouldEndEditing"]) == "function") 
			{
				if (!m_delegate["controlTextShouldEndEditing"].call(m_delegate, this, editor)) 
				{
					NSBeep.beep();
					return false;
				}
			}
		}
		*/
		//! check for controlIsValidObject on delegate?
		return true;
	}
	

	public function textDidEndEditing(notification:NSNotification) 
	{
		validateEditing();
		m_editor = null;
		ASFieldEditingProtocol(m_selcell).endEditingWithDelegate(this);
		m_notificationCenter.postNotificationWithNameObjectUserInfo(
			NSControlTextDidEndEditingNotification, 
			this, 
			{NSFieldEditor : notification.object}
			);
			
		switch(notification.userInfo.NSTextMovement) 
		{
			case NSTextMovement.NSReturnTextMovement:
				if (!sendActionTo(action(), target())) 
				{
					selectText(this);
				}
				break;
				
			case NSTextMovement.NSTabTextMovement:
				m_window.selectKeyViewFollowingView(this);
				if (m_window.firstResponder() == m_window) 
				{
					selectText(this);
				}
				break;
				
			case NSTextMovement.NSBacktabTextMovement:
				m_window.selectKeyViewPrecedingView(this);
				if (m_window.firstResponder() == m_window) 
				{
					selectText(this);
				}
				break;
				
			case NSTextMovement.NSIllegalTextMovement:
				break;
				
		}
	}
  
	//******************************************************															 
	//*                      Events
	//******************************************************
	
	/**
	 * Returns FALSE if the selection mode of the receiver is NSListModeMatrix, 
	 * TRUE if the receiver is in any other selection mode. The receiver does 
	 * not accept first mouse in NSListModeMatrix to prevent the loss of 
	 * multiple selections. The NSEvent parameter, theEvent, is ignored.
	 */
	public function acceptsFirstMouse(theEvent:NSEvent):Boolean
	{
		return m_mode != NSMatrixMode.NSListModeMatrix;
	}
	
	
	/**
	 * The matrix always wants to be first responder.
	 */
	public function acceptsFirstResponder():Boolean 
	{
		return true;
	}
	
	
	public function becomeFirstResponder():Boolean
	{
  		if (m_dottedrow != -1 && m_dottedcol != -1)
  			setNeedsDisplay(true);
  			//! setNeedsDisplayInRect
  			
		return true;
	}
  
  
  	public function resignFirstResponder():Boolean
  	{
  		if (m_dottedrow != -1 && m_dottedcol != -1)
  			setNeedsDisplay(true);
  			//! setNeedsDisplayInRect
  			
  		return true;
  	}
  	
  	
	/**
	 * @see org.actionstep.NSControl#cellTrackingRect
	 */
	private function cellTrackingRect():NSRect 
	{
		return m_bounds;
	}
	
	
	/**
	 * @see org.actionstep.NSResponder#mouseEntered
	 */
	public function mouseEntered(event:NSEvent):Void
	{
		
	}
	

	/**
	 * @see org.actionstep.NSResponder#mouseExited
	 */	
	public function mouseExited(event:NSEvent):Void
	{
		
	}
	
	/**
	 * Responds to theEvent mouse-down event. A mouse-down event in a text 
	 * cell initiates editing mode. A double click in any cell type except 
	 * a text cell sends the double-click action of the receiver (if there 
	 * is one) in addition to the single-click action.
	 *
	 * Your code should never invoke this method, but you may override it 
	 * to implement different mouse tracking than NSMatrix does. The 
	 * response of the receiver depends on its selection mode, as explained 
	 * in the class description.
	 */
	public function mouseDown(theEvent:NSEvent):Void
	{
		//trace(theEvent); // debug info
		
		//
		// Ignore mouse down
		//
		if (m_numrows == 0 || m_numcols == 0)
		{
			super.mouseDown(theEvent);
			return;
		}
		
		//
		// Handle clicks
		//
		if (theEvent.clickCount > 2)
			return;
			
		if (theEvent.clickCount == 2 && m_ignoresMultiClick)
		{
			sendDoubleAction();
			return;
		}
				
		//
		// Record flags (used by cell tracking callbacks)
		//
		m_mousedownflags = theEvent.modifierFlags;

		//
		// Set up tracking data
		//
		m_trackingData = { 
			mouseDown: true, 
			eventMask: NSEvent.NSLeftMouseDownMask | NSEvent.NSLeftMouseUpMask | NSEvent.NSLeftMouseDraggedMask
			| NSEvent.NSMouseMovedMask  | NSEvent.NSOtherMouseDraggedMask | NSEvent.NSRightMouseDraggedMask,
			mouseUp: false, 
			complete: false,
			bounds: cellTrackingRect()
		};
    		
		//
		// Determine cell tracking based on selection mode.
		//
		if (m_mode == NSMatrixMode.NSListModeMatrix)
		{
			//
			// Setup for mouseDownListMode()
			//
			m_isselecting = true;
			
			//
			// Set up callbacks and being processing
			//
			m_cell.setTrackingCallbackSelector(this, "cellTrackingCallbackListMode");
    		mouseDownListMode(theEvent);
		}
		else
		{
			m_cell.setTrackingCallbackSelector(this, "cellTrackingCallbackNonListMode");
			mouseDownNonListMode(theEvent);
		}
	}
	
	
	private function cellTrackingCallbackListMode(mouseUp:Boolean)
	{
		//trace("cellTrackingCallbackListMode");
		
		if (mouseUp) // send action, stop tracking
		{
			m_cell.setTrackingCallbackSelector(null, null);
			this.sendAction();
		}
		else // continue tracking
		{
			NSApplication.sharedApplication().callObjectSelectorWithNextEventMatchingMaskDequeue(
				this, "mouseDownListMode", m_trackingData.eventMask, true);
		}
		
		sendAction();
	}
	
	
	private function cellTrackingCallbackNonListMode(mouseUp:Boolean) 
	{
		//trace("cellTrackingCallbackNonListMode");
		
		if (m_mode != NSMatrixMode.NSTrackModeMatrix)
		{
			highlightCellAtRowColumn(false, m_dottedrow, m_dottedcol);

			m_highlightedcell = null;
		}
		
		if (mouseUp) // stop tracking
		{
			//trace("end tracking");
			m_cell.setTrackingCallbackSelector(null, null);
			//! send action?
		}
		else // continue tracking
		{
			//trace("continue tracking");
			NSApplication.sharedApplication().callObjectSelectorWithNextEventMatchingMaskDequeue(
				this, "mouseDownNonListMode", m_trackingData.eventMask, true);
		}
	}
	
	
	//
	// Variables used by cell tracking
	//
	private var m_lastcell:NSCell = null; // the last selected cell
	private var m_highlightedcell:NSCell = null; // the currently highlighted cell
	private var m_anchor:Number; // the point from which the selection begins (list mode)
	private var m_isselecting:Boolean;
	private var m_lastidx:Number = 0;
	
	/**
	 * Handles NSListModeMatrix mousedown logic.
	 */
	private function mouseDownListMode(theEvent:NSEvent):Void
	{
		//trace("mouseDownListMode");
		
		if (theEvent.type == NSEvent.NSLeftMouseUp) 
		{
			m_cell.setTrackingCallbackSelector(null, null);
			return;
		}
		
		var pt:NSPoint; // The location in the frame
		var cellLoc:Object; // The location of the cell that is currently being hovered over
		var mouseCell:NSCell; // The cell that is currently being hovered over
		var eventMask:Number = 
			NSEvent.NSLeftMouseUpMask | 
			NSEvent.NSLeftMouseDownMask | 
			NSEvent.NSMouseMovedMask | 
			NSEvent.NSLeftMouseDraggedMask |
			NSEvent.NSPeriodicMask;

		pt = convertPointFromView(theEvent.mouseLocation);
		cellLoc = this.getRowColumnForPoint(pt);
		
		//
		// If we're currently over a cell...
		//		
		if (cellLoc != null)
		{
			var mouseIdx:Number = indexFromRowColumn(cellLoc.row, cellLoc.column);
			mouseCell = NSCell(m_cells[mouseIdx]);
			
			//
			// Autoscroll if necessary
			//
			if (m_autoscroll)
			{
				var scrollRect:NSRect = cellFrameAtRowColumn(cellLoc.row, cellLoc.column);
				scrollRectToVisible(scrollRect);
			}
			
			//
			// If a new, enabled cell is under the mouse
			//
			if (mouseCell != m_lastcell && mouseCell.isEnabled())
			{
				if (m_lastcell == null)
				{
					var altDown:Boolean = (m_mousedownflags & NSEvent.NSAlternateKeyMask) != 0;
					var shiftDown:Boolean = (m_mousedownflags & NSEvent.NSShiftKeyMask) != 0;
										
					//
					// When a new cell is pressed, and the Alt and Shift keys
					// are up, we deselect all cells.
					//
					if (!altDown && !shiftDown)
					{
						this.deselectAllCells();
					}
					
					//
					// The clicked cell is the anchor of the selection, unless
					// alt is down.
					//
					if (!altDown)
					{
						m_anchor = mouseIdx;
					}
					else
					{
						if (m_dottedcol == -1)
							m_anchor = 0; // = indexFromRowColumn(0, 0);
						else
							m_anchor = indexFromRowColumn(m_dottedrow, m_dottedcol);
					}
					
					//
					// With the shift key pressed, clicking on a selected cell
					// deselects it (and inverts the selection on mouse dragging).
					//
					if (shiftDown)
					{
						m_isselecting = mouseCell.state() == NSCell.NSOffState;
					}
					else
					{
						m_isselecting = true;
					}
					
					m_lastidx = mouseIdx;
				}
				
				this.setSelectionFromToAnchorHighlight(
					mouseIdx,
					m_lastidx, 
					m_anchor,
					m_isselecting);
					
				m_lastidx = mouseIdx;
				m_lastcell = mouseCell;
			}
		}
		
		m_cell.trackMouseInRectOfViewUntilMouseUp(theEvent, m_trackingData.bounds, this, 
			m_cell.getClass().prefersTrackingUntilMouseUp());
		//NSApplication.sharedApplication().callObjectSelectorWithNextEventMatchingMaskDequeue(this, 
		//	"mouseTrackingCallback", m_trackingData.eventMask, true);
	}
	
	
	/**
	 * Handles non-NSListModeMatrix mousedown logic.
	 */
	private function mouseDownNonListMode(theEvent:NSEvent):Void
	{
		//trace("mouseDownNonListMode");
		
		if (theEvent.type == NSEvent.NSLeftMouseUp) 
		{
			m_cell.setTrackingCallbackSelector(null, null);
			return;
		}
		
		var scrolling:Boolean = false;
		var frame:NSRect;
		var cell:NSCell;
		var highlight:NSCell;
		
		var pt:NSPoint = theEvent.mouseLocation;
		//trace(pt);
		var loc:Object = getRowColumnForPoint(pt);
		//trace(loc.row + ", " + loc.column);
		
		if (loc == null)
			scrolling = false;
		
		if (loc != null)
		{
			cell = cellAtRowColumn(loc.row, loc.column);
			
			//
			// Make sure we're not doing more work than we have to be
			//
			if (cell == m_lastcell)
				return;
				
			//
			// Get the frame
			//
			frame = cellFrameAtRowColumn(loc.row, loc.column);
						
			if (m_autoscroll)
				scrolling = scrollRectToVisible(frame);

			
			//
			// If the cell is enabled, select it.
			//
			if (cell.isEnabled())
			{
				var oldState:Number = cell.state();
				
				selectCellAtRowColumn(loc.row, loc.column);
				
				if (m_mode == NSMatrixMode.NSRadioModeMatrix && !m_allowsemptysel)
				{
					cell.setState(NSCell.NSOnState);
				}
				else
				{
					cell.setState(oldState);
				}
				
				if(theEvent.view == this && cellTrackingRect().pointInRect(
					convertPointFromView(theEvent.mouseLocation, null))) 
				{
					cell.trackMouseInRectOfViewUntilMouseUp(theEvent, m_trackingData.bounds, this, 
						cell.getClass().prefersTrackingUntilMouseUp());
					
					return;
				}
				
				/* //! This has to be moved
				
				//
				// Highlighting
				//
				if (m_mode != NSMatrixMode.NSTrackModeMatrix)
				{
					highlightCellAtRowColumn(false, loc.row, loc.column);
				}
				else
				{
					if (cell.state() != oldState)
					{
						//! setNeedsDisplayInRect(frame);
						setNeedsDisplay(true);
					}
				}
				*/
			}
		}
		
		NSApplication.sharedApplication().callObjectSelectorWithNextEventMatchingMaskDequeue(this, 
			"mouseTrackingCallback", m_trackingData.eventMask, true);
	}
		
	
	/**
	 * @see org.actionstep.NSResponder#keyDown
	 */
	public function keyDown(event:NSEvent):Void
	{
		var chars:String = event.characters;
		var mods:Number = event.modifierFlags;
		var char:Number = event.keyCode;
				
		switch (char)
		{
			//
			// Select text
			//
			case NSCarriageReturnCharacter:
			case NSNewlineCharacter:
			case NSEnterCharacter:
				selectText(this);
				break;
				
			//
			// Perform an action based on mode.
			//
			// NSTrackModeMatrix or NSHighlightModeMatrix:
			//		Set the current cell to the next state.
			//
			// NSListModeMatrix:
			//		Deselect all cells
			//
			// NSRadioModeMatrix:
			//		Select the focused cell
			//
			case 32: //! This is a space, it should be a constant somewhere
				
				if (m_dottedrow != -1 && m_dottedcol != -1)
				{
					if (mods & NSEvent.NSAlternateKeyMask)
					{
						//_altModifier = character;
					}
					else
					{
						var cell:NSCell;
						
						switch (m_mode)
						{
							case NSMatrixMode.NSTrackModeMatrix:
							case NSMatrixMode.NSHighlightModeMatrix:
								cell = cellAtRowColumn(m_dottedrow, m_dottedcol);
								cell.setNextState();
								//! setNeedsDisplayInRect();
								setNeedsDisplay(true);
								
								break;
								
							case NSMatrixMode.NSListModeMatrix:
								if (!(mods & NSEvent.NSShiftKeyMask))
									deselectAllCells();
								
								break;
								
							case NSMatrixMode.NSRadioModeMatrix:
								selectCellAtRowColumn(m_dottedrow, m_dottedcol);
								
								break;
								
						}
						
						displayIfNeeded();
						performClick(this);
					}
					
					return;
				}
				
				break;
				
			//
			// Move focus
			//
			case NSLeftArrowFunctionKey:
			case NSRightArrowFunctionKey:
				if (m_numcols <= 1)
					break;
					
			case NSUpArrowFunctionKey:
			case NSDownArrowFunctionKey:
				
				if (mods & NSEvent.NSShiftKeyMask)
				{
					//! implement
				}
				else if (mods & NSEvent.NSAlternateKeyMask)
				{
					//! implement
				}
				else
				{
					switch (char)
					{
						case NSLeftArrowFunctionKey:
							moveLeft(this);
							break;
							
						case NSRightArrowFunctionKey:
							moveRight(this);
							break;
							
						case NSUpArrowFunctionKey:
							moveUp(this);
							break;
							
						case NSDownArrowFunctionKey:
							moveDown(this);
							break;
					}
				}
				
				return;
		
			//
			// Handle tabbing
			//
			case NSTabCharacter:
				if (m_usetabkey)
				{
					if (mods & NSEvent.NSShiftKeyMask) // go backwards
					{
						if (selectPreviousSelectableCellAfterRowColumn(m_selcell_row, 
							m_selcell_column))
						{
							return; // MUST have this (to indicate the key was handled)
						}
					}
					else
					{
						if (selectNextSelectableCellAfterRowColumn(m_selcell_row,
							m_selcell_column))
						{
							return; // MUST have this (to indicate the key was handled)
						}
					}	
				}
				
				break;
				
			default:
				break;
				
		}
		
		super.keyDown(event);
	}
	
	
	//******************************************************															 
	//*                 Drawing Methods
	//******************************************************
	
	/**
	 * Draws the thing.
	 */
	public function drawRect(rect:NSRect):Void
	{		
		m_mcBounds.clear();
		
		drawBackground(rect);
			
		//
		// Draw the cells
		//
		for (var i:Number = 0; i < m_numrows; i++)
		{
			for (var j:Number = 0; j < m_numcols; j++)
			{
				drawCellAtRowColumn(i, j);
			}
		}
	}
	
	
	/**
	 * Draws the background of the matrix.
	 * 
	 * This method can be overridden for more advanced background drawing.
	 */
	private function drawBackground(rect:NSRect):Void
	{
		if (m_drawsbg)
		{
			ASTheme.current().drawFillWithRectColorInView(rect, m_bgcolor, this);
		}
	}
	
	
	//******************************************************															 
	//*	                Private Methods
	//******************************************************
	
	/**
	 * Renew rows and columns.	
	 *
	 * @param rows 		The new number of rows in the matrix.
	 * @param columns 	The new number of columns in the matrix.
	 * @param rowSpace	
	 * @param colSpace	
	 */
	private function renewRowsColumnsRowSpaceColSpace(
		rows:Number, columns:Number, rowSpace:Number, colSpace:Number):Void
	{			
		var oldMaxC:Number, oldMaxR:Number;
  		var i:Number, j:Number;
		
		//
  		// Check for illegal arguments (negative column or row).
  		//  
 		if (rows < 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSRangeException",
				"NSMatrix::renewRowsColumnsRowSpaceColSpace - " 
				+ rows + 
				" was specified as the row parameter. Negative indices are " +
				"not allowed.");
			trace(e);
			throw e;
		}
		
		if (columns < 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSRangeException",
				"NSMatrix::renewRowsColumnsRowSpaceColSpace - " 
				+ columns + 
				" was specified as the column parameter. Negative indices are " +
				"not allowed.");
			trace(e);
			throw e;
		}
		
		//
		// Modify array size
		//
		if (columns > m_numcols)
		{
			for (i = m_numcols; i < columns; i++)
			{
				for (j = 0; j < m_numrows; j++)
				{
					m_cells.insertObjectAtIndex(null, i + (i + 1) * j);
				}
			}
		}
		
		//
		// Set matrix bounds
		//
		oldMaxC = m_maxcols;
		m_numcols = columns;
		if (columns > m_maxcols)
			m_maxcols = columns;
		
		oldMaxR = m_maxrows;
		m_numrows = rows;
		if (rows > m_maxrows)
			m_maxrows = rows;
					
		//
		// Resize
		//
		if (columns > oldMaxC)
		{
			var end:Number = columns - 1;
			
			// Allocate the new columns and fill them
			for (i = 0; i < oldMaxR; i++)
			{		
				for (j = oldMaxC; j < columns; j++)
				{
					assignCell(null, i, j, false);
					
					if (j == end && colSpace > 0)
					{
						colSpace--;
					}
					else
					{
						assignCell(makeCell(), i, j, false);
					}
				}
			}
		}
				
		if (rows > oldMaxR)
		{
			//trace("rows > oldMaxR");
			var end:Number = rows - 1;
		
			// Allocate the new rows and fill them
			for (i = oldMaxR; i < rows; i++)
			{		
				if (i == end)
				{
					for (j = 0; j < m_maxcols; j++)
					{
						assignCell(null, i, j, false);
						
						if (rowSpace > 0)
						{
							rowSpace--;
						}
						else
						{
							assignCell(makeCell(), i, j, false);
						}
					}
				}
				else
				{
					for (j = 0; j < m_maxcols; j++)
					{
						assignCell(null, i, j, false);
						assignCell(makeCell(), i, j, false);
					}
				}
			}
		}
		
		/*
		//
 		// Expand columns
		//
		if (columns > m_numcols) // Only expand if necessary
		{						
			//
			// Loop through the rows, adding the column to each.
			//
			for (var i:Number = m_numrows; i > 0; i--)
			{	
				var numNewCols:Number = columns - m_numcols;
				
				var insertPoint:Number = i * m_numcols;

				while (numNewCols-- > 0)
					m_cells.insertObjectAtIndex(makeCell(), insertPoint);
			}
		}
		else if (columns < m_numcols)
		{
			var numColsToRemove:Number =  m_numcols - columns;
			
			//
			// Loop through the rows, removing the column from each.
			//
			for (var i:Number = m_numrows; i > 0; i--)
			{
				var removalPoint:Number = i * m_numcols;

				while (numColsToRemove-- > 0)
				{
					var cell:NSCell = NSCell(m_cells.objectAtIndex(removalPoint));
					cell.release();
					m_cells.removeObjectAtIndex(removalPoint);
				}
			}
		}
		
		m_numcols = columns;
		
		//
		// Expand rows
		//
		if (rows > m_numrows) // Only expand if necessary.
		{
			var numCellsToInsert:Number = (rows - m_numrows) * m_numcols;
			
			while (numCellsToInsert-- > 0)
				m_cells.addObject(makeCell());
		}
		else if (rows < m_numrows)
		{
			var numCellsToRemove:Number = (m_numrows - rows) * m_numcols;
			var removalPoint:Number = m_numcols * m_numrows;
			
			while (numCellsToRemove-- > 0)
			{
				var cell:NSCell = NSCell(m_cells.objectAtIndex(removalPoint));

				cell.release();
				m_cells.removeObjectAtIndex(removalPoint);
			}
		}

		m_numrows = rows;
		*/
		
		deselectAllCells();
	}
	
	
	/**
	 * Clears the current selection when in NSRadioModeMatrix.
	 */
	private function clearCurrentRadioSelection(clearVars:Boolean):Void
	{
		if (m_mode != NSMatrixMode.NSRadioModeMatrix || m_selcell == null)
			return;
			
		if (clearVars == undefined)
			clearVars = true;
			
		m_sel.clear();				
		m_selcell.setState(NSCell.NSOffState);
		//! setNeedsDisplayInRect
		drawCellAtRowColumn(m_selcell_row, m_selcell_column);
		
		if (!clearVars)
			return;
		
		m_selcell = null;
		m_selcell_row = m_selcell_column = -1;
	}
	
	
	/**
	 * Replaces the cell that previously occupied row and column with
	 * newCell. This method releases the old cell.
	 */
	private function assignCell(newCell:NSCell, row:Number, column:Number, release:Boolean):Void
	{				
		if (release == undefined)
			release = true;
			
		var idx:Number = indexFromRowColumn(row, column);
		var oldCell:NSCell = NSCell(m_cells.objectAtIndex(idx));
			
		if (release)
			oldCell.release(); // Release the old cell.
			
		m_cells.replaceObject(idx, newCell);
	}
		
	
	/**
	 * Gets the range of cells that are currently visible to the user.
	 */
	private function getVisibleRanges():Object
	{
		//! add code to account for scrolling
		return {rows: new NSRange(0, m_numrows), columns: new NSRange(0, m_numcols)};
	}
	
	
	/**
	 * Updates selection after a column has been removed.
	 *
	 * This method will decrement all selections with columns greater than
	 * the column that has been removed, and will remove selections that existed
	 * within the column.
	 *
	 * If there are no selections as a result of the removal, and allowEmptySelection
	 * is false, (0,0) will be selected.
	 */
	private function updateSelWithColumnRemoved(column:Number):Void
	{		
		var loc:Object;
		var sel:Array = m_sel.internalList();
		
		//
		// Loop through backwards.
		//
		for (var i:Number = sel.length - 1; i >= 0; i--)
		{
			loc = rowColumnFromIndex(sel[i]);
					
			if (loc.column == column)
			{
				cell.setHighlighted(false);
				sel.splice(i, 1);
			}
			else if (loc.column > column)
			{
				sel[i]--;
			}
		}
				
		//
		// If there is no more selection, and we don't allow no selection,
		// select 0, 0.
		//
		if (sel.length == 0 && !m_allowsemptysel)
		{
			selectCellAtRowColumn(0, 0);
		}
	}
	
	
	/**
	 * Updates selection after a row has been removed.
	 *
	 * This method will decrement all selections with rows greater than
	 * the row that has been removed, and will remove selections that existed
	 * within the row.
	 *
	 * If there are no selections as a result of the removal, and allowEmptySelection
	 * is false, (0,0) will be selected.
	 */
	private function updateSelWithRowRemoved(row:Number):Void
	{
		var loc:Object;
		var sel:Array = m_sel.internalList();
		
		//
		// Loop through backwards.
		//
		for (var i:Number = sel.length - 1; i >= 0; i--)
		{
			loc = rowColumnFromIndex(sel[i]);
			
			if (loc.row == row)
			{
				cell.setHighlighted(false);
				sel.splice(i, 1); // remove selection from array
			}
			else if (loc.row > row)
			{
				//
				// decrement the selection index if necessary
				//
				sel[i] = sel[i] - m_numcols;
			}
		}
		
		//
		// If there is no more selection, and we don't allow no selection,
		// select 0, 0.
		//
		if (sel.length == 0 && !m_allowsemptysel)
		{
			selectCellAtRowColumn(0, 0);
		}
	}
	

	/**
	 * Updates the selection array when a column is added. All selections in columns
	 * that are greater than the column that has been added are incremented.
	 */	
	private function updateSelWithColumnAdded(column:Number):Void
	{
		var loc:Object;
		var sel:Array = m_sel.internalList();
		var len:Number = sel.length;
		
		for (var i:Number = 1; i < len; i++)
		{
			loc = rowColumnFromIndex(sel[i]);
			
			if (loc.column >= column)
			{
				sel[i]++;
			}
		}
	}
	
	
	/**
	 * Updates the selection array when a row is added. All selections in rows
	 * that are greater than the row that has been added are incremented.
	 */
	private function updateSelWithRowAdded(row:Number):Void
	{
		var loc:Object;
		var sel:Array = m_sel.internalList();
		var len:Number = sel.length;
		
		for (var i:Number = 1; i < len; i++)
		{
			loc = rowColumnFromIndex(sel[i]);
			
			if (loc.row >= row)
			{
				sel[i] += m_numcols;
			}
		}		
	}
	
	
	/**
	 * Returns the lowest, rightmost selected cell, with row taking precedence.
	 */
	private function getLowestRightmostSelectionLocation():Number
	{
		var cellItr:NSEnumerator = m_sel.objectEnumerator();
		var selLoc:Object;
		var resLoc:Object;
		var resIdx:Number;
		var index:Number;
		
		while (!isNaN (index = Number(cellItr.nextObject())))
		{
			selLoc = rowColumnFromIndex(index);
			
			if (resLoc == null) // Set resLoc to the first item in the list.
			{
				resLoc = selLoc;
				resIdx = index;
				continue;
			}
			
			if (selLoc.row < resLoc.row) // not a candidate
			{
				continue;
			}
			else if (selLoc.row > resLoc.row) // if lower, choose it
			{
				resLoc = selLoc;
				resIdx = index;
			}
			else // == pick farthest to right
			{
				resLoc = resLoc.column > selLoc.column ? resLoc : selLoc;				
				resIdx = indexFromRowColumn(resLoc.row, resLoc.column);
			}
		}
		
		return resIdx;
	}
		
	
	/**
	 *	Recalculates the cell size.
	 */ 	 
	private function recalcCellSize():Void 	 
	{ 	 
		if (m_numcols > 0 && m_numrows > 0)
		{
			m_cellsize = new NSSize( 	 
				(m_frame.size.width - (m_cellspacing.width * (m_numcols + 1))) / m_numcols, 	 
				(m_frame.size.height - (m_cellspacing.height * (m_numrows + 1))) / m_numrows); 	 
		}
	}
         
         
	/**
	 * Makes a cell based on the prototype instance or the cell class,
	 * depending on the value of m_usingcellinstance.
	 */
	private function makeCell():NSCell
	{
		var cell:NSCell;
		
		//
		// Build the cell from the existing cell instance, or the cell
		// class, depending on usingCellInstance.
		//
		if (m_usingcellinstance)
		{
			cell = NSCell(m_prototype.memberwiseClone());
		}
		else
		{
			cell = NSCell(
				org.actionstep.ASUtils.createInstanceOf(m_cellclass));
			cell.init();
		}
		
		return cell;
	}
	
	
	/**
	 * Given a row and column, will return the corresponding index into
	 * the underlying data structure.
	 */         
	private function indexFromRowColumn(row:Number, column:Number):Number
	{
		return (row * m_numcols) + column;
	}
	
	
	/**
	 * Given an index, returns an object with row and column properties.
	 */
	private function rowColumnFromIndex(index:Number):Object
	{
		var ret:Object = new Object();
		
		ret.row = Math.floor(index / m_numcols);
		ret.column = index % m_numcols;
		
		return ret;
	}
	
	
	/**
	 * Selects the text in the cell aCell if the cell is editable
	 * and selectable.
	 *
	 * Returns true if text is successfully selected, and false otherwise.
	 */
	private function selectTextWithCell(aCell:NSCell):Boolean
	{
		if (aCell == null) // You can only select a cell that exists
			return false;
			
		//
		// Cell must be editable and selectable.
		//
		if (!aCell.isEditable() && !aCell.isSelectable())
			return false;
			
		m_editor = ASFieldEditingProtocol(aCell).beginEditingWithDelegate(this);
		
		if (m_editor == null)
			return false;
			
		m_editor.select();
				
		return true;
	}
	
	
	/**
	 * Selects the next selectable cell after the specified row and column.
	 *
	 * This occurs on a tab press.
	 */
	private function selectNextSelectableCellAfterRowColumn(row:Number, 
		column:Number):Boolean
	{
		var cell:NSCell;
		var j:Number = column + 1; // make sure inner loop starts after column
		
		for (var i:Number = row; i < m_numrows; i++)
		{
			for (; j < m_numcols; j++)
			{
				cell = cellAtRowColumn(i, j);
				
				//
				// Select cell if we can
				//
				if (cell.isEditable() && cell.isEnabled())
				{
					selectCellAtRowColumn(i, j);
					return true;
				}
				
			}
			
			j = 0; // all rows after the first should start at column 0
		}
		
		return false;
	}
	
	
	/**
	 * Selects the previous selectable cell after the specified row and column.
	 *
	 * This occurs on a shift+tab press.
	 */
	private function selectPreviousSelectableCellAfterRowColumn(row:Number, 
		column:Number):Boolean
	{
		var cell:NSCell;
		var j:Number = column - 1; // make sure inner loop starts before column
		
		for (var i:Number = row; i >= 0; i--)
		{
			for (; j >= 0; j--)
			{
				cell = cellAtRowColumn(i, j);
				
				//
				// Select cell if we can
				//
				if (cell.isEditable() && cell.isEnabled())
				{
					selectCellAtRowColumn(i, j);
					return true;
				}
				
			}
			
			j = m_numcols - 1; // all rows after the first should start at column 0
		}
		
		return false;
	}
	
	
	/**
	 * Moves the focus or selection (depending on mode) in the direction
	 * specified by direction. direction can be one of the following:
	 *
	 * NSObject.NSUpArrowFunctionKey
	 * NSObject.NSDownArrowFunctionKey
	 * NSObject.NSRightArrowFunctionKey
	 * NSObject.NSLeftArrowFunctionKey
	 */
	private function moveFocusOrSel(direction:Number):Void
	{
		var selectCell:Boolean = false;
		var cell:NSCell;
		var i:Number, j:Number, lastDottedRow:Number, lastDottedCol:Number;
		
		//
		// Check for valid input
		//
		if (direction != NSUpArrowFunctionKey &&
			direction != NSDownArrowFunctionKey &&
			direction != NSLeftArrowFunctionKey &&
			direction != NSRightArrowFunctionKey)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSInvalidArgumentException",
				"NSMatrix::moveFocusOrSel - " + direction + " is not a valid direction",
				null);
			trace(e);
			throw e;
		}
		
		//
		// List and radio modes select their cells
		//
		if (m_mode == NSMatrixMode.NSRadioModeMatrix ||
			m_mode == NSMatrixMode.NSListModeMatrix)
		{
			selectCell = true;
		}
		
		if (m_dottedcol == -1 || m_dottedrow == -1) // No focus yet.
		{
			if (direction == NSUpArrowFunctionKey || direction == NSDownArrowFunctionKey)
			{
				//
				// Traverse cells vertically to find one that accepts first responder
				//
				for (i = 0; i < m_numcols; i++)
				{
					for (j = 0; j < m_numrows; j++)
					{
						cell = cellAtRowColumn(j, i);
						
						if (cell.acceptsFirstResponder())
						{
							m_dottedrow = j;
							m_dottedcol = i;
						}
					}
				}
			}
			else // NSLeftArrowFunctionKey || NSRightArrowFunctionKey
			{
				//
				// Traverse cells horizontally to find one that accepts first responder
				//
				for (i = 0; i < m_numrows; i++)
				{
					for (j = 0; j < m_numcols; j++)
					{
						cell = cellAtRowColumn(i, j);
						
						if (cell.acceptsFirstResponder())
						{
							m_dottedrow = i;
							m_dottedcol = j;
						}
					}
				}				
			}
			
			if (m_dottedrow == -1 || m_dottedcol == -1) // no selection found
				return;
				
			if (selectCell)
			{
				if (m_selcell != null)
					deselectAllCells();
				
				selectCellAtRowColumn(m_dottedrow, m_dottedcol);
			}
			else
			{
				//! setNeedsDisplayInRect
				setNeedsDisplay(true);
			}
		}
		else // A selected or focused row already exists
		{
			lastDottedRow = m_dottedrow;
			lastDottedCol = m_dottedcol;
			
			//
			// Move focus based on direction
			//
			switch (direction)
			{
				case NSUpArrowFunctionKey:
					
					if (m_dottedrow <= 0) // can't move up
						return;
						
					//
					// Move up until a cell can acceptFirstResponder
					//
					for (i = m_dottedrow - 1; i >= 0; i--)
					{
						cell = cellAtRowColumn(i, m_dottedcol);
						
						if (cell.acceptsFirstResponder())
						{
							m_dottedrow = i;
							break;
						}
					}
						
					break;
					
				case NSDownArrowFunctionKey:

					if (m_dottedrow >= m_numrows - 1) // can't move down
						return;
						
					//
					// Move down until a cell can acceptFirstResponder
					//
					for (i = m_dottedrow + 1; i < m_numrows; i++)
					{
						cell = cellAtRowColumn(i, m_dottedcol);
						
						if (cell.acceptsFirstResponder())
						{
							m_dottedrow = i;
							break;
						}
					}
					
					break;
					
				case NSLeftArrowFunctionKey:
				
					if (m_dottedcol <= 0) // can't move left
						return;

					//
					// Move left until a cell can acceptFirstResponder
					//
					for (i = m_dottedcol - 1; i >= 0; i--)
					{
						cell = cellAtRowColumn(m_dottedrow, i);
						
						if (cell.acceptsFirstResponder())
						{
							m_dottedcol = i;
							break;
						}
					}
					
					break;
								
				case NSRightArrowFunctionKey:
				
					if (m_dottedcol >= m_numcols - 1) // can't move right
						return;

					//
					// Move right until a cell can acceptFirstResponder
					//
					for (i = m_dottedcol + 1; i < m_numcols; i++)
					{
						cell = cellAtRowColumn(m_dottedrow, i);
						
						if (cell.acceptsFirstResponder())
						{
							m_dottedcol = i;
							break;
						}
					}
					
					break;
					
			}
			
			//
			// Can't move in direction, so return.
			//
			if ((direction == NSUpArrowFunctionKey || direction == NSDownArrowFunctionKey) &&
				m_dottedrow != i)
			{
				return;
			}
			
			if ((direction == NSLeftArrowFunctionKey || direction == NSRightArrowFunctionKey) &&
				m_dottedcol != i)
			{
				return;
			}
			
			//
			// Do selection / drawing
			//
			if (selectCell)
			{
				if (m_mode == NSMatrixMode.NSRadioModeMatrix)
				{
					//! Do something here. Ask Rich.
				}
				else
					deselectAllCells();
					
				selectCellAtRowColumn(m_dottedrow, m_dottedcol);
			}
			else
			{
				//! setNeedsDisplayInRect - for both old and new dotted cols
				setNeedsDisplay(true);
			}
		}
	}


	/**
	 * Sets the row and column under keyboard control.
	 */
	private function setKeyRowColumn(row:Number, column:Number):Void
	{
		if (m_dottedrow == row && m_dottedcol == column)
			return;
			
		var cell:NSCell = cellAtRowColumn(row, column);
		
		if (cell.acceptsFirstResponder())
		{
			if (m_dottedrow != -1 && m_dottedcol != -1)
			{
				//! setNeedsDisplayInRect(cellFrameAtRowColumn(m_dottedrow, m_dottedcol));
			}
			
			m_dottedrow = row;
			m_dottedcol = column;
			
			//! setNeedsDisplayInRect(cellFrameAtRowColumn(m_dottedrow, m_dottedcol));
			setNeedsDisplay(true);
		}
	}
		
	//******************************************************															 
	//*			   Public Static Properties				   *
	//******************************************************
	//******************************************************															 
	//*				 Public Static Methods				   *
	//******************************************************	
	
	private static function compareRowColumnObject(rc1:Object, rc2:Object):Boolean
	{
		return rc1.row == rc2.row && rc1.column == rc2.column;
	}
	
	public static function cellClass():Function 
	{
		if (g_cellClass == undefined) 
		{
			g_cellClass = org.actionstep.NSCell;
		}
		
		return g_cellClass;
	}
}
