@echo off
REM Enable unsigned CEP extensions + remote debugging (CSXS 9..12) via reg.exe.
REM Equivalent to importing enable-debug.reg. Run, then restart Animate.
setlocal
echo Enabling CEP PlayerDebugMode for CSXS 9..12 (HKCU)...
for %%V in (9 10 11 12) do (
  reg add "HKCU\Software\Adobe\CSXS.%%V" /v PlayerDebugMode /t REG_SZ /d 1 /f >nul
  reg add "HKCU\Software\Adobe\CSXS.%%V" /v LogLevel /t REG_SZ /d 6 /f >nul
  echo   CSXS.%%V -^> PlayerDebugMode=1
)
echo Done. Fully restart Adobe Animate for the change to take effect.
endlocal
