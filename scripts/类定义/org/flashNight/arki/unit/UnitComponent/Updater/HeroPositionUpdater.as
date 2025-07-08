class org.flashNight.arki.unit.UnitComponent.Updater.HeroPositionUpdater {
    
    private static var dispatcher;

    private static var heroX:Number;
    private static var heroZ:Number;
    
    public static function init(hero:MovieClip):Void{
        dispatcher = _root.gameworld.dispatcher;
        heroX = hero._x;
        heroZ = hero.Z轴坐标;
    }
    
    public static function update(hero:MovieClip):Void{
        // 更新玩家位置，若位置变化则发布事件
        var publishEvent:Boolean = false;
        if(heroX != hero._x){
            heroX = hero._x;
            publishEvent = true;
        }
        if(heroZ != hero.Z轴坐标){
            heroZ = hero.Z轴坐标;
            publishEvent = true;
        }
        if(publishEvent){
            // 发布玩家位置事件
            dispatcher.publish("HeroMoved", heroX, heroZ);
        }
    }
}
