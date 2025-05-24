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

import org.flashNight.sara.DynamicsEngine;
import org.flashNight.sara.util.*;
import org.flashNight.sara.graphics.*;
import org.flashNight.sara.primitives.*;
import org.flashNight.sara.constraints.*;

class org.flashNight.sara.constraints.SpringConstraint implements Constraint{
	
	private var p1:Particle;
	private var p2:Particle;
	private var restLength:Number;
	private var tearLength:Number;
	
	private var color:Number;
	private var stiffness:Number;
	private var isVisible:Boolean;

	private var dmc:MovieClip;


	public function SpringConstraint(p1:Particle, p2:Particle, getParent:Function) {

		this.p1 = p1;
		this.p2 = p2;
		restLength = p1.curr.distance(p2.curr);
	
		stiffness = 0.5;
		color = 0x996633;
		
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

		// Remove references to Particle objects to help garbage collection
		p1 = null;
		p2 = null;

		// Reset other properties to default values or null
		restLength = 0;
		stiffness = 0;
		isVisible = false;
		color = 0; // Reset color to default if needed

		e.removeConstraint(this);
	}


	public function resolve():Void {

		var delta:Vector = p1.curr.minusNew(p2.curr);
		var deltaLength:Number = p1.curr.distance(p2.curr);

		var diff:Number = (deltaLength - restLength) / deltaLength;
		var dmd:Vector = delta.mult(diff * stiffness);

		p1.curr.minus(dmd);
		p2.curr.plus(dmd);
	}


	public function setRestLength(r:Number):Void {
		restLength = r;
	}


	public function setStiffness(s:Number):Void {
		stiffness = s;
	}


	public function setVisible(v:Boolean):Void {
		isVisible = v;
	}


	public function paint():Void {
		
		if (isVisible) {
			dmc.clear();
			dmc.lineStyle(0, color, 100);

			Graphics.paintLine(
					dmc, 
					p1.curr.x, 
					p1.curr.y, 
					p2.curr.x, 
					p2.curr.y);
		}
	}
}