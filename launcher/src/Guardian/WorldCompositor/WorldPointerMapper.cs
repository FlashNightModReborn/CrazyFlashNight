using System;
using System.Drawing;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal static class WorldPointerMapper
    {
        internal const uint EpochLimit=0x7FFFFD;
        internal const long SequenceLimit=0x7FFFFFFD;
        // Matches the native compositor's aspect-preserving viewport, including rounding
        // bars. Negative coordinates are retained during a drag outside the client area.
        internal static Point Map(Point display, Size output, Size source)
        {
            if (output.Width < 1 || output.Height < 1 || source.Width < 1 || source.Height < 1)
                throw new ArgumentOutOfRangeException(nameof(output));
            double scale = Math.Min((double)output.Width / source.Width, (double)output.Height / source.Height);
            double left = (output.Width - source.Width * scale) / 2;
            double top = (output.Height - source.Height * scale) / 2;
            return new Point((int)Math.Floor((display.X - left) / scale), (int)Math.Floor((display.Y - top) / scale));
        }
        internal static IntPtr Pack(Point point) => new IntPtr(unchecked((int)((uint)(ushort)point.X | ((uint)(ushort)point.Y << 16))));
        internal static Point Unpack(IntPtr value) => new Point((short)(value.ToInt64() & 65535), (short)((value.ToInt64() >> 16) & 65535));

        // v4 bounded envelope, mirrors the WPARAM/LPARAM layout documented in InputBridge.h.
        //   WPARAM [0:8) kind | [8:15) flags | [16:32) extra | [32:56) bounded epoch | [56:64) geometry
        //   LPARAM [0:16) x | [16:32) y | [32:64) bounded sequence
        // The v2 gesture field is gone; gesture ownership is endpoint-local state.
        internal static long PackWParam(int message,int flags,uint data,uint epoch,uint geometry)
        {
            if(epoch==0 || epoch>EpochLimit)throw new ArgumentOutOfRangeException(nameof(epoch));
            uint kind=message==0x1F ? 0xFEu : (uint)(message-0x200);
            return unchecked((long)kind | ((long)(flags&0x7F)<<8) | (data&0xFFFF0000u)
                | ((long)(epoch&0xFFFFFF)<<32) | ((long)(geometry&0xFF)<<56));
        }
        internal static long PackLParam(Point point,long sequence) {
            if(sequence<1 || sequence>SequenceLimit)throw new ArgumentOutOfRangeException(nameof(sequence));
            return unchecked((long)(uint)(ushort)point.X | ((long)(uint)(ushort)point.Y<<16) | ((long)(uint)sequence<<32));
        }
        // Test mirror of the native decode in InputBridge.cpp WindowProc.
        internal static void UnpackWire(long wp,long lp,
            out uint kind,out uint flags,out uint extra,out uint epoch,out uint geometry,
            out int x,out int y,out uint sequence)
        {
            kind=(uint)(wp&0xFF); flags=(uint)((wp>>8)&0x7F); extra=(uint)((wp>>16)&0xFFFF);
            epoch=(uint)((wp>>32)&0xFFFFFF); geometry=(uint)((wp>>56)&0xFF);
            x=(short)(lp&0xFFFF); y=(short)((lp>>16)&0xFFFF); sequence=(uint)((lp>>32)&0xFFFFFFFF);
        }
        // Legacy arithmetic oracle retained for the frozen RCE-2 counterexample.
        // Production encoding validates the non-wrapping domain first; native
        // v4 admission uses ordinary integer comparison inside that domain.
        internal static bool IsStaleEpoch(uint epoch,uint minEpoch) => unchecked(((epoch-minEpoch)&0xFFFFFFu)>=0x800000u);
    }
    // One packet in the bridge protocol v4 envelope. Screen keeps the physical cursor
    // position so a stale-geometry packet can be remapped instead of dropped.
    // Gesture is host-local bookkeeping for logging and cancel decisions; the v3
    // wire no longer carries it (the receiver only tracks whether an admitted
    // down opened a gesture).
    internal readonly struct PointerPacket
    {
        internal readonly int Message,Flags;
        internal readonly Point Screen,Client;
        internal readonly uint Data,Epoch,Gesture,Geometry;
        internal readonly long Sequence;
        internal PointerPacket(int message,Point screen,Point client,int flags,uint data,uint epoch,uint gesture,uint geometry,long sequence)
        { Message=message; Screen=screen; Client=client; Flags=flags; Data=data; Epoch=epoch; Gesture=gesture; Geometry=geometry; Sequence=sequence; }
    }
    // Local result of posting one packet to the projector thread. Posted means "in the
    // endpoint's message queue" only; endpoint receipt is observed separately through
    // the shared consumedSeq counter. Nothing here may be called delivered.
    internal enum PointerPostStatus { Posted, BridgeClosed, SourceGone, PostFailed }
}
