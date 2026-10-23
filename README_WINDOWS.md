# Panduan Build & Instalasi Native `FreeTDS` + `tds_fdw` di Windows (PostgreSQL 17 x64)

Dokumen ini menjelaskan langkah-langkah lengkap mulai dari persiapan *dependency*, konfigurasi (*setup config*), proses kompilasi (*build*) **FreeTDS (`sybdb.dll`)** dan **`tds_fdw` (`tds_fdw.dll`)** secara native di Windows 64-bit menggunakan **MSVC (Visual Studio 2022)**, hingga cara pemasangan dan penggunaannya di **PostgreSQL 17**.

---

## 1. Arsitektur & Dependency (Prasyarat)

`tds_fdw` adalah ekstensi *Foreign Data Wrapper* PostgreSQL untuk menghubungkan PostgreSQL ke Microsoft SQL Server / Sybase. Di balik layar, `tds_fdw` membutuhkan library **DB-Library (`sybdb`)** dari **FreeTDS**.

```
[PostgreSQL 17 (postgres.exe)]
       │
       ▼
[lib\tds_fdw.dll]  ──(memanggil API DB-Library)──►  [bin\sybdb.dll (FreeTDS 1.5.16)]
                                                           │
                                                           ├──► [bin\libssl-3-x64.dll & libcrypto-3-x64.dll] (TLS/SSL)
                                                           ▼
                                               [Microsoft SQL Server (TCP 1433)]
```

### Perangkat Lunak yang Dibutuhkan:
1. **Visual Studio 2022** (Community / Professional / Enterprise atau Build Tools) dengan komponen:
   * *MSVC v143 - VS 2022 C++ x64/x86 build tools*
   * *Windows 10/11 SDK*
   * *C++ CMake tools for Windows*
   * *(Lokasi di sistem ini: `D:\Program Files\Microsoft Visual Studio\2022\Community`)*
2. **PostgreSQL 17 (Windows x64)**
   * Pastikan folder `include\server`, `include\openssl`, `lib\postgres.lib`, `lib\libssl.lib`, dan `lib\libcrypto.lib` tersedia (bawaan installer resmi EnterpriseDB).
   * *(Lokasi di sistem ini: `D:\Program Files\PostgreSQL\17`)*
3. **Source Code FreeTDS 1.5.16**
   * Lokasi: `D:\BSS\freetds-1.5.16`
4. **Source Code `tds_fdw` (v2.0.5)**
   * Lokasi: `D:\BSS\tds_fdw` (di-clone dari `https://github.com/tds-fdw/tds_fdw.git`)

---

## 2. Setup Config & Build FreeTDS (`sybdb.dll`)

SQL Server modern mewajibkan paket login dienkripsi dengan **TLS/SSL** (*Pre-Login handshake*). Oleh karena itu, `sybdb.dll` **wajib** dikompilasi dengan dukungan **OpenSSL** (kita dapat langsung menggunakan OpenSSL 3.x bawaan PostgreSQL 17).

### Langkah 2.1: Generate Project CMake FreeTDS
Buka PowerShell, lalu jalankan:

```powershell
$cmake = "D:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

New-Item -ItemType Directory -Force -Path "D:\BSS\freetds-1.5.16\build" | Out-Null
Set-Location "D:\BSS\freetds-1.5.16\build"

& $cmake .. -G "Visual Studio 17 2022" -A x64 -DWITH_OPENSSL=OFF
```

### Langkah 2.2: Aktifkan OpenSSL 3.x (Bawaan PostgreSQL 17) di `config.h`
Tambahkan definisi berikut di bagian paling bawah file `D:\BSS\freetds-1.5.16\build\include\config.h`:

```c
#define HAVE_OPENSSL 1
#define HAVE_BIO_GET_DATA 1
#define HAVE_RSA_GET0_KEY 1
#define HAVE_ASN1_STRING_GET0_DATA 1
#define HAVE_SSL_SET_ALPN_PROTOS 1
#pragma comment(lib, "D:/Program Files/PostgreSQL/17/lib/libssl.lib")
#pragma comment(lib, "D:/Program Files/PostgreSQL/17/lib/libcrypto.lib")
```

