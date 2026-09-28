/* CF7 #46：无 CRT 的 Win32 宽字符文件探针。仅读文件，不改 registry/prefix/资产。
 * 两种模式：probe.exe <全新夹具目录>；probe.exe --read <原资源的 Windows 绝对路径>。
 * 名字输出 UTF-16 十六进制，避免控制台代码页伪造“乱码”。GetACP 不代表 Wine Unix codepage。
 */
typedef unsigned int DWORD;
typedef int BOOL;
typedef unsigned short WCHAR;
typedef void *HANDLE;
#define API __declspec(dllimport)
#define CALL __stdcall
#define BAD_HANDLE ((HANDLE)(__INTPTR_TYPE__)-1)
API HANDLE CALL GetStdHandle(DWORD);
API BOOL CALL WriteFile(HANDLE,const void*,DWORD,DWORD*,void*);
API DWORD CALL GetLastError(void);
API WCHAR *CALL GetCommandLineW(void);
API DWORD CALL GetACP(void);
API DWORD CALL GetOEMCP(void);
API DWORD CALL GetCurrentProcessId(void);
API __declspec(noreturn) void CALL ExitProcess(DWORD);
API HANDLE CALL LocalFree(HANDLE);
API WCHAR **CALL CommandLineToArgvW(const WCHAR*,int*);
typedef struct { DWORD low, high; } FILETIME;
typedef struct {
    DWORD attributes;
    FILETIME creation, access, write;
    DWORD size_high, size_low, reserved0, reserved1;
    WCHAR filename[260], alternate[14];
} FIND_DATA;
API HANDLE CALL FindFirstFileW(const WCHAR*,FIND_DATA*);
API BOOL CALL FindNextFileW(HANDLE,FIND_DATA*);
API BOOL CALL FindClose(HANDLE);
API HANDLE CALL CreateFileW(const WCHAR*,DWORD,DWORD,void*,DWORD,DWORD,HANDLE);
API BOOL CALL ReadFile(HANDLE,void*,DWORD,DWORD*,void*);
API BOOL CALL CloseHandle(HANDLE);

static HANDLE output;
static BOOL output_failed;
static WCHAR path_buffer[32768];
static unsigned char read_buffer[65536];
static const unsigned char payload[] = "CF7 issue46 Unicode filename probe v1\n";
static const WCHAR ascii_name[] = L"ascii.bin";
static const WCHAR unicode_name[] = L"加载背景.bin";
static const char digits[] = "0123456789abcdef";

static void raw(const char *s) {
    DWORD n=0, written=0;
    while (s[n]) ++n;
    if (!WriteFile(output,s,n,&written,(void*)0) || written!=n) output_failed=1;
}
static void number(DWORD n) {
    char buffer[11]; unsigned i=10;
    buffer[i]=0;
    do { buffer[--i]=(char)('0'+n%10); n/=10; } while(n);
    raw(buffer+i);
}
static void boolean(BOOL value) { raw(value?"true":"false"); }
static void hex32(DWORD n) {
    char b[11]; int i;
    b[0]='"';b[9]='"';b[10]=0;
    for(i=0;i<8;i++) b[i+1]=digits[(n>>(28-4*i))&15];
    raw(b);
}
static void wide_hex(const WCHAR *w) {
    char b[5]; unsigned i=0;
    raw("\"");
    while(w[i]) {
        unsigned v=w[i];
        if(i)raw(" ");
        b[0]=digits[(v>>12)&15];b[1]=digits[(v>>8)&15];b[2]=digits[(v>>4)&15];b[3]=digits[v&15];b[4]=0;
        raw(b);++i;
    }
    raw("\"");
}
static BOOL wide_equal(const WCHAR *a,const WCHAR *b) {
    unsigned i=0;while(a[i]&&a[i]==b[i])++i;return a[i]==b[i];
}
static BOOL absolute_path(const WCHAR *p) {
    if(!p[0]||!p[1])return 0;
    return (p[1]==':' && (p[2]=='\\'||p[2]=='/')) || (p[0]=='\\'&&p[1]=='\\');
}
static BOOL joined(const WCHAR *dir,const WCHAR *name) {
    unsigned n=0,i=0;
    while(dir[n]) { if(n>=32000)return 0;path_buffer[n]=dir[n];++n; }
    if(n && path_buffer[n-1]!='\\' && path_buffer[n-1]!='/')path_buffer[n++]='\\';
    while(name[i]) { if(n>=32767)return 0;path_buffer[n++]=name[i++]; }
    path_buffer[n]=0;return 1;
}

