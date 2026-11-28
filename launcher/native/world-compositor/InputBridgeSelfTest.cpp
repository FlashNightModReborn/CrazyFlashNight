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
    bool TryInitialize(HWND target,uint64_t cookie);
    void Install(HWND target,InputShared* state,UINT packetMessage);
    LRESULT Drive(UINT message,WPARAM wparam,LPARAM lparam);
    UINT LocalFloor();
    UINT LastEpoch();
    UINT Gesture();
    SHORT MouseKey(int vk);
}

namespace {
InputShared* state=nullptr;
int focusGains=0, mouseDeliveries=0, nativeLeaves=0, failures=0;
POINT lastMouseMove{}, lastLeftUp{};
HWND observedChild=nullptr, expectedFocus=nullptr;
bool focusChangedDuringMouseDelivery=false;
unsigned seen[WM_MOUSELAST-WM_MOUSEFIRST+1]{};
LRESULT CALLBACK TargetProc(HWND hwnd,UINT message,WPARAM wp,LPARAM lp) {
    if(hwnd==observedChild && message>=WM_MOUSEFIRST && message<=WM_MOUSELAST) {
        ++seen[message-WM_MOUSEFIRST];
        if(GetFocus()!=expectedFocus)focusChangedDuringMouseDelivery=true;
    }
    if(hwnd==observedChild && message==WM_SETFOCUS)focusGains++;
    if(message==WM_MOUSELEAVE) nativeLeaves++;
    if(message==WM_MOUSEMOVE) lastMouseMove={static_cast<SHORT>(LOWORD(lp)),static_cast<SHORT>(HIWORD(lp))};
    if(message==WM_LBUTTONUP) lastLeftUp={static_cast<SHORT>(LOWORD(lp)),static_cast<SHORT>(HIWORD(lp))};
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
// time) across a published cancellation boundary.
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
    wchar_t sectionName[96];
    swprintf_s(sectionName,L"Local\\CF7.WorldPointer.SelfTest.%lu",GetCurrentProcessId());
    HANDLE mapping=CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,sizeof(InputShared),sectionName);
    state=mapping ? static_cast<InputShared*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,sizeof(InputShared))) : nullptr;
    if(!target || !other || !state) { std::printf("FAIL fixture error=%lu\n",GetLastError()); return 2; }
    *state={};
    state->magic=InputMagic;
    state->protocolVersion=InputProtocolVersion;
    state->session=17;
    state->hostPid=state->sourcePid=GetCurrentProcessId();
    state->sourceWindow=reinterpret_cast<uint64_t>(target);
    state->ownerWindow=reinterpret_cast<uint64_t>(other);
    ATOM atom=GlobalAddAtomW(sectionName);
    if(!atom || !SetPropW(target,InputProperty,reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(atom))))return 2;
    auto original=GetWindowLongPtrW(target,GWLP_WNDPROC);
    SetParent(target,other);
    SetWindowLongPtrW(target,GWL_STYLE,WS_CHILD|WS_DISABLED);
    observedChild=target;
    expectedFocus=other;
    SetFocus(other);
    Check(GetFocus()==other && !IsWindowEnabled(target),"fixture_focus_on_other_disabled_target");
    for(uint32_t invalidMode:{0u,2u,3u,UINT32_MAX}) {
        state->passiveMode=invalidMode;
        state->ready=0;
        Check(!InputBridgeSelfTest::TryInitialize(target,state->session) && state->ready==InputProfileRejected &&
            state->patchMask==0 && GetWindowLongPtrW(target,GWLP_WNDPROC)==original,
            invalidMode==0 ? "passive_mode_0_bind_rejected_before_install" :
            invalidMode==2 ? "passive_mode_2_bind_rejected_before_install" : "invalid_passive_mode_bind_rejected_before_install");
    }
    state->passiveMode=InputPassiveDisabled;
    Check(!InputBridgeSelfTest::TryInitialize(target,state->session) && state->ready==InputProfileRejected &&
        GetWindowLongPtrW(target,GWLP_WNDPROC)==original,"rejected_bind_cannot_retry_with_valid_profile");
    EnableWindow(target,TRUE);
    state->ready=0;state->passiveMode=InputPassiveDisabled;
    Check(!InputBridgeSelfTest::TryInitialize(target,state->session) && state->ready==InputProfileRejected &&
        GetWindowLongPtrW(target,GWLP_WNDPROC)==original,"passive_bind_requires_disabled_window");
    RemovePropW(target,InputProperty);GlobalDeleteAtom(atom);
    EnableWindow(target,FALSE);
    state->ready=0;
    UINT packet=RegisterWindowMessageW(InputMessage);
    InputBridgeSelfTest::Install(target,state,packet);

    if(argc>1) {std::puts("v3 --long-session evidence is frozen; run G1 -Mode renew to verify v4 continuity, never reinterpret the old failure as success");return 2;}
    (void)argv;

    int f0=focusGains, m0=mouseDeliveries;
    SendDown(packet,5,1);
    Check(GetFocus()==other && focusGains==f0 && mouseDeliveries==m0+2,"down_epoch5_delivered_with_other_focused");
    Check(state->staleRejected==0,"admitted_down_not_counted_stale");
    Check(InputBridgeSelfTest::LastEpoch()==5,"admitted_epoch_updates_endpoint_high_water");
    int beforeLeave=nativeLeaves;
    InputBridgeSelfTest::Drive(WM_MOUSELEAVE,0,0);
    Check(nativeLeaves==beforeLeave,"covered_source_leave_cannot_clear_mapped_hover");

    // The authority cancels through the highest issued epoch, including an
    // unseen Down. Only the exact cancel reaches the original procedure.
    state->issuedEpoch=6;
    state->minEpoch=7;
    state->cancelTicket=1;
    auto priorDowns=seen[WM_LBUTTONDOWN-WM_MOUSEFIRST];
    m0=mouseDeliveries;
    DeliverDown(packet,6,2);
    Check(state->cancelledTicket==1 && !state->heldButtons && InputBridgeSelfTest::LocalFloor()==7,
        "cancel_floor_covers_issued_unseen_epoch");
    Check(focusGains==f0 && GetFocus()==other && seen[WM_LBUTTONDOWN-WM_MOUSEFIRST]==priorDowns && mouseDeliveries==m0+1,
        "queued_epoch6_down_no_focus_no_mouse_delivery");
    InputBridgeSelfTest::Drive(WM_MOUSELEAVE,0,0);
    Check(nativeLeaves==beforeLeave+1,"cancel_restores_native_leave_delivery");
    Check(state->staleRejected==1,"queued_stale_rejection_counted");

    // A direct SendMessage cannot admit even a current, otherwise valid Down.
    m0=mouseDeliveries;
    SendMessageW(target,packet,PacketW(WM_LBUTTONDOWN-WM_MOUSEFIRST,MK_LBUTTON,7),PacketL(10,10,3));
    Check(mouseDeliveries==m0 && !state->heldButtons && GetFocus()==other,"direct_send_refused_before_delivery");
    SendDown(packet,7,3);
    Check(focusGains==f0 && GetFocus()==other && mouseDeliveries==m0+2,"new_gesture_epoch7_readmitted_without_focus");
    InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONUP-WM_MOUSEFIRST,0,7),PacketL(10,10,4));

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

    // Drive all mapped buttons through the disabled child's original procedure.
    *state={};state->passiveMode=InputPassiveDisabled;
    InputBridgeSelfTest::Install(target,state,packet);
    f0=focusGains;
    auto downs=seen[WM_LBUTTONDOWN-WM_MOUSEFIRST], ups=seen[WM_LBUTTONUP-WM_MOUSEFIRST];
    auto moves=seen[0], wheels=seen[WM_MOUSEWHEEL-WM_MOUSEFIRST];
    SendDown(packet,2,1);
    Check(!IsWindowEnabled(target) && InputBridgeSelfTest::MouseKey(VK_LBUTTON)<0,"passive_disabled_virtual_button_down");
    InputBridgeSelfTest::Drive(WM_KILLFOCUS,reinterpret_cast<WPARAM>(other),0);
    Check(InputBridgeSelfTest::Gesture()==1 && InputBridgeSelfTest::LocalFloor()==0,"passive_killfocus_preserves_gesture");
    InputBridgeSelfTest::Drive(packet,PacketW(WM_MOUSEMOVE-WM_MOUSEFIRST,MK_LBUTTON,2),PacketL(11,10,2));
    InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONUP-WM_MOUSEFIRST,0,2),PacketL(11,10,3));
    InputBridgeSelfTest::Drive(packet,PacketW(WM_MOUSEWHEEL-WM_MOUSEFIRST,0,2)|(120u<<16),PacketL(11,10,4));
    Check(seen[WM_LBUTTONDOWN-WM_MOUSEFIRST]==downs+1 && seen[0]==moves+2 &&
        seen[WM_LBUTTONUP-WM_MOUSEFIRST]==ups+1 && seen[WM_MOUSEWHEEL-WM_MOUSEFIRST]==wheels+1 &&
        InputBridgeSelfTest::MouseKey(VK_LBUTTON)==0,"passive_disabled_original_down_move_up_wheel");
    SendDown(packet,3,5);
    state->minEpoch=4;state->cancelTicket=1;
    SendMove(packet,3,6);
    Check(state->cancelledTicket==1 && state->heldButtons==0 && !InputBridgeSelfTest::Gesture() &&
        state->staleRejected==1,"passive_ticket_settled_old_epoch_rejected");
    UINT sequence=7;
    ups=seen[WM_LBUTTONUP-WM_MOUSEFIRST];
    downs=seen[WM_LBUTTONDOWN-WM_MOUSEFIRST];
    InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONUP-WM_MOUSEFIRST,0,3),PacketL(11,10,sequence++));
    Check(seen[WM_LBUTTONUP-WM_MOUSEFIRST]==ups && state->staleRejected==2 && !state->heldButtons &&
        GetFocus()==other,"cancelled_epoch_tail_up_cannot_complete_the_old_press");
    SendDown(packet,4,sequence++);
    InputBridgeSelfTest::Drive(packet,PacketW(WM_MOUSEMOVE-WM_MOUSEFIRST,MK_LBUTTON,4),PacketL(18,20,sequence++));
    LONG freshCompleted=state->completedSeq;
    LONG rejected=state->staleRejected;
    // Reorder the old queued Up after the fresh Down and Move. It must never
    // reach the native original while the fresh primary button owns the drag.
    InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONUP-WM_MOUSEFIRST,0,3),PacketL(11,10,6));
    Check(seen[WM_LBUTTONUP-WM_MOUSEFIRST]==ups && state->completedSeq==freshCompleted &&
        state->heldButtons==MK_LBUTTON && state->staleRejected==rejected+1,
        "old_up_after_fresh_down_and_move_never_reaches_original");
    InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONUP-WM_MOUSEFIRST,0,4),PacketL(-16,-23,sequence++));
    Check(seen[WM_LBUTTONDOWN-WM_MOUSEFIRST]==downs+1 && seen[WM_LBUTTONUP-WM_MOUSEFIRST]==ups+1 &&
        !state->heldButtons && lastLeftUp.x<0 && lastLeftUp.y<0 && GetFocus()==other,
        "first_fresh_left_click_after_cancel_delivered_once");
    for(UINT down:{WM_RBUTTONDOWN,WM_MBUTTONDOWN,WM_XBUTTONDOWN}) {
        UINT mask=down==WM_RBUTTONDOWN ? MK_RBUTTON : down==WM_MBUTTONDOWN ? MK_MBUTTON : MK_XBUTTON1;
        WPARAM extra=down==WM_XBUTTONDOWN ? static_cast<WPARAM>(XBUTTON1)<<16 : 0;
        auto delivered=seen[down-WM_MOUSEFIRST];
        InputBridgeSelfTest::Drive(packet,PacketW(down-WM_MOUSEFIRST,mask,4)|extra,PacketL(4,4,sequence++));
        InputBridgeSelfTest::Drive(packet,PacketW(down+1-WM_MOUSEFIRST,0,4)|extra,PacketL(4,4,sequence++));
        Check(seen[down-WM_MOUSEFIRST]==delivered+1 && !state->heldButtons,"passive_disabled_button_pair");
    }
    auto completed=state->completedSeq;
    DeliverDown(packet,4,1);
    Check(state->completedSeq==completed && state->consumedSeq==completed && !state->heldButtons,"passive_replayed_sequence_refused");
    auto horizontal=seen[WM_MOUSEHWHEEL-WM_MOUSEFIRST];
    InputBridgeSelfTest::Drive(packet,PacketW(WM_MOUSEHWHEEL-WM_MOUSEFIRST,0,4)|(120u<<16),PacketL(11,10,sequence++));
    Check(seen[WM_MOUSEHWHEEL-WM_MOUSEFIRST]==horizontal+1,"passive_disabled_horizontal_wheel");
    downs=seen[WM_LBUTTONDOWN-WM_MOUSEFIRST];ups=seen[WM_LBUTTONUP-WM_MOUSEFIRST];
    SendDown(packet,4,sequence++);
    auto priorMoves=seen[WM_MOUSEMOVE-WM_MOUSEFIRST];
    SendMove(packet,4,sequence++); // No Up was admitted to release the held button.
    Check(state->heldButtons==MK_LBUTTON && seen[WM_MOUSEMOVE-WM_MOUSEFIRST]==priorMoves && GetFocus()==other,
        "move_cannot_release_an_open_gesture");
    SendDown(packet,4,sequence++);
    for(int i=0;i<2;i++)InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONUP-WM_MOUSEFIRST,0,4),PacketL(10,10,sequence++));
    Check(seen[WM_LBUTTONDOWN-WM_MOUSEFIRST]==downs+1 && seen[WM_LBUTTONUP-WM_MOUSEFIRST]==ups+1 &&
        state->duplicateDowns==1 && state->unownedReleases==1,"passive_disabled_duplicate_down_and_orphan_up_refused");
    m0=mouseDeliveries;
    InputBridgeSelfTest::Drive(packet,PacketW(WM_LBUTTONDOWN-WM_MOUSEFIRST,0,4),PacketL(10,10,sequence++));
    Check(!InputBridgeSelfTest::Gesture() && !state->heldButtons && mouseDeliveries==m0,
        "down_without_its_button_flag_cannot_open_a_gesture");
    Check(!focusChangedDuringMouseDelivery && focusGains==f0 && GetFocus()==other,"passive_disabled_zero_focus_transfer");
    for(uint32_t changedMode:{2u,0u}) {
        *state={};state->passiveMode=InputPassiveDisabled;
        InputBridgeSelfTest::Install(target,state,packet);
        SendMove(packet,4,1);
        m0=mouseDeliveries;completed=state->completedSeq;
        state->passiveMode=changedMode;
        SendDown(packet,4,2);
        Check(completed==1 && state->stop==1 && state->invalidRejected==1 && state->completedSeq==completed &&
            mouseDeliveries==m0 && GetFocus()==other,
            "passive_bound_mode_change_seals_delivery");
        state->passiveMode=InputPassiveDisabled;
        SendDown(packet,4,3);
        Check(state->stoppedRejected==1 && state->completedSeq==completed && mouseDeliveries==m0,
            "passive_mode_restored_field_cannot_reopen_sealed_bridge");
    }

    *state={};state->passiveMode=InputPassiveDisabled;
    InputBridgeSelfTest::Install(target,state,packet);
    EnableWindow(target,TRUE);
    m0=mouseDeliveries;
    SendDown(packet,4,1);
    Check(state->stop==1 && state->completedSeq==0 && mouseDeliveries==m0 && GetFocus()==other,
        "reenabled_passive_window_seals_mapped_input");

    // 7. Without a shared section nothing is admissible at all.
    InputBridgeSelfTest::Install(target,nullptr,packet);
    m0=mouseDeliveries;
    DeliverDown(packet,1,15);
    Check(mouseDeliveries==m0,"no_shared_section_refuses_delivery");

    std::printf("RESULT %s failures=%d\n",failures?"FAIL":"PASS",failures);
    return failures ? 1 : 0;
}
