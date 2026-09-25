using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal interface IWorldPointerSink
    {
        PointerPostStatus Send(in PointerPacket packet,Point point);
        bool RaiseMinEpoch(uint epoch);
        long EndpointConsumedSeq { get; }
    }
    internal sealed class NativePointerBridge : IDisposable,IWorldPointerSink
    {
        internal const uint InputMagic=0xCF710001, ProtocolVersion=4;
        private readonly IntPtr _source;
        private readonly uint _message,_control,_pid;
        private readonly object _gate=new object();
        private readonly SemaphoreSlim _paintGate=new SemaphoreSlim(1);
        private readonly TaskCompletionSource<string> _ready=new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource<int> _exit=new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly ulong _cookie;
        private Process _broker;
        private SharedInputStateView _state;
        private bool _closing,_ended;
        private Task<bool> _closeTask;
        internal bool IsAlive { get {lock(_gate)return !_closing && !_ended;} }
        internal ulong SessionIdentity => _cookie;
        private NativePointerBridge(IntPtr source) {
            _source=source;_message=RegisterWindowMessage("CF7.WorldPointer.Packet.v4");
            _control=RegisterWindowMessage("CF7.WorldPointer.Control.v4");GetWindowThreadProcessId(source,out _pid);
            _cookie=BitConverter.ToUInt64(RandomNumberGenerator.GetBytes(8))|1;
        }
        internal static async Task<NativePointerBridge> Start(IntPtr source,IntPtr owner)
        {
            string exe=Path.Combine(AppContext.BaseDirectory,"FlashInputBroker.exe");
            if(!File.Exists(exe) || !File.Exists(Path.Combine(AppContext.BaseDirectory,"FlashInputBridge.dll")))throw new FileNotFoundException("Missing paired input bridge",exe);
            var bridge=new NativePointerBridge(source);
            var start=new ProcessStartInfo(exe) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true};
            foreach(var arg in new[]{source.ToInt64().ToString(CultureInfo.InvariantCulture),Environment.ProcessId.ToString(CultureInfo.InvariantCulture),owner.ToInt64().ToString(CultureInfo.InvariantCulture),bridge._cookie.ToString(CultureInfo.InvariantCulture)})start.ArgumentList.Add(arg);
            try {
                bridge._broker=Process.Start(start);
                _=bridge.ReadCompletion();
                string ready=await bridge._ready.Task.WaitAsync(TimeSpan.FromSeconds(12));
                if(ready==null || !ready.StartsWith("READY ",StringComparison.Ordinal))throw new InvalidOperationException("Input bridge initialization: "+ready);
                string name="Local\\CF7.WorldPointer."+bridge._pid+"."+bridge._broker.Id;
                bridge._state=SharedInputStateView.Open(name,InputMagic,ProtocolVersion);
                if(bridge._state.Session!=bridge._cookie)throw new InvalidOperationException("Input session mismatch");
                LogManager.Log("event=world_pointer_bridge_ready brokerPid="+bridge._broker.Id+" "+ready);
                return bridge;
            } catch {
                if(bridge._broker!=null) { bridge.Dispose(); }
                throw;
            }
        }
        private async Task ReadCompletion()
        {
            int code=-1;
            try {
                string line;while((line=await _broker.StandardOutput.ReadLineAsync())!=null) { _ready.TrySetResult(line);LogManager.Log("event=world_pointer_bridge "+line); }
                _ready.TrySetException(new InvalidOperationException("Broker exited before READY"));
                await _broker.WaitForExitAsync();code=_broker.ExitCode;
            } catch(Exception e) {LogManager.Log("event=world_pointer_bridge_log "+e.Message);}
            finally { _ready.TrySetException(new InvalidOperationException("Broker stream ended"));
                try {await _broker.WaitForExitAsync();code=_broker.ExitCode;}catch {}
                lock(_gate)_ended=true;_exit.TrySetResult(code);}
        }
        public PointerPostStatus Send(in PointerPacket packet,Point point)
        {
            lock(_gate) {
                if(_closing || _ended)return PointerPostStatus.BridgeClosed;
                if(GetWindowThreadProcessId(_source,out uint pid)==0 || pid!=_pid)return PointerPostStatus.SourceGone;
                if(packet.Epoch==0 || packet.Epoch>WorldPointerMapper.EpochLimit || packet.Sequence<1 || packet.Sequence>WorldPointerMapper.SequenceLimit)return PointerPostStatus.BridgeClosed;
                _state?.WriteIssuedEpoch(packet.Epoch);
                if(!PostMessage(_source,_message,new IntPtr(WorldPointerMapper.PackWParam(packet.Message,packet.Flags,packet.Data,packet.Epoch,packet.Geometry)),new IntPtr(WorldPointerMapper.PackLParam(point,packet.Sequence))))return PointerPostStatus.PostFailed;
                return PointerPostStatus.Posted;
            }
        }
        public bool RaiseMinEpoch(uint epoch)
        {
            lock(_gate) {
                if(_closing || _ended || _state==null)return false;
                _state.WriteMinEpoch(epoch);
                _state.RequestCancellation(); // persistent, broker control wakes an otherwise idle endpoint
                return true;
            }
        }
        public long EndpointConsumedSeq {get {lock(_gate)return _state?.ReadConsumedSeq() ?? -1;}}
        internal Task<double> RepaintAsync(double after) => RepaintCore(after);
        private async Task<double> RepaintCore(double after)
        {
            await _paintGate.WaitAsync();
            try {
                int ticket;
                lock(_gate) {
                    if(_closing || _state==null)throw new InvalidOperationException("Input session closing");
                    ticket=_state.RequestPaint((long)(after*Stopwatch.Frequency/1000.0));
                }
                bool returned=await Task.Run(()=>SendMessageTimeout(_source,_control,new IntPtr(((long)ticket<<32)|4),new IntPtr(unchecked((long)_cookie)),2,10000,out IntPtr result)!=IntPtr.Zero && result==new IntPtr(1));
                lock(_gate) {
                    if(_closing || !returned || _state==null || _state.ReadAtomic(140)!=ticket)throw new InvalidOperationException("Repaint result not confirmed for current input session");
                    return _state.ReadAtomic64(144)*1000.0/Stopwatch.Frequency;
                }
            } finally {_paintGate.Release();}
        }
        internal Task<bool> CloseAsync(bool graceful=false)
        {
            lock(_gate) {
                if(_closeTask!=null)return _closeTask;
                _closing=true;
                if(_state!=null) {
                    _state.Exchange(168,graceful ? 1 : 0);
                    if(!graceful) {_state.WriteMinEpoch(WorldPointerMapper.EpochLimit+1);_state.RequestCancellation();_state.Exchange(36,1);}
                    _state.Exchange(96,1);
                }
                return _closeTask=FinishClose();
            }
        }
        private async Task<bool> FinishClose()
        {
            // Never block the owner UI while the target might send focus messages.
            await Task.Yield();
            bool confirmed=false;
            try {
                if(!await _paintGate.WaitAsync(TimeSpan.FromSeconds(12)))throw new TimeoutException("repaint still in flight");
                try {
                    int code=await _exit.Task.WaitAsync(TimeSpan.FromSeconds(15));
                    lock(_gate)confirmed=code==0 && (_state==null || (_state.ReadAtomic(100)==_state.ReadAtomic(96) || _state.ReadAtomic(164)==1));
                } finally {_paintGate.Release();}
            } catch(Exception e) {LogManager.Log("event=world_pointer_closed_unconfirmed session="+_cookie+" reason="+e.Message);}
            if(confirmed)ReleaseMapping();
            else _=ReleaseAfterExit(); // retain mapping while old callbacks/broker may still use it
            LogManager.Log("event=world_pointer_close session="+_cookie+" confirmed="+confirmed);
            return confirmed;
        }
        private async Task ReleaseAfterExit() {await _exit.Task;await _paintGate.WaitAsync();try {ReleaseMapping();}finally {_paintGate.Release();}}
        private void ReleaseMapping() {lock(_gate){_state?.Dispose();_state=null;_broker?.Dispose();}}
        public void Dispose() {if(_broker!=null)_=CloseAsync();}
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hwnd,uint message,IntPtr wp,IntPtr lp);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
        [DllImport("user32.dll",SetLastError=true)] private static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint message,IntPtr wp,IntPtr lp,uint flags,uint timeout,out IntPtr result);
    }
    // Interlocked operations on aligned shared memory; _gate also prevents
    // a concurrent close from unmapping the storage underneath an operation.
    internal sealed unsafe class SharedInputStateView : IDisposable
    {
        internal const int Size=176;
        private const uint FileMapReadWrite=0x0002|0x0004;
        private readonly object _gate=new object();
        private IntPtr _mapping,_view;
        internal ulong Session => unchecked((ulong)ReadAtomic64(88));
        internal static SharedInputStateView Open(string name,uint magic,uint version)
        {
            var state=new SharedInputStateView();
            try {
                state._mapping=OpenFileMappingW(FileMapReadWrite,false,name);
                if(state._mapping==IntPtr.Zero)throw new InvalidOperationException("Input map open failed: "+Marshal.GetLastWin32Error());
                state._view=MapViewOfFile(state._mapping,FileMapReadWrite,0,0,(UIntPtr)Size);
                if(state._view==IntPtr.Zero || unchecked((uint)state.ReadAtomic(0))!=magic || unchecked((uint)state.ReadAtomic(4))!=version)throw new InvalidOperationException("Input mapping protocol mismatch");
                return state;
            } catch {state.Dispose();throw;}
        }
        private ref int Word(int offset) {if(_view==IntPtr.Zero)throw new ObjectDisposedException(nameof(SharedInputStateView));return ref *(int*)((byte*)_view+offset);}
        internal int ReadAtomic(int offset) {lock(_gate)return Interlocked.CompareExchange(ref Word(offset),0,0);}
        internal long ReadAtomic64(int offset) {lock(_gate){if(_view==IntPtr.Zero)throw new ObjectDisposedException(nameof(SharedInputStateView));return Interlocked.Read(ref *(long*)((byte*)_view+offset));}}
        internal void Exchange(int offset,int value) {lock(_gate)Interlocked.Exchange(ref Word(offset),value);}
        private void Raise(int offset,uint value) {
            lock(_gate) {int old=ReadAtomic(offset);while(old<value){int seen=Interlocked.CompareExchange(ref Word(offset),(int)value,old);if(seen==old)break;old=seen;}}
        }
        internal void WriteMinEpoch(uint epoch) {if(epoch>WorldPointerMapper.EpochLimit+1)throw new ArgumentOutOfRangeException(nameof(epoch));Raise(56,epoch);}
        internal void WriteIssuedEpoch(uint epoch) {if(epoch==0 || epoch>WorldPointerMapper.EpochLimit)throw new ArgumentOutOfRangeException(nameof(epoch));Raise(80,epoch);}
        internal void RequestCancellation() {lock(_gate)Interlocked.Increment(ref Word(104));}
        internal int RequestPaint(long ticks) {lock(_gate){Interlocked.Exchange(ref *(long*)((byte*)_view+128),ticks);return Interlocked.Increment(ref Word(136));}}
        internal int ReadConsumedSeq()=>ReadAtomic(60);
        public void Dispose() {lock(_gate){if(_view!=IntPtr.Zero){UnmapViewOfFile(_view);_view=IntPtr.Zero;}if(_mapping!=IntPtr.Zero){CloseHandle(_mapping);_mapping=IntPtr.Zero;}}}
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern IntPtr OpenFileMappingW(uint access,bool inherit,string name);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr MapViewOfFile(IntPtr mapping,uint access,uint offsetHigh,uint offsetLow,UIntPtr size);
        [DllImport("kernel32.dll")] private static extern bool UnmapViewOfFile(IntPtr address);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
    }
}