### Langkah 2.3: Build Target `sybdb` dan `tsql`
Jalankan perintah kompilasi berikut di PowerShell:

```powershell
$env:CL = '/I"D:\Program Files\PostgreSQL\17\include"'
$cmake = "D:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

Set-Location "D:\BSS\freetds-1.5.16\build"
& $cmake --build . --config Release --target sybdb tsql
```

### Langkah 2.4: Verifikasi Hasil Build FreeTDS
Pastikan file berikut telah terbentuk:
* `D:\BSS\freetds-1.5.16\build\src\dblib\Release\sybdb.dll`
* `D:\BSS\freetds-1.5.16\build\src\dblib\Release\sybdb.lib`
* `D:\BSS\freetds-1.5.16\build\src\apps\Release\tsql.exe`

Cek status OpenSSL dengan menjalankan:
```powershell
$env:PATH = "D:\Program Files\PostgreSQL\17\bin;$env:PATH"
& "D:\BSS\freetds-1.5.16\build\src\apps\Release\tsql.exe" -C
```
Pastikan baris **`OpenSSL: yes`** tampil pada output.

---

## 3. Setup Config (Porting MSVC) & Build `tds_fdw.dll`

Source code asli `tds_fdw` dirancang untuk compiler GCC di Linux (`Makefile` / `PGXS`). Agar dapat dikompilasi secara native menggunakan MSVC (`cl.exe`) di Windows untuk PostgreSQL 17, diperlukan 3 penyesuaian kecil pada source code `D:\BSS\tds_fdw`:

### Langkah 3.1: Penyesuaian Source Code `tds_fdw`

1. **File `D:\BSS\tds_fdw\include\tds_fdw.h` (Baris 134–135)**  
   Tambahkan makro `PGDLLEXPORT` agar deklarasi cocok dengan definisi fungsi di `tds_fdw.c` (mencegah error MSVC `C2375: redefinition; different linkage`):
   ```c
   extern PGDLLEXPORT Datum tds_fdw_handler(PG_FUNCTION_ARGS);
   extern PGDLLEXPORT Datum tds_fdw_validator(PG_FUNCTION_ARGS);
   ```

2. **File `D:\BSS\tds_fdw\src\tds_fdw.c` (Bagian Header Atas)**  
   Di Windows/MSVC, `"postgres.h"` **wajib** di-include paling pertama sebelum header sistem (`<stdio.h>`, `<sys/stat.h>`), dan `<unistd.h>` (khusus Linux) dihapus:
   ```c
   #include "postgres.h"
   #include <stdio.h>
   #include <string.h>
   #include <sys/stat.h>
   ```

3. **File `D:\BSS\tds_fdw\src\tds_fdw.c` (Baris ~1309, ~1311, ~1318)**  
   Ganti atribut khusus GCC `__attribute__ ((fallthrough));` menjadi komentar standar:
   ```c
   /* fallthrough */
   ```

### Langkah 3.2: Jalankan Script Kompilasi Dinamis `build_windows.bat`

