import org.flashNight.naki.Sort.*;

class org.flashNight.naki.Sort.SortProbe {

    private static var _seed:Number;
    private static function resetRng():Void { _seed = 12345; }
    private static function rand():Number {
        return (_seed = (_seed * 1664525 + 1013904223) % 4294967296);
    }

    public static function run():Void {
        trace("=================================================================");
        trace("SortProbe Benchmark Batch B");
        trace("=================================================================");

        var sz:Number = 10000;
        var dists:Array = ["sorted", "reverse", "allEqual", "twoValues", "threeValues", "sawTooth20", "descPlateaus", "descPlateaus30", "descPlateaus31", "mountain", "pushFront", "pushBack"];

        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];
            resetRng();
            var master:Array = generateArray(sz, dist);

            // Native
            var a1:Array = master.slice();
            var t0:Number = getTimer();
            a1.sort(Array.NUMERIC);
            var tNat:Number = getTimer() - t0;

            // IntroSort
            resetRng();
            var a2:Array = master.slice();
            t0 = getTimer();
            IntroSort.sort(a2, null);
            var tIntro:Number = getTimer() - t0;

            trace("[BENCH:" + dist + "] native=" + tNat + " intro=" + tIntro);
        }

        trace("");
        trace("[PROBE:done] batchB");
    }


    private static function generateArray(sz:Number, dist:String):Array {
        var arr:Array = new Array(sz);
        var i:Number; var j:Number; var tmp:Number; var half:Number; var k:Number; var v:Number;

        if (dist == "random") {
            for (i = 0; i < sz; i++) arr[i] = rand() % (sz * 2);
        } else if (dist == "sorted") {
            for (i = 0; i < sz; i++) arr[i] = i;
        } else if (dist == "reverse") {
            for (i = 0; i < sz; i++) arr[i] = sz - i;
        } else if (dist == "allEqual") {
            for (i = 0; i < sz; i++) arr[i] = 42;
        } else if (dist == "twoValues") {
            for (i = 0; i < sz; i++) arr[i] = i % 2;
        } else if (dist == "threeValues") {
            for (i = 0; i < sz; i++) arr[i] = i % 3;
        } else if (dist == "fewUnique5") {
            for (i = 0; i < sz; i++) arr[i] = rand() % 5;
        } else if (dist == "fewUnique10") {
            for (i = 0; i < sz; i++) arr[i] = rand() % 10;
        } else if (dist == "organPipe") {
            half = sz >> 1;
            for (i = 0; i < half; i++) arr[i] = i;
            for (i = half; i < sz; i++) arr[i] = sz - 1 - i;
        } else if (dist == "sawTooth20") {
            for (i = 0; i < sz; i++) arr[i] = i % 20;
        } else if (dist == "sawTooth100") {
            for (i = 0; i < sz; i++) arr[i] = i % 100;
        } else if (dist == "nearSorted1") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.01));
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist == "nearSorted5") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.05));
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist == "nearSorted10") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.10));
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist == "nearReverse1") {
            for (i = 0; i < sz; i++) arr[i] = sz - i;
            k = Math.max(1, Math.round(sz * 0.01));
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist == "nearReverse5") {
            for (i = 0; i < sz; i++) arr[i] = sz - i;
            k = Math.max(1, Math.round(sz * 0.05));
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist == "sortedTailRand") {
            var cutoff:Number = Math.round(sz * 0.9);
            for (i = 0; i < cutoff; i++) arr[i] = i;
            for (i = cutoff; i < sz; i++) arr[i] = rand() % (sz * 2);
        } else if (dist == "sortedMidRand") {
            var seg:Number = Math.round(sz * 0.45);
            var mid:Number = sz - seg - seg;
            for (i = 0; i < seg; i++) arr[i] = i;
            for (i = seg; i < seg + mid; i++) arr[i] = rand() % (sz * 2);
            for (i = seg + mid; i < sz; i++) arr[i] = i;
        } else if (dist == "descPlateaus") {
            var plateauSize:Number = Math.floor(sz / 25);
            for (i = 0; i < sz; i++) { arr[i] = 25 - Math.floor(i / plateauSize); if (arr[i] < 1) arr[i] = 1; }
        } else if (dist == "descPlateaus30") {
            plateauSize = Math.floor(sz / 30);
            for (i = 0; i < sz; i++) { arr[i] = 30 - Math.floor(i / plateauSize); if (arr[i] < 1) arr[i] = 1; }
        } else if (dist == "descPlateaus31") {
            plateauSize = Math.floor(sz / 31);
            for (i = 0; i < sz; i++) { arr[i] = 31 - Math.floor(i / plateauSize); if (arr[i] < 1) arr[i] = 1; }
        } else if (dist == "mountain") {
            half = sz >> 1;
            for (i = 0; i < half; i++) arr[i] = i + 1;
            for (i = half; i < sz; i++) arr[i] = sz - (i - half);
        } else if (dist == "valley") {
            half = sz >> 1;
            for (i = 0; i < half; i++) arr[i] = half - i;
            for (i = half; i < sz; i++) arr[i] = i - half;
        } else if (dist == "pushFront") {
            arr[0] = sz;
            for (i = 1; i < sz; i++) arr[i] = i;
        } else if (dist == "pushBack") {
            for (i = 0; i < sz - 1; i++) arr[i] = i + 1;
            arr[sz - 1] = 0;
        }
        return arr;
    }
}
