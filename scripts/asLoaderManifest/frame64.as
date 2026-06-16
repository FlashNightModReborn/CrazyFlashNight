import org.flashNight.arki.unit.HeroUtil;

// 加载主角称号配置
HeroUtil.loadHeroConfig(
    function():Void {
        trace("主程序：主角称号配置加载成功！");
        _root.发布消息("主角称号配置加载完毕");
    },
    function():Void {
        trace("主程序：主角称号配置加载失败，使用默认配置！");
    }
);

import org.flashNight.gesh.xml.LoadXml.MaterialDictionaryLoader;

var 材料大全loader:MaterialDictionaryLoader = MaterialDictionaryLoader.getInstance();

材料大全loader.loadMaterialDictionary(
    function(data:Object):Void {
        trace("主程序：材料大全数据加载成功！");
		_root.发布消息("材料数据加载完毕");
		if(!_root.图鉴信息) _root.图鉴信息 = new Object();
		_root.图鉴信息.材料大全 = data.Material;
    },
    function():Void {
        trace("主程序：材料大全数据加载失败！");
    }
);

// ── 地图面板配置 ──（拓扑收束后，2026-06）
//   两路独立填充 + 一路依赖链：
//   A) AvatarVisibility ← data/map/map_panel.xml (MapAvatarVisibilityLoader async)
//        瘦身后 map_panel.xml 只剩 <avatar_visibility>；失败/缺失 = 空表（默认全可见），仅影响头像门控，不阻塞。
//   B) Catalog (groups/hotspots) ← DataQueryService("map_catalog") async
//        真相源 = launcher/web/modules/map-panel-data.js，build.ps1 Step 1c 派生为 data/map/map_catalog.json。
//        **Catalog 是导航权威：query/结构校验任一失败 = 硬报错 + 地图面板不可用，绝不静默降级。**
//   C) Registry (task_npcs + aliases) ← DataQueryService("task_npc_registry") async
//        真相源同上，build.ps1 Step 1b 派生为 data/map/task_npc_registry.json。
//        依赖 Catalog.HOTSPOT_PAGES → 必须在 Catalog ready 之后（嵌在 B 成功回调内）。
//        失败语义：静默降级（任务红点列表为空），不阻塞游戏进入；错误走 _root.服务器.发布服务器消息 留痕。
import org.flashNight.gesh.xml.LoadXml.MapAvatarVisibilityLoader;
import org.flashNight.arki.map.MapPanelCatalog;
import org.flashNight.arki.map.MapTaskNpcRegistry;
import org.flashNight.neur.Server.DataQueryService;

// A) 头像可见性（独立、可降级）
var mapAvatarLoader:MapAvatarVisibilityLoader = MapAvatarVisibilityLoader.getInstance();
mapAvatarLoader.load(
    function(data:Object):Void {
        if (!MapPanelCatalog.applyAvatarVisibilityFromXml(data)) {
            trace("主程序：地图头像可见性解析失败，降级为默认全可见。");
        } else {
            trace("主程序：地图头像可见性加载成功。");
        }
    },
    function():Void {
        // 加载失败 = 空表 = 默认全可见，不阻塞
        trace("主程序：地图头像可见性文件加载失败，降级为默认全可见。");
    }
);

// B) 导航拓扑 Catalog（导航权威、失败硬报错）→ C) 任务 NPC 注册表（依赖 Catalog）
//   ⚠ 时序：catalog 现经 socket（DataQueryService）取，而非旧版本的本地文件（MapPanelLoader）。
//   sendTaskWithCallback 在 socket 未连接时**立即**回 {success:false,error:"socket not connected"}（不排队）。
//   本 boot 帧在 socket 建连之前就可能执行 → 必须先等 socket 就绪再发 query，否则 catalog 空 →
//   地图只剩 base 页（旧版 task_npc_registry 之所以没踩雷，是因为它嵌在 MapPanelLoader 文件加载回调里，
//   文件加载的异步延迟恰好把 socket 等到了 connected——文件源没了这层缓冲就暴露出来）。
var doMapCatalogQuery:Function = function():Void {
    DataQueryService.query("map_catalog", null, function(resp:Object):Void {
        if (resp == null || !resp.success) {
            var errMsg:String = (resp != null && resp.error != undefined) ? String(resp.error) : "no response";
            trace("主程序：map_catalog query 失败，地图面板不可用: " + errMsg);
            _root.发布消息("[错误] 地图配置加载失败，地图面板不可用: " + errMsg);
            if (_root.服务器 != undefined && _root.服务器.发布服务器消息 != undefined) {
                _root.服务器.发布服务器消息("[MapPanelCatalog] map_catalog query 失败: " + errMsg);
            }
            return;
        }
        if (!MapPanelCatalog.applyFromCatalogJson(resp.result)) {
            trace("主程序：map_catalog 结构不合法，地图面板不可用。");
            _root.发布消息("[错误] 地图配置结构不合法，地图面板不可用");
            if (_root.服务器 != undefined && _root.服务器.发布服务器消息 != undefined) {
                _root.服务器.发布服务器消息("[MapPanelCatalog] applyFromCatalogJson 校验失败（详情见上方留痕）");
            }
            return;
        }
        trace("主程序：地图面板 Catalog 加载成功，发起 task_npc_registry query…");
        DataQueryService.query("task_npc_registry", null, function(resp2:Object):Void {
            if (resp2 == null || !resp2.success) {
                var errMsg2:String = (resp2 != null && resp2.error != undefined) ? String(resp2.error) : "no response";
                if (_root.服务器 != undefined && _root.服务器.发布服务器消息 != undefined) {
                    _root.服务器.发布服务器消息("[MapTaskNpcRegistry] query 失败: " + errMsg2);
                }
                return;
            }
            if (!MapTaskNpcRegistry.applyFromQuery(resp2.result)) {
                if (_root.服务器 != undefined && _root.服务器.发布服务器消息 != undefined) {
                    _root.服务器.发布服务器消息("[MapTaskNpcRegistry] applyFromQuery 校验失败（详情见上方留痕）");
                }
                return;
            }
            trace("主程序：地图任务 NPC 注册表加载完毕");
            _root.发布消息("地图配置加载完毕");
        });
    });
};

// socket 就绪即查；未就绪则等待（最多 ~10s），到点仍未就绪也发 query 让其走正常失败报错路径。
// ⚠ 生命周期：本帧（asLoader 帧 64）在帧 91 会 this.removeMovieClip() 自卸载。绝不能在这里用
//   setInterval + 帧本地闭包轮询——闭包捕获的帧本地变量随时间轴销毁，interval 泄漏且永不触发 query
//   （静默击穿 catalog 的“硬报错”设计）。改用 DataQueryService.whenAvailable：tick clip 挂 _root、
//   等待状态在方法 activation 内，asLoader 卸载后等待门与回调仍存活。详见 DataQueryService.whenAvailable。
DataQueryService.whenAvailable(10000, doMapCatalogQuery);