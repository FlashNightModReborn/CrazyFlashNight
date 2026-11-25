#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <numbers>

// Capture serializes this engine with its state mutex. The engine owns no GPU or clock.
class WorldShakeEngine {
public:
    static constexpr int32_t kMaxSlots = 8;
    static constexpr int32_t kMaxProfiles = 16;
    static constexpr int32_t kDefaultProfileCount = 7;
    static constexpr int32_t kMaxGrant = 1000000000;
    static constexpr float MaxTotalOffsetStagePx = 14.0f;

    struct Counters {
        uint64_t accepted = 0;
        uint64_t rejectedGrant = 0;
        uint64_t droppedCapacity = 0;
        uint64_t clears = 0;
        uint64_t activePasses = 0;
        uint64_t tailPasses = 0;
    };

    static bool ValidProfileTable(const float* profiles, int32_t count, float maxTotalOffsetStagePx) noexcept {
        if (!profiles || count < 1 || count > kMaxProfiles
                || !std::isfinite(maxTotalOffsetStagePx) || maxTotalOffsetStagePx <= 0.0f
                || maxTotalOffsetStagePx > 64.0f) return false;
        for (int32_t i = 0; i < count; ++i) {
            const float* item = profiles + i * 5;
            if (!std::isfinite(item[0]) || item[0] < 1.0f || item[0] > 100.0f || item[0] != std::floor(item[0])
                    || !std::isfinite(item[1]) || item[1] < 0.0f || item[1] > 64.0f
                    || !std::isfinite(item[2]) || item[2] < 1.0f || item[2] > 120.0f || item[2] != std::floor(item[2])
                    || !std::isfinite(item[3]) || item[3] < 0.5f || item[3] > 60.0f
                    || !std::isfinite(item[4]) || !(item[4] == 0.0f || (item[4] >= 1.0f && item[4] <= 100000.0f))) {
                return false;
            }
        }
        return true;
    }

    static bool ValidSubmission(const float* impulses, int32_t count,
            float cameraX, float cameraY, float cameraScale, int32_t maxProfileId = kDefaultProfileCount) noexcept {
        if (!impulses || count < 1 || count > kMaxSlots || maxProfileId < 1 || maxProfileId > kMaxProfiles
                || !std::isfinite(cameraX) || !std::isfinite(cameraY)
                || !std::isfinite(cameraScale) || cameraScale <= 0) return false;
        const float maxProfile = static_cast<float>(maxProfileId);
        for (int32_t i = 0; i < count; ++i) {
            const float* item = impulses + i * 4;
            if (!(item[0] >= 1.0f && item[0] <= maxProfile) || item[0] != std::floor(item[0])
                    || !(std::abs(item[1]) <= 1000000.0f) || !(std::abs(item[2]) <= 1000000.0f)
                    || item[3] != 0) return false;
        }
        return true;
    }

    bool SetProfiles(const float* profiles, int32_t count, float maxTotalOffsetStagePx) noexcept {
        if (!ValidProfileTable(profiles, count, maxTotalOffsetStagePx)) return false;
        Clear();
        for (int32_t i = 0; i < count; ++i) {
            const float* item = profiles + i * 5;
            profiles_[static_cast<std::size_t>(i)] = {
                static_cast<int>(item[0]), item[1], static_cast<int>(item[2]), item[3], item[4]
            };
        }
        profileCount_ = count;
        maxTotalOffsetStagePx_ = maxTotalOffsetStagePx;
        return true;
    }

    int32_t ProfileCount() const noexcept { return profileCount_; }
    float MaxOffsetStagePx() const noexcept { return maxTotalOffsetStagePx_; }

    void SetGrant(int32_t grant, bool clearState) noexcept {
        currentGrant_ = grant;
        if (clearState || grant == 0) Clear();
    }

    void Clear() noexcept {
        activeCount_ = 0;
        ++counters_.clears;
        tailPending_ = lastPresentedX_ != 0 || lastPresentedY_ != 0;
    }

    void ForgetPresentation() noexcept {
        lastPresentedX_ = lastPresentedY_ = 0;
        tailPending_ = false;
    }

