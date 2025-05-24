import org.flashNight.sara.util.*;

/**
 * Vertex3DTest - 测试 Vertex3D 类基本功能的测试类
 * 用于粗略评估 Vertex3D 的各项向量运算（克隆、加减、乘法、点积、叉积、归一化、角度、线性插值、反射等）
 */
class org.flashNight.sara.util.Vertex3DTest {
    
    /**
     * 构造函数，自动运行所有测试
     */
    public function Vertex3DTest() {
        trace("===== Vertex3D 测试开始 =====");
        testClone();
        testArithmetic();
        testDotCross();
        testNormalization();
        testAngle();
        testLerp();
        testReflection();
        trace("===== Vertex3D 测试结束 =====");
    }
    
    /**
     * 测试 clone 方法，验证克隆后的对象是否独立
     */
    private function testClone():Void {
        trace("----- testClone -----");
        var v1:Vertex3D = new Vertex3D(1, 2, 3);
        var v2:Vertex3D = v1.clone();
        trace("v1: " + v1.toString());
        trace("v2 (clone of v1): " + v2.toString());
        // 修改 v1 后，v2 应保持不变
        v1.plus(new Vertex3D(1, 1, 1));
        trace("v1 after adding (1,1,1): " + v1.toString());
        trace("v2 should remain unchanged: " + v2.toString());
    }
    
    /**
     * 测试加、减、乘运算
     */
    private function testArithmetic():Void {
        trace("----- testArithmetic -----");
        var v1:Vertex3D = new Vertex3D(3, 4, 5);
        var v2:Vertex3D = new Vertex3D(1, 1, 1);
        var plusResult:Vertex3D = v1.plusNew(v2);
        trace("v1 + v2: " + plusResult.toString());
        
        var v3:Vertex3D = new Vertex3D(3, 4, 5);
        var minusResult:Vertex3D = v3.minusNew(v2);
        trace("v1 - v2: " + minusResult.toString());
        
        var multResult:Vertex3D = v2.multNew(3);
        trace("v2 * 3: " + multResult.toString());
    }
    
    /**
     * 测试点积和叉积
     */
    private function testDotCross():Void {
        trace("----- testDotCross -----");
        var v1:Vertex3D = new Vertex3D(1, 0, 0);
        var v2:Vertex3D = new Vertex3D(0, 1, 0);
        var dotProd:Number = v1.dot(v2);
        trace("Dot product (1,0,0)·(0,1,0): " + dotProd);
        
        var crossProd:Vertex3D = v1.cross(v2);
        trace("Cross product (1,0,0)x(0,1,0): " + crossProd.toString());
    }
    
    /**
     * 测试归一化功能
     */
    private function testNormalization():Void {
        trace("----- testNormalization -----");
        var v:Vertex3D = new Vertex3D(3, 4, 0);
        trace("Before normalization: " + v.toString() + " (magnitude: " + v.magnitude() + ")");
        v.normalize();
        trace("After normalization: " + v.toString() + " (magnitude: " + v.magnitude() + ")");
    }
    
    /**
     * 测试计算两个向量间的角度
     */
    private function testAngle():Void {
        trace("----- testAngle -----");
        var v1:Vertex3D = new Vertex3D(1, 0, 0);
        var v2:Vertex3D = new Vertex3D(0, 1, 0);
        var angle:Number = v1.angleBetween(v2);
        trace("Angle between (1,0,0) and (0,1,0): " + angle + " radians");
    }
    
    /**
     * 测试线性插值 (lerp) 方法
     */
    private function testLerp():Void {
        trace("----- testLerp -----");
        var v1:Vertex3D = new Vertex3D(0, 0, 0);
        var v2:Vertex3D = new Vertex3D(10, 10, 10);
        var lerpResult:Vertex3D = v1.lerp(v2, 0.5);
        trace("Lerp between (0,0,0) and (10,10,10) at t=0.5: " + lerpResult.toString());
    }
    
    /**
     * 测试反射功能，验证反射后的向量
     */
    private function testReflection():Void {
        trace("----- testReflection -----");
        var v:Vertex3D = new Vertex3D(1, -1, 0);
        // 定义一个法向量，假设为 (0,1,0)，并归一化
        var normal:Vertex3D = new Vertex3D(0, 1, 0);
        normal.normalize();
        var reflected:Vertex3D = v.reflect(normal);
        trace("Reflect (1,-1,0) across (0,1,0): " + reflected.toString());
    }
}
