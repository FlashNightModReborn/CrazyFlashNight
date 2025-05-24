import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.xml.XMLParser;

class org.flashNight.gesh.xml.XMLLoader
{
    private var xml:XML;
    private var onLoadHandler:Function;
    private var onErrorHandler:Function;
    private var parsedData:Object;

    /**
     * 构造函数，初始化 XMLLoader
     * @param xmlFilePath 要加载的 XML 文件地址。
     * @param onLoadHandler 加载完成后的处理函数，接收解析后的对象作为参数。
     * @param onErrorHandler 可选，加载失败后的处理函数。
     */
    public function XMLLoader(xmlFilePath:String, onLoadHandler:Function, onErrorHandler:Function)
    {
        this.xml = new XML();
        this.xml.ignoreWhite = true;
        this.onLoadHandler = onLoadHandler;
        this.onErrorHandler = onErrorHandler;

        var self:XMLLoader = this;
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
        this.xml.load(xmlFilePath);
    }

    /**
     * 处理 XML 加载完成后的逻辑。
     */
    private function handleXMLLoad():Void
    {
        this.parsedData = XMLParser.parseXMLNode(this.xml.firstChild);
        if (this.onLoadHandler != null)
        {
            this.onLoadHandler(this.parsedData);
        }
    }

    /**
     * 处理 XML 加载错误后的逻辑。
     */
    private function handleXMLError():Void
    {
        trace("XMLLoader: Failed to load XML file.");
        if (this.onErrorHandler != null)
        {
            this.onErrorHandler();
        }
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
