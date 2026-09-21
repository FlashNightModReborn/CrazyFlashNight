using System.Text.Json;

namespace Cf7.FieldSupport;

internal static class LayoutCheck
{
    public static int Run(string output)
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);Application.EnableVisualStyles();
        var results=new List<object>();bool passed=true;
        foreach(float scale in new[]{1f,1.25f,1.5f,2f})
        {
            using var form=new MainForm(preview:true);form.ShowLayoutPreview();
            form.Shown+=(_,_)=>form.BeginInvoke(()=>
            {
                try
                {
                    form.Scale(new SizeF(scale,scale));form.MinimumSize=new(680,580);form.ClientSize=new(780,660);
                    form.PerformLayout();Application.DoEvents();
                    foreach(string scenario in new[]{"idle","consent","network","ticket","pair","question","ended"})
                    {
                        form.ShowLayoutPreview(scenario);form.PerformLayout();Application.DoEvents();
                        var value=Wire.Data(form.LayoutEvidence());
                        bool ok=value.GetProperty("promptFits").GetBoolean()&&value.GetProperty("permissionFits").GetBoolean()&&value.GetProperty("guideFits").GetBoolean()&&value.GetProperty("stopInClient").GetBoolean()&&value.GetProperty("primaryInClient").GetBoolean();
                        if(scenario=="question")ok&=value.GetProperty("optionCount").GetInt32()==3&&form.DraftSurvivesRefresh();
                        passed&=ok;results.Add(new{scenario,simulatedControlScale=scale,passed=ok,measurements=value});
                    }
                    var transition=Wire.Data(form.MinimizedEndTransition());bool transitionOk=transition.GetProperty("passed").GetBoolean();
                    passed&=transitionOk;results.Add(new{scenario="minimized_end_transition",simulatedControlScale=scale,passed=transitionOk,measurements=transition});
                }
                catch(Exception ex){passed=false;results.Add(new{simulatedControlScale=scale,passed=false,error=ex.ToString()});}
                finally{form.Close();}
            });
            Application.Run(form);
        }
        using(var baseline=new Form{Text="CF7 离线提醒检查",ClientSize=new(360,160),ShowInTaskbar=true})
        {
            baseline.Shown+=async(_,_)=>
            {
                try
                {
                    await Task.Delay(150);
                    IntPtr before=AttentionReminder.GetForegroundWindow();
                    using var notice=new NoticeWindow("离线检查：新提醒不会自动回答或授予权限",()=>{});
                    notice.Show();Application.DoEvents();
                    IntPtr after=AttentionReminder.GetForegroundWindow();
                    bool ok=before==after&&after!=notice.Handle;
                    passed&=ok;results.Add(new{scenario="nonactivating_notice",passed=ok,foregroundUnchanged=before==after,before=before.ToInt64(),after=after.ToInt64(),noticeHandle=notice.Handle.ToInt64(),noticeWasForeground=after==notice.Handle});
                }
                catch(Exception ex){passed=false;results.Add(new{scenario="nonactivating_notice",passed=false,error=ex.ToString()});}
                finally{baseline.Close();}
            };
            Application.Run(baseline);
        }
        LocalState.Save(Path.GetFullPath(output),new{schema="cf7-field-support-layout-check.v1",passed,scope="seven guided states at current display DPI plus simulated control scales; native notice foreground check; sound audibility and real B display remain human checks",results});
        Console.WriteLine(JsonSerializer.Serialize(new{passed,cases=results.Count,report=Path.GetFullPath(output)},Wire.Json));return passed?0:1;
    }
}
