using System;
using System.Linq;
using System.Text.Json;

namespace CF7Launcher.Guardian.InputOwnership;

internal readonly record struct VersionedComboFrame(string Wire,string Origin,string Session,int Connection,
    int Epoch,int Frame,int Actor,int Module,int ModuleInc,int Config,int Mask,int Facing,int Direction,string Atoms)
{
    internal static bool TryParse(string wire,out VersionedComboFrame frame)
    {
        frame=default;
        if(!SessionInputAuthority.WireText(wire))return false;
        var f=wire.Split('|');
        if(f.Length!=14 || f[0]!="I1" || f[1].Length!=32 || !f[1].All(ch=>ch is >= '0' and <= '9' or >= 'a' and <= 'f') ||
            !Num(2,out int c) || !Num(3,out int epoch) || !Num(4,out int seq) || !Num(5,out int actor) ||
            !Num(6,out int module,0,2) || !Num(7,out int moduleInc) || !Num(8,out int config) ||
            !Num(9,out int mask,0,255) || !Num(10,out int facing,0,1) || f[11] is not ("-1" or "0" or "1") ||
            !Num(12,out int count,0,64))return false;
        if(count==0) {if(f[13]!="-")return false;}
        else {
            var atoms=f[13].Split(';');
            if(atoms.Length!=count)return false;
            // The V8 sampler verifies transitions against the eight-bit level
            // mask before advancing the DFA. Here validate the wire grammar.
            int previous=0, previousAction=0;
            foreach(string atom in atoms) {
                var a=atom.Split(',');
                if(a.Length!=3 || !SessionInputAuthority.Number(a[0],out int edge) || edge<previous ||
                    !SessionInputAuthority.Number(a[1],out int action,1,128) || (action&(action-1))!=0 ||
                    (edge==previous && action<=previousAction) || a[2] is not ("D" or "U"))return false;
                previous=edge;previousAction=action;
            }
        }
        int direction=f[11] switch {"-1"=>-1,"1"=>1,_=>0};
        frame=new(wire,string.Join("|",f,1,8),f[1],c,epoch,seq,actor,module,moduleInc,config,mask,facing,direction,f[13]);
        return true;
        bool Num(int i,out int n,int min=1,int max=int.MaxValue)=>SessionInputAuthority.Number(f[i],out n,min,max);
    }
}
internal sealed partial class SessionInputAuthority
{
    private int _commandSeq;
    private VersionedComboFrame? _pendingCombo;
    internal bool Admits(string session,int connection,int epoch)
    {
        lock(_gate)return _game && session==CurrentSessionId && connection==_connection && epoch==_epoch;
    }
    internal bool BeginCombo(in VersionedComboFrame frame,int actualConnection)
    {
        lock(_gate) {
            if(actualConnection!=frame.Connection || !Admits(frame.Session,frame.Connection,frame.Epoch) ||
                frame.Frame<=_lastComboFrame)return false;
            _lastComboFrame=frame.Frame; _pendingCombo=frame; _comboActive=true;return true;
        }
    }
    internal void EndComboFrame(in VersionedComboFrame frame,string failure=null)
    {
        lock(_gate) {
            if(_pendingCombo!=frame)return;
            _pendingCombo=null;
            if(failure!=null)Revoke(failure);
        }
    }
    private static bool EscapedComboText(string value)
    {
        for(int i=0;i<value.Length;i++) {
            char ch=value[i];
            if(char.IsAsciiLetterOrDigit(ch) || ch is '-' or '_' or '.' or '~')continue;
            if(ch!='%' || i+2>=value.Length || !Uri.IsHexDigit(value[i+1]) || !Uri.IsHexDigit(value[i+2]))return false;
            i+=2;
        }
        return true;
    }
    private static bool ValidComboHints(string hints)
    {
        if(hints=="[]")return true;
        try {
            using var json=JsonDocument.Parse(hints);
            return json.RootElement.ValueKind==JsonValueKind.Array;
        } catch(JsonException) {return false;}
    }
    internal bool CompleteCombo(in VersionedComboFrame frame,string result)
    {
        lock(_gate) {
            if(_pendingCombo!=frame || !Admits(frame.Session,frame.Connection,frame.Epoch))return false;
            _pendingCombo=null;
            if(string.IsNullOrEmpty(result)) {Revoke("combo_result_invalid");return false;}
            if(!WireText(result)) {Revoke("combo_result_overflow");return false;}
            var fields=result.Split('|');
            // TS supplies the four display/business fields plus its command sequence.
            if(_commandSeq==int.MaxValue) {ExhaustSequence();return false;}
            if(fields.Length!=5 || !Number(fields[0],out int sequence,0) || !Number(fields[1],out int command,0)
                || (command==0 ? sequence!=0 : sequence!=_commandSeq+1) ||
                !EscapedComboText(fields[2]) || !EscapedComboText(fields[3]) || !ValidComboHints(fields[4])) {
                Revoke("combo_result_invalid"); return false;
            }
            string packet="I1|K|"+frame.Origin+"|"+result;
            if(!WireText(packet) || _data.Count>=DataCapacity){Revoke("combo_result_overflow");return false;}
            if(command>0)_commandSeq=sequence;
            if(V8ComboCount<int.MaxValue)++V8ComboCount;
            _edgeTail=null; _data.Enqueue(new PendingWire{Record=new(frame.Connection,packet)}); WakeWriter(); return true;
        }
    }
}
