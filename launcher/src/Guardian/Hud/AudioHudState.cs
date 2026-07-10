using System;
using System.Collections.Generic;
using CF7Launcher.Audio;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Native HUD 的唯一轻量 BGM 可视化状态。UiData 只提供曲名/性能偏好，
    /// 播放状态与峰值从 AudioEngine 低频采样；消费者不得再各自维护 peak history。
    /// </summary>
    public sealed class AudioHudState
    {
        private const int HistoryCapacity = 64;
        private const int PeakSampleIntervalMs = 100;
        private const int PlayingPollIntervalMs = 250;

        private readonly float[] _left = new float[HistoryCapacity];
        private readonly float[] _right = new float[HistoryCapacity];
        private int _writeIndex;
        private int _length;
        private int _sampleElapsedMs;
        private int _pollElapsedMs;
        private string _title = "";
        private bool _disableVisualizers;
        private bool _isPlaying;

        public string Title { get { return _title; } }
        public bool DisableVisualizers { get { return _disableVisualizers; } }
        public bool IsPlaying { get { return _isPlaying; } }
        public bool HasSamples { get { return _length > 0; } }
        public int SampleCount { get { return _length; } }
        public bool WantsTick { get { return !string.IsNullOrEmpty(_title) && !_disableVisualizers; } }

        public bool ApplyUiData(IReadOnlyDictionary<string, string> snapshot, ISet<string> changedKeys)
        {
            if (snapshot == null || changedKeys == null) return false;
            bool changed = false;
            string piece;
            if (changedKeys.Contains("s") && snapshot.TryGetValue("s", out piece)
                && StripPrefix(piece, "s") != "1")
            {
                changed = !string.IsNullOrEmpty(_title) || _isPlaying || _length > 0;
                Reset();
                return changed;
            }
            if (changedKeys.Contains("bgm") && snapshot.TryGetValue("bgm", out piece))
            {
                string next = StripPrefix(piece, "bgm") ?? "";
                if (!string.Equals(next, _title, StringComparison.Ordinal))
                {
                    _title = next;
                    ClearSamples();
                    _isPlaying = false;
                    changed = true;
                }
            }
            if (changedKeys.Contains("pl") && snapshot.TryGetValue("pl", out piece))
            {
                int level;
                if (!int.TryParse(StripPrefix(piece, "pl"), out level)) level = 0;
                bool disabled = level >= 2;
                if (disabled != _disableVisualizers)
                {
                    _disableVisualizers = disabled;
                    changed = true;
                }
            }
            return changed;
        }

        public void Reset()
        {
            _title = "";
            _isPlaying = false;
            ClearSamples();
        }

        /// <summary>推进低频采样；返回 true 表示消费者应重绘。</summary>
        public bool Tick(int deltaMs)
        {
            if (string.IsNullOrEmpty(_title) || _disableVisualizers)
            {
                _sampleElapsedMs = 0;
                _pollElapsedMs = 0;
                return false;
            }

            int dt = Math.Max(1, deltaMs);
            bool changed = false;
            _pollElapsedMs += dt;
            if (_pollElapsedMs >= PlayingPollIntervalMs)
            {
                _pollElapsedMs %= PlayingPollIntervalMs;
                bool playing = SafeIsPlaying();
                if (playing != _isPlaying)
                {
                    _isPlaying = playing;
                    changed = true;
                }
            }

            if (!_isPlaying) return changed;
            _sampleElapsedMs += dt;
            if (_sampleElapsedMs >= PeakSampleIntervalMs)
            {
                _sampleElapsedMs %= PeakSampleIntervalMs;
                float left, right;
                SafeGetPeak(out left, out right);
                AddSample(left, right);
                changed = true;
            }
            return changed;
        }

        public void GetSample(int chronologicalIndex, out float left, out float right)
        {
            if (chronologicalIndex < 0 || chronologicalIndex >= _length)
            {
                left = 0f;
                right = 0f;
                return;
            }
            int index = (_writeIndex - _length + chronologicalIndex + HistoryCapacity) % HistoryCapacity;
            left = _left[index];
            right = _right[index];
        }

        internal void ForcePlayingForTest(bool playing) { _isPlaying = playing; }
        internal void AddSampleForTest(float left, float right) { AddSample(left, right); }

        private void AddSample(float left, float right)
        {
            _left[_writeIndex] = ClampPeak(left);
            _right[_writeIndex] = ClampPeak(right);
            _writeIndex = (_writeIndex + 1) % HistoryCapacity;
            if (_length < HistoryCapacity) _length++;
        }

        private void ClearSamples()
        {
            _writeIndex = 0;
            _length = 0;
            _sampleElapsedMs = 0;
            _pollElapsedMs = 0;
        }

        private static string StripPrefix(string value, string key)
        {
            if (string.IsNullOrEmpty(value)) return "";
            string prefix = key + ":";
            return value.StartsWith(prefix, StringComparison.Ordinal) ? value.Substring(prefix.Length) : value;
        }

        private static bool SafeIsPlaying()
        {
            try { return AudioEngine.ma_bridge_bgm_is_playing() == 1; }
            catch { return false; }
        }

        private static void SafeGetPeak(out float left, out float right)
        {
            try { AudioEngine.ma_bridge_bgm_get_peak(out left, out right); }
            catch { left = 0f; right = 0f; }
        }

        private static float ClampPeak(float value)
        {
            if (float.IsNaN(value) || float.IsInfinity(value) || value < 0f) return 0f;
            return value > 1f ? 1f : value;
        }
    }
}
