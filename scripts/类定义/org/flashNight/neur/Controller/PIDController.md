import org.flashNight.neur.Controller.*;
var test:TestPIDController = new TestPIDController();
test.runTests();


Running PIDController Tests...
Testing functionality...
[PASS] Kp getter/setter
[PASS] Ki getter/setter
[PASS] Kd getter/setter
[PASS] Basic PID calculation
Testing boundary conditions...
[PASS] Integral windup prevention
[PASS] Zero deltaTime handling
[PASS] Negative deltaTime handling
Testing performance...
Performance Test Duration: 47ms for 10000 iterations.
