import org.flashNight.naki.Sort.*;

/**
 * 多 seed 稳定性诊断：验证路由决策跨 seed 的一致性
 */
class org.flashNight.naki.Sort.MultiSeedDiag {

    private static var _seed:Number;

    private static function rand():Number {
        return (_seed = (_seed * 1664525 + 1013904223) % 4294967296);
    }

    public static function run():Void {
        trace("=================================================================");
        trace("Multi-Seed Route Stability Diagnostic (n=10000)");
        trace("=================================================================");

        var seeds:Array = [12345, 54321, 99999, 77777, 31415, 271828, 141421, 173205];
        var dists:Array = ["nearSorted1", "nearReverse1", "sortedTailRand", "sortedMidRand"];

        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];
            var natCount:Number = 0;
            var intCount:Number = 0;

            trace("\n--- " + dist + " ---");
            for (var si:Number = 0; si < seeds.length; si++) {
                _seed = seeds[si];
                var arr:Array = genDist(10000, dist);
                var route:String = SortRouter.classifyNumeric(arr);

                // 测性能
                var copy:Array = arr.slice();
                var t0:Number = getTimer();
                copy.sort(Array.NUMERIC);
                var tNat:Number = getTimer() - t0;

                copy = arr.slice();
                t0 = getTimer();
                IntroSort.sort(copy, null);
                var tInt:Number = getTimer() - t0;

                if (route === SortRouter.ROUTE_NATIVE) natCount++;
                else intCount++;

                trace("  seed=" + padL(String(seeds[si]), 6)
                    + "  -> " + padR(route, 8)
                    + "  nat=" + padL(String(tNat), 5)
                    + "  int=" + padL(String(tInt), 5));
            }
            trace("  SUMMARY: NAT=" + natCount + "/" + seeds.length
                + "  INT=" + intCount + "/" + seeds.length
                + "  stability=" + (natCount == seeds.length || intCount == seeds.length ? "STABLE" : "UNSTABLE"));
        }

        trace("\n=================================================================");
    }

    private static function genDist(sz:Number, dist:String):Array {
        var arr:Array = new Array(sz);
        var i:Number, j:Number, k:Number, v:Number, tmp:Number;

        if (dist === "nearSorted1") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.01));
            for (i = 0; i < k; i++) {
                j = rand() % sz; tmp = rand() % sz;
                v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v;
            }
        } else if (dist === "nearReverse1") {
            for (i = 0; i < sz; i++) arr[i] = sz - i;
            k = Math.max(1, Math.round(sz * 0.01));
            for (i = 0; i < k; i++) {
                j = rand() % sz; tmp = rand() % sz;
                v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v;
            }
        } else if (dist === "sortedTailRand") {
            var cutoff:Number = Math.round(sz * 0.9);
            for (i = 0; i < cutoff; i++) arr[i] = i;
            for (i = cutoff; i < sz; i++) arr[i] = rand() % (sz * 2);
        } else if (dist === "sortedMidRand") {
            var seg:Number = Math.round(sz * 0.45);
            var mid:Number = sz - seg - seg;
            for (i = 0; i < seg; i++) arr[i] = i;
            for (i = seg; i < seg + mid; i++) arr[i] = rand() % (sz * 2);
            for (i = seg + mid; i < sz; i++) arr[i] = i;
        }
        return arr;
    }

    private static function padR(s:String, w:Number):String {
        while (length(s) < w) s += " ";
        return s;
    }

    private static function padL(s:String, w:Number):String {
        while (length(s) < w) s = " " + s;
        return s;
    }
}