    // The caller validates the entire batch before entering the engine.
    bool Submit(int32_t grant, const float* impulses, int32_t count, float cameraX, float cameraY,
            float cameraScale, double nowSec) noexcept {
        if (grant <= 0 || grant != currentGrant_) {
            counters_.rejectedGrant += static_cast<uint64_t>(count);
            return false;
        }
        Expire(nowSec);
        const double scale = std::max(cameraScale, 0.01f);
        const double centerX = (512.0 - cameraX) / scale;
        const double centerY = (288.0 - cameraY) / scale;
        bool admitted = false;
        for (int32_t i = 0; i < count; ++i) {
            const float* item = impulses + i * 4;
            const std::size_t profileIndex = static_cast<std::size_t>(item[0]) - 1;
            if (profileIndex >= static_cast<std::size_t>(profileCount_)) continue;
            const auto& profile = profiles_[profileIndex];
            double weight = 1.0;
            if (profile.radius > 0) {
                const double x = item[1] - centerX, y = item[2] - centerY;
                weight = std::max(0.0, 1.0 - (x * x + y * y) / (profile.radius * profile.radius));
            }
            if (weight <= 0.0001) continue;

            const float amplitude = static_cast<float>(profile.amplitude * weight);
            std::size_t index = activeCount_;
            if (activeCount_ == slots_.size()) {
                ++counters_.droppedCapacity;
                index = 0;
                for (std::size_t j = 1; j < activeCount_; ++j) {
                    if (Stronger(slots_[index].amplitude, slots_[index].profile.priority,
                            slots_[j].amplitude, slots_[j].profile.priority)) index = j;
                }
                if (!Stronger(amplitude, profile.priority, slots_[index].amplitude, slots_[index].profile.priority)) continue;
            } else {
                ++activeCount_;
            }

            // The admitted ordinal gives reproducible angle and phase. Start
            // near a vertical peak so simultaneous impacts reinforce.
            const uint64_t bits = MixOrdinal(++impulseOrdinal_);
            const double angle = (Unit(bits) - 0.5) * 0.48;
            const double phase = std::numbers::pi / 2.0 + (Unit(bits >> 16) - 0.5) * 1.3;
            const double duration = profile.ticks / 30.0;
            slots_[index] = {profile, amplitude, nowSec, nowSec + duration, std::sin(angle), std::cos(angle), phase};
            ++counters_.accepted;
            admitted = true;
        }
        return admitted;
    }

    void Expire(double nowSec) noexcept {
        for (std::size_t i = 0; i < activeCount_;) {
            const auto& slot = slots_[i];
            if (nowSec >= slot.expireSec || nowSec - slot.birthSec >= slot.profile.ticks / 30.0) {
                slots_[i] = slots_[--activeCount_];
            } else {
                ++i;
            }
        }
        if (activeCount_ == 0 && (lastPresentedX_ != 0 || lastPresentedY_ != 0)) tailPending_ = true;
    }

    void Sample(double nowSec, float stageScale, int32_t& outDx, int32_t& outDy) noexcept {
        Expire(nowSec);
        double x = 0, y = 0;
        for (std::size_t i = 0; i < activeCount_; ++i) {
            const auto& slot = slots_[i];
            const double dt = std::max(0.0, nowSec - slot.birthSec);
            const double remaining = 1.0 - dt * 30.0 / slot.profile.ticks;
            const double wave = slot.amplitude * remaining * remaining
                * std::sin(slot.phase + 2.0 * std::numbers::pi * slot.profile.frequency * dt);
            x += wave * slot.axisX;
            y += wave * slot.axisY;
        }
        const double magnitude = std::sqrt(x * x + y * y);
        const double scale = magnitude > maxTotalOffsetStagePx_
            ? stageScale * maxTotalOffsetStagePx_ / magnitude : stageScale;
        outDx = static_cast<int32_t>(std::lround(x * scale));
        outDy = static_cast<int32_t>(std::lround(y * scale));
        if (outDx == 0 && outDy == 0 && (lastPresentedX_ != 0 || lastPresentedY_ != 0)) tailPending_ = true;
    }

    void OnPresented(int32_t dx, int32_t dy, bool usedStage) noexcept {
        lastPresentedX_ = dx;
        lastPresentedY_ = dy;
        if (usedStage) ++counters_.activePasses;
        if (dx == 0 && dy == 0) {
            if (tailPending_) {
                tailPending_ = false;
                ++counters_.tailPasses;
            }
        } else if (activeCount_ == 0) {
            // A clear can arrive while the worker is rendering this frame.
            tailPending_ = true;
        }
    }

