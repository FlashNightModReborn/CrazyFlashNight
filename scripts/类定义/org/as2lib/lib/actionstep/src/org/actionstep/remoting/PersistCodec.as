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

import org.actionstep.remoting.BitCodec;

class org.actionstep.remoting.PersistCodec {

	/*
		TYPE-BITS =

		- number
			int 	00
			float	010
			NaN		0110
			+Inf	01110
			-Inf	01111

		- array		1000
		- object	101
		- reference 1001

		- boolean
			true	1101
			false	1100

		- string	1110

		- undefined 1111

		DATA =

		- int
			normal	NN [XX|XX|XX]  : 2 bits + 2-6 bits
			medium	1100 + 16 bits
			big		1101 + 32 bits
			negatif 111 + int

		- float
			as a string with :
			string length	5
			character		4
				number 0-9
				dot     10
				plus    11
				minus   12
				exp     13

		- array
			element	0
			jump	10 + int
			end		11

		- object
			key
				0 + index
				10 + string
			end
				11

		- string
			extended	11
			ASCII		10
			B64			0
			len			int
			chars		 7/8

		- reference
			int


	*/

	var bc : BitCodec;
	var fields : Object;
	var fieldtbl : Array;
	var nfields : Number;
	var next_field_bits : Number;
	var nfields_bits : Number;
	var cache : Array;
	var ocache : Array;
	var result : Object;
	var fast : Boolean;

	function PersistCodec() {
	}

	function encode_array(a : Array) {
		var i : Number;
		var njumps : Number = 0;
		for(i=0;i<a.length;i++) {
			if( a[i] == null )
				njumps++;
			else {
				if( njumps > 0 ) {
					bc.write(2,2);
					encode_int(njumps);
					njumps = 0;
				}
				bc.write(1,0);
				do_encode(a[i]);
			}
		}
		bc.write(2,3);
	}

	function decode_array() : Array {
		var a : Array = new Array();
		a.pos = 0;
		ocache.push(a);
		cache.unshift(a);
		return a;
	}

	function decode_array_item(a : Array) : Boolean {
		var elt : Boolean = (bc.read(1) == 0);
		if( elt )
			a[a.pos++] = do_decode();
		else {
			var exit : Boolean = (bc.read(1) == 1);
			if( exit ) {
				delete a.pos;
				return false;
			}
			a.pos += decode_int();
		}
		return true;
	}

	function decode_array_fast() : Array {
		var a : Array = new Array();
		var pos : Number = 0;
		ocache.push(a);
		while( true ) {
			var elt : Boolean = (bc.read(1) == 0);
			if( elt )
				a[pos++] = do_decode();
			else {
				var exit : Boolean = (bc.read(1) == 1);
				if( exit )
					break;
				pos += decode_int();
			}
			if( bc.error_flag )
				break;
		}
		return a;
	}

	function encode_string(s : String) {
		var is_b64 : Boolean = true;
		var is_ascii : Boolean = true;
		var i : Number;
		for(i=0;i<s.length;i++) {
			if( s.charCodeAt(i) > 127 ) {
				is_b64 = false;
				is_ascii = false;
				break;
			} else if( is_b64 ) {
				var c : String = s.charAt(i);
				if( BitCodec.d64(c) == null )
					is_b64 = false;
			}
	 	}
	 	encode_int(s.length);
		if( is_b64 ) {
			bc.write(1,0);
			for(i=0;i<s.length;i++)
				bc.write(6,BitCodec.d64(s.charAt(i)));
 		} else {
			bc.write(2,is_ascii?2:3);
			for(i=0;i<s.length;i++)
				bc.write(is_ascii?7:8,s.charCodeAt(i));
		}
	}

	function decode_string() : String {
		var len : Number = decode_int();
		var is_b64 : Boolean = (bc.read(1) == 0);
		var s : String = "";
		var i : Number;
		if( is_b64 ) {
			for(i=0;i<len;i++)
				s += BitCodec.c64(bc.read(6));
		} else {
			var is_ascii : Boolean = (bc.read(1) == 0);
			for(i=0;i<len;i++)
				s += BitCodec.chr(bc.read(is_ascii?7:8));
		}
		return s;
	}

