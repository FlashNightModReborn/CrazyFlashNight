import org.cove.flade.surfaces.*;
import org.cove.flade.primitives.*;
import org.cove.flade.constraints.*;
import org.cove.flade.DynamicsEngine;

class MeshExample {
	
	private var engine:DynamicsEngine;
	private var isDrag:Boolean;
	
	public function MeshExample() {

		engine = new DynamicsEngine();

		engine.setDamping(1.0);
		engine.setGravity(0.0, 0.6);
		engine.setSurfaceBounce(0.1);
		engine.setSurfaceFriction(0.25);

		isDrag = false;
		
		var rows:Number = 5;
		var cols:Number = 20;
		var startX:Number = 180;
		var startY:Number = 20;
		var spacing:Number = 12;

		var currX:Number = startX;
		var currY:Number = startY;
		for (var n:Number = 0; n < rows; n++) {
			for (var j:Number = 0; j < cols; j++) {

				// add a little noise
				currY += Math.random();
				currX += Math.random();

				engine.addPrimitive(new RectangleParticle(currX, currY, 1, 1));
				currX += spacing;
			}
			currX = startX;
			currY += spacing;
		}


		// vertical constraints
		var p2:Particle = null;
		for (var n:Number = 0; n < cols; n++) {
			for (var j:Number = 0; j < rows; j++) {

				var i:Number = cols * j + n;
				var p1:Particle = engine.primitives[i];

				if (p2 != null) {
					engine.addConstraint(new SpringConstraint(p1, p2));
				}
				p2 = p1;
			}
			p2 = null;
		}


		// horizontal constraints
		for (var i:Number = 0; i < engine.primitives.length; i++) {

			var p1:Particle = engine.primitives[i];
			if (p2 != null && i % cols != 0) {
				engine.addConstraint(new SpringConstraint(p1, p2));
			}
			p2 = p1;
		}


		// surfaces
		var s0:LineSurface = new LineSurface(0, 350, 675, 350);
		s0.setCollisionDepth(50);
		engine.addSurface(s0);
		
		engine.paintSurfaces();
	}	
	
	
	public function run():Void {
			
		if (!isDrag) {
			engine.primitives[0].pin();
			engine.primitives[19].pin();
		}
		engine.timeStep();
		engine.paintConstraints();
	}	
	
	
	public function onMouseUp():Void {
		isDrag = false;
	}

	
	public function onMouseDown():Void {
		isDrag = true;
	}

	
	public static function main(mc:MovieClip):Void {
		
		var c:MeshExample = new MeshExample();
		Mouse.addListener(c);
		
		var fps:MovieClip = mc.attachMovie("fps","fps", _root.getNextHighestDepth());
		fps._x = 6;
		fps._y = 6;

		mc.onEnterFrame = function() {
			c.run();
		}
	}	
}




