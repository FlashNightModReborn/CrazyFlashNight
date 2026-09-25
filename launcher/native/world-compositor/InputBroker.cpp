#define WIN32_LEAN_AND_MEAN
#include "InputBridge.h"
#include "InputTrace.h"
#include <cstdio>
#include <cwchar>
#include <string>

struct Handle { HANDLE value=nullptr; ~Handle(){if(value)CloseHandle(value);} };
struct TraceCollector {
    Handle mapping;InputTraceShared* view=nullptr;LONG64 next=1,lost=0;
    ~TraceCollector(){if(view)UnmapViewOfFile(view);}
    void Open(const std::wstring& name,uint64_t cookie) {
        wchar_t enabled[8]{};
        if(GetEnvironmentVariableW(L"CF7_FOCUS_TRACE",enabled,8)!=1 || enabled[0]!=L'1')return;
        mapping.value=CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,sizeof(InputTraceShared),(name+L".trace").c_str());
        if(!mapping.value || GetLastError()==ERROR_ALREADY_EXISTS)return;
        view=static_cast<InputTraceShared*>(MapViewOfFile(mapping.value,FILE_MAP_ALL_ACCESS,0,0,sizeof(InputTraceShared)));
        if(view){*view={};view->magic=InputTraceMagic;view->version=1;view->session=cookie;}
    }
    void Drain() {
        if(!view)return;
        LONG64 end=ReadAtomic64(&view->produced);
        if(end-next>=InputTraceCapacity) {
            LONG64 skip=end-next-InputTraceCapacity+1;lost+=skip;next+=skip;
            std::printf("TRACE_GAP session=%llu skipped=%lld totalLost=%lld\n",view->session,skip,lost);
        }
        LARGE_INTEGER frequency{};QueryPerformanceFrequency(&frequency);
        for(;next<=end;next++) {
            InputTraceSnapshot r{};if(!TraceRead(view,next,r))break;
            std::printf("TRACE session=%llu ordinal=%lld qpc=%lld frequency=%lld stage=%ld seq=%ld epoch=%ld msg=0x%lX x=%ld y=%ld buttons=%ld localFloor=%ld focus=0x%llX\n",
                view->session,r.serial,r.ticks,frequency.QuadPart,r.stage,r.sequence,r.epoch,r.message,r.x,r.y,r.buttons,r.floor,r.focus);
        }
        std::fflush(stdout);
    }
};
int wmain(int argc,wchar_t** argv) {
    if(argc!=5)return 2;
    HWND source=reinterpret_cast<HWND>(wcstoull(argv[1],nullptr,10));
    DWORD hostPid=wcstoul(argv[2],nullptr,10);
    HWND owner=reinterpret_cast<HWND>(wcstoull(argv[3],nullptr,10));
    uint64_t cookie=wcstoull(argv[4],nullptr,10);
    DWORD pid=0,ownerPid=0; DWORD thread=GetWindowThreadProcessId(source,&pid);
    GetWindowThreadProcessId(owner,&ownerPid);
    if(!cookie || !thread || pid==hostPid || ownerPid!=hostPid || GetAncestor(source,GA_ROOT)!=owner)return 3;
    Handle host{OpenProcess(SYNCHRONIZE,FALSE,hostPid)}, process{OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid)};
    if(!host.value || !process.value)return 4;
    BOOL wow=FALSE; FILETIME created{},exited{},kernel{},user{};
    if(!IsWow64Process(process.value,&wow) || wow || !GetProcessTimes(process.value,&created,&exited,&kernel,&user))return 8;
    uint64_t birth=(static_cast<uint64_t>(created.dwHighDateTime)<<32)|created.dwLowDateTime;
    // Stable across cooperating protocol versions, unique to the projector
    // process INSTANCE. A crashed owner is not evidence of successful restore.
    std::wstring lockName=L"Local\\CF7.WorldPointer.Owner."+std::to_wstring(pid)+L"."+std::to_wstring(birth);
    Handle exclusive{CreateMutexW(nullptr,FALSE,lockName.c_str())};
    if(!exclusive.value)return 9;
    DWORD acquired=WaitForSingleObject(exclusive.value,0);
    if(acquired==WAIT_ABANDONED) {
        std::puts("FAIL ClosedUnconfirmed abandoned_owner");std::fflush(stdout);
        WaitForSingleObject(process.value,INFINITE);ReleaseMutex(exclusive.value);return 10;
    }
    if(acquired!=WAIT_OBJECT_0) {std::puts("FAIL owner_busy");return 11;}
    if(GetPropW(source,InputProperty) || GetPropW(source,L"CF7.WorldPointer.Map.v3")) {ReleaseMutex(exclusive.value);return 12;}
    std::wstring name=L"Local\\CF7.WorldPointer."+std::to_wstring(pid)+L"."+std::to_wstring(GetCurrentProcessId());
    Handle mapping{CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,sizeof(InputShared),name.c_str())};
    if(!mapping.value || GetLastError()==ERROR_ALREADY_EXISTS){ReleaseMutex(exclusive.value);return 5;}
    auto data=static_cast<InputShared*>(MapViewOfFile(mapping.value,FILE_MAP_ALL_ACCESS,0,0,sizeof(InputShared)));
    if(!data){ReleaseMutex(exclusive.value);return 5;}
    *data={};data->magic=InputMagic;data->protocolVersion=InputProtocolVersion;
    data->hostPid=hostPid;data->sourcePid=pid;data->sourceWindow=reinterpret_cast<uint64_t>(source);
    data->ownerWindow=reinterpret_cast<uint64_t>(owner);data->session=cookie;
    TraceCollector trace;trace.Open(name,cookie);
    ATOM atom=GlobalAddAtomW(name.c_str());
    if(!atom || !SetPropW(source,InputProperty,reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(atom))))return 6;
    wchar_t modulePath[MAX_PATH]{};GetModuleFileNameW(nullptr,modulePath,MAX_PATH);
    std::wstring path=modulePath;path=path.substr(0,path.find_last_of(L"\\/"))+L"\\FlashInputBridge.dll";
    HMODULE module=LoadLibraryExW(path.c_str(),nullptr,LOAD_WITH_ALTERED_SEARCH_PATH);
    auto callback=module ? reinterpret_cast<HOOKPROC>(GetProcAddress(module,"InputHook")) : nullptr;
    HHOOK hook=callback ? SetWindowsHookExW(WH_GETMESSAGE,callback,module,thread) : nullptr;
    if(!hook) {RemovePropW(source,InputProperty);GlobalDeleteAtom(atom);UnmapViewOfFile(data);ReleaseMutex(exclusive.value);return 7;}
    UINT control=RegisterWindowMessageW(InputControlMessage);
    bool initPosted=PostMessageW(source,control,ControlInit,static_cast<LPARAM>(cookie))!=FALSE;
    DWORD started=GetTickCount();
    DWORD lastInit=started;
    while(initPosted && !ReadAtomic(&data->ready) && GetTickCount()-started<10000 && WaitForSingleObject(process.value,10)==WAIT_TIMEOUT) {
        if(GetTickCount()-lastInit>100) {lastInit=GetTickCount();PostMessageW(source,control,ControlInit,static_cast<LPARAM>(cookie));}
    }
    bool ready=ReadAtomic(&data->ready)==1;
    if(ready)std::printf("READY imports=%ld version=%lu session=%llu\n",ReadAtomic(&data->patchMask),InputProtocolVersion,cookie);
    else std::printf("FAIL initialize ready=%ld session=%llu\n",ReadAtomic(&data->ready),cookie);
    std::fflush(stdout);
    trace.Drain();
    DWORD_PTR response=0;
    // Poll is control-only and session-bound. It guarantees release progress
    // after Cancel Post failure even when no further data messages are sent.
    DWORD quiescingSince=0;
    while(ready && !ReadAtomic(&data->stop) && WaitForSingleObject(host.value,0)==WAIT_TIMEOUT && WaitForSingleObject(process.value,100)==WAIT_TIMEOUT)
    {
        trace.Drain();
        SendMessageTimeoutW(source,control,ControlPoll,static_cast<LPARAM>(cookie),SMTO_ABORTIFHUNG|SMTO_BLOCK,100,&response);
        if(ReadAtomic(&data->closeTicket)) {
            if(!quiescingSince)quiescingSince=GetTickCount();
            response=0;
            if(SendMessageTimeoutW(source,control,(static_cast<WPARAM>(ReadAtomic(&data->closeTicket))<<32)|ControlQuiesce,static_cast<LPARAM>(cookie),SMTO_ABORTIFHUNG|SMTO_BLOCK,100,&response)
                && response==1 && ReadAtomic(&data->quiescedTicket)==ReadAtomic(&data->closeTicket))break;
            if(GetTickCount()-quiescingSince>2000) {std::puts("QUIESCE_TIMEOUT explicit_cancel");std::fflush(stdout);break;}
        }
    }
    RaiseAtomic(&data->closeTicket,1);RaiseAtomic(&data->minEpoch,InputEpochLimit+1);
    InterlockedExchange(&data->stop,1);InterlockedIncrement(&data->cancelTicket);
    started=GetTickCount();bool returned=false,reported=false;
    // Do not release installation ownership on timeout. Retain the exact hook,
    // property and mapping until verified restore or actual projector exit.
    while(WaitForSingleObject(process.value,0)==WAIT_TIMEOUT) {
        trace.Drain();
        response=0;
        if(SendMessageTimeoutW(source,control,(static_cast<WPARAM>(ReadAtomic(&data->closeTicket))<<32)|ControlRetire,static_cast<LPARAM>(cookie),SMTO_ABORTIFHUNG|SMTO_BLOCK,250,&response)
            && response==1 && ReadAtomic(&data->stopped)==1 && !ReadAtomic(&data->restoreError)) {
            InterlockedExchange(&data->returnedTicket,ReadAtomic(&data->closeTicket));returned=true;break;
        }
        if(!reported && GetTickCount()-started>10000) {std::puts("CLOSED_UNCONFIRMED restore_or_return");std::fflush(stdout);reported=true;}
        Sleep(100);
    }
    bool targetExited=WaitForSingleObject(process.value,0)==WAIT_OBJECT_0;
    bool unhooked=UnhookWindowsHookEx(hook)!=FALSE;
    bool propertyOwned=!IsWindow(source) || GetPropW(source,InputProperty)==reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(atom));
    if(!targetExited && (!unhooked || !propertyOwned)) {
        std::puts("CLOSED_UNCONFIRMED hook_or_property");std::fflush(stdout);
        WaitForSingleObject(process.value,INFINITE);targetExited=true;
    }
    if(targetExited)InterlockedExchange(&data->targetExited,1);
    if(IsWindow(source) && propertyOwned)RemovePropW(source,InputProperty);
    GlobalDeleteAtom(atom);
    trace.Drain();
    std::printf("STOP session=%llu returned=%d targetExited=%d unhooked=%d propertyOwned=%d consumedSeq=%ld completedSeq=%ld stale=%ld invalid=%ld cancelAck=%ld drained=%ld\n",
        cookie,returned,targetExited,unhooked,propertyOwned,ReadAtomic(&data->consumedSeq),ReadAtomic(&data->completedSeq),
        ReadAtomic(&data->staleRejected),ReadAtomic(&data->invalidRejected),ReadAtomic(&data->cancelledTicket),ReadAtomic(&data->drained));std::fflush(stdout);
    bool okay=targetExited || (returned && unhooked && propertyOwned);
    UnmapViewOfFile(data);if(module)FreeLibrary(module);ReleaseMutex(exclusive.value);
    return okay ? 0 : 13;
}
