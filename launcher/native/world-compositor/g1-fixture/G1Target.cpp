// G1Target.exe: G1 工单跨进程夹具的目标进程（不进正式 runtime 闭包）。
// 真实顶层窗口→跨进程 SetParent 嵌入 Host 的 owner 窗口（镜像生产 Flash 嵌入拓扑，
// 满足 InputBroker 的 GetAncestor(GA_ROOT)==owner 合同）。真实消息泵；原窗口过程
// 把每条 WM_MOUSE*/WM_SETFOCUS/WM_KILLFOCUS 记入本地日志（=桥交付层的真证据）。
// UI 线程受控睡眠经 --stall 标志文件：文件存在期间不取消息，模拟队列积压。
// 命令经注册消息 "CF7.G1.Cmd" 发到子窗口：wParam 1=SetFocus 自聚焦 2=退出 3=log 标记。
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstdint>
#include <cstdarg>
#include <cstdlib>
#include <cwchar>
#include <share.h>

namespace {
FILE* gLog=nullptr;
HWND gChild=nullptr, gOwner=nullptr;
WNDPROC gPrior=nullptr;
MSG gSaved{};bool gHasSaved=false;
volatile LONG gStopReader=0,gReaderCalls=0;
DWORD WINAPI ReadImports(LPVOID) {
    while(!InterlockedCompareExchange(&gStopReader,0,0)) {
        POINT p{};GetCursorPos(&p);GetAsyncKeyState(VK_LBUTTON);GetCapture();
        InterlockedIncrement(&gReaderCalls);Sleep(1);
    }
    return 0;
}
LRESULT CALLBACK ConflictProc(HWND h,UINT m,WPARAM w,LPARAM l) {return CallWindowProcW(gPrior,h,m,w,l);}
UINT gCmdMsg=0, gFillerMsg=0;
wchar_t gStall[MAX_PATH]{}, gFocusKill[MAX_PATH]{};
uint64_t gSeq=0;
bool gInStall=false, gFocusKillDone=false;
int gRenderPercent=100,gPaintTick=0;
int gGeometryOffsetY=0;bool gGeometryPaint=false;
DWORD gStallStart=0, gLastBeat=0;
DWORD gFillerCount=0;
DWORD gOtherMsg=0; uint64_t gOtherCount=0;

void FlushCounters() {
    if(gFillerCount) { std::fprintf(gLog,"%08llu t=%llu FILLER x%lu\n",(unsigned long long)gSeq++,(unsigned long long)GetTickCount64(),(unsigned long)gFillerCount); gFillerCount=0; }
    if(gOtherCount) { std::fprintf(gLog,"%08llu t=%llu OTHER msg=0x%04lX x%llu\n",(unsigned long long)gSeq++,(unsigned long long)GetTickCount64(),(unsigned long)gOtherMsg,(unsigned long long)gOtherCount); gOtherCount=0; }
}
void Log(const char* fmt,...) {
    FlushCounters();
    std::fprintf(gLog,"%08llu t=%llu ",(unsigned long long)gSeq++,(unsigned long long)GetTickCount64());
    va_list ap; va_start(ap,fmt); std::vfprintf(gLog,fmt,ap); va_end(ap);
    std::fputc('\n',gLog); std::fflush(gLog);
}
bool StallOn() { return gStall[0] && GetFileAttributesW(gStall)!=INVALID_FILE_ATTRIBUTES; }
// 停泵期间的真实失焦：把焦点从子窗移回 owner。同线程 SetFocus 会同步派发
// WM_KILLFOCUS 给当前焦点窗（子窗），穿过桥 patched proc → localFloor 当场抬升，
// 不需要泵消息——这是"焦点离开"能先于在队旧包生效的唯一真实机制（跨队列激活
// 失活实测不给外部线程子窗发 KILLFOCUS，焦点簿记保留）。跨线程 SetFocus 需合并
// 输入队列：瞬时 AttachThreadInput 到 owner 所在线程（本线程发起、本线程释放，
// 宿主线程零阻塞）。
void MaybeFocusKill() {
    bool present=gFocusKill[0] && GetFileAttributesW(gFocusKill)!=INVALID_FILE_ATTRIBUTES;
    if(!present) { gFocusKillDone=false; return; }
    if(gFocusKillDone) return;
    gFocusKillDone=true;
    DWORD ownerTid=GetWindowThreadProcessId(gOwner,nullptr);
    BOOL at=AttachThreadInput(GetCurrentThreadId(),ownerTid,TRUE);
    SetLastError(0); HWND prev=SetFocus(gOwner); DWORD err=GetLastError();
    if(at) AttachThreadInput(GetCurrentThreadId(),ownerTid,FALSE);
    Log("FOCUSKILL attach=%d prev=0x%p focus=0x%p err=%lu",(int)at,(void*)prev,(void*)GetFocus(),err);
    DeleteFileW(gFocusKill);
}
void FitToParent() {
    RECT rc{}; if(gOwner && GetClientRect(gOwner,&rc) && rc.right>0 && rc.bottom>0) {
        rc.right=MulDiv(rc.right,gRenderPercent,100);rc.bottom=MulDiv(rc.bottom,gRenderPercent,100);
        RECT me{}; GetWindowRect(gChild,&me);
        POINT tl{}; ClientToScreen(gOwner,&tl);
        if(me.left!=tl.x || me.top!=tl.y+gGeometryOffsetY || me.right-me.left!=rc.right || me.bottom-me.top!=rc.bottom)
            MoveWindow(gChild,0,gGeometryOffsetY,rc.right,rc.bottom,FALSE);
    }
}
// 桥 InstallImports 包装投影器主模块 user32 IAT：目标二进制必须真实含这些导入槽
// （GetCursorPos/GetMessagePos/GetAsyncKeyState/GetKeyState/SetCapture/GetCapture/
// ReleaseCapture），否则 patchMask=0 → ready=-2。只取址不调用，镜像真实投影器的导入面。
volatile ULONG_PTR gImportSink[8];
void TouchImports() {
    gImportSink[0]=(ULONG_PTR)&GetCursorPos;
    gImportSink[1]=(ULONG_PTR)&GetMessagePos;
    gImportSink[2]=(ULONG_PTR)&GetAsyncKeyState;
    gImportSink[3]=(ULONG_PTR)&GetKeyState;
    gImportSink[4]=(ULONG_PTR)&SetCapture;
    gImportSink[5]=(ULONG_PTR)&GetCapture;
    gImportSink[6]=(ULONG_PTR)&ReleaseCapture;
}
const char* MsgName(UINT m) {
    switch(m) {
        case WM_MOUSEMOVE:return "MOUSEMOVE"; case WM_LBUTTONDOWN:return "LBUTTONDOWN";
        case WM_LBUTTONUP:return "LBUTTONUP"; case WM_RBUTTONDOWN:return "RBUTTONDOWN";
        case WM_RBUTTONUP:return "RBUTTONUP"; case WM_MBUTTONDOWN:return "MBUTTONDOWN";
        case WM_MBUTTONUP:return "MBUTTONUP"; case WM_MOUSEWHEEL:return "MOUSEWHEEL";
        case WM_XBUTTONDOWN:return "XBUTTONDOWN"; case WM_XBUTTONUP:return "XBUTTONUP";
        case WM_MOUSEHWHEEL:return "MOUSEHWHEEL"; case WM_CANCELMODE:return "CANCELMODE";
        case WM_SETFOCUS:return "SETFOCUS"; case WM_KILLFOCUS:return "KILLFOCUS";
        case WM_NCDESTROY:return "NCDESTROY"; case WM_ACTIVATE:return "ACTIVATE";
        case WM_MOUSEACTIVATE:return "MOUSEACTIVATE"; case WM_PAINT:return "PAINT";
        default:return nullptr;
    }
}
LRESULT CALLBACK ChildProc(HWND hwnd,UINT message,WPARAM wp,LPARAM lp) {
    if(message==WM_TIMER && wp==71) {gPaintTick++;InvalidateRect(hwnd,nullptr,FALSE);return 0;}
    if(message==WM_PAINT && gGeometryPaint) {
        PAINTSTRUCT paint{};HDC dc=BeginPaint(hwnd,&paint);RECT r{};GetClientRect(hwnd,&r);
        HBRUSH color=CreateSolidBrush(RGB(31,173,89));FillRect(dc,&r,color);DeleteObject(color);
        RECT marker{0,0,20,20};FillRect(dc,&marker,GetSysColorBrush(gPaintTick%2 ? COLOR_WINDOW : COLOR_WINDOWTEXT));
        EndPaint(hwnd,&paint);return 0;
    }
    if(message==gFillerMsg) { gFillerCount++; return 0; }
    if(message==gCmdMsg) {
        if(wp==11) {gGeometryPaint=true;gRenderPercent=static_cast<int>(lp);FitToParent();SetTimer(hwnd,71,50,nullptr);InvalidateRect(hwnd,nullptr,FALSE);return 0;}
        if(wp==12) {gGeometryOffsetY=static_cast<int>(lp);FitToParent();InvalidateRect(hwnd,nullptr,FALSE);return 0;}
        if(wp==10) {gHasSaved=PeekMessageW(&gSaved,gChild,RegisterWindowMessageW(L"CF7.WorldPointer.Packet.v4"),RegisterWindowMessageW(L"CF7.WorldPointer.Packet.v4"),PM_NOREMOVE)!=FALSE;Log("PEEK_SAVED present=%d msg=%u",gHasSaved,gSaved.message);return 0;}
        if(wp==9) {if(gHasSaved){Log("REPLAY_SAVED msg=%u",gSaved.message);DispatchMessageW(&gSaved);gHasSaved=false;}return 0;}
        if(wp==7) {gPrior=reinterpret_cast<WNDPROC>(SetWindowLongPtrW(hwnd,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(ConflictProc)));Log("RESTORE_CONFLICT_INSTALLED");return 0;}
        if(wp==1) { HWND before=GetFocus(); HWND r=SetFocus(gChild);
            Log("CMD FOCUS ret=0x%p focus_before=0x%p focus_after=0x%p err=%lu fg=0x%p",
                (void*)r,(void*)before,(void*)GetFocus(),GetLastError(),(void*)GetForegroundWindow()); }
        else if(wp==2) { Log("CMD EXIT"); FlushCounters(); PostQuitMessage(0); }
        else if(wp==3) { Log("MARK lp=%lld",(long long)lp); }
        else if(wp==4) { Log("CMD WAKE"); } // 唤醒阻塞的 GetMessage，让泵立刻看到 stall 标志
        return 0;
    }
    const char* name=MsgName(message);
    if(name) {
        if(message==WM_SETFOCUS||message==WM_KILLFOCUS)
            Log("%s wp_hwnd=0x%p focus=0x%p fg=0x%p",name,(void*)wp,(void*)GetFocus(),(void*)GetForegroundWindow());
        else if(message==WM_ACTIVATE||message==WM_MOUSEACTIVATE)
            Log("%s wp=0x%llX lp=0x%llX fg=0x%p",name,(unsigned long long)wp,(unsigned long long)lp,(void*)GetForegroundWindow());
        else
            Log("%s wp=0x%llX x=%d y=%d fg=0x%p",name,(unsigned long long)wp,
                (int)(short)(lp&0xFFFF),(int)(short)((lp>>16)&0xFFFF),(void*)GetForegroundWindow());
    } else if(message==WM_NCDESTROY) { Log("NCDESTROY"); }
    else { if(message!=gOtherMsg){FlushCounters();gOtherMsg=message;} gOtherCount++; }
    if(message==WM_NCDESTROY) { FlushCounters(); PostQuitMessage(0); }
    return DefWindowProcW(hwnd,message,wp,lp);
}
int Fail(const char* why) { if(gLog){Log("FAIL %s err=%lu",why,GetLastError());std::fclose(gLog);} return 4; }
}