typedef struct { BOOL opened,complete,payload_match,capped; DWORD error,bytes,fnv; } READ_RESULT;
static READ_RESULT read_path(const WCHAR *path,BOOL compare_payload) {
    READ_RESULT r={0,0,compare_payload,0,0,0,2166136261u};
    HANDLE f=CreateFileW(path,0x80000000u,1,(void*)0,3,0x08000000u,(HANDLE)0);
    DWORD got=0,i;
    if(f==BAD_HANDLE) {r.error=GetLastError();r.payload_match=0;return r;}
    r.opened=1;
    for(;;) {
        if(!ReadFile(f,read_buffer,(DWORD)sizeof(read_buffer),&got,(void*)0)) {r.error=GetLastError();break;}
        if(!got) {r.complete=1;break;}
        if(r.bytes>536870912u-got) {r.capped=1;r.error=223;break;}
        for(i=0;i<got;i++) {
            r.fnv=(r.fnv^read_buffer[i])*16777619u;
            if(compare_payload && (r.bytes+i>=sizeof(payload)-1 || read_buffer[i]!=payload[r.bytes+i]))r.payload_match=0;
        }
        r.bytes+=got;
    }
    if(compare_payload && r.bytes!=sizeof(payload)-1)r.payload_match=0;
    if(!r.complete)r.payload_match=0;
    if(!CloseHandle(f) && !r.error) {r.error=GetLastError();r.complete=0;}
    return r;
}
static void read_result(READ_RESULT r) {
    raw("{\"opened\":");boolean(r.opened);raw(",\"read_all\":");boolean(r.complete);
    raw(",\"payload_match\":");boolean(r.payload_match);raw(",\"win32_error\":");number(r.error);
    raw(",\"bytes\":");number(r.bytes);raw(",\"read_cap_exceeded\":");boolean(r.capped);
    raw(",\"fnv1a32_not_cryptographic\":");hex32(r.fnv);raw("}");
}
static BOOL enumerate(const WCHAR *dir) {
    FIND_DATA data;
    HANDLE find;
    DWORD count=0,error=0;
    BOOL a=0,u=0,capped=0,done=0;
    if(!joined(dir,L"*")) {raw("{\"path_too_long\":true}");return 0;}
    find=FindFirstFileW(path_buffer,&data);
    raw("{\"names_utf16_hex\":[");
    if(find==BAD_HANDLE)error=GetLastError();
    else {
        for(;;) {
            if(count)raw(",");wide_hex(data.filename);++count;
            if(wide_equal(data.filename,ascii_name))a=1;
            if(wide_equal(data.filename,unicode_name))u=1;
            if(!FindNextFileW(find,&data)) {error=GetLastError();done=(error==18);break;}
            if(count>=256) {capped=1;break;}
        }
        if(!FindClose(find) && done) {error=GetLastError();done=0;}
    }
    raw("],\"count\":");number(count);raw(",\"found_ascii\":");boolean(a);
    raw(",\"found_unicode\":");boolean(u);raw(",\"end_error\":");number(error);
    raw(",\"complete\":");boolean(done);raw(",\"capped\":");boolean(capped);raw("}");
    return done&&!capped&&a&&u;
}
void mainCRTStartup(void) {
    int argc=0;
    WCHAR **argv;
    READ_RESULT a,u;
    BOOL names_ok,pass;
    output=GetStdHandle((DWORD)-11);
    argv=CommandLineToArgvW(GetCommandLineW(),&argc);
    if(!argv || (argc!=2 && !(argc==3&&wide_equal(argv[1],L"--read")))) {
        raw("{\"error\":\"usage: probe.exe ABSOLUTE_FIXTURE_DIR | --read ABSOLUTE_WINDOWS_FILE\"}\n");
        if(argv)LocalFree(argv);ExitProcess(2);
    }
    if(!absolute_path(argv[argc-1])) {
        raw("{\"error\":\"explicit absolute Windows path required\"}\n");LocalFree(argv);ExitProcess(2);
    }
    raw("{\"schema\":\"cf7-win32-file-probe/v1\",\"scope\":\"wide-file-api-only\",\"process_bits\":");
    number(sizeof(void*)*8);raw(",\"pid\":");number(GetCurrentProcessId());
    raw(",\"win32_acp\":");number(GetACP());raw(",\"win32_oemcp\":");number(GetOEMCP());
    raw(",\"unix_codepage_observed\":false,\"path_utf16_hex\":");wide_hex(argv[argc-1]);
    if(argc==3) {
        a=read_path(argv[2],0);raw(",\"file\":");read_result(a);
        pass=a.opened&&a.complete&&!a.error;
    } else {
        raw(",\"enumeration\":");names_ok=enumerate(argv[1]);
        if(!joined(argv[1],ascii_name)) {raw(",\"error\":\"path too long\"}\n");LocalFree(argv);ExitProcess(2);}
        a=read_path(path_buffer,1);
        if(!joined(argv[1],unicode_name)) {raw(",\"error\":\"path too long\"}\n");LocalFree(argv);ExitProcess(2);}
        u=read_path(path_buffer,1);
        raw(",\"ascii\":");read_result(a);raw(",\"unicode\":");read_result(u);
        pass=names_ok&&a.opened&&u.opened&&a.complete&&u.complete&&a.payload_match&&u.payload_match&&!a.error&&!u.error;
    }
    raw(",\"passed\":");boolean(pass);raw("}\n");
    LocalFree(argv);ExitProcess(output_failed?2:(pass?0:22));
}