	function encode_object(o : Object) : Void {
		var k : String;
		for( k in o )
			encode_object_field(k,o[k]);
		bc.write(2,3);
	}

	function encode_object_field(k : String,d : Object) : Void {
		if( typeof(d) != "function" && d != null ) {
			if( fields[k] != null ) {
				bc.write(1,0);
				bc.write(nfields_bits,fields[k]);
			} else {
				fields[k] = nfields++;
				if( nfields >= next_field_bits ) {
					nfields_bits++;
					next_field_bits *= 2;
				}
				bc.write(2,2);
				encode_string(k);
			}
			do_encode(d);
		}
	}

	function decode_object_fast() : Object {
		var o : Object = new Object();
		ocache.push(o);
		while( true ) {
			var k : String;
			var is_field_index : Boolean = (bc.read(1) == 0);
			if( is_field_index )
				k = fieldtbl[bc.read(nfields_bits)];
			else {
				var is_end : Boolean = (bc.read(1) == 1);
				if( is_end )
					break;
				k = decode_string();
				fieldtbl[nfields++] = k;
				if( nfields >= next_field_bits ) {
					nfields_bits++;
					next_field_bits *= 2;
				}
			}
			o[k] = do_decode();
			if( bc.error_flag )
				break;
		}
		return o;
	}


	function decode_object() : Object {
		var o : Object = new Object();
		ocache.push(o);
		cache.unshift(o);
		return o;
	}

	function decode_object_field(o : Object) : Boolean {
		var k : String;
		var is_field_index : Boolean = (bc.read(1) == 0);

		if( is_field_index )
			k = fieldtbl[bc.read(nfields_bits)];
		else {
			var is_end : Boolean = (bc.read(1) == 1);
			if( is_end )
				return false;
			k = decode_string();
			fieldtbl[nfields++] = k;
			if( nfields >= next_field_bits ) {
				nfields_bits++;
				next_field_bits *= 2;
			}
		}
		o[k] = do_decode();
		return true;
	}

	function encode_int(o : Number) : Void {
		if( o < 0 ) {
			bc.write(3,7);
			encode_int(-o);
		} else if( o < 4 ) {
			bc.write(2,0);
			bc.write(2,o);
		} else if( o < 16 ) {
			bc.write(2,1);
			bc.write(4,o);
		} else if( o < 64 ) {
			bc.write(2,2);
			bc.write(6,o);
		} else if( o < 65536 ) {
			bc.write(4,12);
			bc.write(16,o);
		} else {
			bc.write(4,13);
			bc.write(16,o & 0xFFFF);
			bc.write(16,(o >> 16) & 0xFFFF);
		}
	}

	function decode_int() : Number {
		var nbits : Number = bc.read(2);
		if( nbits == 3 ) {
			var is_neg : Boolean = (bc.read(1) == 1);
			if( is_neg )
				return -decode_int();
			var is_big : Boolean = (bc.read(1) == 1);
			if( is_big ) {
				var n : Number = bc.read(16);
				var n2 : Number = bc.read(16);
				return n | (n2 << 16);
			} else
				return bc.read(16);
		}
		return bc.read((nbits+1)*2);
	}

	function encode_float(o : Number) {
		var s : String = String(o);
		var l : Number = s.length;
		var i : Number;
		bc.write(5,l);
		for(i=0;i<l;i++) {
			var c : Number = s.charCodeAt(i);
			if( c >= 48 && c <= 58 ) // 0 - 9
				bc.write(4,c-48);
			else if( c == 46 ) // '.'
				bc.write(4,10);
			else if( c == 43 ) // '+'
				bc.write(4,11);
			else if( c == 45 ) // '-'
				bc.write(4,12);
			else // 'e'
				bc.write(4,13);
		}
	}

	function decode_float() : Number {
		var l : Number = bc.read(5);
		var i : Number;
		var s : String = "";
		for(i=0;i<l;i++) {
			var k : Number = bc.read(4);
			if( k < 10 )
				k += 48;
			else switch( k ) {
			case 10: k = 46; break;
			case 11: k = 43; break;
			case 12: k = 45; break;
			default: k = 101; break;
			}
			s += String.fromCharCode(k);
		}
		return parseFloat(s);
	}

