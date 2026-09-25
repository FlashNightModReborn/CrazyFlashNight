// InputBridgeSelfTest.exe: drives the real InputBridge WindowProc against real
// windows and a real v3 shared section, with the bridge installed as the
// window's actual subclass so OS focus messages flow through it. Built only
// via `build.bat selftest`; never part of the runtime closure or the default
// build outputs.
#define WIN32_LEAN_AND_MEAN
#include "InputBridge.h"
#include "InputTrace.h"
#include <cstdio>
#include <cwchar>
#include <initializer_list>

// Provided by InputBridge.cpp when compiled with CF7_INPUT_BRIDGE_SELFTEST.
namespace InputBridgeSelfTest {
    void Install(HWND target,InputShared* state,UINT packetMessage);
    LRESULT Drive(UINT message,WPARAM wparam,LPARAM lparam);
    UINT LocalFloor();
    UINT LastEpoch();
    UINT Gesture();
}

namespace {
InputShared* state=nullptr;
int focusGains=0, mouseDeliveries=0, nativeLeaves=0, failures=0;
POINT lastMouseMove{};
// The "original" window procedure the bridge forwards into. SetFocus performed
// by the bridge shows up here as a real WM_SETFOCUS; CallWindowProcW deliveries
// arrive as their real mouse message ids. Note that a forwarded button-down
// can also make Windows itself juggle focus (mouse activation), so assertions
// on focus are deltas, not exact counts.
LRESULT CALLBACK TargetProc(HWND hwnd,UINT message,WPARAM wp,LPARAM lp) {
    if(message==WM_SETFOCUS) focusGains++;
    if(message==WM_MOUSELEAVE) nativeLeaves++;
    if(message==WM_MOUSEMOVE) lastMouseMove={static_cast<SHORT>(LOWORD(lp)),static_cast<SHORT>(HIWORD(lp))};
    if(message==WM_MOUSEMOVE || message==WM_LBUTTONDOWN || message==WM_LBUTTONUP
        || message==WM_RBUTTONDOWN || message==WM_RBUTTONUP
        || message==WM_MBUTTONDOWN || message==WM_MBUTTONUP
        || message==WM_XBUTTONDOWN || message==WM_XBUTTONUP
        || message==WM_MOUSEWHEEL || message==WM_MOUSEHWHEEL
        || message==WM_CANCELMODE) mouseDeliveries++;
    return DefWindowProcW(hwnd,message,wp,lp);
}
void Check(bool ok,const char* name) {
    std::printf("%s %s\n",ok?"PASS":"FAIL",name);
    if(!ok) failures++;
}
// Wire packing, mirroring the host's PackWParam/PackLParam v3 envelope
// (epoch occupies WPARAM [32:56), geometry [56:64); no gesture field).
WPARAM PacketW(UINT kind,UINT flags,UINT epoch) {
    return static_cast<WPARAM>((kind&0xFFu) | (static_cast<ULONGLONG>(flags&0x7Fu)<<8)
        | (static_cast<ULONGLONG>(epoch&0xFFFFFFu)<<32));
}
LPARAM PacketL(int x,int y,UINT seq) {
    return static_cast<LPARAM>(static_cast<ULONGLONG>(static_cast<USHORT>(x))
        | (static_cast<ULONGLONG>(static_cast<USHORT>(y))<<16)
        | (static_cast<ULONGLONG>(seq)<<32));
}
// Mirrors the host send contract: the issued epoch is published into the
// shared page BEFORE the packet is posted, on every send.
void SendDown(UINT packet,UINT epoch,UINT seq) {
    state->issuedEpoch=static_cast<LONG>(epoch&0xFFFFFFu);
    InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONDOWN-WM_MOUSEFIRST,MK_LBUTTON,epoch),PacketL(10,10,seq));
}
void SendMove(UINT packet,UINT epoch,UINT seq) {
    state->issuedEpoch=static_cast<LONG>(epoch&0xFFFFFFu);
    InputBridgeSelfTest::Drive(packet,PacketW(WM_MOUSEMOVE-WM_MOUSEFIRST,0,epoch),PacketL(1,1,seq));
}
// Dequeues a packet the host already issued (issuedEpoch was published at send
// time): used for packets that sat in the queue across a focus-loss boundary.
void DeliverDown(UINT packet,UINT epoch,UINT seq) {
    InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONDOWN-WM_MOUSEFIRST,MK_LBUTTON,epoch),PacketL(10,10,seq));
}
}

