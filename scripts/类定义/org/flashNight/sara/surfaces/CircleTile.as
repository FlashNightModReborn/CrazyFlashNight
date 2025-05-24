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

import org.flashNight.sara.graphics.*;
import org.flashNight.sara.surfaces.*;
import org.flashNight.sara.primitives.*;
import org.flashNight.sara.DynamicsEngine;

class org.flashNight.sara.surfaces.CircleTile extends AbstractTile implements Surface{

	private var radius:Number;

	public function CircleTile(cx:Number, cy:Number, r:Number, getParent:Function) {		
		super(cx, cy, getParent);
		createBoundingRect(r * 2, r * 2);
		radius = r;
	}
	

	public function paint():Void {
		if (isVisible) {
			dmc.clear();
			dmc.lineStyle(0, 0x222288, 100);
			Graphics.paintCircle(dmc, center.x, center.y, radius);
		}
	}


	public function resolveCircleCollision(p:CircleParticle, sysObj:DynamicsEngine):Void {
		if (isCircleColliding(p)) {
			onContact();
			p.resolveCollision(normal, sysObj);		
		}
	}


	public function resolveRectangleCollision(p:RectangleParticle, sysObj:DynamicsEngine):Void {
		if (isRectangleColliding(p)) {
			onContact();
			p.resolveCollision(normal, sysObj);		
		}
	}
	
	
	private function isCircleColliding(p:CircleParticle):Boolean {
		
		p.getCardXProjection();
		var depthX:Number = testIntervals(p.bmin, p.bmax, minX, maxX);
		if (depthX == 0) return false;
		
		p.getCardYProjection();
		var depthY:Number = testIntervals(p.bmin, p.bmax, minY, maxY);
		if (depthY == 0) return false;
		
		var dx:Number = center.x - p.curr.x;
		var dy:Number = center.y - p.curr.y;
		var len:Number = Math.sqrt(dx * dx + dy * dy);
		var pen:Number = (p.radius + radius) - len;
		
		if (pen > 0) {
			dx /= len;
			dy /= len;
			p.mtd.setTo(-dx * pen, -dy * pen);
			normal.setTo(-dx, -dy);
			return true;
		}
		return false;
	}
	
	
	// TBD: This method is basically identical to the isCircleColliding of the
	// RectangleTile class. Need some type of CollisionResolver class to handle
	// all collisions and move responsibility away from the Surface classes. 
	private function isRectangleColliding(p:RectangleParticle):Boolean {
		
		p.getCardXProjection();
		var depthX:Number = testIntervals(p.bmin, p.bmax, minX, maxX);
		if (depthX == 0) return false;
				
		p.getCardYProjection();
		var depthY:Number = testIntervals(p.bmin, p.bmax, minY, maxY);
		if (depthY == 0) return false;
		
		// determine if the circle's center is in a vertex voronoi region
		var isInVertexX:Boolean = Math.abs(depthX) < radius;
		var isInVertexY:Boolean = Math.abs(depthY) < radius;

		if (isInVertexX && isInVertexY) {

			// get the closest vertex
			var vx:Number = p.curr.x + sign(center.x - p.curr.x) * (p.width / 2);
			var vy:Number = p.curr.y + sign(center.y - p.curr.y) * (p.height / 2);
			p.vertex.setTo(vx, vy);

			// get the distance from the vertex to circle center
			var dx:Number = p.vertex.x - center.x;
			var dy:Number = p.vertex.y - center.y;
			var mag:Number = Math.sqrt(dx * dx + dy * dy);
			var pen:Number = radius - mag;

			// if there is a collision in one of the vertex regions
			if (pen > 0) {
				dx /= mag;
				dy /= mag;
				p.mtd.setTo(dx * pen, dy * pen);
				normal.setTo(dx, dy);
				return true;
			}
			return false;

		} else {
			// collision on one of the 4 edges
			p.setXYMTD(depthX, depthY);
			normal.setTo(p.mtd.x / Math.abs(depthX), p.mtd.y / Math.abs(depthY));
			return true;
		}
	}
	
	// TBD: Put in a util class
	private function sign(val:Number):Number {
		if(val < 0) return -1
		if(val > 0) return 1;
	}
}



