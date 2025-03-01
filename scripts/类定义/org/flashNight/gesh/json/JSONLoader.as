import org.flashNight.neur.Server.ServerManager;

class org.flashNight.gesh.json.JSONLoader {
    private var url:String;
    private var json:IJSON;
    private var onLoadHandler:Function;
    private var onErrorHandler:Function;
    private var parsedData:Object;
    private var parseType:String = "JSON"; // JSON, LiteJSON, FastJSON

    /**
     * Constructor
     * @param jsonURL The URL of the JSON file to load.
     * @param onLoadHandler A callback function to execute when the JSON is loaded successfully.
     * @param onErrorHandler A callback function to execute when an error occurs during loading.
     * @param lenientMode Optional. Whether to enable lenient mode for JSON parsing.
     */
    public function JSONLoader(jsonURL:String, onLoadHandler:Function, onErrorHandler:Function, lenientMode:Boolean, _parseType:String) {
        this.url = jsonURL;
        this.onLoadHandler = onLoadHandler;
        this.onErrorHandler = onErrorHandler;
        switch(_parseType){
            case "LiteJSON":
                this.parseType = "LiteJSON";
                this.json = new LiteJSON();
                break;
            case "FastJSON":
                this.parseType = "FastJSON";
                this.json = new FastJSON();
                break;
            case "JSON":
            default:
                this.parseType = "JSON";
                this.json = new JSON(lenientMode != undefined ? lenientMode : true);
                break;
        }

        this.loadJSON();
    }

    /**
     * Initiates the loading of the JSON file.
     */
    private function loadJSON():Void {
        var self:JSONLoader = this;
        var loader:LoadVars = new LoadVars();
        
        loader.onData = function(rawData:String):Void {
            if (rawData != null) {
                self.handleLoadSuccess(rawData);
            } else {
                self.handleLoadError("Failed to load JSON file.");
            }
        };
        
        loader.load(this.url);
    }

    /**
     * Handles successful loading of the JSON file.
     * @param rawData The raw JSON string data.
     */
    private function handleLoadSuccess(rawData:String):Void {
        try {
            this.parsedData = this.json.parse(rawData);
            
            var errors = this.json["errors"];
            if (errors.length > 0) {
                // Log parsing errors
                for (var i = 0; i < errors.length; i++) {
                    ServerManager.getInstance().sendServerMessage("JSON parsing error: " + errors[i].message);
                }
            }

            if (this.onLoadHandler != null) {
                this.onLoadHandler(this.parsedData);
            }
        } catch (e:Object) {
            this.handleLoadError("JSON parsing error: " + e.message);
        }
    }

    /**
     * Handles errors during loading or parsing.
     * @param errorMessage The error message to log and pass to the error handler.
     */
    private function handleLoadError(errorMessage:String):Void {
        trace("JSONLoader Error: " + errorMessage);
        ServerManager.getInstance().sendServerMessage("JSONLoader Error: " + errorMessage);

        if (this.onErrorHandler != null) {
            this.onErrorHandler(errorMessage);
        }
    }

    /**
     * Returns the parsed JSON data.
     * @return The parsed JSON object.
     */
    public function getParsedData():Object {
        return this.parsedData;
    }
}
