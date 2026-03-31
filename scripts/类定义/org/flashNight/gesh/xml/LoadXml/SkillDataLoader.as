import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;

class org.flashNight.gesh.xml.LoadXml.SkillDataLoader extends BaseXMLLoader {
    private static var instance:SkillDataLoader = null;

    public static function getInstance():SkillDataLoader {
        if (instance == null) {
            instance = new SkillDataLoader();
        }
        return instance;
    }

    private function SkillDataLoader() {
        super("data/skills/skills.xml");
    }

    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:SkillDataLoader = this;
        super.load(function(data:Object):Void {
            trace("SkillDataLoader: 文件加载成功！");
            self.applySkillData(data);
            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("SkillDataLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    private function applySkillData(data:Object):Void {
        var 技能表:Array = data.Skill;
        if (技能表 == undefined) return;
        var 技能表对象:Object = new Object();
        for (var i:Number = 0; i < 技能表.length; i++) {
            var 技能对象:Object = 技能表[i];
            if (!技能对象.Name || 技能对象.Name == "") continue;
            技能对象.id = i;
            技能对象.Passive = 技能对象.Type.indexOf("被动") > -1;
            技能对象.Equippable = 技能对象.Type != "被动";
            技能表对象[技能对象.Name] = 技能对象;
        }
        _root.技能表 = 技能表;
        _root.技能表对象 = 技能表对象;
    }

    public function getSkillData():Object {
        return this.getData();
    }

    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        super.reload(onLoadHandler, onErrorHandler);
    }

    public function getData():Object {
        return super.getData();
    }
}