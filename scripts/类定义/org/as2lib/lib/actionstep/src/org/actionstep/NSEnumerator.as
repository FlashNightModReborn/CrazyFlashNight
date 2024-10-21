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

import org.actionstep.NSArray;

/**
 * Enumerates through a collection of objects.
 *
 * Note: It isn’t safe to modify a mutable collection while enumerating through it.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSEnumerator 
{	
	/** The collection. */
	private var m_list:Array;
	
	/** The current index in the collection. */
	private var m_curidx:Number;
	
	/** True if the enumeration is happening in reverse. */
	private var m_reverse:Boolean;
	
	
	/**
	 * Constructs a new instance of NSEnumerator.
	 *
	 * @param anArray The array to enumerate through.
	 */
	public function NSEnumerator(anArray:Array, reverse:Boolean)
	{
		m_list = anArray;
		m_curidx = reverse ? m_list.length - 1 : 0;
		m_reverse = reverse;
	}
	

	//******************************************************															 
	//*					 Public Methods					   *
	//******************************************************
	
	/**
	 * Returns an array of objects the receiver has yet to enumerate. The array
	 * returned by this method does not contain objects that have already been 
	 * enumerated with previous nextObject messages. Invoking this method 
	 * exhausts the enumerator’s collection so that subsequent invocations of 
	 * nextObject return null.
	 *
	 * @return The array of objects yet to be enumerated through.
	 */
	public function allObjects():NSArray
	{
		var idx:Number = m_curidx;
					
		//
		// Set the current index to exhaust the enumeration.
		//
		if (m_reverse)
		{
			m_curidx = 0; 	
		}	
		else
		{
			m_curidx = m_list.length - 1;
		}
				
		return NSArray.arrayWithArray(m_list.slice(idx, m_curidx));
	}
	
	
	/**
	 * Returns the next object from the collection being enumerated. When 
	 * nextObject returns null, all objects have been enumerated.
	 *
	 * @return The next object in the collection, or null if the end of the 
	 * collection has been reached.
	 */
	public function nextObject():Object
	{
		return (m_curidx == m_list.length || m_curidx == -1) ? null : 
			m_list[m_reverse ? m_curidx-- : m_curidx++];
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
	//******************************************************															 
	//*				  Static Constructor				   *
	//******************************************************
	private static function classConstruct():Boolean
	{
		
		return true;
	}
	
	private static var classConstructed:Boolean = classConstruct();
}
