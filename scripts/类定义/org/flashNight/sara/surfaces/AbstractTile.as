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
import org.flashNight.sara.primitives.*;
import org.flashNight.sara.DynamicsEngine;
import org.flashNight.sara.util.Vector;
import org.flashNight.sara.util.MovieClipUtils;
import org.flashNight.sara.surfaces.Surface;


// TBD: need to clarify responsibilites between the Surface interface and the AbstractTile
class org.flashNight.sara.surfaces.AbstractTile implements Surface{
	
	private var minX:Number;
	private var minY:Number;
	private var maxX:Number;
	private var maxY:Number;
	private var verts:Array;
	
	private var center:Vector;
	private var normal:Vector;
	
	private var dmc:MovieClip;
	private var isVisible:Boolean;
	private var isActivated:Boolean;
	

	public function AbstractTile(cx:Number, cy:Number, getParent:Function) {
	 	center = new Vector(cx, cy);
	 	verts = new Array();
	 	normal = new Vector(0,0);
	 	
	 	isActivated = true;
	 	if(getParent)
		{
			initializeContainer(getParent);
			isVisible = true;
		}
		else
		{
			isVisible = false;
		}
	}


	public function initializeContainer(getParent:Function):Void {
		if(getParent)
		{
			dmc = MovieClipUtils.createClipWithCustomParent(getParent);
		}
		else
		{
			dmc = MovieClipUtils.createEmptyClipWithAutoName();
		}
	}

	public function dispose(e:DynamicsEngine):Void {
		// Dispose of the MovieClip to free graphical resources
		if (dmc) {
			dmc.removeMovieClip();
			dmc = null;
		}

		// Clear the vertices array and its Vector elements
		if (verts) {
			for (var i:Number = 0; i < verts.length; i++) {
				verts[i] = null;
			}
			verts = null;
		}

		// Set vector properties to null to help garbage collection
		if (center) {
			center = null;
		}
		if (normal) {
			normal = null;
		}

		// Reset visibility and activation states
		isVisible = false;
		isActivated = false;

		e.removeSurface(this);
	}



	//TBD:Issues relating to painting, mc's, and visibility could be 
	//centralized somehow, base class, etc.
	public function paint():Void
	{
		
	}

	public function resolveCircleCollision(p:CircleParticle, sysObj:DynamicsEngine):Void
	{

	}


	public function resolveRectangleCollision(p:RectangleParticle, sysObj:DynamicsEngine):Void
	{

	}


	public function setVisible(v:Boolean):Void {
		isVisible = v;
	}


	public function setActiveState(a:Boolean):Void {
		isActivated = a;
	}


	public function getActiveState():Boolean {
		return isActivated;
	}
	
	
	public function createBoundingRect(rw:Number, rh:Number) { 
				
		var t:Number = center.y - rh/2;
		var b:Number = center.y + rh/2;
		var l:Number = center.x - rw/2;
		var r:Number = center.x + rw/2;
		
		verts.push(new Vector(r,b));
		verts.push(new Vector(r,t));
		verts.push(new Vector(l,t));
		verts.push(new Vector(l,b));
		setCardProjections();
	}


	public function testIntervals(
			boxMin:Number, 
			boxMax:Number, 
			tileMin:Number, 
			tileMax:Number):Number {

		// returns 0 if intervals do not overlap. Returns depth if they do overlap
		if (boxMax < tileMin) return 0;
		if (tileMax < boxMin) return 0;

		// return the smallest translation
		var depth1:Number = tileMax - boxMin;
		var depth2:Number = tileMin - boxMax;

		if (Math.abs(depth1) < Math.abs(depth2)) {
			return depth1;
		} else {
			return depth2;
		}
	}


	public function setCardProjections():Void {
		getCardXProjection();
		getCardYProjection();
	}


	// get projection onto a cardinal (world) axis x 
	// TBD: duplicate methods (with different implementation) in 
	// in the Particle base class. 
	public function getCardXProjection():Void {

		minX = verts[0].x;
		for (var i:Number = 1; i < verts.length; i++) {
			if (verts[i].x < minX) {
				minX = verts[i].x;
			}
		}

		maxX = verts[0].x;
		for (var i:Number = 1; i < verts.length; i++) {
			if (verts[i].x > maxX) {
				maxX = verts[i].x;
			}
		}
	}


	// get projection onto a cardinal (world) axis y 
	// TBD: duplicate methods (with different implementation) in 
	// in the Particle base class. 
	public function getCardYProjection():Void {

		minY = verts[0].y;
		for (var i:Number = 1; i < verts.length; i++) {
			if (verts[i].y < minY) {
				minY = verts[i].y;
			}
		}

		maxY = verts[0].y;
		for (var i:Number = 1; i < verts.length; i++) {
			if (verts[i].y > maxY) {
				maxY = verts[i].y;
			}
		}
	}
	
	
	// empty holder for the onContact event
	public function onContact() {
	}

}
