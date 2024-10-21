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

import org.actionstep.NSDictionary;

/**
 * NSException is used for exception handling and contains information about
 * the exception.
 *
 * An exception is a special condition raised to interupt the normal flow of a
 * program.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSException extends Error //! can't extend NSObject
{
	private var m_name:String;
	private var m_reason:String;
	private var m_userinfo:NSDictionary;
	private var m_format:String;
	private var m_arguments:Array;

	// Reference
	private var m_func:String;
	private var m_className:String;
	private var m_line:Number;

	/**A generic name for an exception. You should typically use a more specific exception name.*/
	public static var NSGeneric:String = "NSGenericException";

	/**Name of an exception that occurs when attempting to access outside the bounds of some data,
	 * such as beyond the end of a string.
	 */
	public static var NSRange:String = "NSRangeException";

	/**Name of an exception that occurs when you pass an invalid argument to a method,
	 * such as a nil pointer where a non-nil object is required.
	 */
	public static var NSInvalidArgument:String = "NSInvalidArgumentException";

	/**Name of an exception that occurs when an internal assertion fails and implies an
	 * unexpected condition within the called code.
	 */
	public static var NSInternalInconsistency:String = "NSInternalInconsistencyException";

	/**Obsolete;  not currently used.*/
	public static var NSMalloc:String = "NSMallocException";

	/**Name of an exception that occurs when a remote object is accessed from a thread that
	 * should not access it. See NSConnection's enableMultipleThreads.
	 */
	//public static var NSObjectInaccessible:String = "NSObjectInaccessibleException";

	/**Name of an exception that occurs when the remote side of the NSConnection refused
	 * to send the message to the object because the object has never been vended.
	 */
	//public static var NSObjectNotAvailable:String = "NSObjectNotAvailableException";

	/**Name of an exception that occurs when an internal assertion fails and implies an
	 * unexpected condition within the distributed objects.
	 *
	 * This is a distributed object-specific exception.
	 */
	public static var NSDestinationInvalid:String = "NSDestinationInvalidException";

	/**Name of an exception that occurs when a timeout set on a port expires during a
	 * send or receive operation.
	 *
	 * This is a distributed object-specific exception.
	 */
	//public static var NSPortTimeout:String = "NSPortTimeoutException";

	/**Name of an exception that occurs when the send port of an NSConnection has
	 * become invalid.
	 *
	 * This is a distributed object-specific exception.
	 */
	//public static var NSInvalidSendPort:String = "NSInvalidSendPortException";

	/**Name of an exception that occurs when the receive port of an NSConnection has
	 * become invalid.
	 *
	 * This is a distributed object-specific exception.
	 */
	//public static var NSInvalidReceivePort:String = "NSInvalidReceivePortException";

	/**Generic error occurred on send. This is an NSPort-specific exception.*/
	//public static var NSPortSend:String = "NSPortSendException";

	/**Generic error occurred on receive. This is an NSPort-specific exception.*/
	//public static var NSPortReceive:String = "NSPortReceiveException";

	/**No longer used.*/
	//public static var NSOldStyle:String = "NSOldStyleException";

	/**
	 * Creates a new instance of NSException.
	 */
	public function NSException()
	{
	}


	/**
	 * Initializes the exception with the name name, a human-readable reason
	 * and additional information defined in userInfo.
	 */
	public function initWithNameReasonUserInfo(name:String, reason:String,
		userInfo:NSDictionary):NSException
	{
		m_name = name;
		m_reason = reason;
		m_userinfo = userInfo;

		return this;
	}

	public function get message():String {
	  return description();
	}


	//******************************************************
	//*					  Properties					   *
	//******************************************************

	/**
	 * Returns the name of this exception.
	 */
	public function name():String
	{
		return m_name;
	}


	/**
	 * Returns the reason this exception occured.
	 */
	public function reason():String
	{
		return m_reason;
	}


	/**
	 * Returns the user-defined information describing this exception.
	 */
	public function userInfo():Object
	{
		return m_userinfo;
	}


	/**
	 * Sets the reference location for the exception
	 */
	public function setReference(className:String, file:String, line:Number) {
	  var stuff:Array = className.split("::");
	  m_func = stuff[1];
	  m_className = stuff[0];
	  m_line = line;
	}

	//******************************************************
	//*					 Public Methods					   *
	//******************************************************

	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String
	{
		var desc:String = "NSException(\n\t"+m_name + ":\n\t" + m_reason +
			",\n\t" + m_userinfo;

		if (m_arguments != undefined) {
			desc += ",\n\t" + m_arguments.toString();
		}

		desc += "\n\t)";


		if (m_line != undefined) {

			desc += " -- " + m_className+":"+m_line+" ("+m_func+")\n\t ";
		}

		return desc;
	}


	/**
	 * Raises this exception.
	 */
	public function raise():Void
	{
		throw this;
	}


	/**
	 * @see org.actionstep.NSObject#toString
	 */
	public function toString():String
	{
		return description();
	}

	//******************************************************
	//*				 Public Static Methods				   *
	//******************************************************

	/**
	 * Returns an exception named name, with the reason reason, and
	 * additional information userInfo.
	 */
	public static function exceptionWithNameReasonUserInfo(name:String,
		reason:String, userInfo:NSDictionary):NSException
	{
		return (new NSException()).initWithNameReasonUserInfo(name, reason, userInfo);
	}


	/**
	 * Raises an exception named name, using the format format.
	 * 
	 * Please note this name has been changed from raise(), but ActionScript
	 * does not support instance methods sharing the same name as static methods,
	 * so the change was necessary.
	 */
	public static function raiseMessage(name:String, format:String):Void
	{
		var e:NSException = new NSException();
		e.m_name = name;
		e.m_format = format;
		e.raise();
	}


	/**
	 * Raises an exception named name, with the format format and the
	 * arguments arguments. The arguments should be the arguments
	 * of the method that threw this exception.
	 */
	public static function raiseFormatArguments(name:String, format:String,
		arguments:Array):Void
	{
		var e:NSException = new NSException();
		e.m_name = name;
		e.m_format = format;
		e.m_arguments = arguments;
		e.raise();
	}
}
