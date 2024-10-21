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

import org.actionstep.NSTextFieldCell;

/**
 *
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSSecureTextFieldCell extends NSTextFieldCell
{	
	private var m_echosbullets:Boolean;
	
	public function NSSecureTextFieldCell()
	{
		m_echosbullets = true;
	}
	
	public function init():Void
	{
		super.init();
	}
	
	//******************************************************															 
	//*					  Properties					   *
	//******************************************************
	
	/**
	 * Returns whether the cell outputs bullets instead of each character
	 * typed. Default is TRUE.
	 */
	public function echosBullets():Boolean
	{
		return m_echosbullets;
	}
	
	
	/**
	 * Sets whether the cell outputs bullets instead of each character 
	 * typed.
	 */
	public function setEchosBullets(flag:Boolean):Void
	{
		//
		// Check for same value
		//
		if (m_echosbullets == flag)
			return;
			
		m_echosbullets = flag;
		
		//
		// Change the textfield property if appropriate
		//
		if (m_textField == null || m_textField._parent == undefined) 
			m_textField.password = flag;
	}
	
	/**
	* Returns the cell's textfield. Will build if necessary.
	*/
	private function textField():TextField 
	{
		if (m_textField == null || m_textField._parent == undefined) 
		{
			m_textField = super.textField();
			
			if (m_echosbullets)
				m_textField.password = true;
		}
	
		return m_textField;
	}
	
	//******************************************************														 
	//*					 Public Methods					   *
	//******************************************************
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSSecureTextFieldCell";
	}
	
	//******************************************************															 
	//*					    Events						   *
	//******************************************************
	//******************************************************															 
	//*				    Protected Methods				   *
	//******************************************************
	//******************************************************															 
	//*					 Private Methods				   *
	//******************************************************
	//******************************************************															 
	//*			   Public Static Properties				   *
	//******************************************************
	//******************************************************															 
	//*				 Public Static Methods				   *
	//******************************************************	
}
