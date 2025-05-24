import org.flashNight.naki.DataStructures.*;
class org.flashNight.naki.DataStructures.MatrixGraph {
    private var adjacencyMatrix:AdvancedMatrix;
    private var numVertices:Number;
    private var isDirected:Boolean;

    public function MatrixGraph(numVertices:Number, isDirected:Boolean) {
        this.numVertices = numVertices;
        this.isDirected = isDirected;
        var matrixData:Array = [];
        for (var i:Number = 0; i < numVertices * numVertices; i++) {
            matrixData.push(0);
        }
        this.adjacencyMatrix = new AdvancedMatrix(matrixData).init(numVertices, numVertices);
    }

    public function addEdge(u:Number, v:Number, weight:Number):Void {
        this.adjacencyMatrix.setElement(u, v, weight);
        if (!this.isDirected) {
            this.adjacencyMatrix.setElement(v, u, weight);
        }
    }

    public function removeEdge(u:Number, v:Number):Void {
        this.adjacencyMatrix.setElement(u, v, 0);
        if (!this.isDirected) {
            this.adjacencyMatrix.setElement(v, u, 0);
        }
    }

    public function hasEdge(u:Number, v:Number):Boolean {
        return this.adjacencyMatrix.getElement(u, v) != 0;
    }

    public function getEdgeWeight(u:Number, v:Number):Number {
        return this.adjacencyMatrix.getElement(u, v);
    }

    public function getNeighbors(u:Number):Array {
        var neighbors:Array = [];
        for (var v:Number = 0; v < this.numVertices; v++) {
            if (this.adjacencyMatrix.getElement(u, v) != 0) {
                neighbors.push(v);
            }
        }
        return neighbors;
    }

    public function toString():String {
        return "邻接矩阵：\n" + this.adjacencyMatrix.toString();
    }
}
