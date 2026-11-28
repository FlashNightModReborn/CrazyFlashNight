using System;
using System.ComponentModel;
using CF7Launcher.Guardian.InputOwnership;
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
        long EndpointCompletedSeq => EndpointConsumedSeq;
    }
    internal sealed class NativePointerBridge : IDisposable,IWorldPointerSink
    {
        internal const uint InputMagic=0xCF710001, ProtocolVersion=5;
        private const int BrokerRejectedBeforeInstall=14;
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
        internal static async Task<NativePointerBridge> Start(IntPtr source, IntPtr owner,
            PassiveFlashInputMode mode = PassiveFlashInputMode.Disabled)
        {
            if (mode != PassiveFlashInputMode.Disabled)
                throw new ArgumentOutOfRangeException(nameof(mode));
            string exe=Path.Combine(AppContext.BaseDirectory,"FlashInputBroker.exe");
            if(!File.Exists(exe) || !File.Exists(Path.Combine(AppContext.BaseDirectory,"FlashInputBridge.dll")))throw new FileNotFoundException("Missing paired input bridge",exe);
            var bridge=new NativePointerBridge(source);
            var start=new ProcessStartInfo(exe) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true};
            foreach(var arg in new[]{source.ToInt64().ToString(CultureInfo.InvariantCulture),Environment.ProcessId.ToString(CultureInfo.InvariantCulture),owner.ToInt64().ToString(CultureInfo.InvariantCulture),bridge._cookie.ToString(CultureInfo.InvariantCulture)})start.ArgumentList.Add(arg);
            start.ArgumentList.Add(((int)mode).ToString(CultureInfo.InvariantCulture));
            try {
                try {
                    uint sourceThread=GetWindowThreadProcessId(source,out uint sourcePid);
                    GetWindowThreadProcessId(owner,out uint ownerPid);
                    LogManager.Log(FormatStartupObservation(source,owner,GetAncestor(source,2),sourcePid,sourceThread,ownerPid,Environment.ProcessId,bridge._cookie)
                        +" brokerPath=\""+exe+"\"");
                } catch { } // Observation must not grant or prevent broker admission.
                bridge._broker=StartBroker(start,bridge._cookie);
                _=bridge.ReadCompletion();
                string ready=await WaitForReady(bridge._ready.Task,bridge._broker,bridge._cookie,TimeSpan.FromSeconds(12));
                string name="Local\\CF7.WorldPointer."+bridge._pid+"."+bridge._broker.Id;
                bridge._state=SharedInputStateView.Open(name,InputMagic,ProtocolVersion);
                if(bridge._state.Session!=bridge._cookie || bridge._state.ReadAtomic(84)!=(int)mode)throw new InvalidOperationException("Input session mismatch");
                LogManager.Log("event=world_pointer_bridge_ready brokerPid="+bridge._broker.Id+" "+ready);
                return bridge;
            } catch {
                if(bridge._broker!=null) { bridge.Dispose(); }
                throw;
            }
        }

        internal static Process StartBroker(ProcessStartInfo start, ulong session)
        {
            long started = Stopwatch.GetTimestamp();
            Process broker;
            try {
                broker = Process.Start(start);
            } catch (Exception error) {
                LogBrokerStage("create_failed", session, started, null, error);
                throw;
            }
            LogBrokerStage(broker == null ? "create_no_process" : "created", session, started, broker);
            return broker;
        }

        internal static async Task<string> WaitForReady(Task<string> firstLine, Process broker, ulong session, TimeSpan timeout)
        {
            long started = Stopwatch.GetTimestamp();
            try {
                string ready = await firstLine.WaitAsync(timeout);
                if (ready == null || !ready.StartsWith("READY ", StringComparison.Ordinal))
                    throw new InvalidOperationException("Input bridge initialization: " + ready);
                LogBrokerStage("ready_wait_complete", session, started, broker);
                return ready;
            } catch (Exception error) {
                LogBrokerStage(error is TimeoutException ? "ready_timeout" : "ready_wait_failed", session, started, broker, error);
                throw;
            }
        }

        private static void LogBrokerStage(string stage, ulong session, long started, Process broker, Exception error = null)
        {
            try {
                double elapsed = Stopwatch.GetElapsedTime(started).TotalMilliseconds;
                string message = FormattableString.Invariant($"event=world_pointer_bridge_{stage} session={session} elapsedMs={elapsed:F3}");
                if (broker != null) message += FormattableString.Invariant($" brokerPid={broker.Id}");
                if (error != null) {
                    message += FormattableString.Invariant($" exception={error.GetType().FullName} hresult=0x{error.HResult:X8}");
                    if (error is Win32Exception win32)
                        message += FormattableString.Invariant($" win32={win32.NativeErrorCode}");
                    message += " reason=" + error.Message.Replace('\r',' ').Replace('\n',' ');
                }
                LogManager.Log(message);
            } catch { } // Diagnostics must not change admission or exception propagation.
        }

        private async Task ReadCompletion()
        {
            int? code=null;
            bool stdoutObserved=false,readyLineObserved=false;
            try {
                string line;while((line=await _broker.StandardOutput.ReadLineAsync())!=null) {
                    stdoutObserved=true;
                    readyLineObserved|=line.StartsWith("READY ",StringComparison.Ordinal);
                    _ready.TrySetResult(line);LogManager.Log("event=world_pointer_bridge "+line+" hostSession="+_cookie+" brokerPid="+_broker.Id);
                }
                _ready.TrySetException(new InvalidOperationException("Broker exited before READY"));
                await _broker.WaitForExitAsync();code=_broker.ExitCode;
            } catch(Exception e) {LogManager.Log("event=world_pointer_bridge_log session="+_cookie+" "+e.Message);}
            finally { _ready.TrySetException(new InvalidOperationException("Broker stream ended"));
                try {await _broker.WaitForExitAsync();code=_broker.ExitCode;}catch {}
                try {LogManager.Log(FormatExitObservation(_cookie,_broker.Id,code,stdoutObserved,readyLineObserved));}catch {}
                lock(_gate)_ended=true;_exit.TrySetResult(code ?? -1);}
        }
        internal static string FormatStartupObservation(IntPtr source,IntPtr owner,IntPtr root,uint sourcePid,uint sourceThread,uint ownerPid,int hostPid,ulong session)
            => FormattableString.Invariant($"event=world_pointer_bridge_start session={session} hostPid={hostPid} source=0x{source.ToInt64():X} sourcePid={sourcePid} sourceTid={sourceThread} owner=0x{owner.ToInt64():X} ownerPid={ownerPid} sourceRoot=0x{root.ToInt64():X} observationOnly=1 phase=before_create");
        internal static string FormatExitObservation(ulong session,int brokerPid,int? code,bool stdoutObserved,bool readyLineObserved)
        {
            string exitCode=code?.ToString(CultureInfo.InvariantCulture) ?? "unknown";
            return FormattableString.Invariant($"event=world_pointer_bridge_exit session={session} brokerPid={brokerPid} exitCode={exitCode} stdoutObserved={(stdoutObserved ? 1 : 0)} readyLineObserved={(readyLineObserved ? 1 : 0)}");
        }
        public PointerPostStatus Send(in PointerPacket packet,Point point)
        {
            lock(_gate) {
                if(_closing || _ended || _state==null || _state.ReadAtomic(36)!=0)return PointerPostStatus.BridgeClosed;
                if(GetWindowThreadProcessId(_source,out uint pid)==0 || pid!=_pid)return PointerPostStatus.SourceGone;
                if(packet.Epoch==0 || packet.Epoch>WorldPointerMapper.EpochLimit || packet.Sequence<1 || packet.Sequence>WorldPointerMapper.SequenceLimit)return PointerPostStatus.BridgeClosed;
                _state.WriteIssuedEpoch(packet.Epoch);
                if(!PostMessage(_source,_message,new IntPtr(WorldPointerMapper.PackWParam(packet.Message,packet.Flags,packet.Data,packet.Epoch,packet.Geometry)),new IntPtr(WorldPointerMapper.PackLParam(point,packet.Sequence))))return PointerPostStatus.PostFailed;
                return PointerPostStatus.Posted;
            }
        }
        public bool RaiseMinEpoch(uint epoch)
        {
            lock(_gate) {
                if(_closing || _ended || _state==null || epoch>WorldPointerMapper.EpochLimit+1)return false;
                _state.WriteMinEpoch(epoch);
                return _state.RequestCancellation()>0;
            }
        }
        internal int CancelAck {get {lock(_gate)return _state?.ReadAtomic(108) ?? -1;}}
        private bool _retirementConfirmed;
        internal Func<bool> BeginSemanticCancel()
        {
            lock(_gate) {
                int ticket=0;
                if(_state!=null && !_closing) {
                    int issued=_state.ReadAtomic(80);
                    if(issued>=0 && issued<=WorldPointerMapper.EpochLimit) {
                        _state.WriteMinEpoch((uint)issued+1);
                        ticket=_state.RequestCancellation();
                    } else _state.Exchange(36,1);
                }
                return ()=> {
                    lock(_gate)return _retirementConfirmed || (_state!=null &&
                        (_state.ReadAtomic(164)==1 || (ticket>0 && _state.ReadAtomic(108)>=ticket)));
                };
            }
        }
        public long EndpointConsumedSeq {get {lock(_gate)return _state?.ReadConsumedSeq() ?? -1;}}
        public long EndpointCompletedSeq {get {lock(_gate)return _state?.ReadAtomic(120) ?? -1;}}
        internal async Task<double> RepaintAsync(double after,double deadline,CancellationToken target)
        {
            int RemainingMs() {
                double remaining=deadline-Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency;
                if(remaining<=0)throw new TimeoutException("Capture repaint deadline expired");
                return (int)Math.Min(10000,Math.Ceiling(remaining));
            }
            if(!await _paintGate.WaitAsync(RemainingMs(),target))throw new TimeoutException("Capture repaint gate timed out");
            try {
                target.ThrowIfCancellationRequested();
                RemainingMs();
                int ticket;
                lock(_gate) {
                    if(_closing || _state==null)throw new InvalidOperationException("Input session closing");
                    ticket=_state.RequestPaint((long)(after*Stopwatch.Frequency/1000.0));
                    if(ticket==0)throw new InvalidOperationException("Input repaint sequence exhausted");
                }
                bool returned=await Task.Run(()=> {
                    target.ThrowIfCancellationRequested();
                    return SendMessageTimeout(_source,_control,new IntPtr(((long)ticket<<32)|4),new IntPtr(unchecked((long)_cookie)),
                        2,(uint)RemainingMs(),out IntPtr result)!=IntPtr.Zero && result==new IntPtr(1);
                },target);
                target.ThrowIfCancellationRequested();
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
                    lock(_gate)confirmed=(code==BrokerRejectedBeforeInstall && _state==null) ||
                        (code==0 && (_state==null || _state.ReadAtomic(100)==_state.ReadAtomic(96) || _state.ReadAtomic(164)==1));
                } finally {_paintGate.Release();}
            } catch(Exception e) {LogManager.Log("event=world_pointer_closed_unconfirmed session="+_cookie+" reason="+e.Message);}
            if(confirmed){lock(_gate)_retirementConfirmed=true;ReleaseMapping();}
            else _=ReleaseAfterExit(); // retain mapping while old callbacks/broker may still use it
            LogManager.Log("event=world_pointer_close session="+_cookie+" confirmed="+confirmed);
            return confirmed;
        }
        private async Task ReleaseAfterExit()
        {
            int result=await _exit.Task; await _paintGate.WaitAsync();
            try {
                lock(_gate)if(result==0 && _state!=null)
                    _retirementConfirmed=_state.ReadAtomic(164)==1 || (_state.ReadAtomic(96)>0 && _state.ReadAtomic(96)==_state.ReadAtomic(100));
                ReleaseMapping();
            } finally {_paintGate.Release();}
        }
        private void ReleaseMapping() {lock(_gate){_state?.Dispose();_state=null;_broker?.Dispose();}}
        public void Dispose() {if(_broker!=null)_=CloseAsync();}
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hwnd,uint message,IntPtr wp,IntPtr lp);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd,uint flags);
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
        private int NextTicket(int offset,int limit)
        {
            ref int counter=ref Word(offset);
            int current=Volatile.Read(ref counter);
            while(current>=0 && current<limit) {
                int seen=Interlocked.CompareExchange(ref counter,current+1,current);
                if(seen==current)return current+1;
                current=seen;
            }
            Exchange(36,1);
            return 0;
        }
        // The broker owns the final cancel number for retirement.
        internal int RequestCancellation() {lock(_gate)return NextTicket(104,int.MaxValue-1);}
        internal int RequestPaint(long ticks) {lock(_gate){Interlocked.Exchange(ref *(long*)((byte*)_view+128),ticks);return NextTicket(136,int.MaxValue);}}
        internal int ReadConsumedSeq()=>ReadAtomic(60);
        public void Dispose() {lock(_gate){if(_view!=IntPtr.Zero){UnmapViewOfFile(_view);_view=IntPtr.Zero;}if(_mapping!=IntPtr.Zero){CloseHandle(_mapping);_mapping=IntPtr.Zero;}}}
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern IntPtr OpenFileMappingW(uint access,bool inherit,string name);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr MapViewOfFile(IntPtr mapping,uint access,uint offsetHigh,uint offsetLow,UIntPtr size);
        [DllImport("kernel32.dll")] private static extern bool UnmapViewOfFile(IntPtr address);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
    }
}
