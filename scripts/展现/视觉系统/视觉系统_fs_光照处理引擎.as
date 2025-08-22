

_root.色彩引擎.生成光照调整参数 = function(光照等级, 视觉情况) 
{
    if(光照等级 === 7)
    {
        return null;//光照等级为7时卸载特殊调整
    }

    var 线性插值 = _root.常用工具函数.线性插值;
    var 参数 = {};
    var baseLevel, nextLevel, baseData, nextData;
    
    if (光照等级 >= 0) 
    {
        if (光照等级 <= 9) 
        {
            baseLevel = Math.floor(光照等级);
            nextLevel = Math.ceil(光照等级);
        } 
        else 
        {
            baseLevel = 8; // 使用等级8和9的数据进行插值
            nextLevel = 9;
        }
        
        baseData = _root.色彩引擎.光照等级映射表[视觉情况][baseLevel];
        nextData = _root.色彩引擎.光照等级映射表[视觉情况][nextLevel];// 获取映射表中当前和下一等级的数据

        参数 = {
            红色乘数: 线性插值(光照等级, baseLevel, nextLevel, baseData.红色乘数, nextData.红色乘数),
            绿色乘数: 线性插值(光照等级, baseLevel, nextLevel, baseData.绿色乘数, nextData.绿色乘数),
            蓝色乘数: 线性插值(光照等级, baseLevel, nextLevel, baseData.蓝色乘数, nextData.蓝色乘数),
            透明乘数: 线性插值(光照等级, baseLevel, nextLevel, baseData.透明乘数, nextData.透明乘数),
            亮度: 线性插值(光照等级, baseLevel, nextLevel, baseData.亮度, nextData.亮度),
            对比度: 线性插值(光照等级, baseLevel, nextLevel, baseData.对比度, nextData.对比度),
            饱和度: 线性插值(光照等级, baseLevel, nextLevel, baseData.饱和度, nextData.饱和度),
            色相: 线性插值(光照等级, baseLevel, nextLevel, baseData.色相, nextData.色相)
        };
    } 
    return 参数;
};



_root.色彩引擎.根据光照调整颜色 = function(影片剪辑, 光照等级, 视觉情况, 使用矩阵变换) 
{
    if(!影片剪辑) return;
    var 真实光照 = Math.round(光照等级 * 10) / 10;
    if(真实光照 === 7)
    {
        影片剪辑.filters = [];
        影片剪辑.transform.colorTransform = _root.色彩引擎.空调整颜色;
        return;//光照等级为7时不使用任何变换，节约性能
    }
    
    // 检查是否需要切换调整模式
    if (影片剪辑.使用矩阵变换 !== 使用矩阵变换) 
    {
        影片剪辑.使用矩阵变换 = 使用矩阵变换;
        _global.ASSetPropFlags(影片剪辑, ["使用矩阵变换"], 1, false);
        if (使用矩阵变换) 
        {
            影片剪辑.transform.colorTransform = this.空调整颜色;// 清除可能存在的ColorTransform设置
        } 
        else 
        {
            影片剪辑.filters.length = 0;// 清除可能存在的ColorMatrixFilter设置
        }
    }

    // 实时计算并应用色彩调整
    var 参数 = this.生成光照调整参数(真实光照, 视觉情况);
    if (使用矩阵变换) 
    {
        this.调整颜色(影片剪辑, 参数);
    } 
    else 
    {
        this.初级调整颜色(影片剪辑, 参数);
    }
};


