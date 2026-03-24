/**
 * 生成 SortProbe.as 探针文件（UTF-8 BOM + CRLF）
 */

import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { writeAS2 } from "../src/flash/as2-writer.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
// scripts/ → cf7-sort-fuzzer/ → tools/ → CrazyFlashNight/
const PROJECT_ROOT = resolve(__dirname, "../../../");

const PROBE_PATH = resolve(
  PROJECT_ROOT,
  "scripts/类定义/org/flashNight/naki/Sort/SortProbe.as"
);

const PROBE_SOURCE = `import org.flashNight.naki.Sort.*;

/**
 * SortProbe - Native sort 行为探测器
 *
 * Phase 0: 确认 Flash Player 的 pivot 策略、分区方式、
 *          cmpFn 与 NUMERIC 路径一致性、organPipe/mountain 不对称性。
 *
 * trace 输出格式:
 *   [PROBE:key] value
 *   [BENCH:dist] native=X intro=Y
 *   [CMP_SEQ:label] i,j;i,j;...
 */
class org.flashNight.naki.Sort.SortProbe {

    private static var _seed:Number;
    private static function resetRng():Void { _seed = 12345; }
    private static function rand():Number {
        return (_seed = (_seed * 1664525 + 1013904223) % 4294967296);
    }

    /** 轻量入口: 小数组比较序列 + 结构对比 (预计 <15s) */
    public static function run():Void {
        trace("=================================================================");
        trace("SortProbe - Pivot + Structure Probes");
        trace("=================================================================");

        probePivotStrategy();
        probeOrganPipeVsMountain();

        trace("");
        trace("[PROBE:done] all");
    }

    // ==================================================================
    // 探针 1: cmpFn vs NUMERIC 退化模式对比
    // ==================================================================
    private static function probePathConsistency():Void {
        trace("");
        trace("--- Probe 1: cmpFn vs NUMERIC path consistency ---");

        var cmp:Function = function(a, b):Number { return a - b; };
        // n=5000 + 1 rep: catastrophic 分布的 cmpFn 路径可能极慢
        // (sorted cmpFn n=10000 可能 10s+, AS2 函数调用放大)
        var dists:Array = ["sorted", "random", "allEqual", "organPipe", "mountain"];
        var sz:Number = 5000;
        var REPS:Number = 1;

        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];

            // NUMERIC 路径
            var tNat:Number = 0;
            for (var r:Number = 0; r < REPS; r++) {
                resetRng();
                var a1:Array = generateArray(sz, dist);
                var t0:Number = getTimer();
                a1.sort(Array.NUMERIC);
                tNat += getTimer() - t0;
            }
            tNat = Math.round(tNat / REPS);

            // cmpFn 路径
            var tCmp:Number = 0;
            for (r = 0; r < REPS; r++) {
                resetRng();
                var a2:Array = generateArray(sz, dist);
                t0 = getTimer();
                a2.sort(cmp);
                tCmp += getTimer() - t0;
            }
            tCmp = Math.round(tCmp / REPS);

            trace("[PROBE:path_" + dist + "] numeric=" + tNat + " cmpFn=" + tCmp);
        }
    }

    // ==================================================================
    // 探针 2: pivot 位置探测 (小数组比较序列)
    // ==================================================================
    private static function probePivotStrategy():Void {
        trace("");
        trace("--- Probe 2: Pivot strategy (comparison sequences) ---");

        probeCmpSeq("asc3",  [1, 2, 3]);
        probeCmpSeq("desc3", [3, 2, 1]);
        probeCmpSeq("mid3",  [2, 3, 1]);
        probeCmpSeq("asc5",  [1, 2, 3, 4, 5]);
        probeCmpSeq("desc5", [5, 4, 3, 2, 1]);
        probeCmpSeq("pipe5", [1, 3, 5, 3, 1]);
        probeCmpSeq("eq5",   [3, 3, 3, 3, 3]);
        probeCmpSeq("asc8",  [1, 2, 3, 4, 5, 6, 7, 8]);
        probeCmpSeq("rand8", [5, 2, 8, 1, 7, 3, 6, 4]);
        probeCmpSeq("asc16", [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]);
    }

    private static function probeCmpSeq(label:String, src:Array):Void {
        var n:Number = src.length;
        var wrapped:Array = new Array(n);
        for (var i:Number = 0; i < n; i++) {
            wrapped[i] = {_v: src[i], _i: i};
        }

        var seq:String = "";
        var cmpCount:Number = 0;

        // 注意: AS2 闭包捕获局部变量的方式 — 需要用对象桥接
        var state:Object = {seq: "", cnt: 0};
        var trackerCmp:Function = function(a, b):Number {
            state.seq += a._i + "," + b._i + ";";
            state.cnt++;
            return a._v - b._v;
        };

        wrapped.sort(trackerCmp);
        trace("[CMP_SEQ:" + label + "] " + state.seq);
        trace("[PROBE:cmp_count_" + label + "] " + state.cnt);
    }

    // ==================================================================
    // 探针 3: organPipe vs mountain 对比 + 变体
    // ==================================================================
    private static function probeOrganPipeVsMountain():Void {
        trace("");
        trace("--- Probe 3: organPipe vs mountain timing ---");

        var sz:Number = 10000;
        var REPS:Number = 3;
        var dists:Array = [
            "organPipe",       // arr[0]=0 (min), 对称, 有重复值
            "mountain",        // arr[0]=1 (near min), 非对称, 全唯一
            "valley",          // arr[0]=half (mid), 对称, 有重复值
            "organPipeMid",    // arr[0]=half (mid), 对称, 有重复值
            "mountainSym",     // arr[0]=0 (min), 对称, 有重复值 (=organPipe)
            "sorted",          // baseline: 已知灾难
            "random"           // baseline: 已知安全
        ];

        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];
            var tNat:Number = 0;
            var tIntro:Number = 0;

            for (var r:Number = 0; r < REPS; r++) {
                resetRng();
                var a1:Array = generateArray(sz, dist);
                var t0:Number = getTimer();
                a1.sort(Array.NUMERIC);
                tNat += getTimer() - t0;

                resetRng();
                var a2:Array = generateArray(sz, dist);
                t0 = getTimer();
                IntroSort.sort(a2, null);
                tIntro += getTimer() - t0;
            }
            tNat = Math.round(tNat / REPS);
            tIntro = Math.round(tIntro / REPS);

            trace("[BENCH:" + dist + "] native=" + tNat + " intro=" + tIntro);
        }
    }

    // ==================================================================
    // 数据生成
    // ==================================================================
    private static function generateArray(sz:Number, dist:String):Array {
        var arr:Array = new Array(sz);
        var i:Number;
        var half:Number = sz >> 1;

        if (dist == "sorted") {
            for (i = 0; i < sz; i++) arr[i] = i;
        } else if (dist == "random") {
            for (i = 0; i < sz; i++) arr[i] = rand() % (sz * 2);
        } else if (dist == "allEqual") {
            for (i = 0; i < sz; i++) arr[i] = 42;
        } else if (dist == "organPipe") {
            for (i = 0; i < half; i++) arr[i] = i;
            for (i = half; i < sz; i++) arr[i] = sz - 1 - i;
        } else if (dist == "mountain") {
            for (i = 0; i < half; i++) arr[i] = i + 1;
            for (i = half; i < sz; i++) arr[i] = sz - (i - half);
        } else if (dist == "valley") {
            for (i = 0; i < half; i++) arr[i] = half - i;
            for (i = half; i < sz; i++) arr[i] = i - half;
        } else if (dist == "organPipeMid") {
            // arr[0]=half (中位数), 上升到 sz-1, 再降回 half
            for (i = 0; i < half; i++) arr[i] = half + i;
            for (i = half; i < sz; i++) arr[i] = half + (sz - 1 - i);
        } else if (dist == "mountainSym") {
            // 与 organPipe 完全相同 — 用于确认是否等价
            for (i = 0; i < half; i++) arr[i] = i;
            for (i = half; i < sz; i++) arr[i] = sz - 1 - i;
        }

        return arr;
    }
}
`;

writeAS2(PROBE_PATH, PROBE_SOURCE);
console.log(`SortProbe.as written to ${PROBE_PATH}`);
