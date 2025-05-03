class org.flashNight.gesh.depth.DepthNode {
    public var mc:MovieClip;        // 引用的影片剪辑
    public var depth:Number;        // 当前深度
    public var targetDepth:Number;  // 目标深度
    
    public function DepthNode(mc:MovieClip, depth:Number) {
        this.mc = mc;
        this.depth = depth;
        this.targetDepth = depth;
    }
}