	function encode_ref(o : Object) {
		var i;
		var l = ocache.length;
		for(i=0;i<l;i++) {
			if( ocache[i] == o ) {
				bc.write(4,9);
				encode_int(i);
				return true;
			}
		}
		ocache.push(o);
		return false;
	}

	function do_encode(o : Object) : Boolean {
		if( o == null )
			bc.write(4,15);
		else if( o instanceof Array ) {
			if( !encode_ref(o) ) {
				bc.write(4,8);
				encode_array(Array(o));
			}
		} else switch( typeof(o) ) {
		case "string":
			bc.write(4,14);
			encode_string(String(o));
			break;
		case "number":
			if( isNaN(o) )
				bc.write(4,6);
			else if( o == Infinity )
				bc.write(5,14);
			else if( o == -Infinity )
				bc.write(5,15);
			else if( int(o) == o ) {
				bc.write(2,0);
				encode_int(Number(o));
			} else {
				bc.write(3,2);
				encode_float(Number(o));
			}
			break;
		case "boolean":
			if( o )
				bc.write(4,13);
			else
				bc.write(4,12);
			break;
		default:
			if( !encode_ref(o) ) {
				bc.write(3,5);
				encode_object(o);
			}
			break;
		}
		return true;
	}

	function do_decode() : Object {
		var is_number : Boolean = (bc.read(1) == 0);
		if( is_number ) {
			var is_float : Boolean = (bc.read(1) == 1);
			if( is_float ) {
				var is_special : Boolean = (bc.read(1) == 1);
				if( is_special ) {
					var is_infinity : Boolean = (bc.read(1) == 1);
					if( is_infinity ) {
						var is_negative : Boolean = (bc.read(1) == 1);
						if( is_negative )
							return -Infinity;
						else
							return Infinity;
						return null;
					} else
						return NaN;
				} else
					return decode_float();
			} else
				return decode_int();
		}
		var is_array_obj : Boolean = (bc.read(1) == 0);
		if( is_array_obj ) {
			var is_obj : Boolean = (bc.read(1) == 1);
			if( is_obj )
				return (fast?decode_object_fast():decode_object());
			else {
				var is_ref : Boolean = (bc.read(1) == 1);
				if( is_ref )
					return ocache[decode_int()];
				else
					return (fast?decode_array_fast():decode_array());
			}
		}
		var tflag : Number = bc.read(2);
		if( tflag == 0 )
			return false;
		else if( tflag == 1 )
			return true;
		else if( tflag == 2 )
			return decode_string();
		else
			return null;
	}

	function encodeInit( o : Object ) {
		fast = false;
		bc = new BitCodec();
		fields = new Object();
		nfields = 0;
		next_field_bits = 1;
		nfields_bits = 0;
		cache = new Array();
		ocache = new Array();
		cache.push(o);
 	}

 	function encodeLoop() : Boolean {
		if( cache.length == 0 )
			return true;
		do_encode(cache.shift());
		return false;
	}

	function encodeEnd() : String {
		return bc.toString();
	}

	function encode(o : Object) : String {
		encodeInit(o);
		fast = true;
		while( encodeLoop() ) {
		}
		return encodeEnd();
	}

	function progress() : Number {
		return bc.in_pos * 100 / bc.data.length;
	}

 	function decodeInit( data : String ) {
		fast = false;
		bc = new BitCodec();
		bc.setData(data);
		fieldtbl = new Array();
		nfields = 0;
		next_field_bits = 1;
		nfields_bits = 0;
		cache = new Array();
		ocache = new Array();
		result = null;
	}

	function decodeLoop() : Boolean {
		if( cache.length == 0 )
			result = do_decode();
		else {
			var o : Array = cache[0];
			if( o instanceof Array ) {
				if( !decode_array_item(o) )
					cache.shift();
			} else {
				if( !decode_object_field(o) ) {
					delete o.pos;
					cache.shift();
				}
			}
		}
		if( bc.error_flag ) {
			result = null;
			return false;
		}
		return (cache.length != 0);
	}

	function decodeEnd() : Object {
		return result;
	}

	function decode( data : String ) : Object {
		decodeInit(data);
		fast = true;
		while( decodeLoop() ) {
		}
		return decodeEnd();
	}


}
