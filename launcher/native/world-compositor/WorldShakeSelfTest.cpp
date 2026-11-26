#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "Compositor.h"
#include "WorldShakeStage.h"
#include <cstddef>
#include <cstdio>
#include <limits>
#include <utility>

static_assert(sizeof(ProbeWorldShakeStats) == 88);
static_assert(offsetof(ProbeWorldShakeStats, lastOffsetX) == 16);
static_assert(offsetof(ProbeWorldShakeStats, accepted) == 32);
static_assert(offsetof(ProbeWorldShakeStats, rtBytes) == 80);
static_assert(sizeof(ProbePresentationDiagStats) == 232);
static_assert(offsetof(ProbePresentationDiagStats, retainedShakeBlitActive) == 12);
static_assert(offsetof(ProbePresentationDiagStats, completed) == 16);
static_assert(offsetof(ProbePresentationDiagStats, zeroBypassSamples) == 32);
static_assert(offsetof(ProbePresentationDiagStats, worldPreBlitMsTotal) == 40);
static_assert(offsetof(ProbePresentationDiagStats, shakeBlitActiveMsTotal) == 72);
static_assert(offsetof(ProbePresentationDiagStats, shakeBlitBypassMsTotal) == 104);
static_assert(offsetof(ProbePresentationDiagStats, shakeStageCreates) == 112);
static_assert(offsetof(ProbePresentationDiagStats, shakeStageCreateCpuMaxMs) == 136);
static_assert(offsetof(ProbePresentationDiagStats, bulletHistoryDraws) == 144);
static_assert(offsetof(ProbePresentationDiagStats, rayDraws) == 168);
static_assert(offsetof(ProbePresentationDiagStats, wakeFreshSource) == 192);
static_assert(offsetof(ProbePresentationDiagStats, wakeOther) == 224);

