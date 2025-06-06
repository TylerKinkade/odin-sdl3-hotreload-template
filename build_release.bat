:: This script creates an optimized release build.

@echo off
setlocal enabledelayedexpansion

set OUT_DIR=build\release

if not exist %OUT_DIR% mkdir %OUT_DIR%

:: Build shaders
echo Building shaders...
:: Compile all .vert shaders:
set "SHADER_DIR=assets\shaders"

:: 2) Compile all "*.glsl.vert" → "shadername.spv.vert"
for %%F in ("%SHADER_DIR%\*.glsl.vert") do (
    echo Compiling %%~nxF ...
    :: %%~nF is "shadername.glsl" → strip out ".glsl" to get "shadername"
    set "BASENAME=%%~nF"
    set "STRIPPED=!BASENAME:.glsl=!"
    :: %%~dpF = drive+path\,   %%~xF = ".vert"
    glslc "%%F" -o "%%~dpF!STRIPPED!.spv%%~xF"
)

:: 3) Compile all "*.glsl.frag" → "shadername.spv.frag"
for %%F in ("%SHADER_DIR%\*.glsl.frag") do (
    echo Compiling %%~nxF ...
    set "BASENAME=%%~nF"
    set "STRIPPED=!BASENAME:.glsl=!"
    glslc "%%F" -o "%%~dpF!STRIPPED!.spv%%~xF"
)

odin build source\main_release -out:%OUT_DIR%\game_release.exe -strict-style -vet -no-bounds-check -o:speed -subsystem:windows
IF %ERRORLEVEL% NEQ 0 exit /b 1

xcopy /y /e /i assets %OUT_DIR%\assets > nul
IF %ERRORLEVEL% NEQ 0 exit /b 1

echo Release build created in %OUT_DIR%