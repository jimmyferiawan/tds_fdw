@echo off
setlocal EnableDelayedExpansion

:: ============================================================================
:: Dynamic Installer for FreeTDS (sybdb.dll) + tds_fdw on Windows PostgreSQL
:: Otomatis mendeteksi lokasi source code, service PostgreSQL, dan PG_DIR
:: ============================================================================

:: 1. Cek Hak Akses Administrator
net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Script ini membutuhkan hak akses Administrator.
    echo Silakan klik kanan file ini lalu pilih "Run as administrator".
    pause
    exit /b 1
)

:: 2. Deteksi Dinamis Folder Script (tds_fdw)
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: 3. Deteksi Dinamis File sybdb.dll
set "SYBDB_DLL="
if exist "%SCRIPT_DIR%\sybdb.dll" (
    set "SYBDB_DLL=%SCRIPT_DIR%\sybdb.dll"
) else (
    for /d %%D in ("%SCRIPT_DIR%\..\freetds*") do (
        if exist "%%~fD\build\src\dblib\Release\sybdb.dll" (
            set "SYBDB_DLL=%%~fD\build\src\dblib\Release\sybdb.dll"
        )
    )
)

if not defined SYBDB_DLL (
    echo [WARNING] File sybdb.dll tidak ditemukan secara otomatis.
    set /p "SYBDB_DLL=Masukkan path lengkap ke file sybdb.dll: "
)

if not exist "%SYBDB_DLL%" (
    echo [ERROR] File sybdb.dll tidak ditemukan di: "%SYBDB_DLL%"
    pause
    exit /b 1
)

if not exist "%SCRIPT_DIR%\tds_fdw.dll" (
    echo [ERROR] File tds_fdw.dll tidak ditemukan di: "%SCRIPT_DIR%\tds_fdw.dll"
    echo Jalankan build_windows.bat terlebih dahulu.
    pause
    exit /b 1
)

:: 4. Deteksi Dinamis Lokasi Instalasi PostgreSQL (PG_DIR) & Nama Service (PG_SVC)
set "PG_DIR="
set "PG_SVC="

:: 4a. Cari dari Registry PostgreSQL Installations (EnterpriseDB Installer)
for /f "tokens=*" %%K in ('reg query "HKLM\SOFTWARE\PostgreSQL\Installations" 2^>nul ^| findstr /i "postgresql"') do (
    for /f "tokens=3,*" %%A in ('reg query "%%K" /v "Base Directory" 2^>nul ^| findstr /i "REG_SZ"') do (
        set "PG_DIR=%%B"
    )
    for /f "tokens=3,*" %%A in ('reg query "%%K" /v "Service ID" 2^>nul ^| findstr /i "REG_SZ"') do (
        set "PG_SVC=%%B"
    )
)

:: 4b. Fallback: Cari dari Windows Service postgresql* jika Registry tidak ada
if not defined PG_DIR (
    for /f "usebackq tokens=1,2 delims=|" %%A in (`powershell -NoProfile -Command "$s = Get-CimInstance Win32_Service -Filter \"Name LIKE 'postgresql%%'\" | Select-Object -First 1; if ($s -and $s.PathName -match '\"([^\"]+)[\\/]bin[\\/]pg_ctl\.exe\"') { Write-Output ($s.Name + '|' + $Matches[1]) }"`) do (
        set "PG_SVC=%%A"
        set "PG_DIR=%%B"
    )
)

:: 4c. Fallback: Cari dari pg_config.exe di PATH
if not defined PG_DIR (
    for /f "delims=" %%P in ('where pg_config.exe 2^>nul') do (
        for %%I in ("%%~dpP..") do set "PG_DIR=%%~fI"
    )
)

:: 4d. Fallback: Cari di folder standar C:\ dan D:\
if not defined PG_DIR (
    for %%D in (C D E) do (
        for /d %%V in ("%%D:\Program Files\PostgreSQL\*") do (
            if exist "%%~fV\bin\postgres.exe" set "PG_DIR=%%~fV"
        )
    )
)

:: 4e. Jika masih belum ditemukan, minta input dari user
if not defined PG_DIR (
    echo [WARNING] Folder instalasi PostgreSQL tidak terdeteksi secara otomatis.
    set /p "PG_DIR=Masukkan path folder PostgreSQL (contoh: C:\Program Files\PostgreSQL\17): "
)

:: Bersihkan trailing slash jika ada
if "%PG_DIR:~-1%"=="\" set "PG_DIR=%PG_DIR:~0,-1%"

if not exist "%PG_DIR%\bin\postgres.exe" (
    echo [ERROR] Instalasi PostgreSQL tidak valid di: "%PG_DIR%"
    echo Pastikan folder "%PG_DIR%\bin\postgres.exe" ada.
    pause
    exit /b 1
)

echo ============================================================================
echo  Konfigurasi Terdeteksi:
echo  - Source tds_fdw : "%SCRIPT_DIR%"
echo  - File sybdb.dll : "%SYBDB_DLL%"
echo  - PostgreSQL Dir : "%PG_DIR%"
if defined PG_SVC (
echo  - Service Name   : "%PG_SVC%"
)
echo ============================================================================
echo.

:: 5. Hentikan Sementara Service PostgreSQL (jika terdeteksi)
if defined PG_SVC (
    echo Menghentikan sementara service %PG_SVC%...
    net stop "%PG_SVC%" >nul 2>&1
)

:: 6. Salin File DLL, Control, dan SQL
echo Menyalin file ekstensi ke "%PG_DIR%"...

copy /Y "%SYBDB_DLL%" "%PG_DIR%\bin\sybdb.dll" >nul
if errorlevel 1 (
    echo [ERROR] Gagal menyalin sybdb.dll ke "%PG_DIR%\bin\".
    if defined PG_SVC net start "%PG_SVC%" >nul 2>&1
    pause
    exit /b 1
)

copy /Y "%SYBDB_DLL%" "%PG_DIR%\lib\sybdb.dll" >nul
copy /Y "%SCRIPT_DIR%\tds_fdw.dll" "%PG_DIR%\lib\tds_fdw.dll" >nul
copy /Y "%SCRIPT_DIR%\tds_fdw.control" "%PG_DIR%\share\extension\tds_fdw.control" >nul

if exist "%SCRIPT_DIR%\sql\tds_fdw.sql" (
    copy /Y "%SCRIPT_DIR%\sql\tds_fdw.sql" "%PG_DIR%\share\extension\tds_fdw--2.0.5.sql" >nul
)
for %%F in ("%SCRIPT_DIR%\tds_fdw--*.sql") do (
    copy /Y "%%~fF" "%PG_DIR%\share\extension\" >nul
)

:: 7. Jalankan Kembali Service PostgreSQL
if defined PG_SVC (
    echo Menjalankan kembali service %PG_SVC%...
    net start "%PG_SVC%" >nul 2>&1
)

echo.
echo [SUCCESS] Instalasi sybdb.dll dan tds_fdw ke "%PG_DIR%" berhasil!
echo Anda sekarang dapat menjalankan di PostgreSQL:
echo   CREATE EXTENSION IF NOT EXISTS tds_fdw;
pause
