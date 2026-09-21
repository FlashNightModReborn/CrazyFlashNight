using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace Cf7.FieldSupport;

internal static class Program
{
    [DllImport("kernel32.dll")] private static extern bool FreeConsole();
    [STAThread] public static int Main(string[] args)
    {
        if(args.Length>0&&args[0]=="layout-check")return LayoutCheck.Run(args.Length>1?args[1]:throw new ArgumentException("layout-check needs output path"));
        if(args.Length==0||args[0]=="gui"||args[0]=="gui-preview")
        {
            FreeConsole();Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            using var only=new Mutex(false,"Local\\"+LocalState.PipeName+"-target");
            try{if(!only.WaitOne(0)){MessageBox.Show("当前 Windows 会话已有现场助手，请使用原窗口。","CF7 现场诊断助手");return 1;}}catch(AbandonedMutexException){}
            bool preview=args.Length>0&&args[0]=="gui-preview";
            var form=new MainForm(preview);if(preview)form.ShowLayoutPreview(args.Length>1?args[1]:"question");Application.Run(form);return 0;
        }
        try{return Run(args).GetAwaiter().GetResult();}
        catch(Exception ex){Console.Error.WriteLine(JsonSerializer.Serialize(new{ok=false,error=ex.Message},Wire.Json));return 1;}
    }
    private static async Task<int> Run(string[] args)
    {
        string command=args[0];var flags=new Dictionary<string,string>();
        for(int i=1;i<args.Length;i++){if(!args[i].StartsWith("--")||i+1==args.Length)throw new ArgumentException("参数需要 --name value");flags.Add(args[i][2..],args[++i]);}
        string Need(string name)=>flags.TryGetValue(name,out var value)?value:throw new ArgumentException("缺少 --"+name);
        void Print(object? data)=>Console.WriteLine(JsonSerializer.Serialize(data,Wire.Json));
        if(command=="worker")return ExperimentOperation.Worker(Need("gate"),Need("script"));
        if(command=="selftest")return await SelfTest.Run(Need("output"),flags.GetValueOrDefault("candidate-root"));
        if(command=="connection-check")return await ConnectionCheck.Run(Need("output"),int.Parse(flags.GetValueOrDefault("seconds","210")));
        if(command=="broker"){await Broker.Run(Need("ticket"),Need("developer"),Need("state"),flags.GetValueOrDefault("selftest-pipe"));return 0;}
        if(command=="connect")
        {
            string source=Path.GetFullPath(Need("ticket-file"));if(new FileInfo(source).Length>8192)throw new InvalidDataException("票据文件过大");
            var ticket=LocalState.Read<Ticket>(source);if(ticket.Version!=1||DateTimeOffset.UtcNow>ticket.ExpiresAt)throw new InvalidDataException("票据无效或过期");
            string folder=Path.Combine(LocalState.Root,"controller-private",Wire.Id());LocalState.PrivateDirectory(folder);
            string imported=Path.Combine(folder,"ticket.cf7ticket"),state=Path.Combine(folder,"broker.json");LocalState.Save(imported,ticket);
            var start=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};
            foreach(string arg in new[]{"broker","--ticket",imported,"--developer",Need("developer"),"--state",state})start.ArgumentList.Add(arg);
            using var process=Process.Start(start)!;
            for(int i=0;i<100&&!File.Exists(state)&&!process.HasExited;i++)await Task.Delay(100);
            Print(new{stateFile=state,pid=process.Id,status=File.Exists(state)?LocalState.Read<JsonElement>(state):Wire.Data(new{state="starting"})});return 0;
        }
        if(command=="candidate.pack")
        {
            string path=Path.GetFullPath(Need("root"));string dest=Path.GetFullPath(Need("output"));var identity=Candidate.Pack(path,dest);
            Print(new{path=dest,sha256=Wire.FileHash(dest),identity});return 0;
        }
        if(command=="candidate.verify"){Print(Candidate.Validate(Need("root"),false));return 0;}
        if(command=="help")
        {
            Console.WriteLine("CF7 Field Support 0.1 candidate\nconnect --ticket-file <file> --developer <name>\nstatus | finish\nexec --script-file <ps1> [--timeout-seconds 1800]\noperation --id <id> | cancel --id <id>\nput --file <path>\nget --remote <path> --local <new-path>\nask --request-file <json> | question --id <id> | ask.cancel --id <id>\nreplace --request-file <json> | restore --id <id>\ncandidate.pack --root <candidate> --output <zip>\ncandidate.import --upload-id <id>\ncandidate.launch --request-file <json>\nrpc --request-file <json containing method,data,id>\nselftest --output <new-directory>\nNo command or gui opens the tester window.");return 0;
        }
        string method=command;object data;
        switch(command)
        {
            case "status":case "finish":data=new{};break;
            case "exec":data=new{script=File.ReadAllText(Need("script-file")),timeoutSeconds=int.Parse(flags.GetValueOrDefault("timeout-seconds","1800"))};break;
            case "operation":case "cancel":case "question":case "ask.cancel":case "restore":data=new{id=Need("id")};break;
            case "put":method="put.local";data=new{path=Path.GetFullPath(Need("file"))};break;
            case "get":method="get.local";data=new{remote=Need("remote"),local=Path.GetFullPath(Need("local"))};break;
            case "candidate.import":data=new{uploadId=Need("upload-id")};break;
            case "ask":case "replace":case "candidate.launch":data=LocalState.Read<JsonElement>(Need("request-file"));break;
            case "rpc":
                var request=LocalState.Read<JsonElement>(Need("request-file"));Print(await Broker.Call(request.Text("method"),request.GetProperty("data"),request.Optional("id",Wire.Id())));return 0;
            default:throw new ArgumentException("未知命令，使用 help");
        }
        Print(await Broker.Call(method,data));return 0;
    }
}
