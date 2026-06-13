@echo off
REM ---------------------------------------------------------------------------
REM install-dev.bat — symlink the built panel into the CEP extensions folder.
REM
REM Creates a directory junction/symlink:
REM   %APPDATA%\Adobe\CEP\extensions\com.cf7.animatekit.panel  ->  ..\..\dist
REM
REM Prereqs:
REM   1) Run enable-debug.bat (or import enable-debug.reg) once.
REM   2) Build the panel:  npm run build  (produces dist\ with host/, CSXS/, .debug)
REM   3) Run THIS script. Admin is recommended (mklink /D needs privilege unless
REM      Windows Developer Mode is on). If mklink fails, re-run "As administrator".
REM
REM After install, fully restart Animate -> Window menu -> "CF7 AnimateKit".
REM To update during dev, just rebuild (or use `npm run dev` hot reload); the
REM symlink always points at the latest dist\.
REM ---------------------------------------------------------------------------
setlocal
set "EXT_ID=com.cf7.animatekit.panel"
set "SCRIPT_DIR=%~dp0"
REM dist is one level up from install\  -> packages\cep-panel\dist
for %%I in ("%SCRIPT_DIR%..") do set "PKG_DIR=%%~fI"
set "DIST_DIR=%PKG_DIR%\dist"
set "TARGET=%APPDATA%\Adobe\CEP\extensions\%EXT_ID%"

if not exist "%DIST_DIR%\index.html" (
  echo [install-dev] dist\ not built. Run `npm run build` first.
  exit /b 1
)

if not exist "%APPDATA%\Adobe\CEP\extensions" (
  mkdir "%APPDATA%\Adobe\CEP\extensions"
)

if exist "%TARGET%" (
  echo [install-dev] Removing existing link/folder at:
  echo               %TARGET%
  rmdir "%TARGET%" 2>nul
  if exist "%TARGET%" rmdir /s /q "%TARGET%"
)

echo [install-dev] Linking:
echo   %TARGET%
echo   -^> %DIST_DIR%
mklink /D "%TARGET%" "%DIST_DIR%"
if errorlevel 1 (
  echo [install-dev] mklink failed. Re-run as Administrator, or enable
  echo               Windows Developer Mode, then try again.
  exit /b 1
)

echo [install-dev] Linked. Restart Animate; open Window -^> CF7 AnimateKit.
endlocal
