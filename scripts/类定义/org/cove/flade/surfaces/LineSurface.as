/**
 * Flade - Flash Dynamics Engine
 * Release 0.6 alpha 
 * LineSurface class
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
 
import org.cove.flade.util.*
import org.cove.flade.graphics.*;
import org.cove.flade.surfaces.*;
import org.cove.flade.primitives.*;
import org.cove.flade.DynamicsEngine;

//TBD: this class should be replaced by a rotateable RectangleTile or Capsule (or both)
class org.cove.flade.surfaces.LineSurface extends AbstractTile implements Surface {

	private var p1:Vector;
	private var p2:Vector;
	private var p3:Vector;
	private var p4:Vector;
	private var faceNormal:Vector;
	private var sideNormal:Vector;
	private var collNormal:Vector;
	
	private var rise:Number;
	private var run:Number;
	
	private var invB:Number;
	private var sign:Number;
	private var slope:Number;
	
	private var minF:Number;
	private var maxF:Number;
	private var minS:Number;
	private var maxS:Number;
	private var collisionDepth:Number;
	

	public function LineSurface(p1x:Number, p1y:Number, p2x:Number, p2y:Number) {

		super(0,0);
		p1 = new Vector(p1x, p1y);
		p2 = new Vector(p2x, p2y);
		
		calcFaceNormal();
		collNormal = new Vector(0,0);
		setCollisionDepth(30);
	}

		
	public function paint():Void {	
		if (isVisible) {
			dmc.clear();
			dmc.lineStyle(0, 0x222288, 100);
			Graphics.paintLine(dmc, p1.x, p1.y, p2.x, p2.y);
		}
	}
	
	
	public function resolveCircleCollision(p:CircleParticle, sysObj:DynamicsEngine):Void {
		if (isCircleColliding(p)) {
			onContact();
			p.resolveCollision(faceNormal, sysObj);
		}
	}


	public function resolveRectangleCollision(p:RectangleParticle, sysObj:DynamicsEngine):Void {
		if (isRectangleColliding(p)) {
			onContact();
			p.resolveCollision(collNormal, sysObj);
		}
	}


	public function setCollisionDepth(d:Number) {
		collisionDepth = d;
		precalculate();
	}
	
	
	private function isCircleColliding(p:CircleParticle):Boolean {

		// find the closest point on the surface to the CircleParticle
		findClosestPoint(p.curr, p.closestPoint);

		// get the normal of the circle relative to the location of the closest point
		var circleNormal:Vector = p.closestPoint.minusNew(p.curr);
		circleNormal.normalize();
		
		// if the center of the circle has broken the line keep the normal from 'flipping'
		// to the opposite direction. for small circles, this prevents break-throughs
		if (inequality(p.curr)) {
			var absCX:Number = Math.abs(circleNormal.x);
			circleNormal.x = (faceNormal.x < 0) ? absCX : -absCX
			circleNormal.y = Math.abs(circleNormal.y);
		}
		
		// get contact point on edge of circle
		var contactPoint:Vector = p.curr.plusNew(circleNormal.mult(p.radius));
		if (segmentInequality(contactPoint)) {
			
			if (contactPoint.distance(p.closestPoint) > collisionDepth) {
				return false;
			}
			var dx:Number = contactPoint.x - p.closestPoint.x;
			var dy:Number = contactPoint.y - p.closestPoint.y;
			p.mtd.setTo(-dx, -dy);
			return true;
		}
		return false;
	}


	private function isRectangleColliding(p:RectangleParticle):Boolean {
		
		p.getCardYProjection();
		var depthY:Number = testIntervals(p.bmin, p.bmax, minY, maxY);
		if (depthY == 0) return false;
		
		p.getCardXProjection();
		var depthX:Number = testIntervals(p.bmin, p.bmax, minX, maxX);
		if (depthX == 0) return false;
		
		p.getAxisProjection(sideNormal);
		var depthS:Number = testIntervals(p.bmin, p.bmax, minS, maxS);
		if (depthS == 0) return false;
		
		p.getAxisProjection(faceNormal);
		var depthF:Number = testIntervals(p.bmin, p.bmax, minF, maxF);
		if (depthF == 0) return false;
				
		var absX:Number = Math.abs(depthX);
		var absY:Number = Math.abs(depthY);
		var absS:Number = Math.abs(depthS);
		var absF:Number = Math.abs(depthF);
			
		if (absX <= absY && absX <= absS && absX <= absF) {
			p.mtd.setTo(depthX, 0);
			collNormal.setTo(p.mtd.x / absX, 0);
		} else if (absY <= absX && absY <= absS && absY <= absF) {
			p.mtd.setTo(0, depthY);
			collNormal.setTo(0, p.mtd.y / absY);
		} else if (absF <= absX && absF <= absY && absF <= absS) {
			p.mtd = faceNormal.multNew(depthF);
			collNormal.copy(faceNormal);
		} else if (absS <= absX && absS <= absY && absS <= absF) {
			p.mtd = sideNormal.multNew(depthS);
			collNormal.copy(sideNormal);
		}
		return true;
	}
	
	
	private function precalculate():Void {
		// precalculations for circle collision
		rise = p2.y - p1.y;
		run = p2.x - p1.x;
		
		// TBD: sign is a quick bug fix, needs to be review
		sign = (run >= 0) ? 1 :-1;
		slope = rise / run;
		invB = 1 / (run * run + rise * rise);
			
		// precalculations for rectangle collision
		createRectangle();
		calcSideNormal();
		setCardProjections();
		setAxisProjections();
	}
	
	
	private function calcFaceNormal():Void {
		faceNormal = new Vector(0,0);
		var dx:Number = p2.x - p1.x;
		var dy:Number = p2.y - p1.y;
		faceNormal.setTo(dy, -dx);
		faceNormal.normalize();
	}


	private function segmentInequality(toPoint:Vector):Boolean {
		var u:Number = findU(toPoint);
		var isUnder:Boolean = inequality(toPoint);
		return (u >= 0 && u <= 1 && isUnder);
	}


	private function inequality(toPoint:Vector):Boolean {	
		// TBD: sign is a quick bug fix, needs to be review
		var line:Number = (slope * (toPoint.x - p1.x) + (p1.y - toPoint.y)) * sign;
		return (line <= 0);
	}


	private function findClosestPoint(toPoint:Vector, returnVect:Vector):Void {

		var u:Number = findU(toPoint);
		if (u <= 0) {
			returnVect.copy(p1);
			return;
		}
		
		if (u >= 1) {
			returnVect.copy(p2);
			return;
		}

		var x:Number = p1.x + u * (p2.x - p1.x);
		var y:Number = p1.y + u * (p2.y - p1.y);
		returnVect.setTo(x,y);
	}


	private function findU(p:Vector):Number {
		var a:Number = (p.x - p1.x) * run + (p.y - p1.y) * rise;
		return a * invB;
	}
	
	
	private function createRectangle():Void {
		
		var p3x:Number = p2.x + -faceNormal.x * collisionDepth;
		var p3y:Number = p2.y + -faceNormal.y * collisionDepth;
		
		var p4x:Number = p1.x + -faceNormal.x * collisionDepth;
		var p4y:Number = p1.y + -faceNormal.y * collisionDepth;
		
		p3 = new Vector(p3x, p3y);
		p4 = new Vector(p4x, p4y);
		
		verts.push(p1);
		verts.push(p2);
		verts.push(p3);
		verts.push(p4);
	}
	
	
	private function setAxisProjections():Void {
	
		var temp:Number;
		
		minF = p2.dot(faceNormal);
		maxF = p3.dot(faceNormal);
		if (minF > maxF) {
			temp = minF;
			minF = maxF;
			maxF = temp;
		}
		
		minS = p1.dot(sideNormal);
		maxS = p2.dot(sideNormal);
		if (minS > maxS) {
			temp = minS;
			minS = maxS;
			maxS = temp;
		}	
	}
	
	
	private function calcSideNormal():Void {
		sideNormal = new Vector(0,0);
		var dx:Number = p3.x - p2.x;
		var dy:Number = p3.y - p2.y;
		sideNormal.setTo(dy, -dx);
		sideNormal.normalize();
	}

}