namespace {
using Impulse = std::array<float, 4>;
constexpr Impulse light{1, 512, 288, 0};
constexpr Impulse asura{4, 512, 288, 0};
constexpr Impulse quantum{6, 512, 288, 0};
constexpr Impulse quake{7, 0, 0, 0};
int checks = 0, failures = 0;

void Check(bool pass, const char* description) {
    ++checks;
    if (!pass) {
        ++failures;
        std::printf("FAIL %s\n", description);
    }
}
bool Submit(WorldShakeEngine& engine, const Impulse& impulse, double now, int32_t grant = 1) {
    return engine.Submit(grant, impulse.data(), 1, 0, 0, 1, now);
}
std::pair<int32_t, int32_t> Sample(WorldShakeEngine& engine, double now, float scale = 1) {
    int32_t dx, dy;
    engine.Sample(now, scale, dx, dy);
    return {dx, dy};
}
constexpr std::pair<int32_t, int32_t> zero{};
double Magnitude(std::pair<int32_t, int32_t> xy) {
    return std::hypot(xy.first, xy.second);
}

void ExpiryAndTail() {
    WorldShakeEngine engine;
    engine.SetGrant(1, false);
    Check(Submit(engine, light, 20), "first impulse admitted");
    auto [dx, dy] = Sample(engine, 20);
    Check(dy != 0, "birth has a visible vertical offset");
    Check(Sample(engine, 19) == std::pair{dx, dy}, "negative elapsed time clamps to birth");
    engine.OnPresented(dx, dy, true);
    Check(Sample(engine, 20 + 8.0 / 30.0) == zero && engine.ActiveCount() == 0,
        "exact expiry produces an identity offset");
    Check(engine.TailPending() && engine.NeedsFrame(), "expiry retains the identity frame");
    Check(Sample(engine, 21) == zero && engine.TailPending(), "sampling alone cannot consume the tail");
    engine.OnPresented(0, 0, false);
    Check(!engine.TailPending() && !engine.NeedsFrame(), "successful identity present ends scheduling");
    engine.OnPresented(0, 0, false);
    Check(engine.Counts().activePasses == 1 && engine.Counts().tailPasses == 1, "counts one shifted pass and one tail");

    Check(Submit(engine, quantum, 22), "quantum admitted after expiry");
    Check(Sample(engine, 1022) == zero && !engine.NeedsFrame(), "1000-second stall expires an unpresented impulse without a tail");

    constexpr std::array ticks{8, 10, 12, 10, 18, 24, 14};
    for (std::size_t i = 0; i < ticks.size(); ++i) {
        auto impulse = light;
        impulse[0] = static_cast<float>(i + 1);
        WorldShakeEngine profileEngine;
        profileEngine.SetGrant(1, false);
        const double end = 2 + ticks[i] / 30.0;
        Check(Submit(profileEngine, impulse, 2), "catalog profile admits");
        profileEngine.Expire(std::nextafter(end, 2.0));
        Check(profileEngine.ActiveCount() == 1, "catalog profile alive before its configured duration");
        Check(Sample(profileEngine, end) == zero && !profileEngine.NeedsFrame(), "catalog profile expires at its configured duration");
    }
}

void CapacityAndClamp() {
    WorldShakeEngine engine;
    engine.SetGrant(1, false);
    std::array<float, WorldShakeEngine::kMaxSlots * 4> batch{};
    for (std::size_t i = 0; i < batch.size(); i += light.size()) {
        std::copy(light.begin(), light.end(), batch.begin() + static_cast<std::ptrdiff_t>(i));
    }
    Check(engine.Submit(1, batch.data(), WorldShakeEngine::kMaxSlots, 0, 0, 1, 10), "eight-slot batch admitted");
    Check(engine.ActiveCount() == 8 && engine.Counts().accepted == 8, "capacity full with eight accepted");
    Check(!Submit(engine, light, 10), "same-strength ninth impulse drops");
    Check(Submit(engine, quantum, 10), "stronger ninth impulse evicts a light slot");
    Check(engine.ActiveCount() == 8 && engine.Counts().accepted == 9 && engine.Counts().droppedCapacity == 2,
        "counts rejection and eviction while holding the cap");
    const auto atBirth = Magnitude(Sample(engine, 10, 100)) / 100.0;
    Check(std::abs(atBirth - WorldShakeEngine::MaxTotalOffsetStagePx) < 0.01, "simultaneous stack reaches the 14px vector clamp");
    for (int tick = 0; tick < 80; ++tick) {
        const auto magnitude = Magnitude(Sample(engine, 10 + tick / 100.0, 100)) / 100.0;
        Check(magnitude <= WorldShakeEngine::MaxTotalOffsetStagePx + 0.008, "sample stays within clamp and physical rounding");
    }

    for (std::size_t i = 0; i < batch.size(); i += asura.size()) {
        std::copy(asura.begin(), asura.end(), batch.begin() + static_cast<std::ptrdiff_t>(i));
    }
    engine.Clear();
    Check(engine.Submit(1, batch.data(), WorldShakeEngine::kMaxSlots, 0, 0, 1, 11), "tie-test batch admitted");
    Check(!Submit(engine, {6, 1900, 288, 0}, 11), "distance-attenuated quantum loses on effective amplitude");
    Check(Submit(engine, quake, 11), "quake beats Asura on equal amplitude and higher priority");
    Check(Sample(engine, 11 + 10.0 / 30.0, 100) != zero && engine.ActiveCount() == 1, "replacement survives the evicted profile's expiry");
    Check(engine.Counts().droppedCapacity == 4, "tie-test increments drop and eviction counters");
}

void GrantsAndClears() {
    WorldShakeEngine engine;
    engine.SetGrant(1, false);
    constexpr std::array<float, 8> two{1, 512, 288, 0, 7, 0, 0, 0};
    Check(!engine.Submit(2, two.data(), 2, 0, 0, 1, 9), "stale grant rejects both impulses");
    Check(!Submit(engine, quake, 9, 0), "zero grant rejected");
    Check(engine.Counts().rejectedGrant == 3 && !engine.NeedsFrame() && engine.Counts().accepted == 0,
        "stale grants do not activate or arm a tail");
    Check(Submit(engine, light, 10), "valid grant admits an impulse");
    engine.SetGrant(2, true);
    engine.SetGrant(2, true);
    Check(!engine.NeedsFrame() && engine.Counts().clears == 2 && engine.CurrentGrant() == 2,
        "repeated clear leaves idle state and counts both operations");
    Check(Submit(engine, quake, 11, 2), "new grant admits");
    auto [dx, dy] = Sample(engine, 11);
    engine.OnPresented(dx, dy, true);
    engine.SetGrant(0, false);
    engine.SetGrant(0, true);
    Check(engine.ActiveCount() == 0 && engine.TailPending() && engine.CurrentGrant() == 0,
        "revoke clears slots and arms a single tail after shifted present");
    Check(Sample(engine, 11) == zero, "revoked grant samples identity immediately");
    engine.OnPresented(0, 0, false);
    Check(!engine.NeedsFrame() && engine.Counts().tailPasses == 1, "repeated revoke cannot duplicate tail passes");

    engine.OnPresented(dx, dy, true);
    Check(engine.TailPending(), "shifted present completing after a clear re-arms the tail");
    engine.ForgetPresentation();
    Check(engine.LastX() == 0 && engine.LastY() == 0 && !engine.NeedsFrame(), "resize forgets offsets from old backbuffer");
}

void AttenuationAndValidation() {
    WorldShakeEngine center, halfRadius, distant, screen;
    for (auto* engine : {&center, &halfRadius, &distant, &screen}) engine->SetGrant(1, false);
    Check(Submit(center, light, 7), "center impulse admitted");
    Check(Submit(halfRadius, {1, 962, 288, 0}, 7), "half-radius impulse admitted");
    auto full = Magnitude(Sample(center, 7.05, 100));
    auto attenuated = Magnitude(Sample(halfRadius, 7.05, 100));
    Check(full > 1 && std::abs(attenuated - full * 0.75) < 2, "quadratic camera-distance attenuation is retained after birth");
    const Impulse zoomCenter{1, 1000, 2000, 0};
    WorldShakeEngine zoomed;
    zoomed.SetGrant(1, false);
    Check(zoomed.Submit(1, zoomCenter.data(), 1, 502, 268, 0.001f, 7)
        && Sample(zoomed, 7.05, 100) == Sample(center, 7.05, 100), "birth camera transform clamps scale to 0.01");
    Check(!Submit(distant, {1, 1412, 288, 0}, 7)
        && !Submit(distant, {1, 1411.97f, 288, 0}, 7)
        && !Submit(distant, {1, 90000, 288, 0}, 7)
        && !distant.NeedsFrame() && distant.Counts().accepted == 0, "radius edge, negligible weight, and beyond-radius events remain idle");
    Check(Submit(screen, quake, 7), "quake ignores source coordinates at (0,0)");
    const float extreme = std::numeric_limits<float>::max();
    Check(distant.Submit(1, quake.data(), 1, extreme, -extreme, 0.001f, 7)
        && Sample(screen, 7, 100) == Sample(distant, 7, 100), "screen-wide quake ignores even a distant camera");

    const float nan = std::numeric_limits<float>::quiet_NaN();
    const float inf = std::numeric_limits<float>::infinity();
    Check(WorldShakeEngine::ValidSubmission(light.data(), 1, 0, 0, 1), "valid batch accepted");
    Check(!WorldShakeEngine::ValidSubmission(nullptr, 1, 0, 0, 1)
        && !WorldShakeEngine::ValidSubmission(light.data(), 9, 0, 0, 1)
        && !WorldShakeEngine::ValidSubmission(light.data(), 0, 0, 0, 1)
        && !WorldShakeEngine::ValidSubmission(light.data(), 1, nan, 0, 1)
        && !WorldShakeEngine::ValidSubmission(light.data(), 1, 0, 0, 0)
        && !WorldShakeEngine::ValidSubmission(light.data(), 1, 0, 0, inf), "invalid pointer, count, and camera rejected");
    std::array<float, 8> invalidBatch{1, 512, 288, 0, 2.5f, 0, 0, 0};
    Check(!WorldShakeEngine::ValidSubmission(invalidBatch.data(), 2, 0, 0, 1), "bad profile rejects complete batch");
    invalidBatch[4] = 2;
    invalidBatch[5] = 1000001;
    Check(!WorldShakeEngine::ValidSubmission(invalidBatch.data(), 2, 0, 0, 1), "out-of-bounds coordinates rejected");
    invalidBatch[5] = nan;
    Check(!WorldShakeEngine::ValidSubmission(invalidBatch.data(), 2, 0, 0, 1), "NaN coordinates rejected");
    invalidBatch[5] = 0;
    invalidBatch[7] = 1;
    Check(!WorldShakeEngine::ValidSubmission(invalidBatch.data(), 2, 0, 0, 1), "nonzero reserved rejected");
}

void Determinism() {
    WorldShakeEngine a, b;
    a.SetGrant(1, false);
    b.SetGrant(1, false);
    for (int tick = 0; tick < 90; ++tick) {
        const double now = tick / 30.0;
        if (tick % 4 == 0 && tick < 30) {
            const auto& impulse = tick % 8 == 0 ? quantum : light;
            Check(Submit(a, impulse, now) && Submit(b, impulse, now), "same stream admits in both engines");
        }
        auto offset = Sample(a, now, 1.5f);
        Check(offset == Sample(b, now, 1.5f), "same stream gives identical integer pixels");
        a.OnPresented(offset.first, offset.second, offset != zero);
        b.OnPresented(offset.first, offset.second, offset != zero);
    }
    Check(!a.NeedsFrame() && !b.NeedsFrame(), "identical streams settle to idle");
}

void CustomProfiles() {
    WorldShakeEngine engine;
    engine.SetGrant(1, false);
    Check(Submit(engine, light, 5), "default profile admits before reconfigure");
    auto [dx0, dy0] = Sample(engine, 5);
    engine.OnPresented(dx0, dy0, true);

    std::array<float, 8 * 5> custom{
        1, 2.0f,  6, 20.0f,  800.0f,
        2, 4.0f,  8, 18.0f,  900.0f,
        5, 5.0f, 10, 16.0f, 1000.0f,
        3, 4.5f,  9, 22.0f,  950.0f,
        6, 7.0f, 15, 14.0f, 1400.0f,
        7, 8.0f, 20, 13.0f, 1500.0f,
        4, 5.0f, 12, 16.0f,    0.0f,
        9, 12.0f, 36, 12.0f,   0.0f, // custom 8th screen-wide profile
    };
    Check(engine.SetProfiles(custom.data(), 8, 6.0f), "valid 8-profile table accepted");
    Check(engine.ProfileCount() == 8 && engine.MaxOffsetStagePx() == 6.0f, "profile count and clamp updated");
    Check(engine.ActiveCount() == 0 && engine.TailPending(), "reconfigure clears active slots and preserves identity tail");
    engine.OnPresented(0, 0, false);
    Check(!engine.TailPending(), "identity tail clears after reconfigure");

    const Impulse p8{8, 0, 0, 0};
    const Impulse p9{9, 0, 0, 0};
    Check(WorldShakeEngine::ValidSubmission(p8.data(), 1, 0, 0, 1, engine.ProfileCount()), "profile 8 valid for 8-profile table");
    Check(!WorldShakeEngine::ValidSubmission(p9.data(), 1, 0, 0, 1, engine.ProfileCount()), "profile 9 rejected for 8-profile table");
    Check(Submit(engine, p8, 10), "profile 8 admits");
    const auto clamped = Magnitude(Sample(engine, 10, 100)) / 100.0;
    Check(clamped <= 6.008 && clamped > 5.0, "custom 6px max offset clamp applies");
    engine.Expire(10 + 35.5 / 30.0);
    Check(engine.ActiveCount() == 1, "custom 36-tick duration stays alive at tick 35.5");
    Check(Sample(engine, 10 + 36.0 / 30.0) == zero && engine.ActiveCount() == 0, "custom 36-tick duration expires cleanly");

    const float nan = std::numeric_limits<float>::quiet_NaN();
    Check(!WorldShakeEngine::ValidProfileTable(nullptr, 1, 14.0f)
        && !WorldShakeEngine::ValidProfileTable(custom.data(), 0, 14.0f)
        && !WorldShakeEngine::ValidProfileTable(custom.data(), 17, 14.0f)
        && !WorldShakeEngine::ValidProfileTable(custom.data(), 8, 0.0f)
        && !WorldShakeEngine::ValidProfileTable(custom.data(), 8, 65.0f)
        && !WorldShakeEngine::ValidProfileTable(custom.data(), 8, nan), "invalid profile table bounds rejected");
    auto bad = custom;
    bad[0] = 1.5f; Check(!engine.SetProfiles(bad.data(), 8, 14.0f), "fractional priority rejected");
    bad = custom; bad[1] = -1.0f; Check(!engine.SetProfiles(bad.data(), 8, 14.0f), "negative amplitude rejected");
    bad = custom; bad[2] = 0.0f; Check(!engine.SetProfiles(bad.data(), 8, 14.0f), "zero ticks rejected");
    bad = custom; bad[3] = 0.1f; Check(!engine.SetProfiles(bad.data(), 8, 14.0f), "below-min frequency rejected");
    bad = custom; bad[4] = 0.5f; Check(!engine.SetProfiles(bad.data(), 8, 14.0f), "fractional sub-1 radius rejected");
    Check(engine.ProfileCount() == 8 && engine.MaxOffsetStagePx() == 6.0f, "failed SetProfiles leaves active table intact");
}

void BackbufferClearCoverage() {
    Check(!WorldShakeRequiresBackbufferClear(0, 0, 1920, 1080, 1920, 1080), "16:9 full coverage skips clear");
    Check(WorldShakeRequiresBackbufferClear(0, 60, 1920, 1140, 1920, 1200), "letterbox bars require clear");
    Check(WorldShakeRequiresBackbufferClear(320, 0, 2240, 1080, 2560, 1080), "pillarbox bars require clear");
    Check(WorldShakeRequiresBackbufferClear(0, 0, 1920, 1079, 1920, 1080), "uncovered bottom pixel row requires clear");
    Check(WorldShakeRequiresBackbufferClear(0, 0, 1919, 1080, 1920, 1080), "uncovered right pixel column requires clear");
}
}

int main() {
    ExpiryAndTail();
    CapacityAndClamp();
    GrantsAndClears();
    AttenuationAndValidation();
    Determinism();
    CustomProfiles();
    BackbufferClearCoverage();
    std::printf("WorldShakeSelfTest: %d/%d checks passed (ABI stats: %zu bytes)\n",
        checks - failures, checks, sizeof(ProbeWorldShakeStats));
    return failures == 0 ? 0 : 1;
}