File [build_windows.bat](file:///D:/BSS/tds_fdw/build_windows.bat) telah dibuat **sepenuhnya dinamis** tanpa path statis:
* Otomatis mendeteksi folder `tds_fdw` menggunakan `%~dp0` dan folder `freetds-*` di sebelahnya.
* Otomatis mendeteksi instalasi **Visual Studio (`vcvars64.bat`)** menggunakan `vswhere.exe` (maupun pencarian di drive `C:`, `D:`, `E:`).
* Otomatis mendeteksi lokasi instalasi **PostgreSQL (`PG_DIR`)** melalui Windows Registry (`HKLM\SOFTWARE\PostgreSQL\Installations`).
* Menyalin `sybdb.dll` ke dalam folder `tds_fdw` setelah kompilasi selesai agar folder `tds_fdw` bisa langsung dibawa ke laptop/server lain.

Jalankan script untuk mengompilasi `tds_fdw.dll`:
```powershell
cmd.exe /c "build_windows.bat"
```

---

## 4. Cara Pasang (Instalasi) ke PostgreSQL (Dinamis di Laptop Manapun)

File-file yang dipasang ke direktori instalasi PostgreSQL (`%PG_DIR%`):

| File Sumber (Relatif terhadap folder `tds_fdw`) | Lokasi Tujuan di `%PG_DIR%` | Fungsi |
| :--- | :--- | :--- |
| `sybdb.dll` *(atau `..\freetds-*\build\src\dblib\Release\sybdb.dll`)* | `bin\sybdb.dll` & `lib\sybdb.dll` | Runtime library FreeTDS (DB-Library) |
| `tds_fdw.dll` | `lib\tds_fdw.dll` | Binary ekstensi `tds_fdw` |
| `tds_fdw.control` | `share\extension\tds_fdw.control` | File metadata ekstensi PostgreSQL |
| `sql\tds_fdw.sql` | `share\extension\tds_fdw--2.0.5.sql` | Script instalasi SQL ekstensi v2.0.5 |
| `tds_fdw--*.sql` | `share\extension\` | Script migrasi versi ekstensi |

### Instalasi Otomatis (Dinamis):
Klik kanan pada file **[install_postgresql17.bat](file:///D:/BSS/tds_fdw/install_postgresql17.bat)** $\rightarrow$ pilih **Run as administrator**.

Cara kerja deteksi dinamis di dalam `install_postgresql17.bat`:
1. **Lokasi Source (`SCRIPT_DIR`)**: Menggunakan `%~dp0` (otomatis mengikuti di folder mana pun script diletakkan).
2. **Lokasi `sybdb.dll`**: Mencari `%SCRIPT_DIR%\sybdb.dll` terlebih dahulu, lalu otomatis mencari di `..\freetds*\build\src\dblib\Release\sybdb.dll`.
3. **Lokasi PostgreSQL (`PG_DIR`) & Nama Service (`PG_SVC`)**:
   * Membaca `Base Directory` dan `Service ID` langsung dari Registry `HKLM\SOFTWARE\PostgreSQL\Installations`.
   * *Fallback 1*: Membaca path executable dari Windows Service `postgresql*` (`Win32_Service`).
   * *Fallback 2*: Mencari dari `pg_config.exe` di `PATH` atau memindai `C:\Program Files\PostgreSQL\*`, `D:\Program Files\PostgreSQL\*`, `E:\Program Files\PostgreSQL\*`.
   * *Fallback 3*: Meminta input path dari pengguna jika PostgreSQL diinstal secara portable tanpa Registry/Service.
4. Menghentikan sementara service PostgreSQL (`%PG_SVC%`), menyalin seluruh file ekstensi, lalu menyalakan kembali service tersebut.

---

## 5. Cara Penggunaan di PostgreSQL 17

Buka **pgAdmin 4** atau `psql`, lalu jalankan langkah-langkah SQL berikut:

### 5.1. Aktifkan Ekstensi `tds_fdw`
```sql
CREATE EXTENSION IF NOT EXISTS tds_fdw;
```

### 5.2. Buat Foreign Server ke SQL Server
```sql
CREATE SERVER mssql_server
    FOREIGN DATA WRAPPER tds_fdw
    OPTIONS (
        servername 'localhost',
        port '1433',
        database 'nama_database_mssql',
        tds_version '7.4',
        msg_handler 'notice'
    );
```

### 5.3. Buat User Mapping
```sql
CREATE USER MAPPING FOR CURRENT_USER
    SERVER mssql_server
    OPTIONS (
        username 'sa',
        password 'password_sa_anda'
    );
```

### 5.4. Buat Schema Tujuan & Import Foreign Schema
```sql
CREATE SCHEMA IF NOT EXISTS mssql_data;

IMPORT FOREIGN SCHEMA dbo
    LIMIT TO ("tjabatan", "tsite", "tdepartement", "TLevel")
    FROM SERVER mssql_server
    INTO mssql_data;
```

### 5.5. Query Tabel SQL Server dari PostgreSQL
```sql
SELECT * FROM mssql_data."tjabatan" LIMIT 10;
```
