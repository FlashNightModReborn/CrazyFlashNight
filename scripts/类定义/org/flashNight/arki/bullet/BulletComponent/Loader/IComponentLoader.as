interface org.flashNight.arki.bullet.BulletComponent.Loader.IComponentLoader {
    /**
     * 加载并解析子弹相关信息
     * @param data:Object 原始数据
     * @return Object 加载后的信息
     */
    function load(data:Object):Object;
}
