/**
 * Flade - Flash Dynamics Engine
 * Release 0.6 alpha 
 * Vector class
 * Copyright 2004, 2005 Alec Cove
 * 
 * This file is part of Flade. The Flash Dynamics Engine. 
 *	
 * Flade is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Flade is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Flade; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 * Flash is a registered trademark of Macromedia
 */

class org.cove.flade.util.Vector {
	
	public var x:Number;
	public var y:Number;


	public function Vector(px:Number, py:Number) {
		x = px;
		y = py;
	}
	
	
	public function setTo(px:Number, py:Number):Void {
		x = px;
		y = py;
	}
	
	
	public function copy(v:Vector):Void {
		x = v.x;
		y = v.y;
	}


	public function dot(v:Vector):Number {
		return x * v.x + y * v.y;
	}
	
	
	public function cross(v:Vector):Number {
		return x * v.y - y * v.x;
	}
	
	
	public function plus(v:Vector):Vector {
		x += v.x;
		y += v.y;
		return this;
	}
	

	public function plusNew(v:Vector):Vector {
		return new Vector(x + v.x, y + v.y); 
	}
	

	public function minus(v:Vector):Vector {
		x -= v.x;
		y -= v.y;
		return this;
	}
	

	public function minusNew(v:Vector):Vector {
		return new Vector(x - v.x, y - v.y);    
	}


	public function mult(s:Number):Vector {
		x *= s;
		y *= s;
		return this;
	}


	public function multNew(s:Number):Vector {
		return new Vector(x * s, y * s);
	}

	
	public function distance(v:Vector):Number {
		var dx:Number = x - v.x;
		var dy:Number = y - v.y;
		return Math.sqrt(dx * dx + dy * dy);
	}


	public function normalize():Vector {
	   var mag:Number = Math.sqrt(x * x + y * y);
	   x /= mag;
	   y /= mag;
	   return this;
	}	
	
	
	public function magnitude():Number {
		return Math.sqrt(x * x + y * y);
	}


	/**
	 * projects this vector onto b
	 */
	public function project(b:Vector):Vector {
		var adotb:Number = this.dot(b);
		var len:Number = (b.x * b.x + b.y * b.y);
		
		var proj:Vector = new Vector(0,0);
		proj.x = (adotb / len) * b.x;
		proj.y = (adotb / len) * b.y;
		return proj;
	}
}

