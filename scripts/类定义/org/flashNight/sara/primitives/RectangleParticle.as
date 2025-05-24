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
 
class org.flashNight.sara.primitives.RectangleParticle extends Particle {

	public var width:Number;
	public var height:Number;
	public var vertex:Vector;
	
	public function RectangleParticle(px:Number, py:Number, w:Number, h:Number, getParent:Function) {
		
		super(px, py, getParent);
		width = w;
		height = h;
		
		vertex = new Vector(0, 0);
		extents = new Vector(w/2, h/2);
	}

	public function dispose(e:DynamicsEngine):Void {
		// Call the dispose method of the base class (Particle) to clean up base properties
		super.dispose(e);
		
		// Clear RectangleParticle specific properties
		if (vertex) {
			vertex = null;
		}
		
		// The properties 'width' and 'height' are simple numeric values and don't require special disposal
	}

	
	
	public function paint():Void {
		if (isVisible) {
			dmc.clear();
			dmc.lineStyle(0, 0x666666, 100);
			Graphics.paintRectangle(dmc, curr.x, curr.y, width, height);
		}
	}


	public function checkCollision(surface:Surface, sysObj:DynamicsEngine):Void {
		surface.resolveRectangleCollision(this, sysObj);
	}

}


