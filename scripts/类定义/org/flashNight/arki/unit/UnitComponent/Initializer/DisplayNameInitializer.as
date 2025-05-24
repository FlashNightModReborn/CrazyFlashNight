import org.flashNight.gesh.string.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.DisplayNameInitializer {
    // 表驱动映射，存储称号与对应的处理函数
    private static var _titleHandlers:Object = initializeHandlers();

    // 初始化处理函数映射表（只初始化一次）
    private static function initializeHandlers():Object {
        var obj:Object = {
            坛主: function(target:Object):Void {
                target.称号 = MansionRandomizer.getRandomName() + target.称号;
            },
            散人: function(target:Object):Void {
                target.称号 = HexagramRandomizer.getRandomName() + target.称号;
            }
            // 可在此继续添加新的称号处理逻辑
        };

        return obj;
    }

    // 新增：格式化显示名称的函数
    public static function formatDisplayName(color:String, level:Number, name:String):String {
        return color + "Lv." + level + "   " + name + "</FONT>";
    }

    public static function initialize(target:Object):Void {
        var nameColor:String;

        // 初始化颜色判断逻辑保持不变

        if(target._name == _root.控制目标)
        {
            nameColor = "#FFFF00";
        }
        else if(target.是否为敌人 == false)
        {
            nameColor = "#00FF00";
        }
        else if(target.是否为敌人 == true)
        {
            nameColor = "#CC0000";
        }
        else
        {
            nameColor = "#FFFFFF";
        }

        // 表驱动处理逻辑
        var currentTitle:String = target.称号;
        if (_titleHandlers[currentTitle] != undefined) {
            // 执行对应的处理函数
            _titleHandlers[currentTitle](target);
        }

        if(!currentTitle) {
            target.新版人物文字信息.称号文本框.removeMovieClip();
        }

        if(target.新版人物文字信息) {
            target.人物文字信息.unloadMovie();
        }
        

        var color:String = "<FONT COLOR='" + nameColor + "'>";

        // 设置显示名称（保持不变）
        target.displayName = formatDisplayName(color, target.等级, target.名字);
    }
}