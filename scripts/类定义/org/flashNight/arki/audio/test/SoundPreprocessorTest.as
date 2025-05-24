/**
 * 文件：org/flashNight/arki/audio/test/SoundPreprocessorTest.as
 * 说明：测试 SoundPreprocessor 的异步加载与数据结构构建过程。
 *       加载 "武器"、"特效"、"人物" 三个分类的 XML 后，
 *       序列化输出 soundSourceDict 供调试。
 */

import org.flashNight.arki.audio.SoundPreprocessor;
import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader; // 假设此类已存在，并支持 load(successCallback, errorCallback)

class org.flashNight.arki.audio.test.SoundPreprocessorTest {

    private var preprocessor:SoundPreprocessor;
    // 记录已完成加载的分类数
    private var categoriesLoaded:Number = 0;
    // 总共需要加载的分类数
    private var totalCategories:Number = 3;
    
    public function SoundPreprocessorTest() {
        trace("===== SoundPreprocessorTest Begin =====");
        
        // 1) 创建 SoundPreprocessor 实例
        //    若不传 container，则默认在 _root 上创建 soundManager
        preprocessor = new SoundPreprocessor(null);
        
        // 2) 逐个加载三类音效的 XML（可直接调用 preprocessor.loadCategoryXML 也可手动调用 BaseXMLLoader）
        //    这里演示手动链式加载，以便在测试类中演示异步处理
        this.loadCategory("武器", "sounds/音效-武器/DOMDocument.xml");
        this.loadCategory("特效", "sounds/音效-特效/DOMDocument.xml");
        this.loadCategory("人物", "sounds/音效-人物/DOMDocument.xml");
    }
    
    /**
     * 加载指定分类的 XML，并在回调中更新 soundSourceDict。
     * 加载完成后递增 categoriesLoaded，检测是否所有分类均已加载完成。
     */
    private function loadCategory(category:String, xmlPath:String):Void {
        var self:SoundPreprocessorTest = this;
        var loader:BaseXMLLoader = new BaseXMLLoader(xmlPath);
        
        loader.load(
            function(domdata:Object):Void {
                // 从返回的 domdata 中提取 linkageIdentifier，存入 preprocessor.soundSourceDict
                var soundItems:Object = domdata.media.DOMSoundItem;
                for (var i in soundItems) {
                    var soundIdentifier:String = soundItems[i].linkageIdentifier;
                    if (soundIdentifier != null) {
                        self.preprocessor.soundSourceDict[soundIdentifier] = category;
                    }
                }
                trace("[SoundPreprocessorTest] Loaded category: " + category);
                self.categoriesLoaded++;
                self.checkAllLoaded();
            },
            function():Void {
                trace("[SoundPreprocessorTest] Failed to load category: " + category);
                // 即使加载失败也算一次完成，以便不阻塞后续流程
                self.categoriesLoaded++;
                self.checkAllLoaded();
            }
        );
    }
    
    /**
     * 当所有分类加载完成后，输出 soundSourceDict 的序列化结果。
     */
    private function checkAllLoaded():Void {
        if (this.categoriesLoaded >= this.totalCategories) {
            trace("==== All categories loaded or attempted ====");
            // 输出当前的 soundSourceDict
            var serialized:String = serializeSoundSourceDict(preprocessor.soundSourceDict);
            trace(serialized);
            trace("===== SoundPreprocessorTest End =====");
        }
    }
    
    /**
     * 将 soundSourceDict 序列化为可读字符串，便于外部调试
     */
    private function serializeSoundSourceDict(dict:Object):String {
        var str:String = "===== soundSourceDict contents =====\n";
        for (var key in dict) {
            str += "  " + key + " -> " + dict[key] + "\n";
        }
        str += "====================================\n";
        return str;
    }
    
    /**
     * 可在编译时指定该类为 main，也可在其他代码中手动 new SoundPreprocessorTest()
     */
    public static function main():Void {
        var test:SoundPreprocessorTest = new SoundPreprocessorTest();
    }
}
