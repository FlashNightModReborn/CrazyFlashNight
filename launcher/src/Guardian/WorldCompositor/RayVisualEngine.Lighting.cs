using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed partial class RayVisualEngine
    {
        private RayLightingCatalog _lightingCatalog;
        private readonly Dictionary<int, Arc> _lightingChannels = new();
        private readonly HashSet<int> _lightingLiveChannels = new();
        private readonly List<int> _lightingRetiredChannels = new();

        internal void ConfigureLighting(RayLightingCatalog catalog)
        {
            _lightingCatalog = catalog;
            _draw.LightCount = 0;
            Array.Clear(_draw.Lights);
        }

        private void ClearLighting()
        {
            _draw.LightCount = 0;
            Array.Clear(_draw.Lights);
            _lightingChannels.Clear();
            _lightingLiveChannels.Clear();
            _lightingRetiredChannels.Clear();
        }

        private void BuildLights()
        {
            _draw.LightCount = 0;
            _lightingLiveChannels.Clear();
            _lightingRetiredChannels.Clear();
            // Apply can consume more than one packet before a draw. Remember an
            // already-emitted replacement even if it expired between those draws.
            foreach(var pair in _channelHeads)
            {
                Arc head=pair.Value;
                if(head.Age<(head.Event.Delay>0?1:0)) continue;
                if(!_lightingChannels.TryGetValue(pair.Key,out var current)||NewerChannel(head,current))
                    _lightingChannels[pair.Key]=head;
            }
            // A discontinuous channel may leave its old visible tail in the body
            // list. Its newest channel geometry owns the one light, even if its
            // new profile is none. Tongues and hit ornaments never create lights.
            foreach (Arc arc in _arcs)
            {
                if (!HasChannel(arc)) continue;
                int key = arc.Event.Key;
                _lightingLiveChannels.Add(key);
                if (!Visible(arc)) continue;
                if (!_lightingChannels.TryGetValue(key, out var current) || NewerChannel(arc, current))
                    _lightingChannels[key] = arc;
            }
            // Keep a newer owner's tombstone while any older tail remains. Otherwise
            // a short/none replacement expiring first could relight a retired tail.
            foreach (int key in _lightingChannels.Keys)
                if (!_lightingLiveChannels.Contains(key)) _lightingRetiredChannels.Add(key);
            foreach (int key in _lightingRetiredChannels) _lightingChannels.Remove(key);
            if (_lightingCatalog == null) return;
            foreach (Arc arc in _arcs)
            {
                // Wire kind is main=0, chain=1, fork=2, pierce=3, flame=4.
                // Branches share their primary beam's illuminated neighborhood.
                if (!Visible(arc) || arc.Event.Kind is not (0 or 3 or 4)) continue;
                if (HasChannel(arc) && !ReferenceEquals(_lightingChannels[arc.Event.Key], arc)) continue;
                if (TryBuildLight(arc, out var candidate))
                    _draw.Lights[_draw.LightCount++] = candidate;
            }
        }

        private static bool HasChannel(Arc arc) => arc.Event.Key > 0;

        private static bool NewerChannel(Arc candidate, Arc current) =>
            candidate.Event.Serial > current.Event.Serial
            || (candidate.Event.Serial == current.Event.Serial
                && (candidate.EmissionBirth > current.EmissionBirth
                    || (candidate.EmissionBirth == current.EmissionBirth && candidate.Event.Id > current.Event.Id)));

        private bool TryBuildLight(Arc arc, out WorldLightCandidate candidate)
        {
            candidate = default;
            RayVisualConfig config = arc.Config;
            RayLightOverrides light = config.Light;
            RayLightingProfile profile = _lightingCatalog.Resolve(config.Style, light);
            if (profile == null || light.EnergyScale == 0 || profile.Energy == 0) return false;
            float dx = arc.EndX - arc.StartX, dy = arc.EndY - arc.StartY;
            double actualLength = Math.Sqrt((double)dx * dx + (double)dy * dy);
            // Do not invent a radius or direction for a degenerate/subpixel ray.
            if (!double.IsFinite(actualLength) || actualLength < 1) return false;
            float length = (float)Math.Min(actualLength, profile.MaxLength);
            float directionX = (float)(dx / actualLength), directionY = (float)(dy / actualLength);
            float halfWidth = Math.Clamp(config[2] * profile.WidthScale * light.WidthScale,
                profile.MinWidth, profile.MaxWidth);
            // A short luminous source can illuminate farther sideways than its
            // body length. Only near-zero/blocked geometry collapses the halo;
            // the former length/2 cap erased useful light during flame growth.
            halfWidth = Math.Min(halfWidth, Math.Max(.5f, length * 2));
            float envelope = LightEnvelope(arc, profile, light);
            float energy = profile.Energy * light.EnergyScale * Math.Clamp(arc.Event.Intensity, 0, 1) * envelope;
            if (profile.Flicker > 0)
            {
                // Pure visual hash: phase follows game ticks and preserves its seed
                // across persistent upserts. No gameplay RNG or wall-clock time.
                uint noise = Hash(arc.Seed ^ ((uint)arc.PhaseAge * 747796405u + 0x9e3779b9u));
                energy *= 1 - profile.Flicker * (noise / (float)uint.MaxValue);
            }
            energy = Math.Clamp(energy, 0, 2);
            if (!(energy > 0)) return false;
            int rgb = light.Color >= 0 ? light.Color : (profile.FixedColor >= 0 ? profile.FixedColor : (int)config[0]);
            // An explicit color override is exact. Defaults can be softened toward
            // white; palette scrolling and rainbow stripes never alter this tint.
            float whiten = light.Color >= 0 ? 0 : profile.Whiten;
            float r = ((rgb >> 16) & 255) / 255f, g = ((rgb >> 8) & 255) / 255f, b = (rgb & 255) / 255f;
            r += (1 - r) * whiten; g += (1 - g) * whiten; b += (1 - b) * whiten;
            uint identity = HasChannel(arc) ? (uint)arc.Event.Key | 0x80000000u : (uint)arc.Event.Id;
            long key = ((long)(uint)_epoch << 32) | identity;
            float nearRadius = 0, nearEnergy = 0, nearX = 0, nearY = 0;
            if (profile.Kind == 1)
            {
                nearRadius = Math.Min(halfWidth * profile.NearWidthRatio,
                    Math.Min(profile.MaxNearRadius, length));
                nearEnergy = energy * profile.NearEnergyRatio;
                if (nearRadius > 0 && nearEnergy > 0) { nearX = arc.StartX; nearY = arc.StartY; }
                else { nearRadius = 0; nearEnergy = 0; }
            }
            candidate = new WorldLightCandidate(key, profile.Priority, arc.StartX, arc.StartY,
                length, energy, r, g, b, profile.Kind, directionX, directionY, halfWidth,
                nearX, nearY, nearRadius, nearEnergy);
            return true;
        }

        private static float LightEnvelope(Arc arc, RayLightingProfile profile, RayLightOverrides light)
        {
            // Positive visual fade reaches zero alpha at its endpoint. Even a
            // deliberately long light hold cannot leave one extra lit frame there.
            if (arc.Config[4] > 0 && arc.Age >= arc.Config[3] + arc.Config[4]) return 0;
            int visibleStart = arc.Event.Delay > 0 ? 1 : 0;
            float age = arc.Age - visibleStart;
            float visualEnd = Math.Max(0, arc.Config[3] + arc.Config[4] - visibleStart);
            float visualHold = Math.Max(0, arc.Config[3] - visibleStart);
            float hold = Math.Min(profile.HoldTicks < 0 ? visualHold : profile.HoldTicks, visualEnd);
            float fade = Math.Min(light.FadeTicks < 0 ? profile.FadeTicks : light.FadeTicks, visualEnd - hold);
            if (age <= hold) return 1;
            return fade > 0 ? Math.Clamp(1 - (age - hold) / fade, 0, 1) : 0;
        }
    }
}
