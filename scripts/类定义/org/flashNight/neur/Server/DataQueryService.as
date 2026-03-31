import org.flashNight.neur.Server.ServerManager;

/**
 * Flash 端数据查询服务 — 封装 ServerManager.sendTaskWithCallback，
 * 向 Launcher 的 DataQueryTask 发起 data_query 请求。
 *
 * 用法：
 *   DataQueryService.query("npc_dialogue", {key: npcName, taskProgress: progress}, callback);
 *   DataQueryService.query("merc_bundle", null, callback);
 *
 * callback 签名：function(response:Object):Void
 *   response.success : Boolean
 *   response.result  : 查询结果（success 时）
 *   response.error   : 错误信息（success 为 false 时）
 *
 * 注意：socket 断连时 callback 会被 ServerManager 同步调用 {success:false}。
 */
class org.flashNight.neur.Server.DataQueryService {

    /**
     * 向 Launcher 发起数据查询。
     * @param dataType  查询类型（"npc_dialogue" | "merc_bundle"）
     * @param params    附加参数对象（会被展开合并到 payload），可为 null
     * @param callback  结果回调
     */
    public static function query(
        dataType:String, params:Object, callback:Function
    ):Void {
        var payload:Object = {dataType: dataType};
        if (params != null) {
            for (var k:String in params) payload[k] = params[k];
        }
        ServerManager.getInstance().sendTaskWithCallback(
            "data_query", payload, null, callback
        );
    }

    /**
     * Socket 是否已连接（可走 primary path）。
     */
    public static function isAvailable():Boolean {
        return ServerManager.getInstance().isSocketConnected;
    }
}
