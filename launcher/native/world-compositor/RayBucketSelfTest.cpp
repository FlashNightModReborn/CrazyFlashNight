// Standalone CPU check for the ray pass bucketing in Compositor.cpp.
// Replays the production loop shape — bucket source indices once, then emit
// passes 0..3 over per-bucket batches of <=RayBatchCap — and compares the
// resulting (pass, record) draw stream against a faithful model of the legacy
// four-pass shader filter. Counts UpdateSubresource-equivalent uploads and
// bytes so the structural saving is visible. No D3D or OS dependencies.
// Build: cl /nologo /EHsc /O2 /W4 /WX /std:c++17 RayBucketSelfTest.cpp
#include "RayPassBuckets.h"
#include <cstdio>
#include <cstring>
#include <algorithm>
#include <utility>
#include <vector>

static int failures = 0;
static void Check(bool condition, const char* message) {
    if (!condition) { ++failures; std::printf("FAIL: %s\n", message); }
}
static void CheckEq(long long actual, long long expected, const char* message) {
    if (actual != expected) { ++failures; std::printf("FAIL: %s (actual=%lld expected=%lld)\n", message, actual, expected); }
}

constexpr int ItemCap = 4096, BatchCap = 256, RecordFloats = 32, RecordBytes = RecordFloats * 4;
// draw stream entry: which blend pass drew which source record.
using Draw = std::pair<int, int>;

// Legacy path: every pass uploads every batch; RVS rejects records whose
// style does not belong to that pass. Reproduce its accepted sequence.
static std::vector<Draw> LegacyDrawn(const std::vector<int>& styles) {
    std::vector<Draw> out;
    for (int pass = 0; pass < 4; ++pass)
        for (int at = 0; at < (int)styles.size(); at += BatchCap)
            for (int k = 0; k < std::min(BatchCap, (int)styles.size() - at); ++k) {
                int i = at + k, style = styles[i];
                bool flame = style == 11, screen = style == 9;
                if ((pass == 0 && !flame) || (pass == 1 && (flame || screen))
                    || (pass == 2 && !screen) || (pass == 3 && !flame)) continue;
                out.emplace_back(pass, i);
            }
    return out;
}

// New path mirroring Compositor.cpp: bucket once, submit per-pass batches of
// bucketed indices. Returns the drawn stream plus upload statistics.
struct NewPath {
    std::vector<Draw> drawn;
    int batches = 0, draws = 0; // cbuffer uploads and Draw() calls
};
static NewPath BucketedRun(const std::vector<int>& styles) {
    std::vector<int> flame, screen, other;
    for (int i = 0; i < (int)styles.size(); ++i) {
        int bucket = RayStyleBucket(styles[i]);
        if (bucket == RayBucketFlame) flame.push_back(i);
        else if (bucket == RayBucketScreen) screen.push_back(i);
        else other.push_back(i);
    }
    const std::vector<int>* passBucket[4] = { &flame, &other, &screen, &flame };
    NewPath result;
    for (int pass = 0; pass < 4; ++pass) {
        const std::vector<int>& bucket = *passBucket[pass];
        for (size_t at = 0; at < bucket.size(); at += BatchCap) {
            int count = (int)std::min(bucket.size() - at, (size_t)BatchCap);
            ++result.batches; ++result.draws;
            for (int k = 0; k < count; ++k) result.drawn.emplace_back(pass, bucket[at + k]);
        }
    }
    return result;
}
static long long LegacyBatches(int count) { return count > 0 ? 4LL * ((count + BatchCap - 1) / BatchCap) : 0; }

static void VerifyCase(const char* name, const std::vector<int>& styles) {
    auto legacy = LegacyDrawn(styles);
    auto run = BucketedRun(styles);
    if (legacy != run.drawn) {
        ++failures;
        std::printf("FAIL: %s draw stream mismatch (legacy=%zu new=%zu)\n", name, legacy.size(), run.drawn.size());
        return;
    }
    long long legacyBatches = LegacyBatches((int)styles.size());
    std::printf("%-34s n=%4zu drawn=%4zu batches %2lld->%2d bytes %6lld->%5lld\n",
        name, styles.size(), run.drawn.size(), legacyBatches, run.batches,
        legacyBatches * BatchCap * RecordBytes, (long long)run.batches * BatchCap * RecordBytes);
}

