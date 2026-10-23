@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: Dynamic Build Script for tds_fdw.dll on Windows (MSVC x64)
:: Otomatis mendeteksi lokasi Visual Studio, PostgreSQL, FreeTDS, dan tds_fdw
:: ============================================================================

:: 1. Deteksi Dinamis Folder tds_fdw (berdasarkan lokasi script ini)
set "TDS_FDW_DIR=%~dp0"
if "%TDS_FDW_DIR:~-1%"=="\" set "TDS_FDW_DIR=%TDS_FDW_DIR:~0,-1%"

:: 2. Deteksi Dinamis Folder FreeTDS
set "FREETDS_DIR="
for /d %%D in ("%TDS_FDW_DIR%\..\freetds*") do (
    if exist "%%~fD\include\sybdb.h" set "FREETDS_DIR=%%~fD"
)
if not defined FREETDS_DIR (
    set /p "FREETDS_DIR=Masukkan path folder source FreeTDS (contoh: D:\BSS\freetds-1.5.16): "
)
if "%FREETDS_DIR:~-1%"=="\" set "FREETDS_DIR=%FREETDS_DIR:~0,-1%"

:: 3. Deteksi Dinamis Visual Studio (vcvars64.bat) menggunakan vswhere.exe
set "VCVARS_BAT="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
    for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
        if exist "%%I\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS_BAT=%%I\VC\Auxiliary\Build\vcvars64.bat"
    )
)
if not defined VCVARS_BAT (
    for %%D in (C D E) do (
        for %%E in (Community Professional Enterprise BuildTools) do (
            if exist "%%D:\Program Files\Microsoft Visual Studio\2022\%%E\VC\Auxiliary\Build\vcvars64.bat" (
                set "VCVARS_BAT=%%D:\Program Files\Microsoft Visual Studio\2022\%%E\VC\Auxiliary\Build\vcvars64.bat"
            )
        )
    )
)
if not defined VCVARS_BAT (
    set /p "VCVARS_BAT=Masukkan path lengkap ke vcvars64.bat Visual Studio: "
)

:: 4. Deteksi Dinamis Lokasi Instalasi PostgreSQL (PG_DIR)
set "PG_DIR="
for /f "tokens=*" %%K in ('reg query "HKLM\SOFTWARE\PostgreSQL\Installations" 2^>nul ^| findstr /i "postgresql"') do (
    for /f "tokens=3,*" %%A in ('reg query "%%K" /v "Base Directory" 2^>nul ^| findstr /i "REG_SZ"') do (
        set "PG_DIR=%%B"
    )
)
if not defined PG_DIR (
    for %%D in (C D E) do (
        for /d %%V in ("%%D:\Program Files\PostgreSQL\*") do (
            if exist "%%~fV\lib\postgres.lib" set "PG_DIR=%%~fV"
        )
    )
)
if not defined PG_DIR (
    set /p "PG_DIR=Masukkan path folder PostgreSQL (contoh: C:\Program Files\PostgreSQL\17): "
)
if "%PG_DIR:~-1%"=="\" set "PG_DIR=%PG_DIR:~0,-1%"

echo ============================================================================
echo  Konfigurasi Build Terdeteksi:
echo  - Visual Studio : "%VCVARS_BAT%"
echo  - PostgreSQL    : "%PG_DIR%"
echo  - FreeTDS       : "%FREETDS_DIR%"
echo  - tds_fdw       : "%TDS_FDW_DIR%"
echo ============================================================================

call "%VCVARS_BAT%"
if errorlevel 1 exit /b 1

cd /d "%TDS_FDW_DIR%"

cl.exe /nologo /MD /O2 /W3 ^
  /DWIN32 /D_WINDOWS /D__WIN32__ /D_CRT_SECURE_NO_WARNINGS ^
  /I"%TDS_FDW_DIR%\include" ^
  /I"%PG_DIR%\include\server\port\win32_msvc" ^
  /I"%PG_DIR%\include\server\port\win32" ^
  /I"%PG_DIR%\include\server" ^
  /I"%PG_DIR%\include" ^
  /I"%FREETDS_DIR%\include" ^
  /I"%FREETDS_DIR%\build\include" ^
  src\tds_fdw.c src\options.c src\deparse.c ^
  /LD /link ^
  /LIBPATH:"%PG_DIR%\lib" postgres.lib ^
  /LIBPATH:"%FREETDS_DIR%\build\src\dblib\Release" sybdb.lib ^
  ws2_32.lib ^
  /OUT:tds_fdw.dll

if errorlevel 1 exit /b 1

:: Salin juga sybdb.dll ke folder tds_fdw agar mudah dibawa ke laptop lain
if exist "%FREETDS_DIR%\build\src\dblib\Release\sybdb.dll" (
    copy /Y "%FREETDS_DIR%\build\src\dblib\Release\sybdb.dll" "%TDS_FDW_DIR%\sybdb.dll" >nul
)

echo.
echo [SUCCESS] Build tds_fdw.dll selesai!
