/**
 * Flade - Flash Dynamics Engine
 * Release 0.6 alpha 
 * SpringBox class
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

import org.cove.flade.DynamicsEngine;
import org.cove.flade.primitives.RectangleParticle;
import org.cove.flade.constraints.SpringConstraint;


class org.cove.flade.composites.SpringBox {
	
	public var p0:RectangleParticle;
	public var p1:RectangleParticle;
	public var p2:RectangleParticle;
	public var p3:RectangleParticle;
	
	public function SpringBox (
			px:Number, 
			py:Number, 
			w:Number, 
			h:Number, 
			engine:DynamicsEngine) {

		// top left
		p0 = new RectangleParticle(px - w / 2, py - h / 2, 1, 1);
		// top right
		p1 = new RectangleParticle(px + w / 2, py - h / 2, 1, 1);
		// bottom right
		p2 = new RectangleParticle(px + w / 2, py + h / 2, 1, 1);
		// bottom left
		p3 = new RectangleParticle(px - w / 2, py + h / 2, 1, 1);
		
		p0.setVisible(false);
		p1.setVisible(false);
		p2.setVisible(false);
		p3.setVisible(false);
		
		engine.addPrimitive(p0);
		engine.addPrimitive(p1);
		engine.addPrimitive(p2);
		engine.addPrimitive(p3);

		// edges
		engine.addConstraint(new SpringConstraint(p0, p1));
		engine.addConstraint(new SpringConstraint(p1, p2));
		engine.addConstraint(new SpringConstraint(p2, p3));
		engine.addConstraint(new SpringConstraint(p3, p0));

		// crossing braces
		engine.addConstraint(new SpringConstraint(p0, p2));
		engine.addConstraint(new SpringConstraint(p1, p3));
	}
}