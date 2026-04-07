import org.flashNight.neur.Server.ServerManager;

/**
 * ChunkedBitmapTransport - 分块位图传输层
 *
 * 将 BitmapExporter 产出的 base64 chunks 通过 XMLSocket
 * 以 begin/chunk/end 协议发送到 C# 端。
 *
 * 协议：
 *   begin → {op:"begin", iconName, hash}
 *   chunk × N → {op:"chunk", hash, b64data}
 *   end → {op:"end", hash, current, total}（with callback）
 */
class org.flashNight.neur.Server.ChunkedBitmapTransport {

    /**
     * 发送单个图标的像素数据（所有分块 + 协议包装）。
     *
     * @param taskType  task 路由名（如 "icon_bake"）
     * @param iconName  图标名（业务标识）
     * @param hash      文件名哈希（含帧后缀，如 "df918107_1"）
     * @param chunks    BitmapExporter.render() 返回的分块数组
     * @param current   当前进度序号
     * @param total     总数
     * @param callback  C# end 响应回调 function(resp:Object):Void
     */
    public static function send(
        taskType:String,
        iconName:String,
        hash:String,
        chunks:Array,
        current:Number,
        total:Number,
        callback:Function
    ):Void {
        var sm:ServerManager = ServerManager.getInstance();

        // begin（fire-and-forget）
        sm.sendTaskToNode(taskType, {op: "begin", iconName: iconName, hash: hash});

        // chunks（fire-and-forget）
        var i:Number = 0;
        var len:Number = chunks.length;
        while (i < len) {
            sm.sendTaskToNode(taskType, {op: "chunk", hash: hash, b64data: chunks[i].b64});
            i++;
        }

        // end（with callback）
        sm.sendTaskWithCallback(taskType,
            {op: "end", hash: hash, current: current, total: total},
            null,
            callback
        );
    }
}
