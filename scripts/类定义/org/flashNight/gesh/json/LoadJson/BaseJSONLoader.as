import org.flashNight.gesh.json.JSONLoader;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.json.LoadJson.BaseJSONLoader {
    private var data:Object = null;
    private var _isLoading:Boolean = false; // Indicates if data is being loaded
    private var filePath:String;
    private var parseType:String = "JSON"; // JSON, LiteJSON, FastJSON

    /**
     * Constructor to initialize the JSON loader.
     * @param relativePath String The file path relative to the resource directory.
     */
    public function BaseJSONLoader(relativePath:String, _parseType:String) {
        // Initialize the path manager
        PathManager.initialize();
        if (!PathManager.isEnvironmentValid()) {
            trace("BaseJSONLoader: Resource directory not detected, cannot load file!");
            return;
        }

        // Resolve the full file path
        this.filePath = PathManager.resolvePath(relativePath);
        if (this.filePath == null) {
            trace("BaseJSONLoader: Failed to resolve path, cannot load file!");
        }

        this.parseType = _parseType;
    }

    /**
     * Loads the JSON file.
     * @param onLoadHandler Function Callback function for successful load, receiving parsed data as a parameter.
     * @param onErrorHandler Function Callback function for load failure.
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this._isLoading) {
            trace("BaseJSONLoader: Data is currently being loaded, please avoid duplicate loads!");
            return;
        }

        if (this.data != null) {
            trace("BaseJSONLoader: Data already loaded, directly invoking callback.");
            if (onLoadHandler != null) onLoadHandler(this.data);
            return;
        }

        if (this.filePath == null) {
            trace("BaseJSONLoader: Invalid file path, cannot load!");
            if (onErrorHandler != null) onErrorHandler();
            return;
        }

        this._isLoading = true;
        var self:BaseJSONLoader = this;

        trace("BaseJSONLoader: Starting file load: " + this.filePath);

        // Use JSONLoader to load the file
        new JSONLoader(this.filePath, function(parsedData:Object):Void {
            self._isLoading = false;
            self.data = parsedData; // Save data to the instance variable
            trace("BaseJSONLoader: File loaded successfully!");
            if (onLoadHandler != null) onLoadHandler(parsedData);
        }, function(errorMessage:String):Void {
            self._isLoading = false;
            trace("BaseJSONLoader: File load failed! Error: " + errorMessage);
            if (onErrorHandler != null) onErrorHandler(errorMessage);
        }, null, this.parseType);
    }

    /**
     * Reloads the JSON file, ignoring cached data.
     * @param onLoadHandler Function Callback function for successful load.
     * @param onErrorHandler Function Callback function for load failure.
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.data = null; // Clear existing data
        this.load(onLoadHandler, onErrorHandler);
    }

    /**
     * Retrieves the loaded data.
     * @return Object Parsed data object, or null if not loaded.
     */
    public function getData():Object {
        return this.data;
    }

    /**
     * Checks if data has been loaded.
     * @return Boolean True if data is loaded, otherwise false.
     */
    public function isLoaded():Boolean {
        return this.data != null;
    }

    /**
     * Checks if data is currently being loaded.
     * @return Boolean True if loading is in progress, otherwise false.
     */
    public function isLoadingStatus():Boolean {
        return this._isLoading;
    }

    /**
     * Converts the loaded data to a string for debugging or logging.
     * @return String String representation of the loaded data.
     */
    public function toString():String {
        return ObjectUtil.toString(this.getData());
    }
}
