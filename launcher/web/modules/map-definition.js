// Launcher 在页面创建前注入 C# 校验后的启动快照；开发服务器提供同一 data/map 定义。
if (typeof MapDefinitionData === 'undefined') {
    throw new Error(window.MapDefinitionLoadError || '请通过启动器或仓库开发服务器加载地图定义。');
}
