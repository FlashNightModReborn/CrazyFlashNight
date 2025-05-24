import org.cove.flade.surfaces.*;
import org.cove.flade.constraints.*;
import org.cove.flade.composites.*;
import org.cove.flade.primitives.*;
import org.cove.flade.DynamicsEngine;


class TankExample {

	private var engine:DynamicsEngine;
	
	private var wheelA:Wheel;
	private var wheelB:Wheel;
	private var wheelC:Wheel; 
	private var wheelD:Wheel; 
	
	
	public function TankExample() {

		engine = new DynamicsEngine();
		engine.setDamping(1.0);
		engine.setGravity(0.0, 0.1);
		engine.setSurfaceBounce(0.5);
		engine.setSurfaceFriction(0.1);
				
		// surfaces
		engine.addSurface(new RectangleTile(1, 40, 20, 520));
		engine.addSurface(new LineSurface(0,100,240,100));
		
		engine.addSurface(new CircleTile(240, 100, 15));
		engine.addSurface(new CircleTile(285, 100, 20));
		engine.addSurface(new CircleTile(340, 100, 25));
		engine.addSurface(new CircleTile(405, 100, 30));
		
		engine.addSurface(new RectangleTile(585, 60, 20, 1000));
		
		engine.addSurface(new LineSurface(300,200,595,120));
		
		engine.addSurface(new RectangleTile(240, 200, 120, 20));
		
		engine.addSurface(new RectangleTile(1, 340, 550, 80));
		
		engine.addSurface(new LineSurface(277,300,570,370));
		
		engine.addSurface(new CircleTile(570,370, 170));
		


		var posX:Number = 75;
		var posY:Number = 40;

		var rectWidth:Number = 40;
		var rectHeight:Number = 15;

		var wheelSize:Number = 17;
		var strutRestLength:Number = 5;
		

		// wheels
		wheelA = new Wheel(posX - rectWidth, posY, wheelSize);
		engine.addPrimitive(wheelA);
		wheelB = new Wheel(posX, posY, wheelSize);
		engine.addPrimitive(wheelB);
		wheelC = new Wheel(posX + rectWidth, posY, wheelSize);
		engine.addPrimitive(wheelC);
		wheelD = new Wheel(posX + rectWidth * 2, posY, wheelSize);
		engine.addPrimitive(wheelD);
		
		
		// bodies
		var rectA:SpringBox = new SpringBox(posX - rectWidth/2, posY, rectWidth, rectHeight, engine);
		var rectB:SpringBox = new SpringBox(posX + rectWidth/2, posY, rectWidth, rectHeight, engine);
		var rectC:SpringBox = new SpringBox(posX + rectWidth + rectWidth/2, posY, rectWidth, rectHeight, engine);



		// wheel struts
		var conn1:SpringConstraint = new SpringConstraint(wheelA, rectA.p3);
		conn1.setRestLength(strutRestLength);
		engine.addConstraint(conn1);
		
		var conn1a:SpringConstraint = new SpringConstraint(wheelA, rectA.p0);
		conn1a.setRestLength(strutRestLength);
		engine.addConstraint(conn1a);
		
		var conn2:SpringConstraint = new SpringConstraint(wheelB, rectA.p2);
		conn2.setRestLength(strutRestLength);
		engine.addConstraint(conn2);
		
		var conn2a:SpringConstraint = new SpringConstraint(wheelB, rectA.p1);
		conn2a.setRestLength(strutRestLength);
		engine.addConstraint(conn2a);

		var conn3:SpringConstraint = new SpringConstraint(wheelB, rectB.p3);
		conn3.setRestLength(strutRestLength);
		engine.addConstraint(conn3);
		
		var conn3a:SpringConstraint = new SpringConstraint(wheelB, rectB.p0);
		conn3a.setRestLength(strutRestLength);
		engine.addConstraint(conn3a);

		var conn4:SpringConstraint = new SpringConstraint(wheelC, rectB.p2);
		conn4.setRestLength(strutRestLength);
		engine.addConstraint(conn4);
		
		var conn4a:SpringConstraint = new SpringConstraint(wheelC, rectB.p1);
		conn4a.setRestLength(strutRestLength);
		engine.addConstraint(conn4a);
		
		var conn5:SpringConstraint = new SpringConstraint(wheelC, rectC.p3);
		conn5.setRestLength(strutRestLength);
		engine.addConstraint(conn5);
		
		var conn5a:SpringConstraint = new SpringConstraint(wheelC, rectC.p0);
		conn5a.setRestLength(strutRestLength);
		engine.addConstraint(conn5a);
		
		var conn6:SpringConstraint = new SpringConstraint(wheelD, rectC.p2);
		conn6.setRestLength(strutRestLength);
		engine.addConstraint(conn6);
		
		var conn6a:SpringConstraint = new SpringConstraint(wheelD, rectC.p1);
		conn6a.setRestLength(strutRestLength);
		engine.addConstraint(conn6a);


		// hidden body stiffness springs
		var conn7:SpringConstraint = new SpringConstraint(rectA.p3, rectC.p2);
		conn7.setVisible(false);
		engine.addConstraint(conn7);

		var conn8:SpringConstraint = new SpringConstraint(rectA.p0, rectC.p1);
		conn8.setVisible(false);
		engine.addConstraint(conn8);
	

		engine.paintSurfaces();
	}


	public function run():Void {

		var keySpeed:Number = 2.0;

		if(Key.isDown(Key.LEFT)) {
			wheelA.rp.vs = -keySpeed;
			wheelB.rp.vs = -keySpeed;
			wheelC.rp.vs = -keySpeed;
			wheelD.rp.vs = -keySpeed;
		} else if(Key.isDown(Key.RIGHT)) {
			wheelA.rp.vs = keySpeed;
			wheelB.rp.vs = keySpeed;
			wheelC.rp.vs = keySpeed;
			wheelD.rp.vs = keySpeed;
		} else {
			wheelA.rp.vs = 0;
			wheelB.rp.vs = 0;
			wheelC.rp.vs = 0;
			wheelD.rp.vs = 0;
		}
		
		engine.timeStep();
		engine.paintPrimitives();
		engine.paintConstraints();
	}
	

	public static function main(mc:MovieClip):Void {

		var example:TankExample = new TankExample();

		var fps:MovieClip = mc.attachMovie("fps","fps", _root.getNextHighestDepth());
		fps._x = 20;
		fps._y = 6;

		mc.onEnterFrame = function() {
			example.run();
		}
	}
}