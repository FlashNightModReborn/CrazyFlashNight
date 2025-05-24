/**
 * Flade - Flash Dynamics Engine
 * Release 0.6 alpha 
 * Wheel class
 * Copyright 2004, 2005 Alec Cove, Raigan Burns (Metanet Software)
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
import org.cove.flade.DynamicsEngine;


class org.cove.flade.primitives.Wheel extends CircleParticle {
							
	public var rp:RimParticle;
	private var coeffSlip:Number;				
	

	public function Wheel(x:Number, y:Number, r:Number) {
	
		super(x,y,r);
		
		// TBD: set max torque?
		// rim particle (radius, max torque)
		rp = new RimParticle(r, 2); 		

		// TBD:Review this for a higher level of friction
		// 1 = totally slippery, 0 = full friction
		coeffSlip = 0.0;	
	}


	public function verlet(sysObj:DynamicsEngine):Void {
		rp.verlet(sysObj);
		super.verlet(sysObj);
	}


	public function resolveCollision(normal:Vector, sysObj:DynamicsEngine):Void {
		super.resolveCollision(normal, sysObj);
		resolve(normal);
	}


	public function paint():Void {
		if (isVisible) {
			// draw wheel circle
			var px:Number = curr.x;
			var py:Number = curr.y;
			var rx:Number = rp.curr.x;
			var ry:Number = rp.curr.y;

			dmc.clear();
			dmc.lineStyle(0, 0x222288, 100);
			Graphics.paintCircle(dmc, px, py, radius);

			// draw rim cross
			dmc.lineStyle(0, 0x999999, 100);
			Graphics.paintLine(dmc, rx + px, ry + py, px, py);
			Graphics.paintLine(dmc, -rx + px, -ry + py, px, py);
			Graphics.paintLine(dmc, -ry + px, rx + py, px, py);
			Graphics.paintLine(dmc, ry + px, -rx + py, px, py);
		}
	}


	public function setTraction(t:Number):Void {
		coeffSlip = t;
	}


	/**
	 * simulates torque/wheel-ground interaction - n is the surface normal
	 */
	private function resolve(n:Vector):Void {

		// this is the tangent vector at the rim particle
		var rx:Number = -rp.curr.y;
		var ry:Number = rp.curr.x;

		// normalize so we can scale by the rotational speed
		var len:Number = Math.sqrt(rx * rx + ry * ry);
		rx /= len;
		ry /= len;

		// sx,sy is the velocity of the wheel's surface relative to the wheel
		var sx:Number = rx * rp.speed;
		var sy:Number = ry * rp.speed;

		// tx,ty is the velocity of the wheel relative to the world
		var tx:Number = curr.x - prev.x;
		var ty:Number = curr.y - prev.y;

		// vx,vy is the velocity of the wheel's surface relative to the ground
		var vx:Number = tx + sx;
		var vy:Number = ty + sy;

		// dp is the the wheel's surfacevel projected onto the ground's tangent
		var dp:Number = -n.y * vx + n.x * vy;

		// set the wheel's spinspeed to track the ground
		rp.prev.x = rp.curr.x - dp * rx;
		rp.prev.y = rp.curr.y - dp * ry;

		// some of the wheel's torque is removed and converted into linear displacement
		var w0:Number = 1 - coeffSlip;
		curr.x += w0 * rp.speed * -n.y;
		curr.y += w0 * rp.speed * n.x;
		rp.speed *= coeffSlip;
	}	
}

