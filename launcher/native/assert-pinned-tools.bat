@echo off
setlocal

for %%V in (CF7_CL_EXE CF7_LINK_EXE CF7_RC_EXE) do (
    if not defined %%V (
        echo [FAIL] Missing pinned tool variable %%V. Run launcher\build.ps1.
        exit /b 1
    )
)

set "ACTUAL_CL="
set "ACTUAL_LINK="
set "ACTUAL_RC="
for /f "delims=" %%I in ('where cl.exe 2^>nul') do if not defined ACTUAL_CL set "ACTUAL_CL=%%I"
for /f "delims=" %%I in ('where link.exe 2^>nul') do if not defined ACTUAL_LINK set "ACTUAL_LINK=%%I"
for /f "delims=" %%I in ('where rc.exe 2^>nul') do if not defined ACTUAL_RC set "ACTUAL_RC=%%I"

if /i not "%ACTUAL_CL%"=="%CF7_CL_EXE%" goto :mismatch
if /i not "%ACTUAL_LINK%"=="%CF7_LINK_EXE%" goto :mismatch
if /i not "%ACTUAL_RC%"=="%CF7_RC_EXE%" goto :mismatch

echo [INFO] Pinned native tools selected: cl=%ACTUAL_CL% link=%ACTUAL_LINK% rc=%ACTUAL_RC%
endlocal & exit /b 0

:mismatch
echo [FAIL] vcvars selected tools outside the pinned baseline.
echo        cl   expected=%CF7_CL_EXE% actual=%ACTUAL_CL%
echo        link expected=%CF7_LINK_EXE% actual=%ACTUAL_LINK%
echo        rc   expected=%CF7_RC_EXE% actual=%ACTUAL_RC%
endlocal & exit /b 1
