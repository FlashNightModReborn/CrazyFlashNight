using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed class NativePointerBridge : IDisposable
    {
        private readonly IntPtr _source;
        private readonly uint _message;
        private readonly uint _pid;
        private Process _broker;
        private volatile bool _disposed, _ended;
        internal bool IsAlive => !_disposed && !_ended;
        private NativePointerBridge(IntPtr source) { _source=source; _message=RegisterWindowMessage("CF7.WorldPointer.Packet.v1"); GetWindowThreadProcessId(source,out _pid); }
        internal static async Task<NativePointerBridge> Start(IntPtr source,IntPtr owner)
        {
            string exe=Path.Combine(AppContext.BaseDirectory,"FlashInputBroker.exe");
            if(!File.Exists(exe) || !File.Exists(Path.Combine(AppContext.BaseDirectory,"FlashInputBridge.dll")))
                throw new FileNotFoundException("Missing paired projector input bridge",exe);
            var result=new NativePointerBridge(source);
            var start=new ProcessStartInfo(exe) { UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true };
            start.ArgumentList.Add(source.ToInt64().ToString(System.Globalization.CultureInfo.InvariantCulture));
            start.ArgumentList.Add(Environment.ProcessId.ToString(System.Globalization.CultureInfo.InvariantCulture));
            start.ArgumentList.Add(owner.ToInt64().ToString(System.Globalization.CultureInfo.InvariantCulture));
            try {
                result._broker=Process.Start(start);
                string ready=await result._broker.StandardOutput.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(12));
                if(ready==null || !ready.StartsWith("READY ",StringComparison.Ordinal)) throw new InvalidOperationException("Projector input bridge did not initialize: "+ready);
                LogManager.Log("event=world_pointer_bridge_ready brokerPid="+result._broker.Id+" "+ready);
                _=result.ReadCompletion();
                return result;
            } catch { result.Dispose(); if(result._broker!=null) _=result.ReadCompletion(); throw; }
        }
        private async Task ReadCompletion()
        {
            try { string line; while((line=await _broker.StandardOutput.ReadLineAsync())!=null) LogManager.Log("event=world_pointer_bridge "+line); }
            catch(Exception error) { LogManager.Log("event=world_pointer_bridge_log "+error.Message); }
            finally { _ended=true; _broker.Dispose(); }
        }
        internal void Send(int message,Point point,int flags,uint data=0)
        {
            uint kind=message==0x1F ? 0xFEu : (uint)(message-0x200);
            uint word=kind|((uint)(flags&127)<<8)|(data&0xFFFF0000u);
            if(_disposed || GetWindowThreadProcessId(_source,out uint pid)==0 || pid!=_pid) return;
            PostMessage(_source,_message,new IntPtr(unchecked((int)word)),WorldPointerMapper.Pack(point));
        }
        internal Task<double> RepaintAsync(double resizeStartedMs) => Task.Run(() => {
            if(_disposed || GetWindowThreadProcessId(_source,out uint pid)==0 || pid!=_pid)
                throw new InvalidOperationException("Projector changed before viewport repaint");
            var notBefore=new IntPtr((long)(resizeStartedMs*Stopwatch.Frequency/1000.0));
            if(SendMessageTimeout(_source,_message,new IntPtr(0xFC),notBefore,2,10000,out IntPtr stamp)==IntPtr.Zero || stamp.ToInt64()<=0)
                throw new InvalidOperationException("Projector viewport repaint did not complete");
            return stamp.ToInt64()*1000.0/Stopwatch.Frequency;
        });
        public void Dispose()
        {
            if(_broker==null || _disposed) return;
            _disposed=true;
            if(GetWindowThreadProcessId(_source,out uint pid)!=0 && pid==_pid) PostMessage(_source,_message,new IntPtr(0xFF),IntPtr.Zero);
            // The broker releases only its exact hook after the projector acknowledges
            // restoration or exits. Do not kill a helper with a live window subclass.
        }
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hwnd,uint message,IntPtr wp,IntPtr lp);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
        [DllImport("user32.dll",SetLastError=true)] private static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint message,IntPtr wp,IntPtr lp,uint flags,uint timeout,out IntPtr result);
    }
}
