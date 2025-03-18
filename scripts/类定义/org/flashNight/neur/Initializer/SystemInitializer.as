// org.flashNight.neur.Initializer.SystemInitializer
class org.flashNight.neur.Initializer.SystemInitializer {
    private static var instance:SystemInitializer;
    private var _initializationQueue:Array;
    private var _isInitializing:Boolean;

    private function SystemInitializer() {
        _initializationQueue = [];
        _isInitializing = false;
    }

    public static function getInstance():SystemInitializer {
        if (!instance) {
            instance = new SystemInitializer();
        }
        return instance;
    }

    public function registerComponent(target:Object):Void {
        if (typeof(target.initialize) == "function") {
            _initializationQueue.push(target);
        } else {
            trace("[WARNING] Target does not implement IInitializable: " + target);
        }
    }

    public function startInitialization():Void {
        if (_isInitializing) {
            trace("[WARNING] Initialization is already in progress");
            return;
        }
        
        _isInitializing = true;
        trace("=== Starting System Initialization ===");
        _executeNext();
    }

    private function _executeNext():Void {
        if (_initializationQueue.length > 0) {
            var target:Object = _initializationQueue.shift();
            try {
                trace(">> Initializing: " + target.toString());
                target.initialize();
                _createAsyncCallback(); // 关键改进点
            } catch (e:Error) {
                trace("[ERROR] Failed to initialize " + target + ": " + e.message);
                _executeNext();
            }
        } else {
            trace("=== System Initialization Complete ===");
            _isInitializing = false;
        }
    }

    private function _createAsyncCallback():Void {
        var self:SystemInitializer = this;
        var callback:Function = function() {
            self._executeNext();
            delete self["_asyncCallback"];
        };
        
        // 轻量级异步方案
        this._asyncCallback = setTimeout(callback, 0);

    }

    private function _createHiddenLoader():MovieClip {
        var depth:Number = getNextHighestDepth(_root);
        var mc:MovieClip = _root.createEmptyMovieClip("__asyncLoader"+depth, depth);
        mc._visible = false;
        return mc;
    }

}