int wmain(int argc,wchar_t** argv) {
    const wchar_t* logPath=nullptr; const wchar_t* hwndFile=nullptr;bool stress=false;
    for(int i=1;i+1<argc;i+=2) {
        if(!wcscmp(argv[i],L"--stress-iat"))stress=wcstoul(argv[i+1],nullptr,10)!=0;
        else if(!wcscmp(argv[i],L"--owner")) gOwner=(HWND)_wcstoui64(argv[i+1],nullptr,10);
        else if(!wcscmp(argv[i],L"--log")) logPath=argv[i+1];
        else if(!wcscmp(argv[i],L"--stall")) wcscpy_s(gStall,argv[i+1]);
        else if(!wcscmp(argv[i],L"--focuskill")) wcscpy_s(gFocusKill,argv[i+1]);
        else if(!wcscmp(argv[i],L"--hwndfile")) hwndFile=argv[i+1];
    }
    if(!gOwner||!logPath||!hwndFile) return 2;
    TouchImports();
    // _SH_DENYNO：驱动进程要实时尾随本日志做分层断言。
    gLog=_wfsopen(logPath,L"wb",_SH_DENYNO); if(!gLog) return 3;
    setvbuf(gLog,nullptr,_IONBF,0);
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    gCmdMsg=RegisterWindowMessageW(L"CF7.G1.Cmd");
    gFillerMsg=RegisterWindowMessageW(L"CF7.G1.Filler");
    DWORD pid=GetCurrentProcessId(), tid=GetCurrentThreadId();
    Log("BOOT pid=%lu tid=%lu owner=0x%p",pid,tid,(void*)gOwner);

    WNDCLASSW wc{}; wc.lpfnWndProc=ChildProc; wc.hInstance=GetModuleHandleW(nullptr);
    wc.lpszClassName=L"CF7.G1Target"; wc.hbrBackground=(HBRUSH)(COLOR_WINDOW+1);
    if(!RegisterClassW(&wc)) return Fail("register_class");

    // 生产拓扑：Flash 源窗是宿主顶层窗的跨进程子窗口。先建真实顶层窗再 SetParent；
    // 若环境拒收跨进程 SetParent，退回直接以 owner 为父创建 WS_CHILD。
    gChild=CreateWindowExW(0,wc.lpszClassName,L"g1-target",WS_OVERLAPPED|WS_VISIBLE,
        0,0,100,80,nullptr,nullptr,wc.hInstance,nullptr);
    if(!gChild) return Fail("create_toplevel");
    Log("CREATE_TOP hwnd=0x%p",(void*)gChild);
    if(!SetParent(gChild,gOwner)) {
        DestroyWindow(gChild);
        gChild=CreateWindowExW(0,wc.lpszClassName,L"g1-target",WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS,
            0,0,100,80,gOwner,nullptr,wc.hInstance,nullptr);
        if(!gChild) return Fail("create_child");
        Log("CREATE_CHILD hwnd=0x%p",(void*)gChild);
    } else {
        SetWindowLongW(gChild,GWL_STYLE,WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS);
        Log("REPARENT hwnd=0x%p parent=0x%p",(void*)gChild,(void*)GetParent(gChild));
    }
    HWND root=GetAncestor(gChild,GA_ROOT);
    Log("TOPOLOGY hwnd=0x%p parent=0x%p root=0x%p rootIsOwner=%d",
        (void*)gChild,(void*)GetParent(gChild),(void*)root,root==gOwner?1:0);
    if(root!=gOwner) return Fail("root_not_owner");
    FitToParent();
    ShowWindow(gChild,SW_SHOW);

    FILE* hf=nullptr; _wfopen_s(&hf,hwndFile,L"wb");
    if(hf) { std::fprintf(hf,"child=%llu pid=%lu tid=%lu owner=%llu\n",
        (unsigned long long)(uintptr_t)gChild,pid,tid,(unsigned long long)(uintptr_t)gOwner); std::fclose(hf); }
    Log("PUMP_START child=0x%p",(void*)gChild);

    HANDLE reader=stress ? CreateThread(nullptr,0,ReadImports,nullptr,0,nullptr) : nullptr;
    MSG m;
    for(;;) {
        if(StallOn()) {
            if(!gInStall) { gInStall=true; gStallStart=GetTickCount(); gLastBeat=0; Log("STALL_BEGIN"); }
            DWORD held=GetTickCount()-gStallStart;
            if(held>=20000) { Log("STALL_AUTOEXPIRE heldMs=%lu",held); DeleteFileW(gStall); continue; } // 安全阀防卡死
            MaybeFocusKill();
            if(GetTickCount()-gLastBeat>=500) { gLastBeat=GetTickCount(); Log("STALL tick"); }
            Sleep(40); continue;
        }
        if(gInStall) { gInStall=false; Log("STALL_END heldMs=%lu",GetTickCount()-gStallStart); }
        int got=GetMessageW(&m,nullptr,0,0);
        if(got<=0) break;
        TranslateMessage(&m); DispatchMessageW(&m);
        FitToParent();
    }
    FlushCounters();
    if(reader){InterlockedExchange(&gStopReader,1);WaitForSingleObject(reader,3000);CloseHandle(reader);Log("IAT_READER calls=%ld",gReaderCalls);}
    Log("EXIT");
    std::fclose(gLog);
    return 0;
}
