import org.cove.flade.surfaces.*;
import org.cove.flade.constraints.*;
import org.cove.flade.composites.*;
import org.cove.flade.primitives.*;
import org.cove.flade.DynamicsEngine;



class TwoBoxesExample {
	
	private var engine:DynamicsEngine;
	private	var head:SpringBox;
		
	public function TwoBoxesExample() {

		engine = new DynamicsEngine();
		engine.setDamping(1.0);
		engine.setGravity(0.0, 0.3);
		engine.setSurfaceBounce(0.1);
		engine.setSurfaceFriction(0.1);

		// surfaces
		var lsA:LineSurface = new LineSurface(0,-10,20,400);
		lsA.setCollisionDepth(100);
		engine.addSurface(lsA);
		
		var lsB:LineSurface = new LineSurface(-1,355,300,320);
		lsB.setCollisionDepth(100);
		engine.addSurface(lsB);
		
		engine.addSurface(new RectangleTile(300,330,100,50));
		
		var lsC:LineSurface = new LineSurface(300,320,610,350);
		lsC.setCollisionDepth(100);
		engine.addSurface(lsC);
		
		var lsD:LineSurface = new LineSurface(590,400,600,-5);
		lsD.setCollisionDepth(100);
		engine.addSurface(lsD);
		
		var lsE:LineSurface = new LineSurface(610,5,-10,1);
		lsE.setCollisionDepth(100);
		engine.addSurface(lsE);
		
		engine.addSurface(new CircleTile(370, 130, 60))

	
		// springboxes
		var gx:Number = 100;
		var gy:Number = 200;
		
		var body:SpringBox = new SpringBox(gx, gy + 30, 50, 60, engine);
		head = new SpringBox(gx, gy, 50, 60, engine);


		// connections between springboxes
		var p1:CircleParticle = new CircleParticle(gx, gy, 10);
		engine.addPrimitive(p1);
		var p2:CircleParticle = new CircleParticle(gx, gy + 10, 10);
		engine.addPrimitive(p2);
		var p3:CircleParticle = new CircleParticle(gx, gy + 20, 10);
		engine.addPrimitive(p3);
		var p4:CircleParticle = new CircleParticle(gx, gy + 30, 10);
		engine.addPrimitive(p4);

		var springA1:SpringConstraint = new SpringConstraint(body.p0, p1);
		springA1.setRestLength(25);
		engine.addConstraint(springA1);
		
		var springA2:SpringConstraint = new SpringConstraint(body.p1, p1);
		springA2.setRestLength(25);
		engine.addConstraint(springA2);
		
		var springB:SpringConstraint = new SpringConstraint(p1, p2);
		springB.setRestLength(20);
		engine.addConstraint(springB);
		
		var springC:SpringConstraint = new SpringConstraint(p2, p3);
		springC.setRestLength(20);
		engine.addConstraint(springC);
		
		var springD:SpringConstraint = new SpringConstraint(p3, p4);
		springD.setRestLength(20);
		engine.addConstraint(springD);
		
		var springE1:SpringConstraint = new SpringConstraint(p4, head.p0);
		springE1.setRestLength(25);
		engine.addConstraint(springE1);
		
		var springE2:SpringConstraint = new SpringConstraint(p4, head.p1);
		springE2.setRestLength(25);
		engine.addConstraint(springE2);
			
		var rectParticle1:RectangleParticle = new RectangleParticle(1, 1, 30, 30);
		engine.addPrimitive(rectParticle1);
		
		var springF1:SpringConstraint = new SpringConstraint(body.p2, rectParticle1);
		springF1.setRestLength(70);
		engine.addConstraint(springF1);
		
		var springF2:SpringConstraint = new SpringConstraint(body.p3, rectParticle1);
		springF2.setRestLength(70);
		engine.addConstraint(springF2);
		
		engine.paintSurfaces();
	}

			
	public function run():Void {

		var yspeed:Number = 3;
		var xspeed:Number = 1.5;

		if (Key.isDown(Key.UP)) {
			head.p2.prev.y += yspeed;
			head.p3.prev.y += yspeed;
		} else if (Key.isDown(Key.DOWN)) {
			head.p2.prev.y -= yspeed;
			head.p3.prev.y -= yspeed;
		}

		if (Key.isDown(Key.LEFT)) {
			head.p2.prev.x += xspeed;
			head.p3.prev.x += xspeed;
		} else if (Key.isDown(Key.RIGHT)) {
			head.p2.prev.x -= xspeed;
			head.p3.prev.x -= xspeed;
		}
		engine.timeStep();
		engine.paintPrimitives();
		engine.paintConstraints();
	}

	
	public static function main(mc:MovieClip):Void {

		var example:TwoBoxesExample = new TwoBoxesExample();

		var fps:MovieClip = mc.attachMovie("fps","fps", _root.getNextHighestDepth());
		fps._x = 6;
		fps._y = 6;

		mc.onEnterFrame = function() {
			example.run();
		}
	}
}
