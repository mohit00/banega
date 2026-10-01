@echo off
setlocal EnableDelayedExpansion
REM ---------------------------------------------------------------
REM  Banega Android helper
REM    android.bat run            -> start Pixel_8 emulator if needed, run in demo mode (hot reload)
REM    android.bat api            -> same, connected to the local API server (run dev-servers.bat first)
REM    android.bat apk-api [URL]  -> release APK connected to the API, installed on the emulator/phone and launched
REM                                  URL defaults to this PC's LAN address, e.g. http://192.168.1.21:8765
REM                                  (works on the emulator and on a real phone on the same Wi-Fi)
REM    android.bat debug          -> build debug APK (demo mode)
REM    android.bat release        -> build release APK (demo mode)
REM    android.bat install        -> install the last release APK on the running emulator/device
REM    android.bat all            -> debug + release
REM    android.bat emulator       -> just start the Pixel_8 emulator
REM ---------------------------------------------------------------

set "FLUTTER=D:\DevTools\flutter\bin\flutter.bat"
set "ANDROID_HOME=D:\DevTools\Android\Sdk"
set "ANDROID_SDK_ROOT=D:\DevTools\Android\Sdk"
set "ANDROID_AVD_HOME=D:\DevTools\Android\.android\avd"
set "AVD=Pixel_8"
set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
set "EMU=%ANDROID_HOME%\emulator\emulator.exe"
set "APP_DIR=%~dp0..\app"
set "APK=build\app\outputs\flutter-apk\app-release.apk"
set "PKG=in.kornea.banega"
set "EMU_API_URL=http://10.0.2.2:8765"

set "CMD=%~1"
if "%CMD%"=="" set "CMD=run"

pushd "%APP_DIR%" || (echo Cannot find app folder at %APP_DIR% & exit /b 1)

if /i "%CMD%"=="emulator" goto :cmd_emulator
if /i "%CMD%"=="debug"    goto :cmd_debug
if /i "%CMD%"=="release"  goto :cmd_release
if /i "%CMD%"=="all"      goto :cmd_all
if /i "%CMD%"=="install"  goto :cmd_install
if /i "%CMD%"=="run"      goto :cmd_run
if /i "%CMD%"=="api"      goto :cmd_api
if /i "%CMD%"=="apk-api"  goto :cmd_apk_api
echo Unknown command "%CMD%". Use: run ^| api ^| apk-api ^| debug ^| release ^| install ^| all ^| emulator
popd & exit /b 1

:cmd_emulator
call :start_emulator
goto :done

:cmd_debug
call :build debug ""
goto :done

:cmd_release
call :build release ""
goto :done

:cmd_all
call :build debug "" && call :build release ""
goto :done

:cmd_install
call :start_emulator
call :install
goto :done

:cmd_run
call :start_emulator
echo [banega] Running in demo mode (press r for hot reload, q to quit)...
call "%FLUTTER%" run
goto :done

:cmd_api
call :start_emulator
echo [banega] Running against the local API at %EMU_API_URL% (press r for hot reload, q to quit)...
call "%FLUTTER%" run --dart-define=BANEGA_API_BASE_URL=%EMU_API_URL%
goto :done

:cmd_apk_api
set "API_URL=%~2"
if "%API_URL%"=="" (
  for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lan-ip.ps1"`) do set "API_URL=http://%%i:8765"
)
if "%API_URL%"=="" set "API_URL=%EMU_API_URL%"
call :build release "%API_URL%" || goto :done
call :start_emulator
call :install
goto :done

REM ---------------------------------------------------------------
:build
REM %1 = debug|release, %2 = API URL or ""
set "MODE=%~1"
set "URL=%~2"
if "%URL%"=="" (
  echo [banega] Building %MODE% APK in demo mode...
  call "%FLUTTER%" build apk --%MODE%
) else (
  echo [banega] Building %MODE% APK for API %URL%...
  call "%FLUTTER%" build apk --%MODE% --dart-define=BANEGA_API_BASE_URL=%URL%
)
if errorlevel 1 exit /b 1
echo [banega] APK: %CD%\build\app\outputs\flutter-apk\app-%MODE%.apk
exit /b 0

:start_emulator
"%ADB%" get-state >nul 2>&1
if not errorlevel 1 (
  echo [banega] Device already running.
  exit /b 0
)
echo [banega] Starting emulator %AVD%...
start "" "%EMU%" -avd %AVD% -gpu auto
"%ADB%" wait-for-device
:bootloop
set "BOOTED="
for /f "delims=" %%b in ('"%ADB%" shell getprop sys.boot_completed 2^>nul') do set "BOOTED=%%b"
if not "!BOOTED!"=="1" ( timeout /t 2 /nobreak >nul & goto :bootloop )
echo [banega] Emulator booted.
exit /b 0

:install
if not exist "%APK%" call :build release ""
echo [banega] Installing release APK...
"%ADB%" install -r "%APK%"
if errorlevel 1 (
  echo [banega] The installed build is signed differently. Removing it and installing again ^(this clears the app's login and local data^)...
  "%ADB%" uninstall %PKG% >nul
  "%ADB%" install "%APK%" || exit /b 1
)
"%ADB%" shell monkey -p %PKG% -c android.intent.category.LAUNCHER 1 >nul
echo [banega] Launched %PKG%.
exit /b 0

:done
popd
endlocal
