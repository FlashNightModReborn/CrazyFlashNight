import org.flashNight.neur.Server.ServerManager;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.render.BitmapExporter;

/**
 * IconBaker - 图标烘焙状态机
 *
 * 将 Flash 库中的矢量图标光栅化为 256x256 位图，
 * 通过 XMLSocket 分块传输到 C# 端保存为 PNG。
 *
 * 使用：_root.gameCommands["bakeIcons"] 触发 IconBaker.start()
 */
class org.flashNight.arki.item.IconBaker {

    // 状态机阶段
    private static var IDLE:Number = 0;
    private static var SETUP:Number = 2;
    private static var DRAW:Number = 3;
    private static var WAIT_ACK:Number = 4;

    // 运行时状态
    private static var _iconNames:Array;
    private static var _nameToHash:Object;
    private static var _index:Number;
    private static var _total:Number;
    private static var _phase:Number = 0;
    private static var _container:MovieClip;
    private static var _failedIcons:Array;
    private static var _savedQuality:String;

    // 统计（从 C# 端 end 响应累积）
    private static var _created:Number;
    private static var _updated:Number;
    private static var _unchanged:Number;

    // CRC32 查表
    private static var _crcTable:Array;

    /**
     * 启动烘焙流程。
     * 遍历全部物品，去重 icon name，逐个光栅化。
     * @param maxCount 最大烘焙数量，0 或不传表示全量
     */
    public static function start(maxCount:Number):Void {
        if (_phase != IDLE) {
            _root.发布消息("图标烘焙已在进行中");
            return;
        }

        // 收集唯一 icon name + 计算 CRC32
        var seen:Object = {};
        _iconNames = [];
        _nameToHash = {};
        var allItems:Array = ItemUtil.itemDataArray;

        for (var i:Number = 0; i < allItems.length; i++) {
            var iconName:String = allItems[i].icon;
            if (iconName != undefined && iconName != "" && !seen[iconName]) {
                seen[iconName] = true;
                _iconNames.push(iconName);
                _nameToHash[iconName] = crc32(iconName);
            }
        }

        // maxCount > 0 时截取前 N 个（测试用）
        if (maxCount > 0 && maxCount < _iconNames.length) {
            _iconNames = _iconNames.slice(0, maxCount);
        }

        _total = _iconNames.length;
        _index = 0;
        _failedIcons = [];
        _created = 0;
        _updated = 0;
        _unchanged = 0;

        if (_total == 0) {
            _root.发布消息("没有找到图标数据");
            return;
        }

        // 保存原始画质
        _savedQuality = _root._quality;

        // 重置渲染器校准（用第一个图标重新确定缩放比）
        BitmapExporter.resetCalibration();

        _root.发布消息("开始烘焙 " + _total + " 个图标...");

        // 创建隐藏容器
        _container = _root.createEmptyMovieClip("_iconBaker", 9999999);
        _container._visible = false;

        _phase = SETUP;

        // 启动 onEnterFrame 状态机
        _container.onEnterFrame = function():Void {
            org.flashNight.arki.item.IconBaker.tick();
        };
    }

    /**
     * 每帧调度，根据当前阶段执行对应逻辑。
     */
    private static function tick():Void {
        switch (_phase) {
            case SETUP:
                doSetup();
                break;
            case DRAW:
                doDraw();
                break;
            // WAIT_ACK: 空转等回调
        }
    }

    /**
     * SETUP 阶段：创建图标 MC 并固化第 1 帧。
     * 第一帧是图标，第二帧是掉落物时的画面，与需要烘焙的图标无关，直接丢弃。
     * 如果缺少符号或边界异常则记录失败并推进到下一个图标。
     */
    private static function doSetup():Void {
        var iconName:String = _iconNames[_index];
        var symbolName:String = "图标-" + iconName;

        // 清理上一个
        _container.iconHolder.removeMovieClip();
        var holder:MovieClip = _container.createEmptyMovieClip("iconHolder", 1);
        var iconMC:MovieClip = holder.attachMovie(symbolName, "icon", 1);

        if (iconMC == undefined) {
            _root.服务器.发布服务器消息("[IconBaker] 缺少库符号: " + symbolName);
            _failedIcons.push(iconName);
            advanceToNext();
            return;
        }

        iconMC.gotoAndStop(1);
        _root.服务器.发布服务器消息("[IconBaker] SETUP " + (_index + 1) + "/" + _total + ": " + iconName);
        _phase = DRAW;
    }

