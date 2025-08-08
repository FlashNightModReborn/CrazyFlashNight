/**
 * @class org.flashNight.arki.corpse.CorpseStampSystem
 * @classdesc
 * 尸体/印章系统，一个轻量级的工具类，用于将 BitmapData “印”到一个可复用的影片剪辑上。
 *
 * 核心目的：
 * 作为 ActionScript 2 中 BitmapData.draw() API 的桥梁。由于 draw() 的源通常需要是
 * 一个影片剪辑，本系统提供了一个高效的方式来将内存中的 BitmapData 资产转换为
 * 一个临时的、可用于绘制的影片剪辑“画刷”或“印章”。
 *
 * 工作流程：
 * 1. 游戏启动或过图后，调用 initialize() 来在 _root.gameworld 上创建印章MC。
 * 2. 当需要绘制血迹/弹坑时，调用 getStamp(bitmapData) 获取已配置好的印章MC。
 * 3. 将返回的印章MC作为源，传递给 BitmapData.draw() 或 DeathEffectRenderer 进行绘制。
 *
 * 注意：本系统依赖 _root.gameworld，请确保在使用前其已正确初始化。
 */
class org.flashNight.arki.corpse.CorpseStampSystem {

    // ------------------ 私有常量 ------------------

    /** @private {String} 印章影片剪辑在 gameworld 上的实例名 */
    private static var STAMP_MC_NAME:String = "global_corpseStampMC";
    /** @private {Number} 印章影片剪辑在 gameworld 上的深度，设置较高以避免遮挡 */
    private static var STAMP_MC_DEPTH:Number = 30000;

    // ------------------ 私有静态变量 ------------------

    /** @private {MovieClip} 全局可复用的印章影片剪辑实例 */
    private static var stampMC:MovieClip;
    /** @private {Boolean} 标记系统是否已成功初始化 */
    private static var isInitialized:Boolean = false;


    // ------------------ 公共 API ------------------

    /**
     * 初始化或重置印章系统。
     * 此方法应在游戏启动或每次场景切换（gameworld 重载）后调用。
     * 它会确保印章影片剪辑存在并可供使用。
     *
     * @return {Void}
     */
    public static function initialize():Void {
        var gameWorld:MovieClip = _root.gameworld;
        if (gameWorld == undefined) {
            trace("CorpseStampSystem Error: _root.gameworld not found. System cannot be initialized.");
            isInitialized = false;
            return;
        }

        // 如果之前的实例存在（例如在非重载的重置场景中），先移除
        if (gameWorld[STAMP_MC_NAME] != undefined) {
            gameWorld[STAMP_MC_NAME].removeMovieClip();
        }

        // 创建新的空影片剪辑作为印章
        stampMC = gameWorld.createEmptyMovieClip(STAMP_MC_NAME, STAMP_MC_DEPTH);

        if (stampMC != undefined) {
            isInitialized = true;
        } else {
            isInitialized = false;
            trace("CorpseStampSystem Error: Failed to create the stamp MovieClip on _root.gameworld.");
        }
    }

    /**
     * 获取已附加上指定位图的印章影片剪辑。
     * 这是本系统的核心功能。
     *
     * @param {BitmapData} sourceBitmap - 需要被附加到印章上的位图数据。
     * @return {MovieClip} 返回配置好的印章影片剪辑。如果系统未初始化或输入无效，则返回 undefined。
     */
    public static function getStamp(sourceBitmap:BitmapData):MovieClip {
        // 如果系统未初始化，尝试进行一次即时初始化
        if (!isInitialized) {
            CorpseStampSystem.initialize();
            // 如果初始化仍然失败，则无法继续
            if (!isInitialized) return undefined;
        }
        
        if (sourceBitmap == undefined) {
            trace("CorpseStampSystem Warning: getStamp() was called with null or undefined BitmapData.");
            return undefined;
        }

        // 将位图附加到印章MC上。attachBitmap 会覆盖在同一深度上已有的位图。
        // 使用深度 1，这是相对于 stampMC 内部的深度。
        // smoothing 设置为 false 通常对像素风格的血迹效果更好。
        stampMC.attachBitmap(sourceBitmap, 1, "auto", false);

        return stampMC;
    }
}