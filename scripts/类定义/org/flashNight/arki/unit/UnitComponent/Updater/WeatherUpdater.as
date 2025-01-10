class org.flashNight.arki.unit.UnitComponent.Updater.WeatherUpdater {
    
    public static function getUpdater():Function
    {
        return function():Void {
            var ic:MovieClip = this.新版人物文字信息 || this.人物文字信息;
            ic._alpha = _root.天气系统.人物信息透明度;
        };
    }
}
