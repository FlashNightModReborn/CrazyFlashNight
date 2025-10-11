class org.flashNight.arki.unit.UnitComponent.Updater.WeatherUpdater {

    public static function getUpdater():Function
    {
        // 使用返回函数绕开class无法使用this的限制
        // as2会对固定闭包实例化，因此重复创建的性能问题不大
        return function():Void {
            var ic:MovieClip = this.新版人物文字信息 || this.人物文字信息;

            // 先记录天气系统状态用于调试

            var targetAlpha:Number = _root.天气系统.人物信息透明度;
            /*
            var 光照等级 = _root.天气系统.获得当前光照等级();
            var 启动等级 = _root.天气系统.时间倍率启动等级;
            _root.服务器.发布服务器消息(this._name + " | 光照:" + 光照等级 + " 启动阈值:" + 启动等级 + " | 透明度:" + 目标透明度);
            */
            // 同步透明度
            ic._alpha = targetAlpha;

            // 依据透明度同步可见性：避免夜间遗漏隐藏
            // 当透明度为0时应该隐藏信息框，避免意外显示
            if (targetAlpha <= 0) {
                ic._visible = false;
            } else if (!ic._visible) {
                // 只有当透明度大于0且当前隐藏时才显示
                ic._visible = true;
            }
        };
    }
}
