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

import org.actionstep.NSTextField;

/**
 *
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSSecureTextField extends NSTextField
{	
	private static var g_cellClass:Function = org.actionstep.NSSecureTextFieldCell;
	
	public function NSSecureTextField()
	{
	}
	
	//******************************************************															 
	//*					 Public Methods					   *
	//******************************************************
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSSecureTextField";
	}

	//******************************************************															 
	//*			    Public Static Properties			   *
	//******************************************************
			
	/**
	 * @see org.actionstep.NSControl#cellClass()
	 */
	public static function cellClass():Function 
	{
		return g_cellClass;
	}


	/**
	 * @see org.actionstep.NSControl#setCellClass()
	 */	
	public static function setCellClass(cellClass:Function) 
	{
		if (cellClass == null) 
		{
		g_cellClass = org.actionstep.NSSecureTextFieldCell;
		} 
		else 
		{
			g_cellClass = cellClass;
		}
	}
}
