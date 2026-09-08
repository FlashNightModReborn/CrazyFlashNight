import org.flashNight.gesh.string.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.DisplayNameInitializer {
    // 表驱动映射，存储称号与对应的处理函数
    private static var _titleHandlers:Object = initializeHandlers();

    // 初始化处理函数映射表（只初始化一次）
    private static function initializeHandlers():Object {
        var obj:Object = {
            坛主: function(target:Object):Void {
                target.称号 = MansionRandomizer.getInstance().getRandomName() + target.称号;
            },
            散人: function(target:Object):Void {
                target.称号 = HexagramRandomizer.getInstance().getRandomName() + target.称号;
            },
            军阀: function(target:Object):Void {
                target.称号 = JuntaRandomizer.getInstance().getRandomName();
            }
            // 可在此继续添加新的称号处理逻辑
        };

        return obj;
    }

    // 新增：格式化显示名称的函数
    public static function formatDisplayName(color:String, level:Number, makeBold:String, name:String):String {
        return color + "Lv." + level + "   " + makeBold + name + "</B>" + "</FONT>";
    }

    public static function initialize(target:Object):Void {
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


        refreshName(target, false);
    }

    /** 仅刷新姓名投影，整形不重新随机称号或卸载文字层。 */
    public static function refreshName(target:Object, plainName:Boolean):Void {
        var nameColor:String;
        var shouldBeBold:String;

        // 初始化颜色判断逻辑保持不变

        if(target._name == _root.控制目标)
        {
            nameColor = "#FFFF00";
            shouldBeBold = "";
        }
        else if(target.是否为敌人 == false)
        {
            nameColor = "#00FF00";
            shouldBeBold = "";
        }
        else if(target.是否为敌人 == true)
        {
            nameColor = "#FF2222";
            shouldBeBold = "";
        }
        else
        {
            nameColor = "#FFFFFF";
            shouldBeBold = "<B>";
        }

        var name:String = String(target.名字);
        if (plainName) name = name.split("&").join("&amp;").split("<").join("&lt;").split(">").join("&gt;");
        target.displayName = formatDisplayName("<FONT COLOR='" + nameColor + "'>", target.等级, shouldBeBold, name);
    }
}
