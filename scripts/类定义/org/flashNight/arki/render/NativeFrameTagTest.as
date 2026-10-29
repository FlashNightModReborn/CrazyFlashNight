import flash.display.BitmapData;
import org.flashNight.arki.render.NativeFrameTag;

class org.flashNight.arki.render.NativeFrameTagTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++;
        else { failed++; trace("[TEST_FAIL] NativeFrameTagTest: " + label); }
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        NativeFrameTag.reset();
        NativeFrameTag.update(_root, 3, 0x123456);
        var state:Object = NativeFrameTag.stateForTests();
        check(state.visible && state.epoch == 3 && state.frame == 0x123456, "visible tag carries exact identity");
        check(state.colors[0] == 0x13579B, "magic is fixed");
        check(state.colors[1] == 0x563412, "frame uses little-endian RGB bytes");
        check(state.colors[2] == 0x030000 + NativeFrameTag.checksumForTests(3, 0x123456), "epoch and checksum share one cell");
        check(state.colors[3] == 0xA9CBED, "complement detects damaged frame bytes");
        var pixels:BitmapData = new BitmapData(1024, 576, true, 0);
        _root.__nativeFrameTag._y = 400;
        var bounds:Object = _root.__nativeFrameTag.getBounds();
        trace("NativeFrameTag visual: depth=" + _root.__nativeFrameTag.getDepth()
            + " visible=" + _root.__nativeFrameTag._visible + " alpha=" + _root.__nativeFrameTag._alpha
            + " bounds=" + bounds.xMin + "," + bounds.yMin + " -> " + bounds.xMax + "," + bounds.yMax);
        pixels.draw(_root);
        trace("NativeFrameTag pixels: magic=" + pixels.getPixel(8, 408) + "/" + pixels.getPixel32(8, 408).toString(16)
            + " frame=" + pixels.getPixel(24, 408) + "/" + pixels.getPixel32(24, 408).toString(16));
        check(pixels.getPixel(8, 408) == 0x13579B, "magic is actually rasterized: " + pixels.getPixel32(8, 408).toString(16));
        check(pixels.getPixel(24, 408) == 0x563412, "frame bytes are actually rasterized: " + pixels.getPixel32(24, 408).toString(16));
        pixels.dispose();
        NativeFrameTag.update(_root, -1, 99);
        check(!NativeFrameTag.stateForTests().visible, "negative identity hides the tag");
        NativeFrameTag.update(_root, 65539, 0x123456);
        check(NativeFrameTag.stateForTests().epoch == 3, "epoch wraps into sixteen bits");
        NativeFrameTag.update(_root, 3, 16777216 + 0x123456);
        check(NativeFrameTag.stateForTests().frame == 0x123456, "frame wraps into twenty-four bits");
        NativeFrameTag.update(_root, 3, Number.NaN);
        check(!NativeFrameTag.stateForTests().visible, "non-finite identity cannot publish a stale tag");
        NativeFrameTag.update(_root, 4, 99);
        NativeFrameTag.reset();
        state = NativeFrameTag.stateForTests();
        check(!state.visible && state.epoch == -2 && state.frame == -2 && state.colors.length == 0,
            "scene reset releases the clip and identity");
        NativeFrameTag.update(_root, 3, 0x123456);
        _root.__nativeFrameTag._y = 400;
        trace("NativeFrameTagTest Tests Passed: " + passed);
        trace("NativeFrameTagTest Tests Failed: " + failed);
    }
}
