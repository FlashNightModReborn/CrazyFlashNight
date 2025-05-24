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
import org.flashNight.sara.primitives.RectangleParticle;
import org.flashNight.sara.constraints.SpringConstraint;
import org.flashNight.sara.composites.Composite;


class org.flashNight.sara.composites.SpringBox extends Composite {
	
	public var p0:RectangleParticle;
	public var p1:RectangleParticle;
	public var p2:RectangleParticle;
	public var p3:RectangleParticle;
	private var constraints:Array;  // Array to hold the SpringConstraint references
	
	public function SpringBox (
			px:Number, 
			py:Number, 
			w:Number, 
			h:Number, 
			engine:DynamicsEngine, 
			getParent:Function) {

		super(px, py, 0);
		
		var func = getParent || engine.getClipFunction();
		// top left
		p0 = engine.createRectangleParticlePrimitive(px - w / 2, py - h / 2, 1, 1, func);
		// top right
		p1 = engine.createRectangleParticlePrimitive(px + w / 2, py - h / 2, 1, 1, func);
		// bottom right
		p2 = engine.createRectangleParticlePrimitive(px + w / 2, py + h / 2, 1, 1, func);
		// bottom left
		p3 = engine.createRectangleParticlePrimitive(px - w / 2, py + h / 2, 1, 1, func);

		// edges
        // Initialize constraints array
        constraints = [];

        // Create and store constraints
        constraints.push(engine.createSpringConstraint(p0, p1, func));
        constraints.push(engine.createSpringConstraint(p1, p2, func));
        constraints.push(engine.createSpringConstraint(p2, p3, func));
        constraints.push(engine.createSpringConstraint(p3, p0, func));

        // Crossing braces
        constraints.push(engine.createSpringConstraint(p0, p2, func));
        constraints.push(engine.createSpringConstraint(p1, p3, func));

        // Set particles invisible and remove containers
        var particles:Array = [p0, p1, p2, p3];
        for (var i:Number = 0; i < particles.length; i++) {
            particles[i].setVisible(false);
            particles[i].removeContainer();
        }
	}

    public function dispose(e:DynamicsEngine):Void {
        // Dispose of all constraints
        for (var i:Number = 0; i < constraints.length; i++) {
            constraints[i].dispose(e);
        }
        constraints = null;

        // Dispose of all particles
        var particles:Array = [p0, p1, p2, p3];
        for (var j:Number = 0; j < particles.length; j++) {
            if (particles[j]) {
                particles[j].dispose(e);
                particles[j] = null;
            }
        }

        // Call the dispose method of the superclass
        super.dispose(e);
    }


	public function translate(dx:Number, dy:Number):Void 
	{
		p0.setPos(p0.curr.x + dx, p0.curr.y + dy);
		p1.setPos(p1.curr.x + dx, p1.curr.y + dy);
		p2.setPos(p2.curr.x + dx, p2.curr.y + dy);
		p3.setPos(p3.curr.x + dx, p3.curr.y + dy);

		super.moveTo((p0.curr.x + p1.curr.x + p2.curr.x + p3.curr.x) / 4, (p0.curr.y + p1.curr.y + p2.curr.y + p3.curr.y) / 4);
	}

	public function moveTo(newX:Number, newY:Number):Void {
		// 计算从当前中心到新中心的位移差
		var dx:Number = newX - centerX;
		var dy:Number = newY - centerY;

		translate(dx, dy);
	}

	private function rotateParticle(p:RectangleParticle, angle:Number, centerX:Number, centerY:Number):Void {
		var cosA:Number = Math.cos(angle);
		var sinA:Number = Math.sin(angle);
		var tempX:Number = p.curr.x - centerX;
		var tempY:Number = p.curr.y - centerY;
		var newX:Number = cosA * tempX - sinA * tempY + centerX;
		var newY:Number = sinA * tempX + cosA * tempY + centerY;
		p.setPos(newX, newY);
	}

	public function rotate(angle:Number, centerX:Number, centerY:Number):Void {
		super(angle, centerX, centerY);

		rotateParticle(p0, angle, centerX, centerY);
		rotateParticle(p1, angle, centerX, centerY);
		rotateParticle(p2, angle, centerX, centerY);
		rotateParticle(p3, angle, centerX, centerY);
	}

	public function synchronize():Void {
		// Calculate the center point
		centerX = (p0.curr.x + p1.curr.x + p2.curr.x + p3.curr.x) / 4;
		centerY = (p0.curr.y + p1.curr.y + p2.curr.y + p3.curr.y) / 4;

		var dy:Number = p1.curr.y - p0.curr.y;
		var dx:Number = p1.curr.x - p0.curr.x;
		rotation = Math.atan2(dy, dx) * (180 / Math.PI);  // Convert radians to degrees

		// Log additional details
		//_root.服务器.发布服务器消息("Center: (" + centerX + ", " + centerY + ") Rotation: " + rotation + " degrees, Δx: " + dx + ", Δy: " + dy);

		//super();
	}

}