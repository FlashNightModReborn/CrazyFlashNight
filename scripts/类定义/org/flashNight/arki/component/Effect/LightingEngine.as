/**
 * LightingEngine.as (ActionScript 2)
 * 位于：org.flashNight.arki.component.Effect
 *
 * 光照处理引擎类，负责处理游戏中的光照效果和色彩调整。
 * 提供光照参数生成、光照效果应用等功能，支持矩阵变换和基础变换两种模式。
 * 
 * 主要功能：
 * - 根据光照等级和视觉情况生成色彩调整参数
 * - 应用光照效果到目标MovieClip
 * - 支持实时计算，无缓存机制（优化内存使用） 
 * 
 * 用法示例：
 *   import org.flashNight.arki.component.Effect.LightingEngine;
 *   // 应用光照效果
 *   LightingEngine.applyLighting(_root.gameworld, 5.5, "光照", true);
 *   // 生成光照参数
 *   var params = LightingEngine.generateLightParameters(3.2, "夜视");
 */
import org.flashNight.arki.component.Effect.ColorEngine;
import flash.geom.ColorTransform;
import flash.filters.ColorMatrixFilter;

class org.flashNight.arki.component.Effect.LightingEngine {
    
    /**
     * 光照等级映射表的引用
     * 从 _root.色彩引擎.光照等级映射表 获取数据
     */
    private static function getLightLevelMappingTable():Object {
        return _root.色彩引擎.光照等级映射表;
    }
    
    /**
     * 获取空的ColorTransform对象
     */
    private static function getEmptyColorTransform():ColorTransform {
        var emptyTransform:ColorTransform = _root.色彩引擎.空调整颜色;
        if (!emptyTransform) {
            emptyTransform = ColorEngine.emptyColorTransform;
        }
        return emptyTransform;
    }
    
    /**
     * 线性插值函数
     * 
     * @param value 当前值
     * @param start 起始值  
     * @param end 结束值
     * @param startOutput 起始输出值
     * @param endOutput 结束输出值
     * @return 插值结果
     */
    private static function linearInterpolation(value:Number, start:Number, end:Number, startOutput:Number, endOutput:Number):Number {
        if (start == end) return startOutput;
        var ratio:Number = (value - start) / (end - start);
        return startOutput + ratio * (endOutput - startOutput);
    }
    
    /**
     * 生成光照调整参数
     * 根据光照等级和视觉情况生成色彩调整参数对象
     * 
     * @param lightLevel 光照等级 (0-10)
     * @param visualCondition 视觉情况 ("光照", "夜视" 等)
     * @return 包含色彩调整参数的对象，如果光照等级为7则返回null
     */
    public static function generateLightParameters(lightLevel:Number, visualCondition:String):Object {
        if (lightLevel === 7) {
            return null; // 光照等级为7时卸载特殊调整
        }
        
        var mappingTable:Object = LightingEngine.getLightLevelMappingTable();
        if (!mappingTable || !mappingTable[visualCondition]) {
            return null;
        }
        
        var params:Object = {};
        var baseLevel:Number, nextLevel:Number, baseData:Object, nextData:Object;
        
        if (lightLevel >= 0) {
            if (lightLevel <= 9) {
                baseLevel = Math.floor(lightLevel);
                nextLevel = Math.ceil(lightLevel);
            } else {
                // 使用等级8和9的数据进行插值
                baseLevel = 8;
                nextLevel = 9;
            }
            
            baseData = mappingTable[visualCondition][baseLevel];
            nextData = mappingTable[visualCondition][nextLevel];
            
            if (!baseData || !nextData) {
                return null;
            }
            
            // 获取映射表中当前和下一等级的数据
            params = {
                红色乘数: LightingEngine.linearInterpolation(lightLevel, baseLevel, nextLevel, baseData.红色乘数, nextData.红色乘数),
                绿色乘数: LightingEngine.linearInterpolation(lightLevel, baseLevel, nextLevel, baseData.绿色乘数, nextData.绿色乘数),
                蓝色乘数: LightingEngine.linearInterpolation(lightLevel, baseLevel, nextLevel, baseData.蓝色乘数, nextData.蓝色乘数),
                透明乘数: LightingEngine.linearInterpolation(lightLevel, baseLevel, nextLevel, baseData.透明乘数, nextData.透明乘数),
                亮度: LightingEngine.linearInterpolation(lightLevel, baseLevel, nextLevel, baseData.亮度, nextData.亮度),
                对比度: LightingEngine.linearInterpolation(lightLevel, baseLevel, nextLevel, baseData.对比度, nextData.对比度),
                饱和度: LightingEngine.linearInterpolation(lightLevel, baseLevel, nextLevel, baseData.饱和度, nextData.饱和度),
                色相: LightingEngine.linearInterpolation(lightLevel, baseLevel, nextLevel, baseData.色相, nextData.色相)
            };
        }
        
        return params;
    }
    
    /**
     * 应用光照效果到目标MovieClip
     * 根据光照等级、视觉情况和渲染模式调整目标的颜色
     * 
     * @param target 目标影片剪辑
     * @param lightLevel 光照等级 (0-10)
     * @param visualCondition 视觉情况 ("光照", "夜视" 等)
     * @param useMatrixTransform 是否使用矩阵变换模式
     */
    public static function applyLighting(target:MovieClip, lightLevel:Number, visualCondition:String, useMatrixTransform:Boolean):Void {
        if (!target) return;
        
        var realLightLevel:Number = Math.round(lightLevel * 10) / 10;
        
        // 光照等级为7时不使用任何变换，节约性能
        if (realLightLevel === 7) {
            target.filters = [];
            target.transform.colorTransform = LightingEngine.getEmptyColorTransform();
            return;
        }
        
        // 检查是否需要切换调整模式
        if (target.使用矩阵变换 !== useMatrixTransform) {
            target.使用矩阵变换 = useMatrixTransform;
            _global.ASSetPropFlags(target, ["使用矩阵变换"], 1, false);
            
            if (useMatrixTransform) {
                // 清除可能存在的ColorTransform设置
                target.transform.colorTransform = LightingEngine.getEmptyColorTransform();
            } else {
                // 清除可能存在的ColorMatrixFilter设置
                target.filters.length = 0;
            }
        }
        
        // 实时计算并应用色彩调整
        var params:Object = LightingEngine.generateLightParameters(realLightLevel, visualCondition);
        if (params) {
            if (useMatrixTransform) {
                var filter:ColorMatrixFilter = ColorEngine.adjustColor(target, params);
            } else {
                var transform:ColorTransform = ColorEngine.basicAdjustColor(target, params);
            }
        }
    }
    
    /**
     * 兼容性方法：设置滤镜
     * 提供与原有代码的兼容性
     * 
     * @param target 目标影片剪辑
     * @param filterInstance 滤镜实例
     * @param filterType 滤镜类型
     */
    public static function setFilter(target:MovieClip, filterInstance:Object, filterType:Function):Void {
        ColorEngine.setFilter(target, filterInstance, filterType);
    }
}