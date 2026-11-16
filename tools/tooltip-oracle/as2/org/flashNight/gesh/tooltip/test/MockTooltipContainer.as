/**
 * MockTooltipContainer - 测试用注释框容器
 *
 * 使用真实 createEmptyMovieClip + createTextField 构建，
 * 对齐 flashswf/UI/注释框/LIBRARY/sprite/注释框.xml 资产结构。
 */
class org.flashNight.gesh.tooltip.test.MockTooltipContainer {
    private static var _saved;
    private static var MOCK_DEPTH:Number = 19999;

    public static function install():Void {
        _saved = _root.注释框;
        delete _root.注释框;
        var c:MovieClip = _root.createEmptyMovieClip("注释框", MOCK_DEPTH);

        // 子 MC — 深度对齐 XML 资产层级
        c.createEmptyMovieClip("背景", 4);
        c.createEmptyMovieClip("简介背景", 3);
        c.createEmptyMovieClip("物品图标定位", 2);

        // 真实 TextField — 对齐 XML 资产属性
        c.createTextField("文本框", 5, 0, 0, 56, 60);
        c.createTextField("简介文本框", 6, 0, 0, 56, 60);

        var fields:Array = [c.文本框, c.简介文本框];
        for (var i:Number = 0; i < fields.length; i++) {
            var tf:TextField = fields[i];
            tf.html = true;
            tf.multiline = true;
            tf.wordWrap = true;
            tf.selectable = false;
        }
        // 初始化背景尺寸
        c.背景._width = 83;
        c.背景._height = 83;
        c.简介背景._width = 200;
        c.简介背景._height = 83;
    }

    public static function teardown():Void {
        _root.注释框.removeMovieClip();
        delete _root.注释框;
        if (_saved != undefined && _saved != null) {
            _root.注释框 = _saved;
        }
        _saved = undefined;
    }
}
