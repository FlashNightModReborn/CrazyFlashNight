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
 
import org.flashNight.sara.surfaces.*;
import org.flashNight.sara.graphics.*;
import org.flashNight.sara.primitives.*;
import org.flashNight.sara.DynamicsEngine;


class org.flashNight.sara.surfaces.RectangleTile extends AbstractTile implements Surface {

	private var rectWidth:Number;
	private var rectHeight:Number;
	
	
	public function RectangleTile(cx:Number, cy:Number, rw:Number, rh:Number, getParent:Function) {
		
		super(cx, cy, getParent);
		rectWidth = rw;
		rectHeight = rh;	
		createBoundingRect(rw, rh);
	}


	public function paint():Void {
		if(isVisible) {
			dmc.clear();
			dmc.lineStyle(0, 0x222288, 100);
			Graphics.paintRectangle(dmc, center.x, center.y, rectWidth, rectHeight);
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

		// determine if the circle's center is in a vertex voronoi region
		var isInVertexX:Boolean = Math.abs(depthX) < p.radius;
		var isInVertexY:Boolean = Math.abs(depthY) < p.radius;

		if (isInVertexX && isInVertexY) {
			
			// get the closest vertex
			var vx:Number = center.x + sign(p.curr.x - center.x) * (rectWidth / 2);
			var vy:Number = center.y + sign(p.curr.y - center.y) * (rectHeight / 2);
			
			// get the distance from the vertex to circle center
			var dx:Number = p.curr.x - vx;
			var dy:Number = p.curr.y - vy;
    		var mag:Number = Math.sqrt(dx * dx + dy * dy);
			var pen:Number = p.radius - mag;
			
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
	
	
	private function isRectangleColliding(p:RectangleParticle):Boolean {
		
		p.getCardXProjection();
		var depthX:Number = testIntervals(p.bmin, p.bmax, minX, maxX);
		if (depthX == 0) return false;

		p.getCardYProjection();
		var depthY:Number = testIntervals(p.bmin, p.bmax, minY, maxY);
		if (depthY == 0) return false;
		
		p.setXYMTD(depthX, depthY);
		normal.setTo(p.mtd.x / Math.abs(depthX), p.mtd.y / Math.abs(depthY));
		return true
	}
	
	
	// TBD: Put in a util class
	private function sign(val:Number):Number {
		if(val < 0) return -1
		if(val > 0) return 1;
	}
	
}


		
		
	

