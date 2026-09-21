[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
[ordered]@{
    marker='CF7_FIELD_SUPPORT_PROBE_V1'
    machine=$env:COMPUTERNAME
    account=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    pid=$PID
    directory=(Get-Location).Path
    utc=[DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json
