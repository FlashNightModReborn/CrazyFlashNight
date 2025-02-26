import org.flashNight.gesh.string.*;

class org.flashNight.arki.unit.UnitComponent.Initializer.DisplayNameInitializer {
    public static function initialize(target:Object):Void {
        var nameColor:String;

        if (target.是否为敌人 == false) {
            nameColor = "#00FF00"; // Friendly
        } else if (target.是否为敌人 == true) {
            nameColor = "#CC0000"; // Enemy
        } else if (target._name == _root.控制目标) {
            nameColor = "#FFFF00"; // Targeted
        } else {
            nameColor = "#FFFFFF"; // Default
        }

        switch(target.称号)
        {
            case "坛主":
                target.称号 = MansionRandomizer.getRandomName() + target.称号;
                break;
            case "散人":
                target.称号 = HexagramRandomizer.getRandomName() + target.称号;
                break;
        
            default:
                break;
        }

        target.displayName =  "<FONT COLOR='" + nameColor + "'>" + target.名字 + "</FONT>";
    }
}
