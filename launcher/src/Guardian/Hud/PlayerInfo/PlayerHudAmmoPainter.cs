#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudAmmoPainter
{
    internal static readonly Color NormalText = Color.FromArgb(204, 204, 204);
    internal static readonly Color LowLoadedText = Color.FromArgb(245, 172, 92);
    internal static readonly Color EmptyLoadedText = Color.FromArgb(242, 108, 92);
    internal static readonly Color GhostText = Color.FromArgb(255, 204, 112);
    internal static readonly Color RewardText = Color.FromArgb(202, 173, 255);
    internal static readonly Color ChamberText = Color.FromArgb(155, 224, 233);

    internal static readonly Color ReserveNormalText = Color.FromArgb(176, 184, 186);
    internal static readonly Color ReserveLowText = Color.FromArgb(217, 155, 82);
    internal static readonly Color ReserveEmptyText = Color.FromArgb(200, 100, 88);

    // Hollow chamber / trough palette: subtle recessed track that shows spent capacity without heavy box-in-box clutter.
    internal static readonly Color HollowSlotBorder = Color.FromArgb(148, 96, 108, 114);
    internal static readonly Color HollowSlotInterior = Color.FromArgb(225, 11, 14, 16);
    internal static readonly Color HollowSlotSubtleTick = Color.FromArgb(140, 68, 78, 84);
    internal static readonly Color EmptyHollowBorder = Color.FromArgb(155, 172, 76, 66);
    internal static readonly Color EmptyHollowInterior = Color.FromArgb(225, 22, 12, 12);

    internal static readonly Color BarNormalFill = Color.FromArgb(218, 230, 234);
    internal static readonly Color BarLeadingEdge = Color.FromArgb(255, 252, 254, 255);
    internal static readonly Color BarNotch = Color.FromArgb(225, 12, 15, 17);

    // Tactical card & icon palette
    private static readonly Color CardBgTop = Color.FromArgb(242, 24, 28, 30);
    private static readonly Color CardBgBottom = Color.FromArgb(246, 14, 17, 19);
    private static readonly Color CardBorderDark = Color.FromArgb(245, 6, 8, 9);
    private static readonly Color CardBorderLight = Color.FromArgb(200, 54, 62, 66);
    private static readonly Color CardCornerTick = Color.FromArgb(175, 112, 124, 130);
    private static readonly Color DividerLineColor = Color.FromArgb(135, 72, 82, 88);
    private static readonly Color DividerShadowColor = Color.FromArgb(180, 8, 10, 12);
    private static readonly Color IconRecess = Color.FromArgb(242, 16, 20, 22);

    // Unified layout constants (logical 1024x576 space)
    internal const float CardLeft = 484.0f;
    internal const float CardRightFull = 588.0f;
    internal const float CardRightCompact = 553.0f;
    internal const float Row0Top = 515.5f;
    internal const float Row1Top = 541.5f;
    internal const float RowStep = 26.0f;
    internal const float CardHeight = 22.0f;
    internal const float ContentPadX = 5.2f;
    internal const float IconWidth = 5.8f;
    internal const float IconHeight = 7.5f;
    internal const float IconOffsetY = 3.0f;
    internal const float TextOffsetY = -1.0f;
    internal const float ReserveRowIconOffsetY = 7.2f;
    internal const float ReserveRowTextOffsetY = 3.2f;
    internal const float BarOffsetY = 15.8f;
    internal const float BarHeight = 2.6f;
    internal const float IconToNumberGap = 4.2f;
    internal const float DividerToIconGap = 5.6f;
    internal const float DefaultDualSplitX = 543.5f;

    internal static bool TryParseAmmoCount(string raw, out int count) =>
        int.TryParse(raw.AsSpan().Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out count);

    internal static Color AmmoColor(
        PlayerHudAmmoDetail? detail,
        string loadedText = "",
        int observedCapacity = 0)
    {
        if (detail is { Ghost: > 0 }) return GhostText;
        if (detail is { Reward: > 0 }) return RewardText;
        if (detail is { Chamber: > 0 }) return ChamberText;

        var hasLoaded = TryParseAmmoCount(loadedText, out var parsedLoaded);
        var loaded = detail is { Capacity: > 0 } ? detail.Loaded : (hasLoaded ? parsedLoaded : -1);
        var capacity = detail is { Capacity: > 0 } ? detail.Capacity : Math.Max(observedCapacity, loaded);

        if ((detail is { Capacity: > 0, Loaded: <= 0 }) || (hasLoaded && parsedLoaded <= 0))
            return EmptyLoadedText;

        if (capacity >= 2 && loaded > 0 && loaded < capacity && (loaded * 5 <= capacity || loaded == 1))
            return LowLoadedText;

        return NormalText;
    }

    internal static Color ReserveAmmoColor(string magText)
    {
        var trimmed = magText.AsSpan().Trim();
        if (trimmed.IsEmpty) return ReserveNormalText;
        if (!int.TryParse(trimmed, NumberStyles.Integer, CultureInfo.InvariantCulture, out var clips))
            return ReserveNormalText;
        if (clips <= 0) return ReserveEmptyText;
        if (clips <= 2) return ReserveLowText;
        return ReserveNormalText;
    }

    /// <summary>
    /// Computes the rigid width budget for the primary loaded count based on Max(Loaded, Capacity),
    /// ensuring the split divider never jitters horizontally while firing down a magazine.
    /// </summary>
    internal static PlayerHudNumberText FormatPrimaryLoaded(
        string raw,
        Func<string, float> measure,
        float maxWidth,
        int capacityAnchor = 0)
    {
        var display = raw.Length == 0 ? "—" : raw;
        if (!TryParseAmmoCount(display, out var loaded))
        {
            var fitted = PlayerHudNumberFormat.FitText(display, measure, maxWidth);
            return new(fitted, Math.Clamp(measure(fitted), 12f, maxWidth));
        }

        var anchor = Math.Max(Math.Max(0, loaded), Math.Max(0, capacityAnchor));
        var digits = anchor >= 10000 ? 5 : anchor >= 1000 ? 4 : anchor >= 100 ? 3 : 2;
        var template = new string('8', digits);
        var exactWidth = measure(display);
        var templateWidth = measure(template);
        if (exactWidth <= maxWidth)
        {
            var reserved = Math.Min(maxWidth, Math.Max(exactWidth, templateWidth));
            return new(display, reserved);
        }

        var compact = PlayerHudNumberFormat.Fit(loaded, measure, maxWidth, anchor, compact: true);
        return new(compact, Math.Min(maxWidth, Math.Max(measure(compact), templateWidth)));
    }

    /// <summary>
    /// Formats spare magazine counts with adaptive yielding:
    /// 0~999 exact; 1000~9999 exact when space allows, else 999+;
    /// 10000+ uses tiered 万 notation (1.23万 -> 1.2万 -> 1万+ -> 999+) according to remaining width.
    /// </summary>
    internal static string FormatReserveWithYield(
        string raw,
        Func<string, float> measure,
        float availableWidth)
    {
        if (raw.Length == 0) return "—";
        var trimmed = raw.Trim();
        if (!double.TryParse(trimmed, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) || !double.IsFinite(value))
            return trimmed;

        var clips = (long)Math.Floor(Math.Max(0, value));
        if (clips < 1000)
            return clips.ToString(CultureInfo.InvariantCulture);

        if (clips < 10000)
        {
            var exact = clips.ToString(CultureInfo.InvariantCulture);
            return measure(exact) <= availableWidth ? exact : "999+";
        }

        if (clips < 100_000_000)
        {
            var wan = clips / 10000.0;
            var exactWan = clips % 10000 == 0;
            if (clips < 100_000)
            {
                var twoDec = (Math.Floor(wan * 100) / 100).ToString("0.##", CultureInfo.InvariantCulture) + "万";
                if (measure(twoDec) <= availableWidth) return twoDec;
            }
            var oneDec = (Math.Floor(wan * 10) / 10).ToString("0.#", CultureInfo.InvariantCulture) + "万";
            if (measure(oneDec) <= availableWidth) return oneDec;

            var wholeWan = Math.Floor(wan).ToString("0", CultureInfo.InvariantCulture) + (exactWan ? "万" : "万+");
            if (measure(wholeWan) <= availableWidth) return wholeWan;

            return measure("9999+") <= availableWidth ? "9999+" : "999+";
        }

        return PlayerHudNumberFormat.Fit(clips, measure, availableWidth, clips, compact: true);
    }

    /// <summary>
    /// Resolves the X coordinate of the middle magazine icon / divider in dual/subweapon mode so that:
    /// - For 1~4 digit weapons (up to 9999), both rows lock to a fixed split column (baseSplitX);
    /// - For wider strings, the column shifts smoothly without collision.
    /// </summary>
    internal static float ResolveDualMagazineIconX(
        float leftX,
        float rightEdge,
        float primaryReservedWidth,
        float reserveNeededWidth,
        float baseSplitX = DefaultDualSplitX)
    {
        var minAfterPrimary = leftX + primaryReservedWidth + 4.5f;
        var maxBeforeReserve = rightEdge - (IconWidth + IconToNumberGap + reserveNeededWidth);
        var target = Math.Min(baseSplitX, maxBeforeReserve);
        return Math.Max(minAfterPrimary, target);
    }

    /// <summary>
    /// Paints a device-pixel-snapped tactical readout card that encloses the icon, number, and bottom bar
    /// inside one cohesive frame (replacing the legacy non-uniformly stretched Flash SVG boxes).
    /// </summary>
    internal static void PaintTacticalCard(
        Graphics g,
        RectangleF logicalBounds,
        float scale,
        Color statusAccent)
    {
        if (scale <= 0 || logicalBounds.Width <= 0 || logicalBounds.Height <= 0) return;

        var saved = g.Save();
        try
        {
            g.ScaleTransform(1f / scale, 1f / scale);
            g.SmoothingMode = SmoothingMode.None;
            g.PixelOffsetMode = PixelOffsetMode.Half;

            var x = (int)Math.Round(logicalBounds.Left * scale);
            var y = (int)Math.Round(logicalBounds.Top * scale);
            var w = Math.Max(16, (int)Math.Round(logicalBounds.Width * scale));
            var h = Math.Max(10, (int)Math.Round(logicalBounds.Height * scale));

            var topHalf = h / 2;
            using (var bgTop = new SolidBrush(CardBgTop))
            using (var bgBot = new SolidBrush(CardBgBottom))
            {
                g.FillRectangle(bgTop, x, y, w, topHalf);
                g.FillRectangle(bgBot, x, y + topHalf, w, h - topHalf);
            }

            // Recessed 1px beveled frame: dark top/left shadow + metallic bottom/right rim
            using (var darkBorder = new SolidBrush(CardBorderDark))
            using (var lightBorder = new SolidBrush(CardBorderLight))
            {
                g.FillRectangle(darkBorder, x, y, w, 1);
                g.FillRectangle(darkBorder, x, y, 1, h);
                g.FillRectangle(lightBorder, x, y + h - 1, w, 1);
                g.FillRectangle(lightBorder, x + w - 1, y, 1, h);
            }

            // Left status accent strip flush on the left edge, plus crisp right-side corner bracket ticks
            var accentW = scale >= 1.5f ? 2 : 1;
            var accentColor = Color.FromArgb(190, statusAccent.R, statusAccent.G, statusAccent.B);
            using (var accentBrush = new SolidBrush(accentColor))
            {
                g.FillRectangle(accentBrush, x, y, accentW, h);
            }

            var tickLen = Math.Max(3, (int)Math.Round(3.2f * scale));
            using (var cornerBrush = new SolidBrush(CardCornerTick))
            {
                g.FillRectangle(cornerBrush, x + w - tickLen, y, tickLen, 1);
                g.FillRectangle(cornerBrush, x + w - 1, y, 1, tickLen);
                g.FillRectangle(cornerBrush, x + w - tickLen, y + h - 1, tickLen, 1);
                g.FillRectangle(cornerBrush, x + w - 1, y + h - tickLen, 1, tickLen);
            }
        }
        finally
        {
            g.Restore(saved);
        }
    }

    /// <summary>
    /// Derives a three-tone metallic icon palette (highlight, body, shade) from the paired number's semantic color.
    /// Keeps the icon and its adjacent number in the same color group (normal silver, low amber, empty crimson, or special),
    /// while modulating luminance slightly (~85%) so the number stays the sharpest focal point.
    /// </summary>
    private static (Color Highlight, Color Body, Color Shade) ResolveIconPalette(Color? tint)
    {
        var c = tint ?? NormalText;
        var hiR = (int)Math.Clamp(Math.Round(c.R * 0.90 + 255 * 0.10), 0, 255);
        var hiG = (int)Math.Clamp(Math.Round(c.G * 0.90 + 255 * 0.10), 0, 255);
        var hiB = (int)Math.Clamp(Math.Round(c.B * 0.90 + 255 * 0.10), 0, 255);

        var bodyR = (int)Math.Clamp(Math.Round(c.R * 0.80), 0, 255);
        var bodyG = (int)Math.Clamp(Math.Round(c.G * 0.80), 0, 255);
        var bodyB = (int)Math.Clamp(Math.Round(c.B * 0.80), 0, 255);

        var shadeR = (int)Math.Clamp(Math.Round(c.R * 0.54), 0, 255);
        var shadeG = (int)Math.Clamp(Math.Round(c.G * 0.54), 0, 255);
        var shadeB = (int)Math.Clamp(Math.Round(c.B * 0.54), 0, 255);

        return (
            Color.FromArgb(236, hiR, hiG, hiB),
            Color.FromArgb(222, bodyR, bodyG, bodyB),
            Color.FromArgb(205, shadeR, shadeG, shadeB));
    }

    /// <summary>
    /// Paints a crisp, device-pixel-snapped Twin-Cartridge Bullet Icon inside a (5.8 x 7.0) logical box.
    /// Shares the exact same bounding box and vertical cap-height band as PaintMagazineIcon and the readout digits,
    /// and co-tints with its paired number's status color.
    /// </summary>
    internal static void PaintBulletIcon(
        Graphics g,
        float logicalX,
        float logicalY,
        float scale,
        Color? tintColor = null)
    {
        if (scale <= 0) return;

        var saved = g.Save();
        try
        {
            g.ScaleTransform(1f / scale, 1f / scale);
            g.SmoothingMode = SmoothingMode.None;
            g.PixelOffsetMode = PixelOffsetMode.Half;

            var x = (int)Math.Round(logicalX * scale);
            var y = (int)Math.Round(logicalY * scale);
            var w = Math.Max(7, (int)Math.Round(IconWidth * scale));
            if (w % 2 == 0) w++; // Keep odd width for symmetric center spacing
            var h = Math.Max(8, (int)Math.Round(IconHeight * scale));

            // Use a wider 3px gap at 1080p (w=11 -> 4px + 3px + 4px) so the two cartridges read as slender, airy rounds
            var gap = w >= 11 ? 3 : 1;
            var roundW = (w - gap) / 2;
            var tipH = Math.Max(2, (int)Math.Round(h * 0.28));
            var grooveY = y + tipH;
            var rimH = 1;
            var rimY = y + h - rimH;
            var extractorY = rimY - 1;
            var bodyTop = grooveY + 1;
            var bodyH = Math.Max(2, extractorY - bodyTop);

            var (hiColor, bodyColor, shadeColor) = ResolveIconPalette(tintColor);
            using var hiBrush = new SolidBrush(hiColor);
            using var bodyBrush = new SolidBrush(bodyColor);
            using var shadeBrush = new SolidBrush(shadeColor);

            for (var c = 0; c < 2; c++)
            {
                var cx = x + c * (roundW + gap);

                // 1. Ogive bullet tip (top row tapered, lower tip rows full roundW)
                var topCrownW = Math.Max(1, roundW - 2);
                var topCrownX = cx + (roundW - topCrownW) / 2;
                g.FillRectangle(hiBrush, topCrownX, y, topCrownW, 1);
                if (tipH > 1)
                {
                    g.FillRectangle(hiBrush, cx, y + 1, roundW, tipH - 1);
                }

                // 2. Cartridge casing body (cylindrical highlight on left, shade on right)
                g.FillRectangle(bodyBrush, cx, bodyTop, roundW, bodyH);
                if (roundW >= 3)
                {
                    g.FillRectangle(hiBrush, cx, bodyTop, 1, bodyH);
                    g.FillRectangle(shadeBrush, cx + roundW - 1, bodyTop, 1, bodyH);
                }

                // 3. Extractor neck (inset by 1px when wide enough)
                if (roundW >= 3)
                {
                    g.FillRectangle(shadeBrush, cx + 1, extractorY, Math.Max(1, roundW - 2), 1);
                }

                // 4. Base extractor rim
                g.FillRectangle(hiBrush, cx, rimY, roundW, rimH);
            }
        }
        finally
        {
            g.Restore(saved);
        }
    }

    /// <summary>
    /// Paints a crisp, device-pixel-snapped Box Magazine Icon inside the exact same (5.8 x 7.0) logical box
    /// as PaintBulletIcon, co-tinted with the reserve magazine status color.
    /// </summary>
    internal static void PaintMagazineIcon(
        Graphics g,
        float logicalX,
        float logicalY,
        float scale,
        Color? tintColor = null)
    {
        if (scale <= 0) return;

        var saved = g.Save();
        try
        {
            g.ScaleTransform(1f / scale, 1f / scale);
            g.SmoothingMode = SmoothingMode.None;
            g.PixelOffsetMode = PixelOffsetMode.Half;

            var x = (int)Math.Round(logicalX * scale);
            var y = (int)Math.Round(logicalY * scale);
            var w = Math.Max(7, (int)Math.Round(IconWidth * scale));
            if (w % 2 == 0) w++;
            var h = Math.Max(8, (int)Math.Round(IconHeight * scale));

            var (hiColor, bodyColor, shadeColor) = ResolveIconPalette(tintColor);
            using var hiBrush = new SolidBrush(hiColor);
            using var bodyBrush = new SolidBrush(bodyColor);
            using var shadeBrush = new SolidBrush(shadeColor);
            using var recessBrush = new SolidBrush(IconRecess);

            var lipH = 1;
            var notchW = Math.Max(1, w / 3);
            if ((w - notchW) % 2 != 0) notchW++;
            var lipW = (w - notchW) / 2;

            // 1. Top feed lips with center witness notch
            g.FillRectangle(hiBrush, x + 1, y, Math.Max(1, lipW - 1), lipH);
            g.FillRectangle(hiBrush, x + w - lipW, y, Math.Max(1, lipW - 1), lipH);

            // 2. Crisp 1px-walled magazine body (lighter visual weight to match adjacent digit stroke width)
            var bodyTop = y + lipH + 1;
            var bodyH = Math.Max(4, y + h - bodyTop);
            g.FillRectangle(bodyBrush, x, bodyTop, w, bodyH);
            g.FillRectangle(hiBrush, x, bodyTop, w, 1);
            g.FillRectangle(hiBrush, x, bodyTop, 1, bodyH);
            g.FillRectangle(shadeBrush, x + w - 1, bodyTop, 1, bodyH);

            // 3. Large recessed interior window + subtle horizontal witness ribs
            var border = 1;
            var innerX = x + border;
            var innerY = bodyTop + border;
            var innerW = Math.Max(3, w - border * 2);
            var innerH = Math.Max(2, bodyH - border * 2);
            g.FillRectangle(recessBrush, innerX, innerY, innerW, innerH);

            // Witness ribs inside the recessed window (inset by 2px so the interior stays airy)
            var ribPad = innerW >= 7 ? 2 : 1;
            var ribW = Math.Max(1, innerW - ribPad * 2);
            if (innerH >= 5)
            {
                var rib1 = innerY + innerH / 3;
                var rib2 = innerY + (innerH * 2) / 3;
                g.FillRectangle(bodyBrush, innerX + ribPad, rib1, ribW, 1);
                g.FillRectangle(bodyBrush, innerX + ribPad, rib2, ribW, 1);
            }
            else if (innerH >= 3)
            {
                var rib = innerY + innerH / 2;
                g.FillRectangle(bodyBrush, innerX + ribPad, rib, ribW, 1);
            }
        }
        finally
        {
            g.Restore(saved);
        }
    }

    /// <summary>
    /// Paints a crisp 1px vertical divider tick separating the Primary Chamber zone from the Reserve Magazine zone.
    /// </summary>
    internal static void PaintZoneDivider(
        Graphics g,
        float logicalX,
        float logicalTop,
        float logicalHeight,
        float scale)
    {
        if (scale <= 0) return;

        var saved = g.Save();
        try
        {
            g.ScaleTransform(1f / scale, 1f / scale);
            g.SmoothingMode = SmoothingMode.None;
            g.PixelOffsetMode = PixelOffsetMode.Half;

            var px = (int)Math.Round(logicalX * scale);
            var py = (int)Math.Round(logicalTop * scale);
            var ph = Math.Max(6, (int)Math.Round(logicalHeight * scale));

            using var line = new SolidBrush(DividerLineColor);
            using var shadow = new SolidBrush(DividerShadowColor);
            g.FillRectangle(shadow, px - 1, py, 1, ph);
            g.FillRectangle(line, px, py, 1, ph);
        }
        finally
        {
            g.Restore(saved);
        }
    }

    /// <summary>
    /// Paints a 10-slot discrete spare magazine stock bar for Single-Gun Row 1 (备用弹匣槽),
    /// giving Single-Gun Row 1 the exact same bottom bar rhythm and hollow-slot clarity as Row 0.
    /// </summary>
    internal static void PaintReserveMagazineBar(
        Graphics g,
        RectangleF logicalBounds,
        float scale,
        string magText)
    {
        if (scale <= 0 || logicalBounds.Width <= 0 || logicalBounds.Height <= 0) return;

        var trimmed = magText.Trim();
        var isInfinite = trimmed == "无限";
        var hasClips = int.TryParse(trimmed, NumberStyles.Integer, CultureInfo.InvariantCulture, out var clips);
        var filledSlots = isInfinite ? 10 : hasClips ? Math.Clamp(clips, 0, 10) : 0;

        var saved = g.Save();
        try
        {
            g.ScaleTransform(1f / scale, 1f / scale);
            g.SmoothingMode = SmoothingMode.None;
            g.PixelOffsetMode = PixelOffsetMode.Half;

            var pxLeft = (int)Math.Round(logicalBounds.Left * scale);
            var pxTop = (int)Math.Round(logicalBounds.Top * scale);
            var pxWidth = Math.Max(8, (int)Math.Round(logicalBounds.Width * scale));
            var pxHeight = Math.Max(3, (int)Math.Round(logicalBounds.Height * scale));

            const int slotCount = 10;
            const int gap = 1;
            var fillColor = isInfinite
                ? ChamberText
                : filledSlots <= 2
                    ? ReserveLowText
                    : ReserveNormalText;
            using var fillBrush = new SolidBrush(fillColor);
            var emptyBorder = (hasClips && clips <= 0) ? EmptyHollowBorder : HollowSlotBorder;
            var emptyInterior = (hasClips && clips <= 0) ? EmptyHollowInterior : HollowSlotInterior;

            for (var i = 0; i < slotCount; i++)
            {
                var cellLeft = pxLeft + (int)Math.Round((double)i * (pxWidth + gap) / slotCount);
                var nextLeft = pxLeft + (int)Math.Round((double)(i + 1) * (pxWidth + gap) / slotCount);
                var cellRight = i == slotCount - 1 ? pxLeft + pxWidth : nextLeft - gap;
                var cellW = Math.Max(1, cellRight - cellLeft);

                if (i < filledSlots)
                {
                    g.FillRectangle(fillBrush, cellLeft, pxTop, cellW, pxHeight);
                }
                else
                {
                    DrawHollowSlot(g, cellLeft, pxTop, cellW, pxHeight, emptyBorder, emptyInterior);
                }
            }
        }
        finally
        {
            g.Restore(saved);
        }
    }

    /// <summary>
    /// Paints a device-pixel-snapped graphical magazine bar with hollow spent chambers/trough:
    /// - Small (1..12): 1:1 discrete cells (filled solid vs hollow slot for spent rounds)
    /// - Medium (13..30): 1:1 discrete cells when physical width >= cap * 3, else 5-round grouped cells
    /// - Large (>30, up to 9999+): 100% hollow trough + solid fill + 20% quintile notches + bright leading edge
    /// </summary>
    internal static void PaintMagazineBar(
        Graphics g,
        RectangleF logicalBounds,
        float scale,
        PlayerHudAmmoDetail? detail,
        string loadedText,
        int observedCapacity)
    {
        if (scale <= 0 || logicalBounds.Width <= 0 || logicalBounds.Height <= 0) return;

        var hasLoaded = TryParseAmmoCount(loadedText, out var parsedLoaded);
        var isInfinite = !hasLoaded && loadedText.Trim() == "无限";
        int capacity, loaded, normal, chamber, ghost, reward;

        if (detail is { Capacity: > 0 })
        {
            capacity = detail.Capacity;
            loaded = detail.Loaded;
            normal = detail.Normal;
            chamber = detail.Chamber;
            ghost = detail.Ghost;
            reward = detail.Reward;
        }
        else if (isInfinite)
        {
            capacity = 1;
            loaded = 1;
            normal = 1;
            chamber = ghost = reward = 0;
        }
        else if (hasLoaded)
        {
            loaded = Math.Max(0, parsedLoaded);
            capacity = Math.Max(observedCapacity, loaded);
            normal = Math.Min(capacity, loaded);
            chamber = 0;
            ghost = 0;
            reward = Math.Max(0, loaded - normal);
        }
        else
        {
            capacity = 0;
            loaded = 0;
            normal = chamber = ghost = reward = 0;
        }

        var saved = g.Save();
        try
        {
            g.ScaleTransform(1f / scale, 1f / scale);
            g.SmoothingMode = SmoothingMode.None;
            g.PixelOffsetMode = PixelOffsetMode.Half;

            var pxLeft = (int)Math.Round(logicalBounds.Left * scale);
            var pxTop = (int)Math.Round(logicalBounds.Top * scale);
            var pxWidth = Math.Max(8, (int)Math.Round(logicalBounds.Width * scale));
            var pxHeight = Math.Max(3, (int)Math.Round(logicalBounds.Height * scale));

            if (capacity <= 0)
            {
                DrawHollowSlot(g, pxLeft, pxTop, pxWidth, pxHeight, HollowSlotBorder, HollowSlotInterior);
                return;
            }

            if (loaded <= 0)
            {
                var useEmptyCells = (capacity <= 12 && pxWidth >= capacity * 2)
                    || (capacity <= 30 && pxWidth >= capacity * 3);
                if (useEmptyCells)
                {
                    const int gap = 1;
                    for (var i = 0; i < capacity; i++)
                    {
                        var cellLeft = pxLeft + (int)Math.Round((double)i * (pxWidth + gap) / capacity);
                        var nextLeft = pxLeft + (int)Math.Round((double)(i + 1) * (pxWidth + gap) / capacity);
                        var cellRight = i == capacity - 1 ? pxLeft + pxWidth : nextLeft - gap;
                        var cellW = Math.Max(1, cellRight - cellLeft);
                        DrawHollowSlot(g, cellLeft, pxTop, cellW, pxHeight, EmptyHollowBorder, EmptyHollowInterior);
                    }
                }
                else
                {
                    DrawHollowSlot(g, pxLeft, pxTop, pxWidth, pxHeight, EmptyHollowBorder, EmptyHollowInterior);
                }
                return;
            }

            var isLow = capacity >= 2 && loaded > 0 && loaded < capacity && (loaded * 5 <= capacity || loaded == 1)
                && chamber == 0 && ghost == 0 && reward == 0;
            var normalFillColor = isLow ? LowLoadedText : BarNormalFill;

            var useOneToOneCells = (capacity <= 12 && pxWidth >= capacity * 2)
                || (capacity <= 30 && pxWidth >= capacity * 3);
            var useGroupedCells = !useOneToOneCells && capacity <= 30 && pxWidth >= 18;

            if (useOneToOneCells)
            {
                PaintDiscreteOneToOne(g, pxLeft, pxTop, pxWidth, pxHeight, capacity, loaded, normal, chamber, reward, ghost, normalFillColor);
            }
            else if (useGroupedCells)
            {
                PaintDiscreteGrouped(g, pxLeft, pxTop, pxWidth, pxHeight, capacity, loaded, normal, chamber, reward, ghost, normalFillColor);
            }
            else
            {
                PaintContinuousNotched(g, pxLeft, pxTop, pxWidth, pxHeight, scale, capacity, loaded, normal, chamber, reward, ghost, normalFillColor);
            }
        }
        finally
        {
            g.Restore(saved);
        }
    }

    private static void DrawHollowSlot(
        Graphics g,
        int x,
        int y,
        int w,
        int h,
        Color borderColor,
        Color interiorColor)
    {
        using var border = new SolidBrush(borderColor);
        using var interior = new SolidBrush(interiorColor);
        g.FillRectangle(border, x, y, w, h);
        if (w >= 3 && h >= 3)
        {
            g.FillRectangle(interior, x + 1, y + 1, w - 2, h - 2);
        }
        else if (h >= 3)
        {
            g.FillRectangle(interior, x, y + 1, w, h - 2);
        }
    }

    private static void PaintDiscreteOneToOne(
        Graphics g,
        int pxLeft,
        int pxTop,
        int pxWidth,
        int pxHeight,
        int capacity,
        int loaded,
        int normal,
        int chamber,
        int reward,
        int ghost,
        Color normalFillColor)
    {
        const int gap = 1;
        using var normalBrush = new SolidBrush(normalFillColor);
        using var chamberBrush = new SolidBrush(ChamberText);
        using var rewardBrush = new SolidBrush(RewardText);
        using var ghostBrush = new SolidBrush(GhostText);

        Brush BrushFor(int idx)
        {
            if (idx < normal) return normalBrush;
            if (idx < normal + chamber) return chamberBrush;
            if (idx < normal + chamber + reward) return rewardBrush;
            return ghostBrush;
        }

        for (var i = 0; i < capacity; i++)
        {
            var cellLeft = pxLeft + (int)Math.Round((double)i * (pxWidth + gap) / capacity);
            var nextLeft = pxLeft + (int)Math.Round((double)(i + 1) * (pxWidth + gap) / capacity);
            var cellRight = i == capacity - 1 ? pxLeft + pxWidth : nextLeft - gap;
            var cellW = Math.Max(1, cellRight - cellLeft);

            if (i < loaded)
            {
                g.FillRectangle(BrushFor(i), cellLeft, pxTop, cellW, pxHeight);
            }
            else
            {
                DrawHollowSlot(g, cellLeft, pxTop, cellW, pxHeight, HollowSlotBorder, HollowSlotInterior);
            }
        }

        if (loaded > capacity)
        {
            var overflow = loaded - capacity;
            var overflowW = Math.Clamp((int)Math.Round((double)overflow / capacity * pxWidth), 2, pxWidth);
            var overBrush = ghost > 0 ? ghostBrush : reward > 0 ? rewardBrush : chamberBrush;
            g.FillRectangle(overBrush, pxLeft, pxTop, overflowW, Math.Max(1, pxHeight / 2));
        }
    }

    private static void PaintDiscreteGrouped(
        Graphics g,
        int pxLeft,
        int pxTop,
        int pxWidth,
        int pxHeight,
        int capacity,
        int loaded,
        int normal,
        int chamber,
        int reward,
        int ghost,
        Color normalFillColor)
    {
        const int groupSize = 5;
        const int gap = 1;
        var cellCount = (int)Math.Ceiling(capacity / (double)groupSize);
        using var normalBrush = new SolidBrush(normalFillColor);
        using var chamberBrush = new SolidBrush(ChamberText);
        using var rewardBrush = new SolidBrush(RewardText);
        using var ghostBrush = new SolidBrush(GhostText);

        var activeBrush = ghost > 0 ? ghostBrush : reward > 0 ? rewardBrush : chamber > 0 ? chamberBrush : normalBrush;

        for (var i = 0; i < cellCount; i++)
        {
            var cellLeft = pxLeft + (int)Math.Round((double)i * (pxWidth + gap) / cellCount);
            var nextLeft = pxLeft + (int)Math.Round((double)(i + 1) * (pxWidth + gap) / cellCount);
            var cellRight = i == cellCount - 1 ? pxLeft + pxWidth : nextLeft - gap;
            var cellW = Math.Max(1, cellRight - cellLeft);

            var startRound = i * groupSize;
            var endRound = Math.Min(capacity, startRound + groupSize);
            var cellCap = Math.Max(1, endRound - startRound);
            var cellLoaded = Math.Clamp(loaded - startRound, 0, cellCap);

            DrawHollowSlot(g, cellLeft, pxTop, cellW, pxHeight, HollowSlotBorder, HollowSlotInterior);
            if (cellLoaded > 0)
            {
                var fillW = cellLoaded >= cellCap ? cellW : Math.Max(1, (int)Math.Round((double)cellLoaded / cellCap * cellW));
                var brush = startRound + cellLoaded - 1 < normal ? normalBrush : activeBrush;
                g.FillRectangle(brush, cellLeft, pxTop, fillW, pxHeight);
            }
        }
    }

    private static void PaintContinuousNotched(
        Graphics g,
        int pxLeft,
        int pxTop,
        int pxWidth,
        int pxHeight,
        float scale,
        int capacity,
        int loaded,
        int normal,
        int chamber,
        int reward,
        int ghost,
        Color normalFillColor)
    {
        // 1. 100% full-length hollow trough so the spent right portion clearly shows the container boundary.
        DrawHollowSlot(g, pxLeft, pxTop, pxWidth, pxHeight, HollowSlotBorder, HollowSlotInterior);

        // Subtle quintile ticks inside the hollow trough
        using var subtleTickBrush = new SolidBrush(HollowSlotSubtleTick);
        for (var k = 1; k <= 4; k++)
        {
            var notchX = pxLeft + (int)Math.Round(pxWidth * (k / 5.0));
            if (pxHeight >= 3)
                g.FillRectangle(subtleTickBrush, notchX, pxTop + 1, 1, pxHeight - 2);
        }

        var baseLoaded = Math.Min(capacity, loaded);
        var fillRatio = Math.Clamp((double)baseLoaded / capacity, 0.0, 1.0);
        var fillWidth = baseLoaded > 0 ? Math.Max(1, (int)Math.Round(pxWidth * fillRatio)) : 0;

        using var normalBrush = new SolidBrush(normalFillColor);
        using var chamberBrush = new SolidBrush(ChamberText);
        using var rewardBrush = new SolidBrush(RewardText);
        using var ghostBrush = new SolidBrush(GhostText);

        if (fillWidth > 0)
        {
            if (chamber == 0 && reward == 0 && ghost == 0)
            {
                g.FillRectangle(normalBrush, pxLeft, pxTop, fillWidth, pxHeight);
            }
            else
            {
                var total = Math.Max(1, loaded);
                var normalW = (int)Math.Round((double)normal / total * fillWidth);
                var chamberW = (int)Math.Round((double)chamber / total * fillWidth);
                var rewardW = (int)Math.Round((double)reward / total * fillWidth);
                var ghostW = Math.Max(0, fillWidth - normalW - chamberW - rewardW);

                var curX = pxLeft;
                if (normalW > 0) { g.FillRectangle(normalBrush, curX, pxTop, normalW, pxHeight); curX += normalW; }
                if (chamberW > 0) { g.FillRectangle(chamberBrush, curX, pxTop, chamberW, pxHeight); curX += chamberW; }
                if (rewardW > 0) { g.FillRectangle(rewardBrush, curX, pxTop, rewardW, pxHeight); curX += rewardW; }
                if (ghostW > 0) { g.FillRectangle(ghostBrush, curX, pxTop, ghostW, pxHeight); }
            }

            if (loaded < capacity && fillWidth >= 2)
            {
                var edgeW = scale >= 1.6f && fillWidth >= 4 ? 2 : 1;
                using var edgeBrush = new SolidBrush(BarLeadingEdge);
                g.FillRectangle(edgeBrush, pxLeft + fillWidth - edgeW, pxTop, edgeW, pxHeight);
            }
        }

        if (loaded > capacity)
        {
            var overflow = loaded - capacity;
            var overflowW = Math.Clamp((int)Math.Round((double)overflow / capacity * pxWidth), 2, pxWidth);
            var overBrush = ghost > 0 ? ghostBrush : reward > 0 ? rewardBrush : chamberBrush;
            g.FillRectangle(overBrush, pxLeft, pxTop, overflowW, Math.Max(1, pxHeight / 2));
        }

        // Crisp dark notches across the filled portion at 20% quintile divisions
        using var notchBrush = new SolidBrush(BarNotch);
        var notchH = pxHeight >= 4 ? pxHeight - 1 : pxHeight;
        for (var k = 1; k <= 4; k++)
        {
            var notchX = pxLeft + (int)Math.Round(pxWidth * (k / 5.0));
            if (notchX < pxLeft + fillWidth)
                g.FillRectangle(notchBrush, notchX, pxTop, 1, notchH);
        }
    }
}
