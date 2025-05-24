import org.flashNight.sara.util.*;
class org.flashNight.sara.util.TriangleFace {
    public var originalVertices:Array;  // 原始顶点
    public var transformedVertices:Array;  // 变换后的顶点
    public var normal:Vertex3D;  // 法向量
    
    public function TriangleFace() {
        originalVertices = [new Vertex3D(0, 0, 0), new Vertex3D(0, 0, 0), new Vertex3D(0, 0, 0)];
        transformedVertices = [new Vertex3D(0, 0, 0), new Vertex3D(0, 0, 0), new Vertex3D(0, 0, 0)];
        normal = new Vertex3D(0, 0, 0);
    }
}