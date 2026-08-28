import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.xml.XMLParser;

class org.flashNight.gesh.xml.StageXMLLoader
{
    private var xml:XML;
    private var onLoadHandler:Function;
    private var onErrorHandler:Function;
    private var parsedData:Object;
    private var settled:Boolean = false;

    /**
     * 构造函数，初始化 StageXMLLoader
     * @param xmlFilePath 要加载的 XML 文件地址。
     * @param onLoadHandler 加载完成后的处理函数，接收解析后的对象作为参数。
     * @param onErrorHandler 可选，加载失败后的处理函数。
     */
    public function StageXMLLoader(xmlFilePath:String, onLoadHandler:Function, onErrorHandler:Function)
    {
        this.xml = new XML();
        this.xml.ignoreWhite = true;
        this.onLoadHandler = onLoadHandler;
        this.onErrorHandler = onErrorHandler;

        var self:StageXMLLoader = this;
        this.xml.onLoad = function(loadSuccess:Boolean):Void {
            if (loadSuccess)
            {
                self.handleXMLLoad();
            }
            else
            {
                self.handleXMLError();
            }
        };
        try
        {
            if (this.xml.load(xmlFilePath) !== true)
            {
                this.finishError("XML load did not start");
            }
        }
        catch (loadStartError)
        {
            this.finishError("XML load start exception: " + loadStartError);
        }
    }

    /**
     * 处理 XML 加载完成后的逻辑。
     */
    private function handleXMLLoad():Void
    {
        if (this.settled) return;
        var root:XMLNode = this.xml.firstChild;
        if (root == null)
        {
            this.finishError("XML loaded but has no root element");
            return;
        }
        try
        {
            this.parsedData = XMLParser.parseStageXMLNode(root);
        }
        catch (parseError)
        {
            this.finishError("stage XML parse exception: " + parseError);
            return;
        }
        if (this.parsedData == null)
        {
            this.finishError("stage XML parser returned null");
            return;
        }
        this.finishSuccess();
    }

    /**
     * 处理 XML 加载错误后的逻辑。
     */
    private function handleXMLError():Void
    {
        this.finishError("failed to load XML file");
    }

    private function finishSuccess():Void
    {
        if (this.settled) return;
        this.settled = true;
        var callback:Function = this.onLoadHandler;
        this.releaseCallbacks();
        if (callback != null) callback(this.parsedData);
    }

    private function finishError(reason:String):Void
    {
        if (this.settled) return;
        this.settled = true;
        trace("[StageXMLLoader] " + reason);
        var callback:Function = this.onErrorHandler;
        this.releaseCallbacks();
        if (callback != null) callback();
    }

    private function releaseCallbacks():Void
    {
        if (this.xml != null) this.xml.onLoad = null;
        this.xml = null;
        this.onLoadHandler = null;
        this.onErrorHandler = null;
    }

    /**
     * 获取解析后的数据。
     * @return Object 解析后的数据对象。
     */
    public function getParsedData():Object
    {
        return this.parsedData;
    }
}
