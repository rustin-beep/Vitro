@echo off
rem Unified vitro launcher (cmd form) - three-backend edition (2026-10-15):
rem default = js entry (MoonBit shell compiled to JS, node runs it directly);
rem --backend wasm = legacy gateway wasm-gc shell; --backend native = exe.
rem rc=3 from wasm shell falls back to native. ASCII-only: cmd.exe parses this
rem file in the OEM codepage, UTF-8 bytes corrupt commands. Chinese messages
rem live in the node shell / sh launcher.
rem goto-form (no parenthesized blocks): %errorlevel% expands at parse time
rem inside ( ) blocks and keeps its stale value - a classic cmd pitfall.
setlocal
set "REPO=%~dp0..\.."
set "JS_ENTRY=%REPO%\moonbit\_build\js\release\build\cmd\vitro_js\vitro_js.js"
set "WASM_SHELL=%REPO%\moonbit\_build\js\release\build\cmd\vitro_wasm\vitro_wasm.js"
set "NATIVE_EXE=%REPO%\moonbit\_build\native\release\build\cmd\vitro\vitro.exe"

if not "%~1"=="--backend" goto run_default_js
if "%~2"=="native" goto force_native
if "%~2"=="wasm" goto strip_wasm
if "%~2"=="js" goto strip_js
goto run_default_js

:force_native
echo [vitro] backend=native ^(explicit --backend^) 1>&2
if not exist "%NATIVE_EXE%" goto no_native
for /f "tokens=2,*" %%a in ("%*") do set "REST=%%b"
"%NATIVE_EXE%" %REST%
exit /b %errorlevel%

:strip_wasm
for /f "tokens=2,*" %%a in ("%*") do set "REST=%%b"
goto run_wasm

:strip_js
for /f "tokens=2,*" %%a in ("%*") do set "REST=%%b"
goto run_js_explicit

:run_default_js
if not exist "%JS_ENTRY%" goto no_js_entry
where node >nul 2>nul
if errorlevel 1 goto no_node
echo [vitro] backend=js ^(default^) 1>&2
if defined REST (
  node "%JS_ENTRY%" %REST%
) else (
  node "%JS_ENTRY%" %*
)
exit /b %errorlevel%

:run_js_explicit
if not exist "%JS_ENTRY%" goto no_js_entry
where node >nul 2>nul
if errorlevel 1 goto no_node
echo [vitro] backend=js ^(explicit --backend^) 1>&2
node "%JS_ENTRY%" %REST%
exit /b %errorlevel%

:run_wasm
if not exist "%WASM_SHELL%" goto no_shell
where node >nul 2>nul
if errorlevel 1 goto no_node
echo [vitro] backend=wasm ^(gateway wasm-gc shell^) 1>&2
node "%WASM_SHELL%" %REST%
set "RC=%errorlevel%"
if "%RC%"=="5" goto old_node
exit /b %RC%

:no_shell
echo [vitro] backend=native ^(fallback: wasm shell missing^) 1>&2
if not exist "%NATIVE_EXE%" goto no_native
"%NATIVE_EXE%" %*
exit /b %errorlevel%

:no_node
echo [vitro] backend=native ^(fallback: node not in PATH^) 1>&2
if not exist "%NATIVE_EXE%" goto no_native
"%NATIVE_EXE%" %*
exit /b %errorlevel%

:no_js_entry
echo [vitro] backend=native ^(fallback: js entry missing - build: cd moonbit ^&^& moon build --release --target js cmd/vitro_js^) 1>&2
if not exist "%NATIVE_EXE%" goto no_native
"%NATIVE_EXE%" %*
exit /b %errorlevel%

:old_node
echo [vitro] backend=native ^(fallback: node too old^) 1>&2
if not exist "%NATIVE_EXE%" goto no_native
"%NATIVE_EXE%" %*
exit /b %errorlevel%

:no_native
rem #100 (2026-10-15): fail loud with build hint instead of bare rc=127
echo [vitro] native exe missing: %NATIVE_EXE% 1>&2
echo [vitro] rebuild ^(Windows requires MOON_CC=clang - moon issue 2254^): cd moonbit ^&^& MOON_CC=clang moon build --release --target native cmd/vitro 1>&2
exit /b 127
