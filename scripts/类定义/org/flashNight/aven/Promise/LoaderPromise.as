/**
 * org.flashNight.aven.Promise.LoaderPromise
 *
 * Callback → Promise 薄包装层。
 * 将 BaseXMLLoader / BaseJSONLoader 的回调接口桥接为 Promise 接口，
 * 供 ListLoader 等编排器消费。
 *
 * 每次调用创建全新的 Base*Loader 实例（无跨调用缓存）。
 * 缓存由上层领域 loader 的 super.load() 管理。
 */
import org.flashNight.aven.Promise.Promise;
import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;

class org.flashNight.aven.Promise.LoaderPromise {

    /**
     * 加载 XML 文件，返回 Promise。
     * 内部使用 BaseXMLLoader（含 PathManager 路径解析）。
     *
     * @param relativePath 相对于资源根目录的路径（如 "data/items/武器_刀_默认.xml"）
     * @return Promise 成功时 fulfill 为解析后的 Object，失败时 reject 为错误描述 String
     */
    public static function loadXML(relativePath:String):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            var loader:BaseXMLLoader = new BaseXMLLoader(relativePath);
            loader.load(
                function(data:Object):Void {
                    resolve(data);
                },
                function():Void {
                    reject("Failed to load XML: " + relativePath);
                }
            );
        });
    }

    /**
     * 加载 JSON 文件，返回 Promise。
     * 内部使用 BaseJSONLoader（含 PathManager 路径解析）。
     *
     * @param relativePath 相对于资源根目录的路径
     * @param parseType    可选，解析器类型："JSON"（默认）、"LiteJSON"、"FastJSON"
     * @return Promise 成功时 fulfill 为解析后的 Object，失败时 reject 为错误描述 String
     */
    public static function loadJSON(relativePath:String, parseType:String):Promise {
        return new Promise(function(resolve:Function, reject:Function):Void {
            var loader:BaseJSONLoader = new BaseJSONLoader(relativePath, parseType);
            loader.load(
                function(data:Object):Void {
                    resolve(data);
                },
                function(errorMessage:String):Void {
                    reject(errorMessage || ("Failed to load JSON: " + relativePath));
                }
            );
        });
    }
}
