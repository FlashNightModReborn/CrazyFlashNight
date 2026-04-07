import org.flashNight.neur.Server.ServerManager;
import org.flashNight.neur.Server.ChunkedBitmapTransport;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.render.BitmapExporter;

/**
 * IconBaker - 图标烘焙状态机
 *
 * 将 Flash 库中的矢量图标光栅化为 256x256 位图，
 * 每个图标导出两帧（f1=图标, f2=掉落物），
 * 通过 ChunkedBitmapTransport 分块传输到 C# 端保存为 PNG。
 *
 * 使用：_root.gameCommands["bakeIcons"] 触发 IconBaker.start()
 */
class org.flashNight.arki.item.IconBaker {

    // 状态机阶段
    private static var IDLE:Number = 0;
    private static var SETUP:Number = 2;
    private static var DRAW_F1:Number = 3;
    private static var WAIT_F1:Number = 4;
    private static var DRAW_F2:Number = 5;
    private static var WAIT_F2:Number = 6;

    // 运行时状态
    private static var _iconNames:Array;
    private static var _nameToHash:Object;
    private static var _index:Number;
    private static var _total:Number;
    private static var _phase:Number = 0;
    private static var _container:MovieClip;
    private static var _failedIcons:Array;
    private static var _savedQuality:String;
    private static var _isFullBake:Boolean;

    // 统计（按图标粒度，非帧粒度）
    private static var _created:Number;
    private static var _updated:Number;
    private static var _unchanged:Number;
    // 当前图标的最高优先级动作：created > updated > unchanged
    private static var _iconAction:String;

    // CRC32 查表
    private static var _crcTable:Array;

    // 任务路由名
    private static var TASK:String = "icon_bake";

    /**
     * 启动烘焙流程。
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

        var i:Number = 0;
        while (i < allItems.length) {
            var iconName:String = allItems[i].icon;
            if (iconName != undefined && iconName != "" && !seen[iconName]) {
                seen[iconName] = true;
                _iconNames.push(iconName);
                _nameToHash[iconName] = crc32(iconName);
            }
            i++;
        }

        // maxCount > 0 时截取前 N 个（测试用）
        _isFullBake = !(maxCount > 0 && maxCount < _iconNames.length);
        if (!_isFullBake) {
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

        _savedQuality = _root._quality;
        BitmapExporter.resetCalibration();

        _root.发布消息("开始烘焙 " + _total + " 个图标（" + (_isFullBake ? "全量" : "测试") + "）...");

        _container = _root.createEmptyMovieClip("_iconBaker", 9999999);
        _container._visible = false;
        _phase = SETUP;

        _container.onEnterFrame = function():Void {
            org.flashNight.arki.item.IconBaker.tick();
        };
    }

    private static function tick():Void {
        switch (_phase) {
            case SETUP:    doSetup();   break;
            case DRAW_F1:  doDrawF1();  break;
            case DRAW_F2:  doDrawF2();  break;
            // WAIT_F1, WAIT_F2: 空转等回调
        }
    }

    /**
     * SETUP：创建图标 MC，停在第 1 帧。
     */
    private static function doSetup():Void {
        var iconName:String = _iconNames[_index];
        var symbolName:String = "图标-" + iconName;

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
        _iconAction = "unchanged"; // 每个图标开始时重置
        _root.服务器.发布服务器消息("[IconBaker] SETUP " + (_index + 1) + "/" + _total + ": " + iconName);
        _phase = DRAW_F1;
    }

    /**
     * DRAW_F1：渲染第 1 帧（图标）并发送。
     */
    private static function doDrawF1():Void {
        var iconName:String = _iconNames[_index];
        var hash:String = _nameToHash[iconName];
        var iconMC:MovieClip = _container.iconHolder.icon;

        _root._quality = "BEST";
        iconMC.gotoAndStop(1);
        var result:Object = BitmapExporter.render(iconMC, "f1");
        _root._quality = _savedQuality;

        if (result == null) {
            _root.服务器.发布服务器消息("[IconBaker] f1 渲染失败: " + iconName);
            _failedIcons.push(iconName);
            // f1 失败仍尝试 f2
            _phase = DRAW_F2;
            return;
        }

        _phase = WAIT_F1;
        ChunkedBitmapTransport.send(TASK, iconName, hash + "_1", result,
            _index + 1, _total,
            function(resp:Object):Void {
                org.flashNight.arki.item.IconBaker.onFrameSaved(resp);
                org.flashNight.arki.item.IconBaker._phase = DRAW_F2;
            }
        );
    }

