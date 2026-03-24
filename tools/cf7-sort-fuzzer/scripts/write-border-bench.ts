/**
 * 生成边界样本多 seed × 多 rep benchmark harness
 *
 * 测量三条链路:
 *   native_total  = arr.sort(Array.NUMERIC)
 *   intro_total   = IntroSort.sort(arr, null)
 *   router_total  = SortRouter.sort(arr, null)  // classify + chosen_sort
 *
 * 输出格式:
 *   [BORDER:dist:seed:rep] native=X intro=Y router=Z
 */

import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { writeAS2 } from "../src/flash/as2-writer.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PROJECT_ROOT = resolve(__dirname, "../../../");

const PROBE_PATH = resolve(
  PROJECT_ROOT,
  "scripts/类定义/org/flashNight/naki/Sort/SortProbe.as"
);

const SEEDS = [12345, 54321, 99999, 77777, 31415, 271828, 141421, 173205];
const REPS = 3;
const DISTS = ["sawTooth20", "nearSorted1", "fewUnique10"];

const SOURCE = `import org.flashNight.naki.Sort.*;

class org.flashNight.naki.Sort.SortProbe {

    private static var _seed:Number;
    private static function setSeed(s:Number):Void { _seed = s; }
    private static function rand():Number {
        return (_seed = (_seed * 1664525 + 1013904223) % 4294967296);
    }

    public static function run():Void {
        trace("=================================================================");
        trace("Border Sample Benchmark: 8 seeds x ${REPS} reps");
        trace("Metrics: native / intro / router (ms)");
        trace("=================================================================");

        var sz:Number = 10000;
        var seeds:Array = [${SEEDS.join(", ")}];
        var dists:Array = [${DISTS.map(d => `"${d}"`).join(", ")}];

        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];
            trace("");
            trace("--- " + dist + " ---");

            for (var si:Number = 0; si < seeds.length; si++) {
                var seed:Number = seeds[si];

                for (var rep:Number = 0; rep < ${REPS}; rep++) {
                    // Native
                    setSeed(seed);
                    var master:Array = generateArray(sz, dist);
                    var a1:Array = master.slice();
                    var t0:Number = getTimer();
                    a1.sort(Array.NUMERIC);
                    var tNat:Number = getTimer() - t0;

                    // IntroSort
                    var a2:Array = master.slice();
                    t0 = getTimer();
                    IntroSort.sort(a2, null);
                    var tIntro:Number = getTimer() - t0;

                    // Router (classify + sort)
                    var a3:Array = master.slice();
                    t0 = getTimer();
                    SortRouter.sort(a3, null);
                    var tRouter:Number = getTimer() - t0;

                    trace("[BORDER:" + dist + ":" + seed + ":" + rep + "] native=" + tNat + " intro=" + tIntro + " router=" + tRouter);
                }
            }
        }

        trace("");
        trace("[PROBE:done] border");
    }

    private static function generateArray(sz:Number, dist:String):Array {
        var arr:Array = new Array(sz);
        var i:Number; var j:Number; var tmp:Number; var k:Number; var v:Number;

        if (dist == "sawTooth20") {
            for (i = 0; i < sz; i++) arr[i] = i % 20;
        } else if (dist == "nearSorted1") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.01));
            for (i = 0; i < k; i++) {
                j = rand() % sz; tmp = rand() % sz;
                v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v;
            }
        } else if (dist == "fewUnique10") {
            for (i = 0; i < sz; i++) arr[i] = rand() % 10;
        }
        return arr;
    }
}
`;

writeAS2(PROBE_PATH, SOURCE);
console.log(`Border benchmark harness written (${DISTS.length} dists × ${SEEDS.length} seeds × ${REPS} reps = ${DISTS.length * SEEDS.length * REPS} measurements)`);
