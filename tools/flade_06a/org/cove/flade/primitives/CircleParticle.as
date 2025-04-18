/**
 * Flade - Flash Dynamics Engine
 * Release 0.6 alpha 
 * CircleParticle class
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
import org.cove.flade.surfaces.Surface;
import org.cove.flade.primitives.Particle;
import org.cove.flade.DynamicsEngine;
 
class org.cove.flade.primitives.CircleParticle extends Particle {

	public var radius:Number;
	public var closestPoint:Vector;
	public var contactRadius:Number;
	
	
	public function CircleParticle(px:Number, py:Number, r:Number) {
		super(px, py);
		radius = r;
		contactRadius = r;
		
		extents = new Vector(r, r); 
		closestPoint = new Vector(0,0);
	}
	
	
	public function paint():Void {
		dmc.clear();
		dmc.lineStyle(0, 0x666666, 100);
		Graphics.paintCircle(dmc, curr.x, curr.y, radius);
	}


	public function checkCollision(surface:Surface, sysObj:DynamicsEngine):Void {
		surface.resolveCircleCollision(this, sysObj);
	}

}