    bool NeedsFrame() const noexcept { return activeCount_ != 0 || tailPending_; }
    bool TailPending() const noexcept { return tailPending_; }
    uint32_t ActiveCount() const noexcept { return static_cast<uint32_t>(activeCount_); }
    int32_t CurrentGrant() const noexcept { return currentGrant_; }
    int32_t LastX() const noexcept { return lastPresentedX_; }
    int32_t LastY() const noexcept { return lastPresentedY_; }
    const Counters& Counts() const noexcept { return counters_; }

private:
    struct Profile {
        int priority;
        float amplitude;
        int ticks;
        float frequency;
        float radius;
    };
    static constexpr std::array<Profile, kMaxProfiles> kDefaultProfiles{{
        {1, 3.5f,  8, 22.0f,  900.0f}, // light
        {2, 5.0f, 10, 20.0f, 1000.0f}, // standard
        {5, 6.0f, 12, 18.0f, 1100.0f}, // support
        {3, 5.5f, 10, 24.0f,  950.0f}, // asura
        {6, 8.5f, 18, 15.0f, 1500.0f}, // heavy
        {7, 9.5f, 24, 14.0f, 1600.0f}, // quantum
        {4, 5.5f, 14, 17.0f,    0.0f}, // quake_screen
    }};
    struct Slot {
        Profile profile;
        float amplitude;
        double birthSec, expireSec;
        double axisX, axisY, phase;
    };
    static bool Stronger(float amplitude, int priority, float otherAmplitude, int otherPriority) noexcept {
        return amplitude > otherAmplitude || (amplitude == otherAmplitude && priority > otherPriority);
    }
    static uint64_t MixOrdinal(uint64_t n) noexcept {
        n = (n ^ (n >> 30)) * 0xbf58476d1ce4e5b9ULL;
        n = (n ^ (n >> 27)) * 0x94d049bb133111ebULL;
        return n ^ (n >> 31);
    }
    static double Unit(uint64_t bits) noexcept { return static_cast<double>(bits & 0xffff) / 65535.0; }

    std::array<Profile, kMaxProfiles> profiles_ = kDefaultProfiles;
    int32_t profileCount_ = kDefaultProfileCount;
    float maxTotalOffsetStagePx_ = MaxTotalOffsetStagePx;
    std::array<Slot, kMaxSlots> slots_{};
    std::size_t activeCount_ = 0;
    int32_t currentGrant_ = 0;
    int32_t lastPresentedX_ = 0, lastPresentedY_ = 0;
    bool tailPending_ = false;
    uint64_t impulseOrdinal_ = 0;
    Counters counters_;
};

#ifdef CF7_WORLD_SHAKE_D3D11
#include <d3d11.h>
#include <winrt/base.h>
#include <CompositorShaders.g.h>
#include "Compositor.h"
#include "CasSourceStage.h"

// GPU resources belong to the capture worker.
class WorldShakeStage {
public:
    // Pixel centers lie in the half-open viewport. Use the same destination
    // coverage for the blit and the shifted damage layer's integer scissor.
    static D3D11_RECT ContentPixels(const D3D11_VIEWPORT& view, int width, int height) noexcept {
        auto edge = [](float value, int limit) {
            return static_cast<LONG>(std::clamp(std::ceil(value - 0.5f), 0.0f, static_cast<float>(limit)));
        };
        return {edge(view.TopLeftX, width), edge(view.TopLeftY, height),
            edge(view.TopLeftX + view.Width, width), edge(view.TopLeftY + view.Height, height)};
    }

    bool EnsureOutputSize(ID3D11Device* device, int width, int height) {
        if (allocGuard_.IsLatched(width, height)) return false;
        if (texture_ && width == width_ && height == height_) return true;
        Reset();
        return allocGuard_.TryAllocate(device, width, height, [&] {
            D3D11_TEXTURE2D_DESC texture{};
            texture.Width = static_cast<UINT>(width);
            texture.Height = static_cast<UINT>(height);
            texture.MipLevels = texture.ArraySize = texture.SampleDesc.Count = 1;
            texture.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
            texture.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
            winrt::check_hresult(device->CreateTexture2D(&texture, nullptr, texture_.put()));
            winrt::check_hresult(device->CreateRenderTargetView(texture_.get(), nullptr, target_.put()));
            winrt::check_hresult(device->CreateShaderResourceView(texture_.get(), nullptr, source_.put()));
            auto vs = CompositorShaders::ShakeVS;
            auto ps = CompositorShaders::ShakePS;
            winrt::check_hresult(device->CreateVertexShader(vs.data, vs.size, nullptr, vs_.put()));
            winrt::check_hresult(device->CreatePixelShader(ps.data, ps.size, nullptr, ps_.put()));
            D3D11_BUFFER_DESC constants{};
            constants.ByteWidth = sizeof(BlitParams);
            constants.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
            winrt::check_hresult(device->CreateBuffer(&constants, nullptr, constants_.put()));
            D3D11_SAMPLER_DESC sampler{};
            sampler.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
            sampler.AddressU = sampler.AddressV = sampler.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
            sampler.ComparisonFunc = D3D11_COMPARISON_NEVER;
            sampler.MaxAnisotropy = 1;
            winrt::check_hresult(device->CreateSamplerState(&sampler, sampler_.put()));
            D3D11_RASTERIZER_DESC scissor{};
            scissor.FillMode = D3D11_FILL_SOLID;
            scissor.CullMode = D3D11_CULL_NONE;
            scissor.DepthClipEnable = TRUE;
            scissor.ScissorEnable = TRUE;
            winrt::check_hresult(device->CreateRasterizerState(&scissor, scissor_.put()));
            width_ = width;
            height_ = height;
        }, [&] { Reset(); });
    }