    /**
     * DRAW_F2：渲染第 2 帧（掉落物）并发送。
     */
    private static function doDrawF2():Void {
        var iconName:String = _iconNames[_index];
        var hash:String = _nameToHash[iconName];
        var iconMC:MovieClip = _container.iconHolder.icon;

        // 检查是否有第 2 帧
        if (iconMC._totalframes < 2) {
            // 只有 1 帧，通知 C# 清除该图标可能残留的 f2
            var sm:ServerManager = ServerManager.getInstance();
            sm.sendTaskToNode(TASK, {op: "purge_frame", iconName: iconName, frameKey: "f2"});
            advanceToNext();
            return;
        }

        _root._quality = "BEST";
        iconMC.gotoAndStop(2);
        var result:Object = BitmapExporter.render(iconMC, null);
        _root._quality = _savedQuality;

        if (result == null) {
            // f2 渲染失败不算整体失败
            advanceToNext();
            return;
        }

        _phase = WAIT_F2;
        ChunkedBitmapTransport.send(TASK, iconName, hash + "_2", result,
            _index + 1, _total,
            function(resp:Object):Void {
                org.flashNight.arki.item.IconBaker.onFrameSaved(resp);
                org.flashNight.arki.item.IconBaker.advanceToNext();
            }
        );
    }

    /**
     * 帧保存回调（f1 和 f2 共用）。
     * 按优先级提升当前图标动作：created > updated > unchanged。
     */
    private static function onFrameSaved(resp:Object):Void {
        if (resp.success) {
            var action:String = resp.action;
            // 提升优先级：created > updated > unchanged
            if (action === "created") {
                _iconAction = "created";
            } else if (action === "updated" && _iconAction !== "created") {
                _iconAction = "updated";
            }
            // unchanged 不提升（默认值）
        } else {
            var iconName:String = _iconNames[_index];
            _root.服务器.发布服务器消息("[IconBaker] 保存失败: " + iconName + " - " + resp.error);
            _failedIcons.push(iconName);
        }
    }

    /**
     * 推进到下一个图标，或完成烘焙。
     */
    private static function advanceToNext():Void {
        // 按图标粒度累加统计
        if (_iconAction === "created") _created++;
        else if (_iconAction === "updated") _updated++;
        else _unchanged++;

        _index++;
        if (_index >= _total) {
            _phase = IDLE;
            _container.removeMovieClip();

            var msg:String = "烘焙完成: " + _total + " 个图标";
            if (_created > 0) msg += ", 新增 " + _created;
            if (_updated > 0) msg += ", 更新 " + _updated;
            if (_unchanged > 0) msg += ", 未变 " + _unchanged;
            if (_failedIcons.length > 0) msg += ", 失败 " + _failedIcons.length;
            _root.发布消息(msg);

            // 通知 C# 端完成（含 fullBake 标志供清理判断）
            var sm:ServerManager = ServerManager.getInstance();
            sm.sendTaskToNode(TASK, {
                op: "complete",
                total: _total,
                failed: _failedIcons.length,
                failedNames: _failedIcons,
                fullBake: _isFullBake
            });
        } else {
            _phase = SETUP;
        }
    }

    // ================================================================
    // CRC32 (ISO 3309, polynomial 0xEDB88320)
    // ================================================================

    private static function initCrcTable():Void {
        _crcTable = [];
        var i:Number = 0;
        while (i < 256) {
            var c:Number = i;
            var j:Number = 0;
            while (j < 8) {
                if (c & 1) {
                    c = 0xEDB88320 ^ (c >>> 1);
                } else {
                    c = c >>> 1;
                }
                j++;
            }
            _crcTable[i] = c;
            i++;
        }
    }

    public static function crc32(str:String):String {
        if (_crcTable == undefined) initCrcTable();
        var bytes:Array = stringToUTF8Bytes(str);
        var crc:Number = 0xFFFFFFFF;
        var i:Number = 0;
        var len:Number = bytes.length;
        while (i < len) {
            crc = _crcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
            i++;
        }
        crc = crc ^ 0xFFFFFFFF;
        return padHex8(crc);
    }

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

    private static function padHex8(n:Number):String {
        var hex:String = "0123456789abcdef";
        var s:String = "";
        var i:Number = 7;
        while (i >= 0) {
            s += hex.charAt((n >>> (i * 4)) & 0xF);
            i--;
        }
        return s;
    }
}
