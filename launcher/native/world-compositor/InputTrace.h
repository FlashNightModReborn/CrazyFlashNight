#pragma once
#include "InputBridge.h"

// Optional diagnostics in a SEPARATE mapping; the v4 input ABI is unchanged.
// One target UI-thread writer, broker reader. No allocation, I/O or waits in
// TraceWrite. Every field is atomic so overwrite during a read is well-defined.
constexpr uint32_t InputTraceMagic=0xCF710D01, InputTraceCapacity=128;
enum InputTraceStage : LONG { TraceEnter=1, TraceReturn=2, TraceStale=3,
    TraceStopped=4, TraceInvalid=5, TraceFocusLost=6, TraceCancel=7, TraceLeave=8, TraceReady=9,
    TraceNativePointer=10, TraceCursorVirtual=11, TraceCursorPhysical=12, TraceSourceLeaveSuppressed=13 };
struct InputTraceRecord {
    volatile LONG64 serial,ticks;
    volatile LONG sequence,epoch,message,stage,x,y,buttons,floor;
    volatile LONG64 focus;
};
struct InputTraceShared {
    uint32_t magic,version;
    uint64_t session;
    volatile LONG64 produced;
    InputTraceRecord records[InputTraceCapacity];
};
struct InputTraceSnapshot {
    LONG64 serial,ticks;
    LONG sequence,epoch,message,stage,x,y,buttons,floor;
    LONG64 focus;
};
static_assert(sizeof(InputTraceRecord)==56 && offsetof(InputTraceShared,records)==24,"trace ABI");
inline void TraceWrite(InputTraceShared* trace,LONG stage,LONG sequence,LONG epoch,
    LONG message,POINT point,LONG buttons,LONG floor,HWND focus) {
    if(!trace)return;
    LONG64 serial=ReadAtomic64(&trace->produced)+1;
    auto& r=trace->records[(serial-1)%InputTraceCapacity];
    InterlockedExchange64(&r.serial,0);
    LARGE_INTEGER now{};QueryPerformanceCounter(&now);
    InterlockedExchange64(&r.ticks,now.QuadPart);
    InterlockedExchange(&r.sequence,sequence);InterlockedExchange(&r.epoch,epoch);
    InterlockedExchange(&r.message,message);InterlockedExchange(&r.stage,stage);
    InterlockedExchange(&r.x,point.x);InterlockedExchange(&r.y,point.y);
    InterlockedExchange(&r.buttons,buttons);InterlockedExchange(&r.floor,floor);
    InterlockedExchange64(&r.focus,reinterpret_cast<LONG64>(focus));
    InterlockedExchange64(&r.serial,serial);
    InterlockedExchange64(&trace->produced,serial);
}
inline bool TraceRead(InputTraceShared* trace,LONG64 serial,InputTraceSnapshot& out) {
    auto& r=trace->records[(serial-1)%InputTraceCapacity];
    if(ReadAtomic64(&r.serial)!=serial)return false;
    out.serial=serial;out.ticks=ReadAtomic64(&r.ticks);
    out.sequence=ReadAtomic(&r.sequence);out.epoch=ReadAtomic(&r.epoch);
    out.message=ReadAtomic(&r.message);out.stage=ReadAtomic(&r.stage);
    out.x=ReadAtomic(&r.x);out.y=ReadAtomic(&r.y);
    out.buttons=ReadAtomic(&r.buttons);out.floor=ReadAtomic(&r.floor);
    out.focus=ReadAtomic64(&r.focus);
    return ReadAtomic64(&r.serial)==serial;
}
