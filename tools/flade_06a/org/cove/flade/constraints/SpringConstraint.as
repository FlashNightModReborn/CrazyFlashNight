/**
 * Flade - Flash Dynamics Engine
 * Release 0.6 alpha 
 * SpringConstraint class
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
 
import org.cove.flade.util.*;
import org.cove.flade.graphics.*;
import org.cove.flade.primitives.*;
import org.cove.flade.constraints.*;

class org.cove.flade.constraints.SpringConstraint implements Constraint{
	
	private var p1:Particle;
	private var p2:Particle;
	private var restLength:Number;
	private var tearLength:Number;
	
	private var color:Number;
	private var stiffness:Number;
	private var isVisible:Boolean;

	private var dmc:MovieClip;


	public function SpringConstraint(p1:Particle, p2:Particle) {

		this.p1 = p1;
		this.p2 = p2;
		restLength = p1.curr.distance(p2.curr);
	
		stiffness = 0.5;
		color = 0x996633;
		
		initializeContainer();
		isVisible = true;
	}
	
	
	public function initializeContainer():Void {
		var depth:Number = _root.getNextHighestDepth();
		var drawClipName:String = "_" + depth;
		dmc = _root.createEmptyMovieClip (drawClipName, depth);
	}


	public function resolve():Void {

		var delta:Vector = p1.curr.minusNew(p2.curr);
		var deltaLength:Number = p1.curr.distance(p2.curr);

		var diff:Number = (deltaLength - restLength) / deltaLength;
		var dmd:Vector = delta.mult(diff * stiffness);

		p1.curr.minus(dmd);
		p2.curr.plus(dmd);
	}


	public function setRestLength(r:Number):Void {
		restLength = r;
	}


	public function setStiffness(s:Number):Void {
		stiffness = s;
	}


	public function setVisible(v:Boolean):Void {
		isVisible = v;
	}


	public function paint():Void {
		
		if (isVisible) {
			dmc.clear();
			dmc.lineStyle(0, color, 100);

			Graphics.paintLine(
					dmc, 
					p1.curr.x, 
					p1.curr.y, 
					p2.curr.x, 
					p2.curr.y);
		}
	}
}