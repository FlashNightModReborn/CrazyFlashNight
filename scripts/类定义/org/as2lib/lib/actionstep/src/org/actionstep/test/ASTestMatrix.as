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
 
import org.actionstep.constants.NSAlertStyle;
import org.actionstep.constants.NSButtonType;
import org.actionstep.NSAlert;
import org.actionstep.NSApplication;
import org.actionstep.NSArray;
import org.actionstep.NSButton;
import org.actionstep.NSButtonCell;
import org.actionstep.NSColor;
import org.actionstep.NSMatrix;
import org.actionstep.NSRect;
import org.actionstep.NSSize;
import org.actionstep.NSTextField;
import org.actionstep.NSView;
import org.actionstep.NSWindow;
import org.actionstep.test.ASTestView;

/**
 * Tests the NSMatrix...
 *
 * @author Scott Hyndman
 */
class org.actionstep.test.ASTestMatrix 
{	
	public static var g_app:NSApplication;
	public static var g_win:NSWindow;
	
	public static function test():Void
	{
		var app:NSApplication;
		var window:NSWindow;
		var view:NSView;
		var addColumnButton:NSButton, addRowButton:NSButton, remColButton:NSButton, remRowButton:NSButton,
			insertColButton:NSButton, insertRowButton:NSButton;
		var insertColIdxInput:NSTextField, insertColTitleInput:NSTextField, insertRowIdxInput:NSTextField,
			insertRowTitleInput:NSTextField;
		
		//
		// Setup
		//
		app = g_app = NSApplication.sharedApplication();
		window = g_win = (new NSWindow()).initWithContentRect(new NSRect(0,0,800,600));
		view = (new ASTestView()).initWithFrame(new NSRect(0,0,800,600));
		
		//
		// Create matrix
		//
		var cell:NSButtonCell = (new NSButtonCell()).initTextCell("test");
		cell.setButtonType(NSButtonType.NSRadioButton);
		cell.setEditable(true);
		var matrix:NSMatrix = (new NSMatrix()).initWithFrameModePrototypeNumberOfRowsNumberOfColumns
			(new NSRect(10,90,270,200), org.actionstep.constants.NSMatrixMode.NSRadioModeMatrix,
			cell, 2, 2);
				
		matrix.setBackgroundColor(new NSColor(0x000099));
		matrix.setCellBackgroundColor(new NSColor(0xFFFFFF));
		matrix.setIntercellSpacing(new NSSize(3, 3));	
		view.addSubview(matrix);
				
		var target:Object = {};
		target.addColumn = function()
		{
			matrix.addColumn();
			matrix.sizeToCells();
		};
		target.addRow = function()
		{
			matrix.addRow();
			matrix.sizeToCells();
		};
		target.removeRow = function()
		{
			var i:Number = parseInt(insertRowIdxInput.stringValue());
			
			if (isNaN(i) || i == undefined)
				i = matrix.numberOfRows() - 1;
			
			if(i < 0 || i >= matrix.numberOfRows())
			{
				ASTestMatrix.showErrorBox("Out of range.");
				return;
			}
			matrix.removeRow(i);
			matrix.sizeToCells();
		};
		target.removeColumn = function()
		{
			var i:Number = parseInt(insertColIdxInput.stringValue());
			
			if (isNaN(i) || i == undefined)
				i = matrix.numberOfColumns() - 1;
				
			if(i < 0 || i >= matrix.numberOfColumns())
			{
				ASTestMatrix.showErrorBox("Out of range.");
				return;
			}
			
			matrix.removeColumn(i);
			matrix.sizeToCells();
		};
		target.insertColumn = function()
		{
			var insert:Number = parseInt(insertColIdxInput.stringValue());
			
			if (isNaN(insert) || insert < 0)
			{
				ASTestMatrix.showErrorBox("Insert index is out of range.");
				return;
			}
			
			cell = (new NSButtonCell()).initTextCell(insertColTitleInput.stringValue());
			matrix.insertColumnWithCells(insert, NSArray.arrayWithObject(cell));
			matrix.sizeToCells();
		};
		target.insertRow = function()
		{
			var insert:Number = parseInt(insertRowIdxInput.stringValue());
			
			if (isNaN(insert) || insert < 0)
			{
				ASTestMatrix.showErrorBox("Insert index is out of range.");
				return;
			}
			
			cell = (new NSButtonCell()).initTextCell(insertRowTitleInput.stringValue());
			matrix.insertRowWithCells(insert, NSArray.arrayWithObject(cell));
			matrix.sizeToCells();
		};

		addColumnButton = (new NSButton()).initWithFrame(new NSRect(10,10,100,30));
		addColumnButton.setTitle("Add Column");
		addColumnButton.setTarget(target);
		addColumnButton.setAction("addColumn");		
		view.addSubview(addColumnButton);
		
		addRowButton = (new NSButton()).initWithFrame(new NSRect(120,10,100,30));
		addRowButton.setTitle("Add Row");
		addRowButton.setTarget(target);
		addRowButton.setAction("addRow");		
		view.addSubview(addRowButton);
		
		remRowButton = (new NSButton()).initWithFrame(new NSRect(120,50,100,30));
		remRowButton.setTitle("Remove Row");
		remRowButton.setTarget(target);
		remRowButton.setAction("removeRow");		
		view.addSubview(remRowButton);
		
		remColButton = (new NSButton()).initWithFrame(new NSRect(10,50,100,30));
		remColButton.setTitle("Remove Column");
		remColButton.setTarget(target);
		remColButton.setAction("removeColumn");		
		view.addSubview(remColButton);

		insertColButton = (new NSButton()).initWithFrame(new NSRect(340,10,100,30));
		insertColButton.setTitle("Insert Column");
		insertColButton.setTarget(target);
		insertColButton.setAction("insertColumn");		
		view.addSubview(insertColButton);

		insertColIdxInput = (new NSTextField()).initWithFrame(new NSRect(230, 13, 20, 23));
		view.addSubview(insertColIdxInput);
		
		insertColTitleInput = (new NSTextField()).initWithFrame(new NSRect(250, 13, 80, 23));
		view.addSubview(insertColTitleInput);
		
		insertRowButton = (new NSButton()).initWithFrame(new NSRect(340,50,100,30));
		insertRowButton.setTitle("Insert Row");
		insertRowButton.setTarget(target);
		insertRowButton.setAction("insertRow");		
		view.addSubview(insertRowButton);

		insertRowIdxInput = (new NSTextField()).initWithFrame(new NSRect(230, 53, 20, 23));
		view.addSubview(insertRowIdxInput);
		
		insertRowTitleInput = (new NSTextField()).initWithFrame(new NSRect(250, 53, 80, 23));
		view.addSubview(insertRowTitleInput);
		
		window.setContentView(view);
		
		//
		// tabbing
		//
		window.setInitialFirstResponder(addColumnButton);
		addColumnButton.setNextKeyView(addRowButton);
		addRowButton.setNextKeyView(insertColIdxInput);
		insertColIdxInput.setNextKeyView(insertColTitleInput);
		insertColTitleInput.setNextKeyView(insertColButton);
		insertColButton.setNextKeyView(remColButton);
		remColButton.setNextKeyView(remRowButton);
		remRowButton.setNextKeyView(insertRowIdxInput);
		insertRowIdxInput.setNextKeyView(insertRowTitleInput);
		insertRowTitleInput.setNextKeyView(insertRowButton);
		insertRowButton.setNextKeyView(matrix);		
		matrix.setNextKeyView(addColumnButton);
		
		app.run();
	}
	
	
	public static function showErrorBox(message:String):Void
	{
		var del:Object = {};
		del.alertCallback = function(sheet, ret:NSArray, ctxt:Object)
		{
			sheet.close();
		};
		del.respondsToSelector = function()
		{
			return true;
		};
		
		var alert:NSAlert = (new NSAlert()).init();
		
		alert.addButtonWithTitle("OK");
		alert.setMessageText(message);
		alert.setAlertStyle(NSAlertStyle.NSWarning);
		alert.beginSheetModalForWindowModalDelegateDidEndSelectorContextInfo
			(g_win, del, "alertCallback", new Date());
	}
	
	public static function alertCallback(sheet:NSWindow, ret:NSArray, ctxt:Object) 
	{
		sheet.close();
	}
}
