#define WIN32_LEAN_AND_MEAN
#include "InputBridge.h"
#include <cstring>

// Loaded by a thread-specific hook into the paired x64 projector only. No
// global process injection, cursor warping, polling thread, or AS2 script work.
namespace {
HWND target=nullptr;
WNDPROC originalProc=nullptr;
InputShared* shared=nullptr;
HANDLE mapping=nullptr;
UINT packetMessage=0;
POINT virtualPoint{};
UINT buttons=0;
bool enabled=false, captured=false;
LONGLONG lastPaintTicks=0;
RECT lastPaintBounds{};
struct Patch { ULONG_PTR* slot; ULONG_PTR original; } patches[32]{};
int patchCount=0;
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
    if(!enabled || !target) return realCursor(point);
    if(!point) return FALSE;
    *point=virtualPoint; ClientToScreen(target,point);
    if(shared) InterlockedIncrement(&shared->cursorReads);
    return TRUE;
}
DWORD WINAPI Position() {
    if(!enabled) return realPosition();
    POINT point=virtualPoint; ClientToScreen(target,&point);
    return MAKELONG(static_cast<WORD>(point.x),static_cast<WORD>(point.y));
}
SHORT KeyValue(int key,KeyProc fallback) {
    int mask=ButtonMask(key);
    if(!enabled || !mask) return fallback(key);
    if(shared) InterlockedIncrement(&shared->keyReads);
    return (buttons&mask)!=0 ? static_cast<SHORT>(0x8000) : 0;
}
SHORT WINAPI Async(int key) { return KeyValue(key,realAsync); }
SHORT WINAPI Key(int key) { return KeyValue(key,realKey); }
HWND WINAPI Capture(HWND hwnd) {
    if(enabled && hwnd==target) { HWND previous=captured ? target : realGetCapture(); captured=true; return previous; }
    return realCapture(hwnd);
}
HWND WINAPI GetCapture() { return enabled && captured ? target : realGetCapture(); }
BOOL WINAPI Release() { if(enabled) { captured=false; return TRUE; } return realRelease(); }

