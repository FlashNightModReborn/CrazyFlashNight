import org.flashNight.sara.util.*;


class org.flashNight.sara.util.Renderer {
    private var drawClip:MovieClip; // 用于绘制的单一 MovieClip
    private static var FOCAL_LENGTH:Number = 2.2; // 焦距参数
    private static var SCREEN_CENTER_X:Number = 256;
    private static var SCREEN_CENTER_Y:Number = 256;
    private static var SCREEN_SCALE_X:Number = 512;
    private static var SCREEN_SCALE_Y:Number = 512;
    private static var COLOR_OFFSET:Number = 127;

    public function Renderer() {
        // 在最高深度创建一个用于绘制的空 MovieClip
        drawClip = _root.createEmptyMovieClip("drawClip", _root.getNextHighestDepth());
    }

    // 清除之前的绘制内容
    private function clearClip():Void {
        drawClip.clear();
    }

    // 使用矢量绘制三角形
    public function drawTriangle(x1:Number, y1:Number, x2:Number, y2:Number, x3:Number, y3:Number, color:Number):Void {
        drawClip.lineStyle(0, color, 100);
        drawClip.beginFill(color, 100);
        drawClip.moveTo(x1, y1);
        drawClip.lineTo(x2, y2);
        drawClip.lineTo(x3, y3);
        drawClip.lineTo(x1, y1);
        drawClip.endFill();
    }

    // 渲染模型
    public function renderModel(faces:Array, rotation:Number):Void {
        clearClip(); // 清除上次的绘制内容
        var cosR:Number = Math.cos(rotation); // 旋转角度的余弦值
        var sinR:Number = Math.sin(rotation); // 旋转角度的正弦值

        for (var i:Number = 0; i < faces.length; i++) {
            var face:TriangleFace = faces[i];
            for (var j:Number = 0; j < 3; j++) {
                var vertex:Vertex3D = face.originalVertices[j];
                // 计算旋转后的坐标
                face.transformedVertices[j].x = vertex.x * cosR - vertex.z * sinR;
                face.transformedVertices[j].z = vertex.x * sinR + vertex.z * cosR + FOCAL_LENGTH;
                // 投影变换
                face.transformedVertices[j].x = face.transformedVertices[j].x / face.transformedVertices[j].z;
                face.transformedVertices[j].y = vertex.y / face.transformedVertices[j].z;
            }

            // 计算法向量
            var v0:Vertex3D = face.transformedVertices[0];
            var v1:Vertex3D = face.transformedVertices[1];
            var v2:Vertex3D = face.transformedVertices[2];
            face.normal.x = (v1.y - v0.y) * (v2.z - v0.z) - (v1.z - v0.z) * (v2.y - v0.y);
            face.normal.y = (v1.z - v0.z) * (v2.x - v0.x) - (v1.x - v0.x) * (v2.z - v0.z);
            face.normal.z = (v1.x - v0.x) * (v2.y - v0.y) - (v1.y - v0.y) * (v2.x - v0.x);

            // 背面剔除
            if (face.normal.z < 0) continue; // 不渲染背向的面

            // 计算光照强度
            var light:Number = face.normal.z / Math.sqrt(face.normal.x * face.normal.x + face.normal.y * face.normal.y + face.normal.z * face.normal.z);
            var grey:Number = light * COLOR_OFFSET + COLOR_OFFSET;
            var color:Number = grey << 16 | grey << 8 | grey;

            // 使用矢量绘制三角形
            drawTriangle(
                SCREEN_CENTER_X + SCREEN_SCALE_X * face.transformedVertices[0].x,
                SCREEN_CENTER_Y + SCREEN_SCALE_Y * face.transformedVertices[0].y,
                SCREEN_CENTER_X + SCREEN_SCALE_X * face.transformedVertices[1].x,
                SCREEN_CENTER_Y + SCREEN_SCALE_Y * face.transformedVertices[1].y,
                SCREEN_CENTER_X + SCREEN_SCALE_X * face.transformedVertices[2].x,
                SCREEN_CENTER_Y + SCREEN_SCALE_Y * face.transformedVertices[2].y,
                color
            );
        }
    }
}
