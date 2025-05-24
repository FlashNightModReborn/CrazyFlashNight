/**
 * Sara - Customized Dynamics Engine for FlashNight Game
 * Release based on Flade 0.6 alpha modified for project-specific functionalities
 * Copyright 2004, 2005 Alec Cove
 * Modifications by fs, 2024
 *
 * This file is part of Sara, a customized dynamics engine developed for the FlashNight game project.
 *
 * Sara is free software; you can redistribute it and/or modify it under the terms of the GNU General
 * Public License as published by the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Sara is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
 * implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
 * License for more details.
 *
 * You should have received a copy of the GNU General Public License along with Sara; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 *
 * Flash is a registered trademark of Adobe Systems Incorporated.
 */

import org.flashNight.sara.util.*;
import org.flashNight.sara.DynamicsEngine;


// TBD: extends particle...or rename
class org.flashNight.sara.primitives.RimParticle {
	
	public var curr:Vector;
	public var prev:Vector;
	public var speed:Number;
	public var vs:Number;
	
	private var wr:Number;
	private var maxTorque:Number;	
	
	/**
	 * The RimParticle is really just a second component of the wheel model.
	 * The rim particle is simulated in a coordsystem relative to the wheel's 
	 * center, not in worldspace
	 */
	public function RimParticle(r:Number, mt:Number) {

		curr = new Vector(r, 0);
		prev = new Vector(0, 0);

		vs = 0;			// variable speed
		speed = 0; 		// initial speed
		maxTorque = mt; 	
		wr = r;		
	}

	public function dispose():Void 
	{
		// Clear the Vector properties to help garbage collection
		if (curr) {
			curr = null;
		}
		if (prev) {
			prev = null;
		}
		
		// Since `speed`, `vs`, `wr`, and `maxTorque` are primitive types, they do not require disposal
		// However, if there were any complex objects or event listeners, they should be disposed of here
	}


	// TBD: provide a way to get the worldspace position of the rimparticle
	// either here, or in the wheel class, so it can be used to move other
	// primitives / constraints
	public function verlet(sysObj:DynamicsEngine):Void {

		//clamp torques to valid range
		speed = Math.max(-maxTorque, Math.min(maxTorque, speed + vs));

		//apply torque
		//this is the tangent vector at the rim particle
		var dx:Number = -curr.y;
		var dy:Number =  curr.x;

		//normalize so we can scale by the rotational speed
		var len:Number = Math.sqrt(dx * dx + dy * dy);
		dx /= len;
		dy /= len;

		curr.x += speed * dx;
		curr.y += speed * dy;		

		var ox:Number = prev.x;
		var oy:Number = prev.y;
		var px:Number = prev.x = curr.x;		
		var py:Number = prev.y = curr.y;		

		curr.x += sysObj.coeffDamp * (px - ox);
		curr.y += sysObj.coeffDamp * (py - oy);	

		// hold the rim particle in place
		var clen:Number = Math.sqrt(curr.x * curr.x + curr.y * curr.y);
		var diff:Number = (clen - wr) / clen;

		curr.x -= curr.x * diff;
		curr.y -= curr.y * diff;
	}
	
}
