class org.flashNight.sara.util.MovieClipUtils {
    private static var getClipFunction:Function;

    // 初始化函数，设置 getClipFunction
    public static function initialize(gameworldClip:MovieClip):Void {
		_root.服务器.发布服务器消息("init " + gameworldClip);
        getClipFunction = function():MovieClip {
            return gameworldClip;
        };
    }
    
    // 创建并返回一个新的 MovieClip 实例，使用 linkageId 和指定的父级 MovieClip
    public static function createLinkedClip(linkageId:String, parent:MovieClip):MovieClip {
        var depth:Number = parent.getNextHighestDepth();
        var newClip:MovieClip = parent.attachMovie(linkageId, linkageId + "_" + depth, depth);
        if (!newClip) {
            trace("Error: Failed to attach movie clip using linkage ID " + linkageId);
            return null;
        }

        _root.服务器.发布服务器消息("createLinkedClip: Created new clip with ID " + linkageId + " at depth " + depth);
        return newClip;
    }

    public static function createEmptyClip(namePrefix:String):MovieClip {
        var parent:MovieClip = getClipFunction(); // 使用 getClipFunction 获取父级
        var depth:Number = parent.getNextHighestDepth();
        var clipName:String = namePrefix ? namePrefix + "_" + depth : "_" + depth;
        return parent.createEmptyMovieClip(clipName, depth);
    }

    public static function createEmptyClipAtDepht(namePrefix:String, depth:Number):MovieClip {
        var parent:MovieClip = getClipFunction();
        if (depth < 0 || depth > 1048575) {
            trace("Error: Invalid depth provided.");
            return null;
        }

        _root.服务器.发布服务器消息("AtDepht " + parent);
        var clipName:String = namePrefix ? namePrefix + "_" + depth : "_" + depth;
        return parent.createEmptyMovieClip(clipName, depth);
    }

    public static function createEmptyClipWithAutoName():MovieClip {
        var parent:MovieClip = getClipFunction();
        var depth:Number = parent.getNextHighestDepth();
        var clipName:String = "_" + depth;

        _root.服务器.发布服务器消息("AutoName " + parent);

        return parent.createEmptyMovieClip(clipName, depth);
    }

	public static function createClipWithCustomParent(getParent:Function):MovieClip {
        var parent:MovieClip = getParent(); // 使用传入的函数获取 parent
        var usedDepth:Number = parent.getNextHighestDepth();
        var clipName:String = "_" + usedDepth;

        _root.服务器.发布服务器消息("CustomParent " + parent);

        return parent.createEmptyMovieClip(clipName, usedDepth);
    }
}
