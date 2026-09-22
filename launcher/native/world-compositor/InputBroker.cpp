#define WIN32_LEAN_AND_MEAN
#include "InputBridge.h"
#include <cstdio>
#include <cwchar>
#include <string>

int wmain(int argc,wchar_t** argv) {
    if(argc!=4) return 2;
    HWND source=reinterpret_cast<HWND>(wcstoull(argv[1],nullptr,10));
    DWORD hostPid=wcstoul(argv[2],nullptr,10);
    HWND owner=reinterpret_cast<HWND>(wcstoull(argv[3],nullptr,10));
    DWORD sourcePid=0, actualHost=0;
    DWORD thread=GetWindowThreadProcessId(source,&sourcePid);
    GetWindowThreadProcessId(owner,&actualHost);
    if(!thread || !IsWindow(source) || sourcePid==hostPid || actualHost!=hostPid || GetAncestor(source,GA_ROOT)!=owner) return 3;
    HANDLE host=OpenProcess(SYNCHRONIZE,FALSE,hostPid), process=OpenProcess(SYNCHRONIZE,FALSE,sourcePid);
    if(!host || !process) return 4;
    BOOL wow64=FALSE;
    HANDLE query=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,sourcePid);
    if(!query || !IsWow64Process(query,&wow64) || wow64) { std::puts("FAIL architecture"); return 8; }
    CloseHandle(query);
    std::wstring name=L"Local\\CF7.WorldPointer."+std::to_wstring(sourcePid)+L"."+std::to_wstring(GetCurrentProcessId());
    HANDLE mapping=CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,sizeof(InputShared),name.c_str());
    auto data=static_cast<InputShared*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,sizeof(InputShared)));
    if(!data) return 5;
    *data={InputMagic,hostPid,sourcePid,0,reinterpret_cast<uint64_t>(source),reinterpret_cast<uint64_t>(owner),0,0,0,0,0,0};
    ATOM atom=GlobalAddAtomW(name.c_str());
    if(!atom || !SetPropW(source,InputProperty,reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(atom)))) return 6;
    wchar_t modulePath[MAX_PATH]{}; GetModuleFileNameW(nullptr,modulePath,MAX_PATH);
    std::wstring path=modulePath; path=path.substr(0,path.find_last_of(L"\\/")+1)+L"FlashInputBridge.dll";
    HMODULE module=LoadLibraryExW(path.c_str(),nullptr,LOAD_WITH_ALTERED_SEARCH_PATH);
    auto callback=module ? reinterpret_cast<HOOKPROC>(GetProcAddress(module,"_InputHook@12")) : nullptr;
    if(!callback && module) callback=reinterpret_cast<HOOKPROC>(GetProcAddress(module,"InputHook"));
    HHOOK hook=callback ? SetWindowsHookExW(WH_GETMESSAGE,callback,module,thread) : nullptr;
    if(!hook) { std::printf("FAIL hook error=%lu\n",GetLastError()); return 7; }
    UINT message=RegisterWindowMessageW(InputMessage);
    PostMessageW(source,message,0xFD,0);
    DWORD start=GetTickCount();
    while(!data->ready && GetTickCount()-start<10000 && WaitForSingleObject(process,0)==WAIT_TIMEOUT) Sleep(10);
    if(data->ready==1) { std::printf("READY imports=%ld\n",data->patchMask); std::fflush(stdout); }
    else { std::printf("FAIL initialize ready=%ld imports=%ld error=%lu\n",data->ready,data->patchMask,GetLastError()); std::fflush(stdout); }
    HANDLE handles[]{host,process};
    if(data->ready==1) while(!data->stopped && WaitForMultipleObjects(2,handles,FALSE,100)==WAIT_TIMEOUT) {}
    InterlockedExchange(&data->stop,1);
    PostMessageW(source,message,0xFF,0);
    // A successful target initialization pins the DLL. On timeout, the shared
    // stop flag prevents a late install; an in-flight install restores itself.
    start=GetTickCount();
    while(!data->stopped && data->ready!=0 && GetTickCount()-start<5000 && WaitForSingleObject(process,100)==WAIT_TIMEOUT) PostMessageW(source,message,0xFF,0);
    UnhookWindowsHookEx(hook);
    if(IsWindow(source)) RemovePropW(source,InputProperty);
    GlobalDeleteAtom(atom);
    std::printf("STOP cursorReads=%ld keyReads=%ld\n",data->cursorReads,data->keyReads);
    UnmapViewOfFile(data); CloseHandle(mapping); CloseHandle(host); CloseHandle(process);
    if(module) FreeLibrary(module);
    return 0;
}