    static D3D11_RECT SamplePixels(const D3D11_VIEWPORT& content, const D3D11_VIEWPORT& rendered,
            int width, int height) noexcept {
        // Read whole texels inside both the stage and the captured rectangle.
        // Cropped captures can leave a sliver of the stage unpainted.
        return {
            static_cast<LONG>(std::ceil(std::max({0.f, content.TopLeftX, rendered.TopLeftX}))),
            static_cast<LONG>(std::ceil(std::max({0.f, content.TopLeftY, rendered.TopLeftY}))),
            static_cast<LONG>(std::floor(std::min({static_cast<float>(width),
                content.TopLeftX + content.Width, rendered.TopLeftX + rendered.Width}))),
            static_cast<LONG>(std::floor(std::min({static_cast<float>(height),
                content.TopLeftY + content.Height, rendered.TopLeftY + rendered.Height}))),
        };
    }

    void BlitToBackbuffer(ID3D11DeviceContext* context, ID3D11RenderTargetView* backbuffer,
            int width, int height, const D3D11_VIEWPORT& content, const D3D11_RECT& samples,
            int32_t dx, int32_t dy) const noexcept {
        ID3D11ShaderResourceView* empty = nullptr;
        context->PSSetShaderResources(0, 1, &empty);
        context->OMSetRenderTargets(1, &backbuffer, nullptr);
        const float black[]{0, 0, 0, 1};
        context->ClearRenderTargetView(backbuffer, black);

        const auto dest = ContentPixels(content, width, height);
        const BlitParams params{dx, dy, width, height, samples.left, samples.top, samples.right - 1, samples.bottom - 1};
        const D3D11_VIEWPORT viewport{static_cast<float>(dest.left), static_cast<float>(dest.top),
            static_cast<float>(dest.right - dest.left), static_cast<float>(dest.bottom - dest.top), 0, 1};
        context->RSSetViewports(1, &viewport);
        context->UpdateSubresource(constants_.get(), 0, nullptr, &params, 0, 0);
        auto constants = constants_.get();
        auto source = source_.get();
        auto sampler = sampler_.get();
        context->PSSetConstantBuffers(0, 1, &constants);
        context->PSSetShaderResources(0, 1, &source);
        context->PSSetSamplers(0, 1, &sampler);
        context->VSSetShader(vs_.get(), nullptr, 0);
        context->PSSetShader(ps_.get(), nullptr, 0);
        context->OMSetBlendState(nullptr, nullptr, 0xffffffff);
        context->Draw(3, 0);
        context->PSSetShaderResources(0, 1, &empty);
    }

    ID3D11Texture2D* Texture() const noexcept { return texture_.get(); }
    ID3D11RenderTargetView* Target() const noexcept { return target_.get(); }
    ID3D11RasterizerState* ScissorRaster() const noexcept { return scissor_.get(); }
    uint64_t Bytes() const noexcept { return static_cast<uint64_t>(width_) * height_ * 4; }

    void Reset() noexcept {
        source_ = nullptr;
        target_ = nullptr;
        texture_ = nullptr;
        vs_ = nullptr;
        ps_ = nullptr;
        constants_ = nullptr;
        sampler_ = nullptr;
        scissor_ = nullptr;
        width_ = height_ = 0;
        allocGuard_.ClearLatch();
    }

private:
    struct BlitParams {
        int32_t dx, dy, width, height;
        LONG minX, minY, maxX, maxY;
    };
    static_assert(sizeof(BlitParams) == 32);
    winrt::com_ptr<ID3D11Texture2D> texture_;
    winrt::com_ptr<ID3D11RenderTargetView> target_;
    winrt::com_ptr<ID3D11ShaderResourceView> source_;
    winrt::com_ptr<ID3D11VertexShader> vs_;
    winrt::com_ptr<ID3D11PixelShader> ps_;
    winrt::com_ptr<ID3D11Buffer> constants_;
    winrt::com_ptr<ID3D11SamplerState> sampler_;
    winrt::com_ptr<ID3D11RasterizerState> scissor_;
    int width_ = 0, height_ = 0;
    StageAllocationGuard allocGuard_;
};
#endif
