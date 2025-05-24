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
import org.flashNight.sara.graphics.*;
import org.flashNight.sara.surfaces.Surface;
import org.flashNight.sara.primitives.Particle;
import org.flashNight.sara.DynamicsEngine;
 
class org.flashNight.sara.primitives.CircleParticle extends Particle {

	public var radius:Number;
	public var closestPoint:Vector;
	public var contactRadius:Number;
	
	
	public function CircleParticle(px:Number, py:Number, r:Number, getParent:Function) {
		super(px, py, getParent);
		radius = r;
		contactRadius = r;
		
		extents = new Vector(r, r); 
		closestPoint = new Vector(0,0);
	}

	public function dispose(e:DynamicsEngine):Void {
		// Call the dispose method of the base class (Particle)
		super.dispose(e);
		
		// Clear CircleParticle specific properties
		if (closestPoint) {
			closestPoint = null;
		}

		// Additional properties specific to CircleParticle can be cleaned here
		// Currently, 'radius' and 'contactRadius' do not require disposal as they are simple data types (Number)
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


