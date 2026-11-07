using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using CF7Launcher.Guardian.Hud.Icons;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.Loot
{
    public sealed partial class LootIconCatalog
    {
        // Descriptors never own or retain an evictable bitmap, codec or encoded data.
        internal sealed class IconDescription
        {
            internal string Name, Poster, Webp;
            internal string[] Keys;
            internal IconTimeline Timeline;
            internal double Fps;
            internal bool Legacy, Failed;
            internal int Revision;
            internal bool Animated => !Failed && Timeline != null && Keys.Length > 1;
            internal int Sample(long ticks, bool animate) => animate && !Failed && Timeline != null ? Timeline.Sample(ticks) : -1;
        }

        private sealed class WebpMetadata
        {
            internal int[] Durations;
            internal string[] Keys;
            internal bool Failed;
        }

        private readonly Dictionary<string, IconDescription> _descriptions = new Dictionary<string, IconDescription>(StringComparer.Ordinal);
        private readonly Dictionary<string, WebpMetadata> _webpMetadata = new Dictionary<string, WebpMetadata>(StringComparer.Ordinal);
        private readonly HashSet<string> _failedPlaybackFrames = new HashSet<string>(StringComparer.Ordinal);
        private bool _playbackDisposed;
        internal long PlaybackFileOpens { get; private set; }
        internal long PlaybackCodecCreations { get; private set; }
        internal long PlaybackFullDecodes { get; private set; }

        /// <summary>Binding/preparation entry, never called by visual signature sampling.</summary>
        internal IconDescription DescribeForPlayback(string name, bool animate)
        {
            if (string.IsNullOrEmpty(name)) return null;
            lock (_gate)
            {
                if (_playbackDisposed) return null;
                if (!_descriptions.TryGetValue(name, out var description))
                {
                    EnsureManifestLoaded();
                    description = new IconDescription { Name = name };
                    if (_manifest == null || !_manifest.TryGetValue(name, out var entry))
                        description.Legacy = true; // Enemy aliases and recoverable doll requests keep their existing contract.
                    else
                    {
                        description.Poster = entry.F1;
                        description.Fps = entry.Fps;
                        if (entry.FrameUris != null && entry.FrameUris.Count > 1)
                            PreparePngTimeline(description, entry.FrameUris);
                        else if (entry.Format == "webp-animated" && !entry.StaticPlayback)
                            description.Webp = !string.IsNullOrEmpty(entry.Uri) ? entry.Uri : entry.F1;
                    }
                    _descriptions.Add(name, description);
                }
                if (animate && description.Webp != null && description.Timeline == null && !description.Failed)
                {
                    WebpMetadata metadata = GetWebpMetadata(description.Webp);
                    if (metadata.Failed) description.Failed = true;
                    else
                    {
                        description.Keys = metadata.Keys;
                        int[] slots = new int[metadata.Keys.Length];
                        for (int i = 0; i < slots.Length; i++) slots[i] = i;
                        description.Timeline = new IconTimeline(slots, description.Fps, metadata.Durations);
                    }
                }
                return description;
            }
        }

        private void PreparePngTimeline(IconDescription description, List<string> uris)
        {
            var indices = new Dictionary<string, int>(StringComparer.Ordinal);
            var keys = new List<string>();
            int[] slots = new int[uris.Count];
            for (int i = 0; i < uris.Count; i++)
            {
                string uri = uris[i];
                // A missing slot keeps its original duration; only the picture is substituted.
                if (string.IsNullOrEmpty(uri) || !File.Exists(Path.Combine(_iconsDir, uri)))
                    uri = description.Poster ?? string.Empty;
                if (!indices.TryGetValue(uri, out int index))
                {
                    index = keys.Count;
                    indices.Add(uri, index);
                    keys.Add(uri);
                }
                slots[i] = index;
            }
            description.Keys = keys.ToArray();
            if ((long)keys.Count * ThumbBytes > _frameCache.MaxBytes) description.Failed = true;
            else description.Timeline = new IconTimeline(slots, description.Fps);
        }

        private WebpMetadata GetWebpMetadata(string uri)
        {
            if (_webpMetadata.TryGetValue(uri, out var metadata)) return metadata;
            metadata = new WebpMetadata { Failed = true };
            _webpMetadata.Add(uri, metadata); // Remember failure even when a usable poster exists.
            string path = Path.Combine(_iconsDir, uri);
            try
            {
                if (!File.Exists(path)) return metadata;
                PlaybackFileOpens++;
                using (SKData encoded = SKData.Create(path))
                {
                    PlaybackCodecCreations++;
                    using (SKCodec codec = SKCodec.Create(encoded))
                    {
                        if (codec == null || codec.FrameCount < 2 || codec.Info.Width <= 0 || codec.Info.Height <= 0
                            || (long)codec.FrameCount * ThumbBytes > _frameCache.MaxBytes) return metadata;
                        StoreWebpMetadata(uri, codec.FrameInfo, metadata);
                    }
                }
            }
            catch (Exception ex) { LogManager.Log("[LootIcon] timeline unavailable: " + uri + ": " + ex.Message); }
            return metadata;
        }

        private WebpMetadata StoreWebpMetadata(string uri, SKCodecFrameInfo[] infos, WebpMetadata metadata = null)
        {
            if (metadata == null && _webpMetadata.TryGetValue(uri, out metadata) && !metadata.Failed) return metadata;
            metadata = metadata ?? new WebpMetadata();
            metadata.Durations = new int[infos.Length];
            metadata.Keys = new string[infos.Length];
            for (int i = 0; i < infos.Length; i++)
            {
                metadata.Durations[i] = Math.Max(0, infos[i].Duration);
                metadata.Keys[i] = uri + "#f" + i;
            }
            metadata.Failed = false;
            _webpMetadata[uri] = metadata;
            return metadata;
        }

        /// <summary>The catalog lock covers lookup, eviction on a miss, and the actual Draw.</summary>
        internal bool TryDrawPlayback(Graphics graphics, Rectangle destination, IconDescription description, int content, float alpha)
        {
            if (description == null) return false;
            lock (_gate)
            {
                if (_playbackDisposed) return false;
                Bitmap bitmap = null;
                if (description.Legacy)
                {
                    if (TryGet(description.Name, out var legacy)) bitmap = legacy.First;
                }
                else if (content >= 0 && !description.Failed && description.Timeline != null)
                {
                    string key = description.Keys[content];
                    if (!_frameCache.TryGet(key, out bitmap))
                    {
                        if (description.Webp != null)
                        {
                            var loaded = LoadWebpFrames(description.Webp, out _);
                            if (loaded != null && content < loaded.Length) bitmap = loaded[content];
                        }
                        else bitmap = LoadPlaybackPoster(key);
                        if (bitmap == null) { description.Failed = true; description.Revision++; }
                    }
                }
                if (bitmap == null && !description.Legacy) bitmap = LoadPlaybackPoster(description.Poster);
                if (bitmap == null) return false;
                if (alpha >= 0.999f)
                    graphics.DrawImage(bitmap, destination, 0, 0, bitmap.Width, bitmap.Height, GraphicsUnit.Pixel);
                else
                {
                    using (var attributes = new ImageAttributes())
                    {
                        attributes.SetColorMatrix(new ColorMatrix { Matrix33 = Math.Clamp(alpha, 0f, 1f) });
                        graphics.DrawImage(bitmap, destination, 0, 0, bitmap.Width, bitmap.Height, GraphicsUnit.Pixel, attributes);
                    }
                }
                return true;
            }
        }

        private Bitmap LoadPlaybackPoster(string uri)
        {
            if (string.IsNullOrEmpty(uri) || _failedPlaybackFrames.Contains(uri)) return null;
            if (_frameCache.TryGet(uri, out var bitmap)) return bitmap;
            bitmap = LoadFrame(uri);
            if (bitmap == null) _failedPlaybackFrames.Add(uri);
            return bitmap;
        }
    }
}
