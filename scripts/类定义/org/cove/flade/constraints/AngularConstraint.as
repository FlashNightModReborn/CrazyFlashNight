/**
 * Flade - Flash Dynamics Engine
 * Release 0.6 alpha 
 * AngularConstraint class
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
import org.cove.flade.primitives.Particle;
import org.cove.flade.constraints.Constraint;

class org.cove.flade.constraints.AngularConstraint implements Constraint {

	public var targetTheta:Number;

	private var pA:Vector;
	private var pB:Vector;
	private var pC:Vector;
	private var pD:Vector

	private var lineA:Line;
	private var lineB:Line;
	private var lineC:Line;

	private var stiffness:Number;
	
	public function AngularConstraint(p1:Particle, p2:Particle, p3:Particle) {

		pA = p1.curr;
		pB = p2.curr;
		pC = p3.curr;

		lineA = new Line(pA, pB);
		lineB = new Line(pB, pC);

		// lineC is the reference line for getting the angle of the line segments
		pD = new Vector(pB.x + 0, pB.y - 1);
		lineC = new Line(pB, pD);

		// theta to constrain to -- domain is -Math.PI to Math.PI
		targetTheta = calcTheta(pA, pB, pC);

		// coefficient of stiffness
		stiffness = 1;
	}


	public function resolve():Void {

		var center:Vector = getCentroid();

		// make sure the reference line position gets updated
		lineC.p2.x = lineC.p1.x + 0;
		lineC.p2.y = lineC.p1.y - 1;

		var abRadius:Number = pA.distance(pB);
		var bcRadius:Number = pB.distance(pC);

		var thetaABC:Number = calcTheta(pA, pB, pC);
		var thetaABD:Number = calcTheta(pA, pB, pD);
		var thetaCBD:Number = calcTheta(pC, pB, pD);

		var halfTheta:Number = (targetTheta - thetaABC) / 2;
		var paTheta:Number = thetaABD + halfTheta * stiffness;
		var pcTheta:Number = thetaCBD - halfTheta * stiffness;

		pA.x = abRadius * Math.sin(paTheta) + pB.x;
		pA.y = abRadius * Math.cos(paTheta) + pB.y;
		pC.x = bcRadius * Math.sin(pcTheta) + pB.x;
		pC.y = bcRadius * Math.cos(pcTheta) + pB.y;

		// move corrected angle to pre corrected center
		var newCenter:Vector = getCentroid();
		var dfx:Number = newCenter.x - center.x;
		var dfy:Number = newCenter.y - center.y;

		pA.x -= dfx; 
		pA.y -= dfy;
		pB.x -= dfx;  
		pB.y -= dfy;
		pC.x -= dfx;  
		pC.y -= dfy; 
	}


	public function paint():Void {	
		// maintain the constraint interface. angular constraints are
		// painted by their two component SpringConstraints.
	}


	public function setStiffness(s:Number):Void {
		stiffness = s;
	}


	private function calcTheta(pa:Vector, pb:Vector, pc:Vector):Number {

		var AB:Vector = new Vector(pb.x - pa.x, pb.y - pa.y);
		var BC:Vector = new Vector(pc.x - pb.x, pc.y - pb.y);

		var dotProd:Number = AB.dot(BC);
		var crossProd:Number = AB.cross(BC);
		return Math.atan2(crossProd, dotProd);
	}


	private function getCentroid():Vector {
		var avgX:Number = (pA.x + pB.x + pC.x) / 3;
		var avgY:Number = (pA.y + pB.y + pC.y) / 3;
		return new Vector(avgX, avgY);
	}
	
}
