import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.arki.merc.ArenaDropRuleCatalog;

/**
 * data/arena/arena_drop_rules.xml 的启动期严格加载器。
 *
 * 成功回调只会收到 ArenaDropRuleCatalog.parse() 归一化后的 catalog；
 * 文件缺失、schema 漂移或规则闭包非法都走失败回调，由 BootSequencer 停在加载页。
 */
class org.flashNight.gesh.xml.LoadXml.ArenaDropRulesLoader extends BaseXMLLoader {
    private static var instance:ArenaDropRulesLoader = null;
    private var parsedCatalog:Object = null;

    public static function getInstance():ArenaDropRulesLoader {
        if (instance == null) instance = new ArenaDropRulesLoader();
        return instance;
    }

    private function ArenaDropRulesLoader() {
        super("data/arena/arena_drop_rules.xml");
    }

    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadArenaDropRules(onLoadHandler, onErrorHandler);
    }

    public function loadArenaDropRules(onLoadHandler:Function,
                                       onErrorHandler:Function):Void {
        var self:ArenaDropRulesLoader = this;
        if (self.parsedCatalog != null) {
            if (onLoadHandler != null) onLoadHandler(self.parsedCatalog);
            return;
        }

        super.load(function(raw:Object):Void {
            var parsed:Object = ArenaDropRuleCatalog.parse(raw);
            if (parsed == null) {
                trace("ArenaDropRulesLoader: 文件结构非法！");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            self.parsedCatalog = parsed;
            trace("ArenaDropRulesLoader: 文件加载成功，共 "
                + parsed.sources.length + " 个装备来源");
            if (onLoadHandler != null) onLoadHandler(parsed);
        }, function():Void {
            trace("ArenaDropRulesLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    public function getArenaDropRuleCatalog():Object {
        return this.parsedCatalog;
    }

    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.parsedCatalog = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    public function getData():Object {
        return this.parsedCatalog;
    }
}