bool PatchSlot(ULONG_PTR* slot,ULONG_PTR replacement) {
    if(patchCount>=32) return false;
    DWORD old=0;
    if(!VirtualProtect(slot,sizeof(*slot),PAGE_READWRITE,&old)) return false;
    patches[patchCount++]={slot,*slot}; *slot=replacement;
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
void Restore() {
    enabled=false; buttons=0; captured=false;
    if(target && originalProc && IsWindow(target)) SetWindowLongPtrW(target,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(originalProc));
    for(int i=patchCount-1;i>=0;i--) {
        DWORD old=0;
        if(VirtualProtect(patches[i].slot,sizeof(ULONG_PTR),PAGE_READWRITE,&old)) {
            *patches[i].slot=patches[i].original;
            DWORD ignored=0; VirtualProtect(patches[i].slot,sizeof(ULONG_PTR),old,&ignored);
        }
    }
    patchCount=0;
    if(shared) InterlockedExchange(&shared->stopped,1);
    target=nullptr;
}
LRESULT CALLBACK WindowProc(HWND hwnd,UINT message,WPARAM wp,LPARAM lp) {
    if(message==packetMessage) {
        UINT kind=static_cast<UINT>(wp)&255, flags=(static_cast<UINT>(wp)>>8)&127, extra=HIWORD(wp);
        if(kind==0xFD) return 0;
        if(kind==0xFF) { Restore(); return 0; }
        if(kind==0xFC) {
            // MoveWindow(TRUE) usually already painted this viewport. Reuse that
            // completion instead of forcing a second full Flash rasterization.
            RECT bounds{}; GetClientRect(hwnd,&bounds);
            if(lastPaintTicks<lp || !EqualRect(&bounds,&lastPaintBounds)) {
                if(!RedrawWindow(hwnd,nullptr,nullptr,RDW_INVALIDATE|RDW_UPDATENOW|RDW_ALLCHILDREN)) return 0;
            }
            GdiFlush();
            if(lastPaintTicks<lp || !EqualRect(&bounds,&lastPaintBounds)) return 0;
            return static_cast<LRESULT>(lastPaintTicks);
        }
        UINT type=kind==0xFE ? WM_CANCELMODE : WM_MOUSEFIRST+kind;
        if(type!=WM_MOUSEMOVE && type!=WM_LBUTTONDOWN && type!=WM_LBUTTONUP
            && type!=WM_RBUTTONDOWN && type!=WM_RBUTTONUP && type!=WM_MBUTTONDOWN && type!=WM_MBUTTONUP
            && type!=WM_XBUTTONDOWN && type!=WM_XBUTTONUP && type!=WM_MOUSEWHEEL && type!=WM_MOUSEHWHEEL && type!=WM_CANCELMODE) return 0;
        virtualPoint={static_cast<SHORT>(LOWORD(lp)),static_cast<SHORT>(HIWORD(lp))};
        // Registered messages are not DPI-virtualized like native mouse messages.
        // Convert the host's physical client pixels to this projector's DPI space.
        POINT origin{};
        ClientToScreen(hwnd,&origin);
        LogicalToPhysicalPointForPerMonitorDPI(hwnd,&origin);
        virtualPoint.x+=origin.x; virtualPoint.y+=origin.y;
        PhysicalToLogicalPointForPerMonitorDPI(hwnd,&virtualPoint);
        ScreenToClient(hwnd,&virtualPoint);
        bool down=type==WM_LBUTTONDOWN || type==WM_RBUTTONDOWN || type==WM_MBUTTONDOWN || type==WM_XBUTTONDOWN;
        if(down) SetFocus(hwnd);
        enabled=true;
        buttons=flags;
        WPARAM nativeFlags=buttons;
        LPARAM nativePosition=MAKELPARAM(static_cast<SHORT>(virtualPoint.x),static_cast<SHORT>(virtualPoint.y));
        if(type==WM_MOUSEWHEEL || type==WM_MOUSEHWHEEL) {
            nativeFlags=MAKEWPARAM(buttons,extra);
            POINT screen=virtualPoint; ClientToScreen(hwnd,&screen);
            nativePosition=MAKELPARAM(static_cast<SHORT>(screen.x),static_cast<SHORT>(screen.y));
        } else if(type==WM_XBUTTONDOWN || type==WM_XBUTTONUP) nativeFlags=MAKEWPARAM(buttons,extra);
        if(type==WM_CANCELMODE) { buttons=0; captured=false; }
        // Activation can clear Flash's hover target. Re-establish the mapped
        // location after focus and before the button edge, on its own UI thread.
        if(down) CallWindowProcW(originalProc,hwnd,WM_MOUSEMOVE,buttons,nativePosition);
        return CallWindowProcW(originalProc,hwnd,type,nativeFlags,nativePosition);
    }
    if(message==WM_ENTERMENULOOP || message==WM_KILLFOCUS) { enabled=false; buttons=0; captured=false; }
    if(message==WM_NCDESTROY) {
        WNDPROC proc=originalProc; Restore(); return CallWindowProcW(proc,hwnd,message,wp,lp);
    }
    // Physical motion updates the desktop pointer normally. When the renderer owns
    // this gesture only the tagged, mapped packet may update the projector's pointer.
    if(enabled && message==WM_MOUSEMOVE) return 0;
    LRESULT result=CallWindowProcW(originalProc,hwnd,message,wp,lp);
    if(message==WM_PAINT) {
        LARGE_INTEGER painted{}; QueryPerformanceCounter(&painted);
        lastPaintTicks=painted.QuadPart; GetClientRect(hwnd,&lastPaintBounds);
    }
    return result;
}
bool Initialize(HWND hwnd) {
    ATOM atom=static_cast<ATOM>(reinterpret_cast<UINT_PTR>(GetPropW(hwnd,InputProperty)));
    wchar_t name[160]{};
    if(!atom || !GlobalGetAtomNameW(atom,name,160)) return false;
    if(shared) { UnmapViewOfFile(shared); shared=nullptr; }
    if(mapping) { CloseHandle(mapping); mapping=nullptr; }
    mapping=OpenFileMappingW(FILE_MAP_ALL_ACCESS,FALSE,name);
    if(!mapping) return false;
    shared=static_cast<InputShared*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,sizeof(InputShared)));
    DWORD ownerPid=0; GetWindowThreadProcessId(reinterpret_cast<HWND>(shared ? shared->ownerWindow : 0),&ownerPid);
    if(!shared || shared->magic!=InputMagic || shared->sourcePid!=GetCurrentProcessId()
        || shared->sourceWindow!=reinterpret_cast<uint64_t>(hwnd) || ownerPid!=shared->hostPid || shared->stop || shared->stopped) return false;
    target=hwnd;
    lastPaintTicks=0; lastPaintBounds={};
    // The subclass and import wrappers must remain mapped until process exit even
    // if the owner dies while a callback is still unwinding.
    HMODULE pinned=nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&WindowProc),&pinned);
    originalProc=reinterpret_cast<WNDPROC>(SetWindowLongPtrW(hwnd,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(WindowProc)));
    if(!originalProc) { InterlockedExchange(&shared->ready,-1); return false; }
    InstallImports();
    if(shared->stop) { Restore(); return false; }
    // This projector imports GetCursorPos/GetKeyState and the capture family;
    // GetMessagePos/GetAsyncKeyState are optional on other projector versions.
    bool complete=(shared->patchMask&121)==121;
    InterlockedExchange(&shared->ready,complete ? 1 : -2);
    if(!complete) Restore();
    return true;
}
}
extern "C" __declspec(dllexport) LRESULT CALLBACK InputHook(int code,WPARAM wp,LPARAM lp) {
    if(code>=0) {
        if(!packetMessage) packetMessage=RegisterWindowMessageW(InputMessage);
        auto message=reinterpret_cast<MSG*>(lp);
        if(!target && message->message==packetMessage) Initialize(message->hwnd);
        if(shared && shared->stop && !shared->stopped) Restore();
    }
    return CallNextHookEx(nullptr,code,wp,lp);
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID) { if(reason==DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(module); return TRUE; }
