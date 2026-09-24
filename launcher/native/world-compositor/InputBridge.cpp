#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "InputBridge.h"
#include "InputTrace.h"
#include <cstring>
#include <cwchar>
#include <algorithm>
#include <string>

// Loaded by a thread-specific hook into the paired x64 projector only. No
// global process injection, cursor warping, polling thread, or AS2 script work.
namespace {
HWND target=nullptr;
WNDPROC originalProc=nullptr;
InputShared* shared=nullptr;
HANDLE mapping=nullptr;
HANDLE traceMapping=nullptr;
InputTraceShared* traceState=nullptr;
UINT packetMessage=0;
POINT virtualPoint{};
UINT buttons=0, activeGesture=0;
bool enabled=false, captured=false;
LONGLONG lastPaintTicks=0;
RECT lastPaintBounds{};
UINT lastEpoch=0, localFloor=0, controlMessage=0;
DWORD targetThread=0, lastCursorTrace=0;
LONG lastCursorKind=0;
void Observe(LONG stage,UINT sequence=0,UINT epoch=0,UINT message=0,POINT point={}) {
    TraceWrite(traceState,stage,sequence,epoch,message,point,buttons,localFloor,GetFocus());
}
int procedureDepth=0, dispatchDepth=0, hookDepth=0;
volatile LONG wrapperDepth=0;
struct WrapperScope {WrapperScope(){InterlockedIncrement(&wrapperDepth);} ~WrapperScope(){InterlockedDecrement(&wrapperDepth);} };
SRWLOCK stateLock=SRWLOCK_INIT;
struct ReadLock { ReadLock(){AcquireSRWLockShared(&stateLock);} ~ReadLock(){ReleaseSRWLockShared(&stateLock);} };
struct WriteLock { WriteLock(){AcquireSRWLockExclusive(&stateLock);} ~WriteLock(){ReleaseSRWLockExclusive(&stateLock);} };
struct Depth { int& value; explicit Depth(int& v):value(v){++value;} ~Depth(){--value;} };
struct Patch { ULONG_PTR* slot; ULONG_PTR original,replacement; } patches[32]{};
int patchCount=0;
LRESULT CALLBACK WindowProc(HWND,UINT,WPARAM,LPARAM);
using CursorProc=BOOL(WINAPI*)(LPPOINT);
using PositionProc=DWORD(WINAPI*)();
using KeyProc=SHORT(WINAPI*)(int);
using CaptureProc=HWND(WINAPI*)(HWND);
using GetCaptureProc=HWND(WINAPI*)();
using ReleaseProc=BOOL(WINAPI*)();
CursorProc realCursor=::GetCursorPos;
PositionProc realPosition=::GetMessagePos;
KeyProc realAsync=::GetAsyncKeyState, realKey=::GetKeyState;
CaptureProc realCapture=::SetCapture;
GetCaptureProc realGetCapture=::GetCapture;
ReleaseProc realRelease=::ReleaseCapture;

int ButtonMask(int key) {
    switch(key) { case VK_LBUTTON:return MK_LBUTTON; case VK_RBUTTON:return MK_RBUTTON;
        case VK_MBUTTON:return MK_MBUTTON; case VK_XBUTTON1:return MK_XBUTTON1; case VK_XBUTTON2:return MK_XBUTTON2; default:return 0; }
}
BOOL WINAPI Cursor(LPPOINT point) {
    WrapperScope invocation;
    CursorProc fallback;
    { ReadLock guard; fallback=realCursor;
      if(enabled && target) { if(!point)return FALSE; *point=virtualPoint; ClientToScreen(target,point);
        if(traceState && GetCurrentThreadId()==targetThread && (lastCursorKind!=TraceCursorVirtual || GetTickCount()-lastCursorTrace>=250)) {
            lastCursorKind=TraceCursorVirtual;lastCursorTrace=GetTickCount();Observe(TraceCursorVirtual,0,lastEpoch,0,virtualPoint);
        }
        if(shared)InterlockedIncrement(&shared->cursorReads); return TRUE; } }
    BOOL okay=fallback(point);
    if(okay && traceState && GetCurrentThreadId()==targetThread && (lastCursorKind!=TraceCursorPhysical || GetTickCount()-lastCursorTrace>=250)) {
        lastCursorKind=TraceCursorPhysical;lastCursorTrace=GetTickCount();POINT client=*point;ScreenToClient(target,&client);
        Observe(TraceCursorPhysical,0,lastEpoch,0,client);
    }
    return okay;
}
DWORD WINAPI Position() {
    WrapperScope invocation;
    PositionProc fallback;
    { ReadLock guard; fallback=realPosition; if(enabled && target) { POINT p=virtualPoint; ClientToScreen(target,&p); return MAKELONG(static_cast<WORD>(p.x),static_cast<WORD>(p.y)); } }
    return fallback();
}
SHORT KeyValue(int key,bool asynchronous) {
    WrapperScope invocation;
    KeyProc fallback;
    { ReadLock guard; fallback=asynchronous ? realAsync : realKey;
      int mask=ButtonMask(key); if(enabled && mask) { if(shared)InterlockedIncrement(&shared->keyReads); return (buttons&mask) ? static_cast<SHORT>(0x8000) : 0; } }
    return fallback(key);
}
SHORT WINAPI Async(int key) { return KeyValue(key,true); }
SHORT WINAPI Key(int key) { return KeyValue(key,false); }
HWND WINAPI Capture(HWND hwnd) {
    WrapperScope invocation;
    CaptureProc fallback;
    { WriteLock guard; fallback=realCapture; if(enabled && hwnd==target) { HWND previous=captured ? target : nullptr; captured=true; return previous; } }
    return fallback(hwnd);
}
HWND WINAPI GetCapture() {
    WrapperScope invocation;
    GetCaptureProc fallback;
    { ReadLock guard; fallback=realGetCapture; if(enabled && captured)return target; }
    return fallback();
}
BOOL WINAPI Release() {
    WrapperScope invocation;
    ReleaseProc fallback;
    { WriteLock guard; fallback=realRelease; if(enabled) {captured=false; return TRUE;} }
    return fallback();
}

bool PatchSlot(ULONG_PTR* slot,ULONG_PTR replacement) {
    if(patchCount>=32) return false;
    DWORD old=0;
    if(!VirtualProtect(slot,sizeof(*slot),PAGE_READWRITE,&old)) return false;
    patches[patchCount++]={slot,*slot,replacement}; InterlockedExchangePointer(reinterpret_cast<PVOID volatile*>(slot),reinterpret_cast<PVOID>(replacement));
    DWORD ignored=0; VirtualProtect(slot,sizeof(*slot),old,&ignored);
    return true;
}
void InstallImports() {
    auto base=reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
    auto dos=reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    auto nt=reinterpret_cast<IMAGE_NT_HEADERS*>(base+dos->e_lfanew);
    auto directory=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if(!directory.VirtualAddress) return;
    auto imports=reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base+directory.VirtualAddress);
    for(;imports->Name;imports++) {
        if(_stricmp(reinterpret_cast<char*>(base+imports->Name),"user32.dll")!=0 || !imports->OriginalFirstThunk) continue;
        auto names=reinterpret_cast<IMAGE_THUNK_DATA*>(base+imports->OriginalFirstThunk);
        auto addresses=reinterpret_cast<IMAGE_THUNK_DATA*>(base+imports->FirstThunk);
        for(;names->u1.AddressOfData;names++,addresses++) {
            if(IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            const char* name=reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(base+names->u1.AddressOfData)->Name;
            ULONG_PTR replacement=0;
            // Preserve an earlier application's import wrapper if one exists.
            if(strcmp(name,"GetCursorPos")==0) { realCursor=reinterpret_cast<CursorProc>(addresses->u1.Function); replacement=reinterpret_cast<ULONG_PTR>(Cursor); }
            else if(strcmp(name,"GetMessagePos")==0) { realPosition=reinterpret_cast<PositionProc>(addresses->u1.Function); replacement=reinterpret_cast<ULONG_PTR>(Position); }
            else if(strcmp(name,"GetAsyncKeyState")==0) { realAsync=reinterpret_cast<KeyProc>(addresses->u1.Function); replacement=reinterpret_cast<ULONG_PTR>(Async); }
            else if(strcmp(name,"GetKeyState")==0) { realKey=reinterpret_cast<KeyProc>(addresses->u1.Function); replacement=reinterpret_cast<ULONG_PTR>(Key); }
            else if(strcmp(name,"SetCapture")==0) { realCapture=reinterpret_cast<CaptureProc>(addresses->u1.Function); replacement=reinterpret_cast<ULONG_PTR>(Capture); }
            else if(strcmp(name,"GetCapture")==0) { realGetCapture=reinterpret_cast<GetCaptureProc>(addresses->u1.Function); replacement=reinterpret_cast<ULONG_PTR>(GetCapture); }
            else if(strcmp(name,"ReleaseCapture")==0) { realRelease=reinterpret_cast<ReleaseProc>(addresses->u1.Function); replacement=reinterpret_cast<ULONG_PTR>(Release); }
            if(replacement && PatchSlot(&addresses->u1.Function,replacement)) {
                const char* required[]{"GetCursorPos","GetMessagePos","GetAsyncKeyState","GetKeyState","SetCapture","GetCapture","ReleaseCapture"};
                for(int i=0;i<7;i++) if(strcmp(name,required[i])==0) InterlockedOr(&shared->patchMask,1L<<i);
            }
        }
    }
}
LRESULT Original(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    Depth depth(dispatchDepth);
    if(shared)InterlockedExchange(&shared->dispatchDepth,dispatchDepth);
    LRESULT result=CallWindowProcW(originalProc,hwnd,msg,wp,lp);
    if(shared)InterlockedExchange(&shared->dispatchDepth,dispatchDepth-1);
    return result;
}
void CancelEndpoint() {
    if(!shared || dispatchDepth) return;
    LONG ticket=ReadAtomic(&shared->cancelTicket);
    if(ticket==ReadAtomic(&shared->cancelledTicket)) return;
    { WriteLock guard; enabled=false; buttons=0; captured=false; activeGesture=0; }
    InterlockedExchange(&shared->heldButtons,0);
    if(reinterpret_cast<WNDPROC>(GetWindowLongPtrW(target,GWLP_WNDPROC))!=WindowProc) {
        InterlockedExchange(&shared->restoreError,1);return; // original cancellation ownership is unconfirmed
    }
    Original(target,WM_CANCELMODE,0,0);
    if(realGetCapture()==target)realRelease();
    InterlockedExchange(&shared->cancelledTicket,ticket);
    Observe(TraceCancel,0,ReadAtomic(&shared->issuedEpoch),WM_CANCELMODE);
}
bool Restore() {
    // Called by a synchronous control on the target UI thread, never nested
    // inside an original call or getmessage callback. Its return is separately
    // acknowledged by the broker, after SendMessageTimeout has returned.
    if(!shared || hookDepth || dispatchDepth || procedureDepth>1 || ReadAtomic(&wrapperDepth))return false;
    CancelEndpoint();
    MSG msg{};
    while(PeekMessageW(&msg,target,packetMessage,packetMessage,PM_REMOVE))
        InterlockedIncrement(&shared->drained);
    WriteLock guard;
    if(ReadAtomic(&wrapperDepth))return false;
    enabled=false; buttons=0; captured=false; activeGesture=0;
    bool okay=true;
    if(target && IsWindow(target)) {
        auto current=reinterpret_cast<WNDPROC>(GetWindowLongPtrW(target,GWLP_WNDPROC));
        if(current!=WindowProc)okay=false;
        else { SetLastError(0); auto previous=SetWindowLongPtrW(target,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(originalProc));
            if(!previous && GetLastError())okay=false; }
    }
    for(int i=patchCount-1;i>=0;i--) {
        DWORD old=0;
        if(!VirtualProtect(patches[i].slot,sizeof(ULONG_PTR),PAGE_READWRITE,&old)) { okay=false; continue; }
        auto found=InterlockedCompareExchangePointer(reinterpret_cast<PVOID volatile*>(patches[i].slot),
            reinterpret_cast<PVOID>(patches[i].original),reinterpret_cast<PVOID>(patches[i].replacement));
        if(found!=reinterpret_cast<PVOID>(patches[i].replacement))okay=false;
        DWORD ignored=0; if(!VirtualProtect(patches[i].slot,sizeof(ULONG_PTR),old,&ignored))okay=false;
    }
    if(!okay) { InterlockedExchange(&shared->restoreError,1); InterlockedExchange(&shared->stopped,-1); return false; }
    patchCount=0;
    InterlockedExchange(&shared->stopped,1);
    // All wrappers have left the shared lock, no original/getmessage call is
    // outstanding, and all remaining old MSG copies are WM_NULL.
    UnmapViewOfFile(shared); shared=nullptr;
    if(mapping)CloseHandle(mapping); mapping=nullptr;
    if(traceState)UnmapViewOfFile(traceState);traceState=nullptr;
    if(traceMapping)CloseHandle(traceMapping);traceMapping=nullptr;
    target=nullptr; originalProc=nullptr;
    return true;
}
UINT PacketButtonBit(UINT type,UINT extra) {
    switch(type) { case WM_LBUTTONDOWN:case WM_LBUTTONUP:return MK_LBUTTON;
        case WM_RBUTTONDOWN:case WM_RBUTTONUP:return MK_RBUTTON;
        case WM_MBUTTONDOWN:case WM_MBUTTONUP:return MK_MBUTTON;
        case WM_XBUTTONDOWN:case WM_XBUTTONUP:return extra==XBUTTON1 ? MK_XBUTTON1 : MK_XBUTTON2;
        default:return 0; }
}
LRESULT Deliver(HWND hwnd,WPARAM wp,LPARAM lp) {
        UINT kind=static_cast<UINT>(wp)&255;
        // v4 bounded envelope: flags/extra share the low word with v1; the high half carries
        // the 24-bit input epoch, the geometry version, and the packet sequence.
        // The v2 gesture field is gone: gesture ownership is endpoint-local state.
        UINT flags=(static_cast<UINT>(wp)>>8)&127, extra=(static_cast<UINT>(wp)>>16)&0xFFFF;
        UINT epoch=static_cast<UINT>((wp>>32)&0xFFFFFF);
        UINT seq=static_cast<UINT>((static_cast<ULONGLONG>(lp)>>32)&0xFFFFFFFF);
        UINT diagnosticType=kind==0xFE ? WM_CANCELMODE : WM_MOUSEFIRST+kind;
        bool edge=diagnosticType!=WM_MOUSEMOVE;
        if(!shared)return 0;
        if(reinterpret_cast<WNDPROC>(GetWindowLongPtrW(hwnd,GWLP_WNDPROC))!=WindowProc){if(edge)Observe(TraceStopped,seq,epoch,diagnosticType);InterlockedExchange(&shared->stop,1);return 0;}
        InterlockedExchange(&shared->consumedSeq,static_cast<LONG>(seq));
        CancelEndpoint();
        if(ReadAtomic(&shared->stop) || ReadAtomic(&shared->cancelTicket)!=ReadAtomic(&shared->cancelledTicket)) {
            if(edge)Observe(TraceStopped,seq,epoch,diagnosticType);
            InterlockedIncrement(&shared->stoppedRejected);return 0;
        }
        if(epoch==0 || epoch>static_cast<UINT>(InputEpochLimit) || seq==0 || seq>static_cast<UINT>(InputSequenceLimit)) {
            if(edge)Observe(TraceInvalid,seq,epoch,diagnosticType);
            InterlockedIncrement(&shared->invalidRejected);return 0;
        }
        UINT floor=static_cast<UINT>(ReadAtomic(&shared->minEpoch));
        if(floor>static_cast<UINT>(InputEpochLimit+1)) {if(edge)Observe(TraceInvalid,seq,epoch,diagnosticType);InterlockedIncrement(&shared->invalidRejected);InterlockedExchange(&shared->stop,1);return 0;}
        if(epoch<floor || epoch<localFloor) {
            if(edge)Observe(TraceStale,seq,epoch,diagnosticType);
            InterlockedIncrement(&shared->staleRejected);return 0;
        }
        UINT type=kind==0xFE ? WM_CANCELMODE : WM_MOUSEFIRST+kind;
        if(type!=WM_MOUSEMOVE && type!=WM_LBUTTONDOWN && type!=WM_LBUTTONUP
            && type!=WM_RBUTTONDOWN && type!=WM_RBUTTONUP && type!=WM_MBUTTONDOWN && type!=WM_MBUTTONUP
            && type!=WM_XBUTTONDOWN && type!=WM_XBUTTONUP && type!=WM_MOUSEWHEEL && type!=WM_MOUSEHWHEEL && type!=WM_CANCELMODE) return 0;
        lastEpoch=std::max(lastEpoch,epoch);
        POINT point{static_cast<SHORT>(LOWORD(lp)),static_cast<SHORT>(HIWORD(lp))};
        // Registered messages are not DPI-virtualized like native mouse messages.
        // Convert the host's physical client pixels to this projector's DPI space.
        // The host's unheld (-1,-1) leave sentinel is not an on-screen point.
        // Preserve it: an unsuccessful outside-window DPI conversion must not
        // turn it into a positive client point and retain a corner button hover.
        bool presentationLeave=type==WM_MOUSEMOVE && point.x==-1 && point.y==-1 && (flags&0x73)==0;
        if(!presentationLeave) {
            POINT origin{};
            ClientToScreen(hwnd,&origin);
            LogicalToPhysicalPointForPerMonitorDPI(hwnd,&origin);
            point.x+=origin.x; point.y+=origin.y;
            PhysicalToLogicalPointForPerMonitorDPI(hwnd,&point);
            ScreenToClient(hwnd,&point);
        }
        bool down=type==WM_LBUTTONDOWN || type==WM_RBUTTONDOWN || type==WM_MBUTTONDOWN || type==WM_XBUTTONDOWN;
        bool up=type==WM_LBUTTONUP || type==WM_RBUTTONUP || type==WM_MBUTTONUP || type==WM_XBUTTONUP;
        UINT bit=PacketButtonBit(type,extra);
        // Gesture ownership is classified, not trusted: a down for an already-held
        // button is a duplicate; an up/cancel without an open gesture is unowned.
        // Both are still forwarded so the projector's own button state can release.
        // The data envelope carries no gesture id: an admitted down opens the endpoint-owned
        // gesture; the matching release or a cancel closes it again.
        if(down) { if(bit && (buttons&bit)) InterlockedIncrement(&shared->duplicateDowns); activeGesture=1; SetFocus(hwnd); }
        if((up && (!activeGesture || !(buttons&bit))) || (type==WM_CANCELMODE && !activeGesture && !buttons))
            InterlockedIncrement(&shared->unownedReleases);
        { WriteLock guard; enabled=true; virtualPoint=point; buttons=flags&0x73; }
        InterlockedExchange(&shared->heldButtons,static_cast<LONG>(buttons));
        WPARAM nativeFlags=flags;
        LPARAM nativePosition=MAKELPARAM(static_cast<SHORT>(point.x),static_cast<SHORT>(point.y));
        if(type==WM_MOUSEWHEEL || type==WM_MOUSEHWHEEL) {
            nativeFlags=MAKEWPARAM(flags,extra);
            POINT screen=point; ClientToScreen(hwnd,&screen);
            nativePosition=MAKELPARAM(static_cast<SHORT>(screen.x),static_cast<SHORT>(screen.y));
        } else if(type==WM_XBUTTONDOWN || type==WM_XBUTTONUP) nativeFlags=MAKEWPARAM(flags,extra);
        if(type==WM_CANCELMODE) { WriteLock guard; buttons=0; captured=false; activeGesture=0; }
        else if(up && !buttons) activeGesture=0;
        // Activation can clear Flash's hover target. Re-establish the mapped
        // location after focus and before the button edge, on its own UI thread.
        if(down) Original(hwnd,WM_MOUSEMOVE,flags,nativePosition);
        if(edge)Observe(TraceEnter,seq,epoch,type,point);
        else if(static_cast<SHORT>(LOWORD(lp))<0 || static_cast<SHORT>(HIWORD(lp))<0)Observe(TraceLeave,seq,epoch,type,point);
        LRESULT result=Original(hwnd,type,nativeFlags,nativePosition);
        if(edge)Observe(TraceReturn,seq,epoch,type,point);
        InterlockedExchange(&shared->completedSeq,static_cast<LONG>(seq));
        return result;
}
LRESULT CALLBACK WindowProc(HWND hwnd,UINT message,WPARAM wp,LPARAM lp) {
    Depth depth(procedureDepth);
    if(message==packetMessage)return 0; // only the dequeue hook may admit data
    if(message==controlMessage) {
        if(!shared || static_cast<uint64_t>(lp)!=shared->session)return 0;
        UINT kind=static_cast<UINT>(wp);
        if(kind==ControlPoll) {CancelEndpoint();return 1;}
        if(kind==ControlQuiesce) {
            if(static_cast<LONG>(wp>>32)!=ReadAtomic(&shared->closeTicket))return 0;
            if(hookDepth || dispatchDepth || procedureDepth>1)return 0;
            CancelEndpoint();
            MSG queued{};
            if(PeekMessageW(&queued,target,packetMessage,packetMessage,PM_NOREMOVE))return 0;
            if(buttons || captured || activeGesture)return 0;
            LONG ticket=ReadAtomic(&shared->closeTicket);
            if(!ticket)return 0;
            InterlockedExchange(&shared->quiescedTicket,ticket);return 1;
        }
        if(kind==ControlRetire) {
            if(!ReadAtomic(&shared->stop) || static_cast<LONG>(wp>>32)!=ReadAtomic(&shared->closeTicket))return 0;
            return Restore() ? 1 : 0;
        }
        if(kind==ControlRepaint && !ReadAtomic(&shared->stop)) {
            LONG ticket=static_cast<LONG>(wp>>32);
            if(!ticket || ticket!=ReadAtomic(&shared->paintTicket))return 0;
            LONGLONG after=ReadAtomic64(&shared->paintRequestTicks);
            RECT bounds{};GetClientRect(hwnd,&bounds);
            if(lastPaintTicks<after || !EqualRect(&bounds,&lastPaintBounds))
                if(!RedrawWindow(hwnd,nullptr,nullptr,RDW_INVALIDATE|RDW_UPDATENOW|RDW_ALLCHILDREN))return 0;
            GdiFlush();
            if(lastPaintTicks<after || !EqualRect(&bounds,&lastPaintBounds))return 0;
            if(ticket!=ReadAtomic(&shared->paintTicket))return 0;
            InterlockedExchange64(&shared->paintResultTicks,lastPaintTicks);
            InterlockedExchange(&shared->paintAck,ticket);return 1;
        }
        return 0;
    }
    // Flash arms TrackMouseEvent after the mapped WM_MOUSEMOVE. The physical
    // pointer is over P, not this covered source F, so Windows immediately emits
    // a source-window LEAVE even when the mapped pointer remains over a button.
    // While mapped input owns hover, only the host's mapped outside point may
    // leave it. Actual focus/menu revocation below still disables this guard.
    if(enabled && message==WM_MOUSELEAVE) {
        Observe(TraceSourceLeaveSuppressed,0,lastEpoch,message,virtualPoint);
        return 0;
    }
    if(message==WM_MOUSELEAVE || message==WM_MOUSEHOVER || message==WM_CAPTURECHANGED || message==WM_SETFOCUS) {
        Observe(TraceNativePointer,0,lastEpoch,message,virtualPoint);
    }
    if(message==WM_ENTERMENULOOP || message==WM_KILLFOCUS) {
        { WriteLock guard; enabled=false; buttons=0; captured=false; activeGesture=0; }
        if(shared) {
            InterlockedExchange(&shared->heldButtons,0);
            UINT issued=static_cast<UINT>(ReadAtomic(&shared->issuedEpoch));
            if(issued>static_cast<UINT>(InputEpochLimit)) {InterlockedIncrement(&shared->invalidRejected);InterlockedExchange(&shared->stop,1);issued=InputEpochLimit;}
            UINT top=std::max(lastEpoch,issued);
            localFloor=std::max(localFloor,std::min(top+1,static_cast<UINT>(InputEpochLimit+2)));
            Observe(TraceFocusLost,0,issued,message);
        }
    }
    if(enabled && message==WM_MOUSEMOVE)return 0;
    LRESULT result=Original(hwnd,message,wp,lp);
    if(message==WM_PAINT) {
        LARGE_INTEGER painted{};QueryPerformanceCounter(&painted);
        lastPaintTicks=painted.QuadPart;GetClientRect(hwnd,&lastPaintBounds);
    }
    return result;
}
bool Initialize(HWND hwnd,uint64_t cookie) {
    WriteLock guard;
    if(target || shared || ReadAtomic(&wrapperDepth))return false;
    ATOM atom=static_cast<ATOM>(reinterpret_cast<UINT_PTR>(GetPropW(hwnd,InputProperty)));
    wchar_t name[160]{};
    if(!atom || !GlobalGetAtomNameW(atom,name,160)) return false;
    if(shared) { UnmapViewOfFile(shared); shared=nullptr; }
    if(mapping) { CloseHandle(mapping); mapping=nullptr; }
    mapping=OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,name);
    if(!mapping) return false;
    shared=static_cast<InputShared*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,sizeof(InputShared)));
    // Protocol negotiation: a version mix must fail loudly. MapViewOfFile also
    // fails outright when the broker's section is smaller than this v3 view.
    if(!shared) { CloseHandle(mapping); mapping=nullptr; return false; }
    if(shared->magic!=InputMagic || shared->protocolVersion!=InputProtocolVersion) {
        InterlockedExchange(&shared->ready,-3);
        return false;
    }
    if(shared->session!=cookie) { UnmapViewOfFile(shared);shared=nullptr;CloseHandle(mapping);mapping=nullptr;return false; }
    DWORD ownerPid=0; GetWindowThreadProcessId(reinterpret_cast<HWND>(shared->ownerWindow),&ownerPid);
    if(shared->sourcePid!=GetCurrentProcessId()
        || shared->session!=cookie || !cookie
        || shared->sourceWindow!=reinterpret_cast<uint64_t>(hwnd) || ownerPid!=shared->hostPid || shared->stop || shared->stopped) {
        InterlockedExchange(&shared->ready,-4);
        return false;
    }
    HMODULE priorModule=nullptr;
    auto prior=GetWindowLongPtrW(hwnd,GWLP_WNDPROC);
    if(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(prior),&priorModule)) {
        wchar_t priorPath[MAX_PATH]{};GetModuleFileNameW(priorModule,priorPath,MAX_PATH);
        const wchar_t* leaf=wcsrchr(priorPath,L'\\');leaf=leaf ? leaf+1 : priorPath;
        if(_wcsicmp(leaf,L"FlashInputBridge.dll")==0) {InterlockedExchange(&shared->ready,-6);return false;}
    }
    target=hwnd;
    std::wstring traceName=std::wstring(name)+L".trace";
    traceMapping=OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,traceName.c_str());
    if(traceMapping) {
        traceState=static_cast<InputTraceShared*>(MapViewOfFile(traceMapping,FILE_MAP_ALL_ACCESS,0,0,sizeof(InputTraceShared)));
        if(!traceState || traceState->magic!=InputTraceMagic || traceState->version!=1 || traceState->session!=cookie) {
            if(traceState)UnmapViewOfFile(traceState);traceState=nullptr;CloseHandle(traceMapping);traceMapping=nullptr;
        }
    }
    targetThread=GetCurrentThreadId();lastCursorTrace=0;lastCursorKind=0;
    lastPaintTicks=0; lastPaintBounds={};
    lastEpoch=0; localFloor=0;
    // The subclass and import wrappers must remain mapped until process exit even
    // if the owner dies while a callback is still unwinding.
    HMODULE pinned=nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&WindowProc),&pinned);
    originalProc=reinterpret_cast<WNDPROC>(SetWindowLongPtrW(hwnd,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(WindowProc)));
    if(!originalProc) { InterlockedExchange(&shared->ready,-1); return false; }
    InstallImports();
    if(ReadAtomic(&shared->stop)) { InterlockedExchange(&shared->ready,-5); return false; }
    // This projector imports GetCursorPos/GetKeyState and the capture family;
    // GetMessagePos/GetAsyncKeyState are optional on other projector versions.
    bool complete=(shared->patchMask&121)==121;
    Observe(TraceReady);
    InterlockedExchange(&shared->ready,complete ? 1 : -2);
    // Failed installation remains owned until an explicit retirement succeeds.
    return true;
}
}
#ifdef CF7_INPUT_BRIDGE_SELFTEST
// InputBridgeSelfTest.exe compiles this translation unit with these entry
// points to drive the real WindowProc and module state against a real window
// and shared section. The shipping FlashInputBridge.dll build never defines
// the macro; production behavior is unchanged.
namespace InputBridgeSelfTest {
    // Installs the real WindowProc as the window's subclass, mirroring the
    // production Initialize path; OS messages (WM_SETFOCUS/WM_KILLFOCUS and the
    // like) then flow through the bridge exactly as they do in the projector.
    void Install(HWND hwnd,InputShared* state,UINT message) {
        target=hwnd; shared=state; packetMessage=message;
        enabled=false; buttons=0; captured=false; activeGesture=0;
        lastEpoch=0; localFloor=0;
        if(!originalProc)
            originalProc=reinterpret_cast<WNDPROC>(SetWindowLongPtrW(hwnd,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(&WindowProc)));
    }
    LRESULT Drive(UINT message,WPARAM wp,LPARAM lp) { return message==packetMessage ? Deliver(target,wp,lp) : WindowProc(target,message,wp,lp); }
    UINT LocalFloor() { return localFloor; }
    UINT LastEpoch() { return lastEpoch; }
    UINT Gesture() { return activeGesture; }
}
#endif
extern "C" __declspec(dllexport) LRESULT CALLBACK InputHook(int code,WPARAM wp,LPARAM lp) {
    if(code<0)return CallNextHookEx(nullptr,code,wp,lp);
    Depth depth(hookDepth);
    if(!packetMessage)packetMessage=RegisterWindowMessageW(InputMessage);
    if(!controlMessage)controlMessage=RegisterWindowMessageW(InputControlMessage);
    auto msg=reinterpret_cast<MSG*>(lp);
    UINT id=msg->message; HWND hwnd=msg->hwnd; WPARAM data=msg->wParam; LPARAM argument=msg->lParam;
    if(id==packetMessage || id==controlMessage) {
        // Clear BEFORE any potentially reentrant original call. Even a retained
        // PeekMessage(PM_NOREMOVE) copy cannot later dispatch this protocol.
        msg->message=WM_NULL;msg->wParam=0;msg->lParam=0;
        if(wp==PM_REMOVE) {
            if(id==controlMessage && data==ControlInit && !target)Initialize(hwnd,static_cast<uint64_t>(argument));
            else if(id==packetMessage && target==hwnd)Deliver(hwnd,data,argument);
        }
    } else if(shared)CancelEndpoint();
    return CallNextHookEx(nullptr,code,wp,lp);
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID) { if(reason==DLL_PROCESS_ATTACH)DisableThreadLibraryCalls(module);return TRUE; }
