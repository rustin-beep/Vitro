@echo off
rem wasmoon arm build (Windows): vcvars64 + the wasmoon-cl driver wrapper.
rem
rem Prerequisites (see scripts/msvc/setup.ps1 upstream pattern):
rem   WASMOON_SRC  wasmoon checkout whose modules/* the moon.work wires in
rem                (default: D:\code\wasmoon-upstream-main; override as needed)
rem   MOON_CC      path to the wasmoon-cl driver built by scripts/msvc/setup.ps1
rem   WASMOON_MSVC_CL / _LIB / _ML64   toolchain paths recorded by setup.ps1
rem
rem On macOS/Linux this wrapper is not needed: `moon build --target native`
rem links clang directly (run_duel.py handles the platform branch).

setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1

cd /d "%~dp0"

if not defined WASMOON_SRC set "WASMOON_SRC=D:\code\wasmoon-upstream-main"
for /f "delims=" %%i in ('where cl.exe') do if not defined WASMOON_MSVC_CL set "WASMOON_MSVC_CL=%%i"
for /f "delims=" %%i in ('where lib.exe') do if not defined WASMOON_MSVC_LIB set "WASMOON_MSVC_LIB=%%i"
for /f "delims=" %%i in ('where ml64.exe') do if not defined WASMOON_MSVC_ML64 set "WASMOON_MSVC_ML64=%%i"

if not defined MOON_CC (
  if exist "%WASMOON_SRC%\target\msvc-tools\wasmoon-cl.exe" (
    set "MOON_CC=%WASMOON_SRC%\target\msvc-tools\wasmoon-cl.exe"
  ) else (
    set "MOON_CC=D:\code\wasmoon\target\msvc-tools\wasmoon-cl.exe"
  )
)
if not defined MOON_WORK set "MOON_WORK=%~dp0..\moon.work"

moon build --target native
exit /b %errorlevel%
