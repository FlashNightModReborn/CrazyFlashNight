import org.cove.flade.surfaces.*;
import org.cove.flade.constraints.*;
import org.cove.flade.composites.*;
import org.cove.flade.primitives.*;
import org.cove.flade.DynamicsEngine;



class CarExample {
	
	
	private var engine:DynamicsEngine;
	private var ang:AngularConstraint;
	private var angDefault:Number;
	
	private var wheelA:Wheel;
	private var wheelB:Wheel;
		
		
	public function CarExample() {

		engine = new DynamicsEngine();
		
		engine.setDamping(1.0);
		engine.setGravity(0.0, 0.5);
		engine.setSurfaceBounce(0.1);
		engine.setSurfaceFriction(0.1);
		
		
		// surfaces starting with lower left
		engine.addSurface(new RectangleTile(15, 300, 20, 100));
		
		var switchLine:LineSurface = new LineSurface(25, 350, 150, 350)
		engine.addSurface(switchLine);
		
		engine.addSurface(new LineSurface(150, 350, 250, 300));
		engine.addSurface(new RectangleTile(300, 308, 100, 15));
		engine.addSurface(new LineSurface(350, 300, 460, 250));
		engine.addSurface(new RectangleTile(528, 252, 135, 20))
				
		// create the upward surface that branches, inactive to start
		var toggleLine:LineSurface = new LineSurface(220, 150, 460, 248);
		toggleLine.setActiveState(false);
		engine.addSurface(toggleLine);
		
		// if the car touches the right rectangle then turn off the upward ramp
		switchLine.onContact = function() {
			toggleLine.setActiveState(false);
		}
		
		// if the car touches the right rectangle then turn on the upward ramp
		var switchRect:RectangleTile = new RectangleTile(580, 217, 30, 90);
		switchRect.onContact = function() {
			toggleLine.setActiveState(true);
		}
		engine.addSurface(switchRect);
		
		engine.addSurface(new CircleTile(185, 155, 35));
		engine.addSurface(new RectangleTile(100, 108, 100, 15));
		engine.addSurface(new LineSurface(5, 20, 5, 275));
		engine.addSurface(new CircleTile(32, 195, 26));
		
		
	
		// create the car
		var leftX:Number = 70;
		var rightX:Number = 130
		var widthX:Number = rightX - leftX;
		var midX:Number = leftX + (widthX / 2);
		var topY:Number = 300;
		
		
		// wheels
		wheelA = new Wheel(leftX, topY, 20);
		engine.addPrimitive(wheelA);
		
		wheelB = new Wheel(rightX, topY, 20);
		engine.addPrimitive(wheelB);
		
		
		// body
		var rectA:SpringBox = new SpringBox(midX, topY, widthX, 15, engine);
		
		
		// wheel struts
		var conn1:SpringConstraint = new SpringConstraint(wheelA, rectA.p3);
		engine.addConstraint(conn1);
		
		var conn2:SpringConstraint = new SpringConstraint(wheelB, rectA.p2);
		engine.addConstraint(conn2);
		
		var conn1a:SpringConstraint = new SpringConstraint(wheelA, rectA.p0);
		engine.addConstraint(conn1a);
		
		var conn2a:SpringConstraint = new SpringConstraint(wheelB, rectA.p1);
		engine.addConstraint(conn2a);
		
		
		// triangle top of car
		var p1:CircleParticle = new CircleParticle(midX, topY - 25, 2, 2);
		engine.addPrimitive(p1);
		
		var conn3:SpringConstraint = new SpringConstraint(wheelA, p1);
		engine.addConstraint(conn3);
		
		var conn4:SpringConstraint = new SpringConstraint(wheelB, p1);
		engine.addConstraint(conn4);
		
		
		// angular constraint for triangle top
		ang = new AngularConstraint(wheelA, p1, wheelB);
		engine.addConstraint(ang);
		angDefault = ang.targetTheta;
			
			
		// trailing body
		var rp1:RectangleParticle = new RectangleParticle(midX, topY - 20, 1, 1);
		engine.addPrimitive(rp1);
		
		var conn6:SpringConstraint = new SpringConstraint(p1, rp1);
		conn6.setRestLength(7);
		engine.addConstraint(conn6);
		
		var rp2:RectangleParticle = new RectangleParticle(midX, topY - 10, 1, 1);
		engine.addPrimitive(rp2);
				
		var conn7:SpringConstraint = new SpringConstraint(rp1, rp2);
		conn7.setRestLength(7);
		engine.addConstraint(conn7);
		
		var rp3:RectangleParticle = new RectangleParticle(midX, topY - 5, 7, 7);
		engine.addPrimitive(rp3);
		
		var conn8:SpringConstraint = new SpringConstraint(rp2, rp3);
		conn8.setRestLength(7);
		engine.addConstraint(conn8);
	
	
		// no need to redraw surfaces
		engine.paintSurfaces();
	}
	
	
	
	public function run():Void {
			
		var keySpeed:Number = 2.0;

		if(Key.isDown(Key.LEFT)) {
			wheelA.rp.vs = -keySpeed;
			wheelB.rp.vs = -keySpeed;
		} else if(Key.isDown(Key.RIGHT)) {
			wheelA.rp.vs = keySpeed;
			wheelB.rp.vs = keySpeed;
		} else {
			wheelA.rp.vs = 0;
			wheelB.rp.vs = 0;
		}

		if (Key.isDown(Key.UP)) {
			if (ang.targetTheta < 2.5) ang.targetTheta += .1;
		} else {
			if (ang.targetTheta > angDefault) ang.targetTheta -= .1;
		}


		engine.timeStep();
		engine.paintPrimitives();
		engine.paintConstraints();		
	}	
	
	
	public static function main(mc:MovieClip):Void {
		
		var c:CarExample = new CarExample();
		
		var fps:MovieClip = mc.attachMovie("fps","fps", _root.getNextHighestDepth());
		fps._x = 6;
		fps._y = 6;
		
		mc.onEnterFrame = function() {
			c.run();
		}
	}	
}




