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
import org.flashNight.sara.surfaces.*;
import org.flashNight.sara.primitives.*;
import org.flashNight.sara.constraints.*;
import org.flashNight.sara.composites.*; 

class org.flashNight.sara.DynamicsEngine 
{
    private static var getClipFunc:Function;

	public var gravity:Vector;
	public var coeffRest:Number;
	public var coeffFric:Number;
	public var coeffDamp:Number;	

	public var primitives:Array;
	public var surfaces:Array;
	public var constraints:Array;
	public var composites:Array;

	private var precision:Number;  //每隔几帧进行一次解算
	
	public function DynamicsEngine() 
	{
			
		primitives = new Array();
		surfaces = new Array();
		constraints = new Array();
		composites = new Array();

		// default values
		gravity = new Vector(0,1);	
		coeffRest = 1 + 0.5;
		coeffFric = 0.01;	// surface friction
		coeffDamp = 0.99; 	// global damping
		precision = 1;
	}

	//

	public function setClipFunction(getParent:Function):Void
	{
		getClipFunc = getParent;
	}

	public function getClipFunction():Function
	{
		return getClipFunc;
	}
	
	//

	public function addPrimitive(p:Particle):Void {
		primitives.push(p);
	}

	public function createRectangleParticlePrimitive(px:Number, py:Number, w:Number, h:Number, getParent:Function):RectangleParticle
	{
		var p = new RectangleParticle(px, py, w, h, getParent || getClipFunc);
		addPrimitive(p);
		return p;
	}

	public function createCicleParticlePrimitive(px:Number, py:Number, r:Number, getParent:Function):CircleParticle
	{
		var p = new CircleParticle(px, py, r, getParent || getClipFunc);
		addPrimitive(p);
		return p;
	}


	public function addSurface(s:Surface):Void {
		surfaces.push(s);
	}

	public function createLineSurface(p1x:Number, p1y:Number, p2x:Number, p2y:Number, getParent:Function):LineSurface
	{
		var s = new LineSurface(p1x, p1y, p2x, p2y, getParent || getClipFunc);
		addSurface(s);
		return s;
	}

	public function createCircleTile(cx:Number, cy:Number, r:Number, getParent:Function):CircleTile
	{
		var s = new CircleTile(cx, cy, r, getParent || getClipFunc);
		addSurface(s);
		return s;
	}

	
	public function addConstraint(c:Constraint):Void {
		constraints.push(c);
	}

	public function createSpringConstraint(p1:Particle, p2:Particle, getParent:Function):SpringConstraint
	{
		var c = new SpringConstraint(p1, p2, getParent || getClipFunc);
		addConstraint(c);
		return c;
	}


	//

	public function addComposite(c:Composite):Void {
		composites.push(c);
	}

	public function createSpringBox(px:Number, py:Number, w:Number, h:Number, getParent:Function):SpringBox
	{
		var s = new SpringBox(px, py, w, h, this);
		addComposite(s);
		return s;
	}

	//
	
	
	public function paintSurfaces():Void {
		for (var j:Number = 0; j < surfaces.length; j++) {
			surfaces[j].paint();
		}
	}


	public function paintPrimitives():Void {
		for (var j:Number = 0; j < primitives.length; j++) {
			primitives[j].paint();
		}
	}


	public function paintConstraints():Void {
		for (var j:Number = 0; j < constraints.length; j++) {
			constraints[j].paint();
		}
	}

	
	public function paintComposites():Void {
		for (var j:Number = 0; j < composites.length; j++) {
			composites[j].paint();
		}
	}


	public function timeStep():Void {
		verlet();
		satisfyConstraints();
		checkCollisions();
		synchronization();
	}

	public function removePrimitive(p:Particle):Void {
		var index:Number = primitives.indexOf(p);
		if (index != -1) {
			primitives.splice(index, 1);
		}
	}

	public function disposePrimitive(p:Particle):Void {
		p.dispose(this);
	}

	public function removeSurface(s:Surface):Void {
		var index:Number = surfaces.indexOf(s);
		if (index != -1) {
			surfaces.splice(index, 1);
		}
	}

	public function disposeSurface(s:Surface):Void
	{
		s.dispose(this);  
	}

	public function removeConstraint(c:Constraint):Void {
		var index:Number = constraints.indexOf(c);
		if (index != -1) {
			constraints.splice(index, 1);
		}
	}

	public function disposeConstraint(c:Constraint):Void 
	{
		c.dispose(this);  
	}

	public function removeComposite(c:Composite):Void {
		var index:Number = composites.indexOf(c);
		if (index != -1) {
			composites.splice(index, 1);
		}
	}

	public function disposeComposite(c:Composite):Void
	{
		c.dispose(this);
	}

	
	
	// TBD: Property of surface, not system
	public function setSurfaceBounce(kfr:Number):Void {
		coeffRest = 1 + kfr;
	}
	
	
	// TBD: Property of surface, not system
	public function setSurfaceFriction(f:Number):Void {
		coeffFric = f;
	}


	public function setDamping(d:Number):Void {
		coeffDamp = d;
	}


	public function setGravity(gx:Number, gy:Number):Void {
		gravity.x = gx;
		gravity.y = gy;
	}

	
	private function verlet():Void {
		for (var i:Number = 0; i < primitives.length; i++) {
			primitives[i].verlet(this);		
		}
	}


	private function satisfyConstraints():Void {
		for (var n:Number = 0; n < constraints.length; n++) {
			constraints[n].resolve();
		}
	}

	private function synchronization():Void
	{
		for (var i:Number = 0; i < composites.length; i++) {
			composites[i].synchronize();
			//_root.服务器.发布服务器消息(i);
		}
		//_root.服务器.发布服务器消息(composites.length);
	}


	private function checkCollisions():Void {

		for (var j:Number = 0; j < surfaces.length; j++) {
			var s:Surface = surfaces[j];
			if (s.getActiveState()) {
				for (var i:Number = 0; i < primitives.length; i++) {	
					primitives[i].checkCollision(s, this);
				}
			}
		}
	}	
}
