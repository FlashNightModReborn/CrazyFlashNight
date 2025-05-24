/**
 * Flade - Flash Dynamics Engine
 * Release 0.6 alpha 
 * Graphics class
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


//TBD: rename this to reflect its vector and/or default nature
class org.cove.flade.graphics.Graphics {

	public static function paintLine (
			dmc:MovieClip, 
			x0:Number, 
			y0:Number, 
			x1:Number, 
			y1:Number):Void {
		
		dmc.moveTo(x0, y0);
		dmc.lineTo(x1, y1);
	}


	public static function paintCircle (dmc:MovieClip, x:Number, y:Number, r:Number):Void {

		var mtp8r:Number = Math.tan(Math.PI/8) * r;
		var msp4r:Number = Math.sin(Math.PI/4) * r;

		with (dmc) {
			moveTo(x + r, y);
			curveTo(r + x, mtp8r + y, msp4r + x, msp4r + y);
			curveTo(mtp8r + x, r + y, x, r + y);
			curveTo(-mtp8r + x, r + y, -msp4r + x, msp4r + y);
			curveTo(-r + x, mtp8r + y, -r + x, y);
			curveTo(-r + x, -mtp8r + y, -msp4r + x, -msp4r + y);
			curveTo(-mtp8r + x, -r + y, x, -r + y);
			curveTo(mtp8r + x, -r + y, msp4r + x, -msp4r + y);
			curveTo(r + x, -mtp8r + y, r + x, y);
		}
	}
	
	
	public static function paintRectangle(
			dmc:MovieClip, 
			x:Number, 
			y:Number, 
			w:Number, 
			h:Number):Void {
		
		var w2:Number = w/2;
		var h2:Number = h/2;
		
		with (dmc) {
			moveTo(x - w2, y - h2);
			lineTo(x + w2, y - h2);
			lineTo(x + w2, y + h2);
			lineTo(x - w2, y + h2);
			lineTo(x - w2, y - h2);
		}
	}
}
