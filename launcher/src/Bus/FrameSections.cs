using System;

namespace CF7Launcher.Bus;

// Each consumer receives an owned string. Ordered, unique production sections
// are sliced directly from the original packet; legacy malformed input keeps
// the former tail-stripping decisions, including null versus empty payloads.
internal readonly record struct FrameSections(string Camera, string HitNumbers, string Fps,
    string Ui, string Input, string Bullets, string Combat, string Rays, string Chains, string Lights)
{
    internal static FrameSections Parse(string wire)
    {
        Span<int> offsets = stackalloc int[10];
        offsets.Fill(-1);
        int last = 0;
        bool canonical = true;
        for (int i = 1; i < wire.Length; i++)
        {
            int section = wire[i];
            if (section < 1 || section > 9) continue;
            if (section <= last) { canonical = false; break; }
            offsets[section] = i;
            last = section;
        }
        if (!canonical || offsets[1] == 1 || (offsets[2] >= 0 && offsets[1] < 0)) return Legacy(wire);
        int bodyEnd = wire.Length;
        for (int section = 3; section <= 9; section++)
            if (offsets[section] >= 0) { bodyEnd = offsets[section]; break; }
        string camera = wire.Substring(1, (offsets[1] >= 0 ? offsets[1] : bodyEnd) - 1);
        string numbers = offsets[1] < 0 ? "" : wire.Substring(offsets[1] + 1,
            (offsets[2] >= 0 ? offsets[2] : bodyEnd) - offsets[1] - 1);
        string fps = offsets[2] < 0 ? "" : wire.Substring(offsets[2] + 1, bodyEnd - offsets[2] - 1);
        return new(camera, numbers, fps, Slice(wire, offsets, 3), Slice(wire, offsets, 4),
            Slice(wire, offsets, 5), Slice(wire, offsets, 6), Slice(wire, offsets, 7),
            Slice(wire, offsets, 8), Slice(wire, offsets, 9));
    }

    private static string Slice(string wire, ReadOnlySpan<int> offsets, int section)
    {
        int start = offsets[section];
        if (start < 0) return null;
        int end = wire.Length;
        for (int next = section + 1; next <= 9; next++)
            if (offsets[next] >= 0) { end = offsets[next]; break; }
        return wire.Substring(start + 1, end - start - 1);
    }

    internal static FrameSections Legacy(string wire)
    {
        string free = XmlSocketServer.SplitFrameSection(wire, '\x09', out string lights);
        free = XmlSocketServer.SplitFrameSection(free, '\x08', out string chains);
        free = XmlSocketServer.SplitFrameSection(free, '\x07', out string rays);
        free = XmlSocketServer.SplitFrameCombatFxSection(free, out string combat);
        free = XmlSocketServer.SplitFrameVisualSection(free, out string bullets);
        free = XmlSocketServer.SplitFrameSection(free, '\x04', out string input);
        string body = XmlSocketServer.SplitFrameSection(free, '\x03', out string ui);
        int first = body.IndexOf('\x01', 1);
        if (first <= 1) return new(body.Substring(1), "", "", ui, input, bullets, combat, rays, chains, lights);
        int second = body.IndexOf('\x02', first + 1);
        string numbers = second < 0 ? body.Substring(first + 1) : body.Substring(first + 1, second - first - 1);
        string fps = second < 0 ? "" : body.Substring(second + 1);
        return new(body.Substring(1, first - 1), numbers, fps, ui, input, bullets, combat, rays, chains, lights);
    }
}
