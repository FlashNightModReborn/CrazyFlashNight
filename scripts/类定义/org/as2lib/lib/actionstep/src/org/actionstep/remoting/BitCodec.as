/*
 * Copyright (c) 2005, Motion-Twin
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

class org.actionstep.remoting.BitCodec {
	var error_flag : Boolean;
	var nbits : Number;
	var bits : Number;
	var data : String;
	var in_pos : Number;

	function BitCodec() {
		setData("");
	}

	function setData( d : String ) {
		error_flag = false;
		data = d;
		in_pos = 0;
		nbits = 0;
		bits = 0;
	}

	function read( n : Number ) : Number {
		while(nbits < n) {
			var c : Number = d64(data.charAt(in_pos++));
			if( in_pos > data.length || c == null ) {
				error_flag = true;
				return -1;
			}
			nbits += 6;
			bits <<= 6;
			bits |= c;
		}
		nbits -= n;
		var k = (bits >> nbits) & ((1 << n) - 1);
		return k;
	}

	function nextPart() {
		nbits = 0;
	}

	function hasError() : Boolean {
		return error_flag;
	}

	function toString() : String {
		if( nbits > 0 )
			write(6-nbits,0);
		return data;
	}

	function write( n : Number, b : Number ) {
		nbits += n;
		bits <<= n;
		bits |= b;
		while(nbits >= 6) {
			nbits -= 6;
			data += c64((bits >> nbits) & 63);
		}
	}

	static function ord( code : String ) : Number {
		return code.charCodeAt(0);
	}

	static function chr( code : Number ) : String {
		return String.fromCharCode(code);
	}

	static function d64( code : String ) : Number {
		if( code >= "a" && code <= "z" )
			return ord(code) - ord("a");
		if( code >= "A" && code <= "Z" )
			return ord(code) - ord("A") + 26;
		if( code >= "0" && code <= "9" )
			return ord(code) - ord("0") + 52;
		if( code == "-")
			return 62;
		if( code == "_" )
			return 63;
		return null;
	}

	static function c64( code : Number ) : String {
		if( code < 0 )
			return "?";
		if( code < 26 )
			return chr(code+ord("a"));
		if( code < 52 )
			return chr((code-26)+ord("A"));
		if( code < 62 )
			return chr((code-52)+ord("0"));
		if( code == 62 )
			return "-";
		if( code == 63 )
			return "_";
		return "?";
	}

}