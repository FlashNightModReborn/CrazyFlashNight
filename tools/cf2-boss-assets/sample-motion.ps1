param([int]$TimeoutSeconds=600,[switch]$RunJsflChoice)
$ErrorActionPreference='Stop'
if(Get-Process Animate -ErrorAction SilentlyContinue){throw 'Preserve the existing Animate editor; native sampling was not started.'}
$exe='C:\Program Files\Adobe\Adobe Animate 2024\Animate.exe'
if(-not(Test-Path -LiteralPath $exe)){throw 'Native Animate authoring sampler is unavailable; do not approximate parenting.'}
$run=[guid]::NewGuid().ToString('N')
$result=& python -B -X utf8 (Join-Path $PSScriptRoot 'sample-motion.py') --prepare $run
if($LASTEXITCODE -ne 0){throw 'Native sampling preparation failed.'}
$jobFile=($result | ConvertFrom-Json).job
$job=Get-Content -LiteralPath $jobFile -Raw -Encoding UTF8 | ConvertFrom-Json
$process=Start-Process -FilePath $exe -ArgumentList ('"'+$job.script+'"') -WorkingDirectory (Split-Path -Parent $job.script) -PassThru
[IO.File]::WriteAllText((Join-Path (Split-Path -Parent $jobFile) 'process.json'),(@{pid=$process.Id;startUtc=$process.StartTime.ToUniversalTime().ToString('o');executable=$exe}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Host "[CF2 native authoring samples] $jobFile"
if($RunJsflChoice){
    # Explicit opt-in after inspecting this installation's default radio choice:
    # "作为命令运行". Do not tick "不再显示" or change a global preference.
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Cf2NativeJsflChoice {
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint process);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd,uint message,IntPtr wparam,IntPtr lparam);
}
'@
    [void]$process.WaitForInputIdle(30000)
    $deadline=[DateTime]::UtcNow.AddSeconds(45)
    $handled=$false
    while(-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline -and -not $handled){
        $process.Refresh()
        if($process.MainWindowHandle -ne [IntPtr]::Zero){
            $main=[System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
            $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,'打开 JSFL 文件')
            $dialog=$main.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)
            if($null -ne $dialog){
                $hwnd=[IntPtr]$dialog.Current.NativeWindowHandle
                [uint32]$owner=0
                [void][Cf2NativeJsflChoice]::GetWindowThreadProcessId($hwnd,[ref]$owner)
                if($owner -ne $process.Id -or $dialog.Current.ProcessId -ne $process.Id){throw 'Native JSFL choice owner changed.'}
                $down=[Cf2NativeJsflChoice]::PostMessage($hwnd,0x0100,[IntPtr]13,[IntPtr]0)
                $up=[Cf2NativeJsflChoice]::PostMessage($hwnd,0x0101,[IntPtr]13,[IntPtr]0)
                if(-not $down -or -not $up){throw 'Native JSFL run choice was not delivered.'}
                $handled=$true
                [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $jobFile) 'choice.json'),(@{pid=$owner;hwnd=$hwnd.ToInt64();choice='reviewed-default-run-command';globalPreferenceChanged=$false}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
            }
        }
        if(-not $handled){[void]$process.WaitForExit(250)}
    }
}
if(-not $process.WaitForExit($TimeoutSeconds*1000)){
    throw "Native sampling did not exit; preserve its editor and exact job, do not replay: $jobFile"
}
& python -B -X utf8 (Join-Path $PSScriptRoot 'sample-motion.py') --check-report (Split-Path -Parent $jobFile)
if($LASTEXITCODE -ne 0){throw 'Native sampling report failed validation.'}
