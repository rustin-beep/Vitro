@echo off
rem Unified vitro launcher (cmd form) - default wasm shell via node; rc=3 falls
rem back to native exe. ASCII-only: cmd.exe parses this file in the OEM codepage,
rem UTF-8 bytes corrupt commands. Chinese messages live in the node shell.
rem goto-form (no parenthesized blocks): %errorlevel% expands at parse time
rem inside ( ) blocks and keeps its stale value - a classic cmd pitfall.
setlocal
set "REPO=%~dp0..\.."
set "WASM_SHELL=%REPO%\scripts\vitro_cli\main.js"
set "NATIVE_EXE=%REPO%\moonbit\_build\native\release\build\cmd\vitro\vitro.exe"

if not "%~1"=="--backend" goto run_default
if "%~2"=="native" goto force_native
if "%~2"=="wasm" goto strip_wasm
goto run_default

:force_native
echo [vitro] backend=native ^(explicit --backend^) 1>&2
for /f "tokens=2,*" %%a in ("%*") do set "REST=%%b"
"%NATIVE_EXE%" %REST%
exit /b %errorlevel%

:strip_wasm
for /f "tokens=2,*" %%a in ("%*") do set "REST=%%b"

:run_default
if not exist "%WASM_SHELL%" goto no_shell
where node >nul 2>nul
if errorlevel 1 goto no_node

if defined REST (
  node "%WASM_SHELL%" %REST%
) else (
  node "%WASM_SHELL%" %*
)
set "RC=%errorlevel%"
if "%RC%"=="3" goto old_node
exit /b %RC%

:no_shell
echo [vitro] backend=native ^(fallback: wasm shell missing^) 1>&2
"%NATIVE_EXE%" %*
exit /b %errorlevel%

:no_node
echo [vitro] backend=native ^(fallback: node not in PATH^) 1>&2
"%NATIVE_EXE%" %*
exit /b %errorlevel%

:old_node
echo [vitro] backend=native ^(fallback: node too old^) 1>&2
"%NATIVE_EXE%" %*
exit /b %errorlevel%
