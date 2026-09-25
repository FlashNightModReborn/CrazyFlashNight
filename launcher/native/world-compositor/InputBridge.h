#pragma once
#include <windows.h>
#include <cstdint>
#include <cstddef>
constexpr wchar_t InputProperty[]=L"CF7.WorldPointer.Map.v4";
constexpr wchar_t InputMessage[]=L"CF7.WorldPointer.Packet.v4";
constexpr uint32_t InputMagic=0xCF710001;
constexpr uint32_t InputProtocolVersion=4;
// v4 keeps the data envelope; epochs never wrap inside a session.
// Data is consumed only by WH_GETMESSAGE on PM_REMOVE, then tombstoned to
// WM_NULL before the MSG escapes to Translate/DispatchMessage. Direct sent
// data is rejected. Controls use a separate message and exact 64-bit session.
constexpr wchar_t InputControlMessage[]=L"CF7.WorldPointer.Control.v4";
constexpr LONG InputEpochLimit=0x7FFFFD, InputSequenceLimit=0x7FFFFFFD;
constexpr UINT ControlInit=1, ControlPoll=2, ControlRetire=3, ControlRepaint=4, ControlQuiesce=5;
inline LONG ReadAtomic(volatile LONG* p) { return InterlockedCompareExchange(p,0,0); }
inline LONG64 ReadAtomic64(volatile LONG64* p) { return InterlockedCompareExchange64(p,0,0); }
inline void RaiseAtomic(volatile LONG* p,LONG value) {
    LONG old=ReadAtomic(p);
    while(old<value) { LONG seen=InterlockedCompareExchange(p,value,old); if(seen==old) break; old=seen; }
}
struct InputShared {
    uint32_t magic;            // 0  InputMagic
    uint32_t protocolVersion;  // 4  InputProtocolVersion; mismatch must fail init, never run v1 semantics
    uint32_t hostPid;          // 8
    uint32_t sourcePid;        // 12
    uint64_t sourceWindow;     // 16
    uint64_t ownerWindow;      // 24
    volatile LONG ready;             // 32  1 ok | -1 subclass | -2 imports | -3 protocol | -4 identity
    volatile LONG stop;              // 36
    volatile LONG stopped;           // 40
    volatile LONG cursorReads;       // 44
    volatile LONG keyReads;          // 48
    volatile LONG patchMask;         // 52
    volatile LONG minEpoch;          // 56  host->bridge: lowest acceptable input epoch (cancel floor, low 24 bits)
    volatile LONG consumedSeq;       // 60  bridge->host: low 32 of last packet sequence seen by WindowProc
    volatile LONG staleRejected;     // 64  packets rejected by the epoch gates (shared floor or local focus-loss floor)
    volatile LONG stoppedRejected;   // 68  packets rejected while stopping or without shared state
    volatile LONG unownedReleases;   // 72  up/cancel with no open gesture or unheld button (forwarded, counted)
    volatile LONG duplicateDowns;    // 76  down for an already-held button (forwarded, counted)
    volatile LONG issuedEpoch;       // 80  host->bridge: newest epoch handed to the queue (low 24 bits),
                                     //     published before every packet post; read at the focus-loss boundary
    uint32_t reserved;               // 84  tail padding: the struct stays 8-aligned for the uint64 fields
    uint64_t session;                   // 88 immutable control identity
    volatile LONG closeTicket;          // 96 Host seals all producers before publishing stop
    volatile LONG returnedTicket;       // 100 broker: retire SendMessage has RETURNED
    volatile LONG cancelTicket;         // 104 persistent release request
    volatile LONG cancelledTicket;      // 108 endpoint: original cancellation returned
    volatile LONG dispatchDepth;        // 112 endpoint original-handler calls in flight
    volatile LONG hookDepth;            // 116 endpoint getmessage calls in flight
    volatile LONG completedSeq;         // 120 diagnostic original-return, not business ACK
    volatile LONG heldButtons;          // 124 mouse mask only (0x73)
    volatile LONG64 paintRequestTicks;  // 128 serialized repaint request
    volatile LONG paintTicket;          // 136
    volatile LONG paintAck;             // 140
    volatile LONG64 paintResultTicks;   // 144
    volatile LONG invalidRejected;      // 152
    volatile LONG drained;              // 156
    volatile LONG restoreError;         // 160 no successor on any restore error
    volatile LONG targetExited;         // 164 broker observed actual process handle exit
    volatile LONG graceful;            // 168 close mode; producer seal precedes request
    volatile LONG quiescedTicket;       // 172 target UI: queue empty, no callback or held state
};
static_assert(sizeof(void*)==8, "The paired projector is x64");
static_assert(sizeof(InputShared)==176, "Host and broker map the same InputShared size");
static_assert(offsetof(InputShared,minEpoch)==56, "Host shares the minEpoch offset");
static_assert(offsetof(InputShared,consumedSeq)==60, "Host shares the consumedSeq offset");
static_assert(offsetof(InputShared,issuedEpoch)==80, "Host shares the issuedEpoch offset");

static_assert(offsetof(InputShared,session)==88 && offsetof(InputShared,paintRequestTicks)==128, "v4 offsets");