    /**
     * DRAW 阶段：委托 BitmapExporter 光栅化 + 编码，发送分块到 C#。
     */
    private static function doDraw():Void {
        var iconName:String = _iconNames[_index];
        var hash:String = _nameToHash[iconName];
        var iconMC:MovieClip = _container.iconHolder.icon;

        // 切换到最佳渲染品质
        _root._quality = "BEST";

        // 委托渲染 + 像素提取 + base64 编码
        var chunks:Array = BitmapExporter.render(iconMC);

        // 恢复画质
        _root._quality = _savedQuality;

        if (chunks == null) {
            _root.服务器.发布服务器消息("[IconBaker] 渲染失败: " + iconName);
            _failedIcons.push(iconName);
            advanceToNext();
            return;
        }

        // 发送 begin
        var sm:ServerManager = ServerManager.getInstance();
        sm.sendTaskToNode("icon_bake", {op: "begin", iconName: iconName, hash: hash});

        // 发送分块
        var i:Number = 0;
        while (i < chunks.length) {
            sm.sendTaskToNode("icon_bake", {op: "chunk", hash: hash, b64data: chunks[i].b64});
            i++;
        }

        // 发送 end（with callback）
        _phase = WAIT_ACK;
        sm.sendTaskWithCallback("icon_bake",
            {op: "end", hash: hash, current: _index + 1, total: _total},
            null,
            function(resp:Object):Void {
                org.flashNight.arki.item.IconBaker.onIconSaved(resp);
            }
        );
    }

    /**
     * C# 端 end 响应回调。
     */
    private static function onIconSaved(resp:Object):Void {
        if (resp.success) {
            var action:String = resp.action;
            if (action == "created") _created++;
            else if (action == "updated") _updated++;
            else if (action == "unchanged") _unchanged++;
        } else {
            var iconName:String = _iconNames[_index];
            _root.服务器.发布服务器消息("[IconBaker] 保存失败: " + iconName + " - " + resp.error);
            _failedIcons.push(iconName);
        }
        advanceToNext();
    }

    /**
     * 推进到下一个图标，或完成烘焙。
     */
    private static function advanceToNext():Void {
        _index++;
        if (_index >= _total) {
            // 全部完成
            _phase = IDLE;
            _container.removeMovieClip();

            var msg:String = "烘焙完成: " + _total + " 个图标";
            if (_created > 0) msg += ", 新增 " + _created;
            if (_updated > 0) msg += ", 更新 " + _updated;
            if (_unchanged > 0) msg += ", 未变 " + _unchanged;
            if (_failedIcons.length > 0) msg += ", 失败 " + _failedIcons.length;
            _root.发布消息(msg);

            // 通知 C# 端完成
            var sm:ServerManager = ServerManager.getInstance();
            sm.sendTaskToNode("icon_bake", {
                op: "complete",
                total: _total,
                failed: _failedIcons.length,
                failedNames: _failedIcons
            });
        } else {
            _phase = SETUP;
        }
    }

    // ================================================================
    // CRC32 (ISO 3309, polynomial 0xEDB88320)
    // ================================================================

    /**
     * 初始化 CRC32 查表。
     */
    private static function initCrcTable():Void {
        _crcTable = [];
        for (var i:Number = 0; i < 256; i++) {
            var c:Number = i;
            for (var j:Number = 0; j < 8; j++) {
                if (c & 1) {
                    c = 0xEDB88320 ^ (c >>> 1);
                } else {
                    c = c >>> 1;
                }
            }
            _crcTable[i] = c;
        }
    }

    /**
     * 计算字符串的 CRC32（UTF-8 编码后），返回 8 位十六进制字符串。
     */
    public static function crc32(str:String):String {
        if (_crcTable == undefined) initCrcTable();

        // 转 UTF-8 字节
        var bytes:Array = stringToUTF8Bytes(str);

        var crc:Number = 0xFFFFFFFF;
        for (var i:Number = 0; i < bytes.length; i++) {
            crc = _crcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
        }
        crc = crc ^ 0xFFFFFFFF;

        return padHex8(crc);
    }

    /**
     * 将字符串转为 UTF-8 字节数组。
     */
    private static function stringToUTF8Bytes(str:String):Array {
        var bytes:Array = [];
        var i:Number = 0;
        while (i < str.length) {
            var c:Number = str.charCodeAt(i++);
            if (c >= 0xD800 && c <= 0xDBFF && i < str.length) {
                var c2:Number = str.charCodeAt(i++);
                if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
                    var cp:Number = ((c - 0xD800) << 10) + (c2 - 0xDC00) + 0x10000;
                    bytes.push(0xF0 | ((cp >> 18) & 0x07));
                    bytes.push(0x80 | ((cp >> 12) & 0x3F));
                    bytes.push(0x80 | ((cp >> 6) & 0x3F));
                    bytes.push(0x80 | (cp & 0x3F));
                } else {
                    i--;
                }
            } else if (c < 0x80) {
                bytes.push(c);
            } else if (c < 0x800) {
                bytes.push(0xC0 | (c >> 6));
                bytes.push(0x80 | (c & 0x3F));
            } else {
                bytes.push(0xE0 | (c >> 12));
                bytes.push(0x80 | ((c >> 6) & 0x3F));
                bytes.push(0x80 | (c & 0x3F));
            }
        }
        return bytes;
    }

    /**
     * 将 Number 转为 8 位零填充十六进制字符串。
     */
    private static function padHex8(n:Number):String {
        var hex:String = "0123456789abcdef";
        var s:String = "";
        for (var i:Number = 7; i >= 0; i--) {
            s += hex.charAt((n >>> (i * 4)) & 0xF);
        }
        return s;
    }
}