int wmain(int argc,wchar_t** argv) {
    InputTraceShared diagnostic{};
    for(int n=1;n<=static_cast<int>(InputTraceCapacity)+3;n++)
        TraceWrite(&diagnostic,TraceReturn,n,n+10,WM_LBUTTONUP,POINT{n,-n},0,0,nullptr);
    InputTraceSnapshot record{};
    Check(!TraceRead(&diagnostic,1,record),"trace_overwritten_record_is_not_fabricated");
    Check(TraceRead(&diagnostic,InputTraceCapacity+3,record) && record.sequence==InputTraceCapacity+3
        && record.x==record.sequence && record.y==-record.sequence && record.ticks>0,"trace_committed_record_exact");
    InterlockedExchange64(&diagnostic.records[3].serial,0);
    Check(!TraceRead(&diagnostic,4,record),"trace_partial_record_refused");
    WNDCLASSW wc{};
    wc.lpfnWndProc=TargetProc;
    wc.hInstance=GetModuleHandleW(nullptr);
    wc.lpszClassName=L"CF7InputBridgeSelfTestTarget";
    if(!RegisterClassW(&wc)) { std::printf("FAIL register_class error=%lu\n",GetLastError()); return 2; }
    HWND target=CreateWindowExW(0,wc.lpszClassName,L"target",WS_OVERLAPPED,0,0,200,100,nullptr,nullptr,wc.hInstance,nullptr);
    HWND other=CreateWindowExW(0,wc.lpszClassName,L"other",WS_OVERLAPPED,0,0,50,50,nullptr,nullptr,wc.hInstance,nullptr);
    HANDLE mapping=CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,sizeof(InputShared),L"Local\\CF7.WorldPointer.SelfTest");
    state=mapping ? static_cast<InputShared*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,sizeof(InputShared))) : nullptr;
    if(!target || !other || !state) { std::printf("FAIL fixture error=%lu\n",GetLastError()); return 2; }
    *state={};
    state->magic=InputMagic;
    state->protocolVersion=InputProtocolVersion;
    UINT packet=RegisterWindowMessageW(InputMessage);
    InputBridgeSelfTest::Install(target,state,packet);

    if(argc>1) {std::puts("v3 --long-session evidence is frozen; run G1 -Mode renew to verify v4 continuity, never reinterpret the old failure as success");return 2;}
    (void)argv;

    // 1. Down(epoch=5) is admitted: real SetFocus plus original-proc delivery
    //    of the re-hover move and the button edge.
    int f0=focusGains, m0=mouseDeliveries;
    SendDown(packet,5,1);
    Check(focusGains>f0 && mouseDeliveries==m0+2,"down_epoch5_admitted_focus_and_delivery");
    Check(state->staleRejected==0,"admitted_down_not_counted_stale");
    Check(InputBridgeSelfTest::LastEpoch()==5,"admitted_epoch_updates_endpoint_high_water");
    int beforeLeave=nativeLeaves;
    InputBridgeSelfTest::Drive(WM_MOUSELEAVE,0,0);
    Check(nativeLeaves==beforeLeave,"covered_source_leave_cannot_clear_mapped_hover");

    // 2. RCE-1 regression: the host has already issued Down(6) — issuedEpoch=6
    //    was published at send time — but the packet is still queued behind the
    //    focus-loss boundary. A real SetFocus to another window delivers
    //    WM_KILLFOCUS through the installed bridge proc: the local floor must
    //    rise one past the ISSUED epoch (max(lastEpoch=5, issued=6)+1=7), not
    //    just past the newest packet this endpoint processed.
    state->issuedEpoch=6; // host posted Down(6); the projector has not seen it yet
    SetFocus(target); // guard: make sure the target holds focus first
    SetFocus(other);
    Check(InputBridgeSelfTest::LocalFloor()==7,"killfocus_floor_covers_issued_unseen_epoch");
    InputBridgeSelfTest::Drive(WM_MOUSELEAVE,0,0);
    Check(nativeLeaves==beforeLeave+1,"real_focus_loss_restores_native_leave_delivery");
    // The queued Down(6) is dequeued after the boundary: zero SetFocus, zero
    // original-proc mouse delivery, counted as stale.
    f0=focusGains; m0=mouseDeliveries;
    DeliverDown(packet,6,2);
    Check(focusGains==f0 && mouseDeliveries==m0,"queued_epoch6_down_no_focus_no_delivery");
    Check(state->staleRejected==1,"queued_stale_rejection_counted");

    // 3. Recovery needs no other path: the host's next physical down starts a
    //    new gesture, which mints the next epoch (7). That packet is admitted
    //    exactly once — focus plus both deliveries.
    f0=focusGains; m0=mouseDeliveries;
    SendDown(packet,7,3);
    Check(focusGains>f0 && mouseDeliveries==m0+2,"new_gesture_epoch7_readmitted_after_loss");

    // 4. WM_ENTERMENULOOP (in-session menu focus loss, owner never deactivates)
    //    raises the same issued-based floor; a packet issued before the menu
    //    boundary is rejected, and the next gesture's down is admitted again.
    InputBridgeSelfTest::Drive(WM_ENTERMENULOOP,0,0);
    Check(InputBridgeSelfTest::LocalFloor()==8,"entermenuloop_floor_covers_issued_epoch");
    f0=focusGains; m0=mouseDeliveries;
    DeliverDown(packet,7,4);
    Check(focusGains==f0 && mouseDeliveries==m0,"queued_epoch7_down_rejected_after_menuloop");
    Check(state->staleRejected==2,"menuloop_stale_rejection_counted");
    // Re-admission proof: ENTERMENULOOP never moved the real focus, so the next
    // gesture's down is delivered (SetFocus is a no-op while target holds it).
    m0=mouseDeliveries;
    SendDown(packet,8,5);
    Check(mouseDeliveries==m0+2,"new_gesture_epoch8_readmitted_after_menuloop");

    // v4 bounds: no artificial floor movement, no wire wrap. Domain failure
    // leaves high-water and original handler untouched. Actual continuation is
    // covered by the cross-process production renewal test, not by resetting here.
    m0=mouseDeliveries;
    SendMove(packet,static_cast<UINT>(InputEpochLimit),10);
    Check(mouseDeliveries==m0+1,"last_ordinary_epoch_admitted_with_old_floors");
    UINT high=InputBridgeSelfTest::LastEpoch();
    for(UINT invalid:{0u,0x7FFFFEu,0x800000u,0xFFFFFFu}) {
        m0=mouseDeliveries;f0=focusGains;
        DeliverDown(packet,invalid,11);
        Check(mouseDeliveries==m0 && focusGains==f0 && InputBridgeSelfTest::LastEpoch()==high,"invalid_epoch_no_effect");
    }
    for(UINT invalidSeq:{0u,0x7FFFFFFEu,0xFFFFFFFFu}) {
        m0=mouseDeliveries;
        InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONDOWN-WM_MOUSEFIRST,MK_LBUTTON,static_cast<UINT>(InputEpochLimit)),PacketL(1,1,invalidSeq));
        Check(mouseDeliveries==m0,"invalid_sequence_no_delivery");
    }
    // Modifier bits must not keep a mouse gesture alive after its Up.
    state->minEpoch=0;InputBridgeSelfTest::Install(target,state,packet);
    SendDown(packet,2,12);
    InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONUP-WM_MOUSEFIRST,MK_SHIFT|MK_CONTROL,2),PacketL(10,10,13));
    Check(InputBridgeSelfTest::Gesture()==0 && state->heldButtons==0,"modifier_up_releases_mouse_gesture");
    InputBridgeSelfTest::Drive(packet,PacketW(WM_MOUSEMOVE-WM_MOUSEFIRST,0,2),PacketL(-1,-1,14));
    Check(lastMouseMove.x==-1 && lastMouseMove.y==-1,"presentation_leave_preserves_negative_sentinel");

    // 7. Without a shared section nothing is admissible at all.
    InputBridgeSelfTest::Install(target,nullptr,packet);
    m0=mouseDeliveries;
    DeliverDown(packet,1,15);
    Check(mouseDeliveries==m0,"no_shared_section_refuses_delivery");

    std::printf("RESULT %s failures=%d\n",failures?"FAIL":"PASS",failures);
    return failures ? 1 : 0;
}