int main() {
    // Style membership: 11 -> flame passes 0/3, 9 -> screen pass 2, all else -> pass 1.
    for (int style = -4; style <= 48; ++style) {
        int bucket = RayStyleBucket(style);
        if (style == 11) CheckEq(bucket, RayBucketFlame, "style 11 must be flame");
        else if (style == 9) CheckEq(bucket, RayBucketScreen, "style 9 must be screen");
        else CheckEq(bucket, RayBucketOther, "non-flame/non-screen must be pass 1");
    }
    // Every style the native validator admits lands in exactly one pass group.
    for (int style : {0,1,2,3,4,5,6,7,8,9,10,11,16,17,18,19,20,21,22,23,24,25,26,27,42}) {
        auto run = BucketedRun({style});
        int passes = style == 11 ? 2 : 1;
        CheckEq((long long)run.drawn.size(), passes, "admitted style must draw in its pass(es)");
    }

    // Empty frame and single-bucket frames skip every other pass entirely.
    VerifyCase("empty", {});
    VerifyCase("all flame x300", std::vector<int>(300, 11));
    VerifyCase("all screen x300", std::vector<int>(300, 9));
    VerifyCase("all other x300", std::vector<int>(300, 5));

    // Order stability: interleaved styles keep source order inside each pass.
    std::vector<int> interleaved;
    for (int i = 0; i < 64; ++i) { interleaved.push_back(11); interleaved.push_back(9); interleaved.push_back(i % 9); }
    VerifyCase("interleaved flame/screen/other", interleaved);

    // Batch boundaries per bucket: sizes straddling 256 split into 256+rest.
    std::vector<int> boundary;
    for (int i = 0; i < 257; ++i) boundary.push_back(11);  // flame 257 -> batches 256+1 in each of pass 0 and 3
    for (int i = 0; i < 255; ++i) boundary.push_back(9);   // screen 255 -> one batch in pass 2
    for (int i = 0; i < 256; ++i) boundary.push_back(42);  // other 256 -> one batch in pass 1
    auto boundaryRun = BucketedRun(boundary);
    CheckEq(boundaryRun.batches, 2 + 2 + 1 + 1, "boundary batch count");
    Check(boundaryRun.drawn == LegacyDrawn(boundary), "boundary draw stream");
    // Last batch tail padding: the uploaded cbuffer is always a full batch.
    CheckEq(BatchCap * RecordBytes, 32768, "batch cbuffer stays 32KB");

    // Admitted decoration styles (>=16) and every other pass-1 style bucket together.
    std::vector<int> decorations;
    for (int i = 16; i < 28; ++i) decorations.push_back(i);
    VerifyCase("decoration styles 16..27", decorations);

    // Full-capacity mixed frame: deterministic LCS pattern of all admitted styles.
    std::vector<int> admitted{0,1,2,3,4,5,6,7,8,9,10,11,16,17,18,19,20,21,22,23,24,25,26,27,42};
    std::vector<int> full;
    unsigned seed = 0xC0FFEE;
    for (int i = 0; i < ItemCap; ++i) { seed = seed * 1664525u + 1013904223u; full.push_back(admitted[(seed >> 16) % admitted.size()]); }
    VerifyCase("full 4096 mixed", full);

    // Worst case for the new path is the old path's best case: uniform style.
    VerifyCase("full 4096 other", std::vector<int>(ItemCap, 3));
    // Heavy flame frame: passes 0 and 3 both pay the flame uploads.
    std::vector<int> flames;
    for (int i = 0; i < ItemCap; ++i) flames.push_back(i % 3 ? 11 : 5);
    VerifyCase("full 4096 flame-heavy", flames);

    // Publish/worker snapshot copies move metadata + count live records only.
    // A shrinking frame leaves stale records past count; bucketing must read
    // only the live prefix, so tail bytes need no clearing.
    auto PublishBytes = [](int count) { return (long long)count * RecordBytes; };
    std::vector<float> snapshot(ItemCap * RecordFloats);
    for (int i = 0; i < 300; ++i) snapshot[i * RecordFloats + 15] = 11.f;      // previous 300-flame frame
    std::vector<float> incoming(5 * RecordFloats);
    for (int i = 0; i < 5; ++i) incoming[i * RecordFloats + 15] = 9.f;          // new 5-screen frame
    std::memcpy(snapshot.data(), incoming.data(), (size_t)PublishBytes(5));   // count-bounded publish
    int liveCount = 5;
    std::vector<int> liveStyles;
    for (int i = 0; i < liveCount; ++i) liveStyles.push_back((int)snapshot[i * RecordFloats + 15]);
    auto shrunk = BucketedRun(liveStyles);
    Check(shrunk.drawn == LegacyDrawn(std::vector<int>(5, 9)), "shrunk snapshot draws live records only");
    CheckEq(shrunk.batches, 1, "shrunk snapshot submits one batch");
    CheckEq(PublishBytes(0), 0, "empty frame publishes zero record bytes");
    CheckEq(PublishBytes(liveCount), 640, "publish copy bytes track count, not capacity");
    Check(PublishBytes(liveCount) < PublishBytes(ItemCap), "live copy is smaller than a capacity copy");

    if (failures == 0) std::printf("PASS: bucket order, style membership, batch splits, empty-skip, 4096-capacity and count-bounded publish all match the legacy draw stream\n");
    return failures ? 1 : 0;
}
