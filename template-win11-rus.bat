@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ================= НАСТРОЙКИ WIFI ПРОФИЛЯ =================
set "WIFI_SSID=ИМЯ_СЕТИ"		    (имя сети к которой подключаетесь)	
set "DNS1=8.8.8.8"				      (адрес DNS1)	
set "DNS2=8.8.4.4"				      (адрес DNS2)	
set "PROXY_SERVER=адрес:порт"   (прокси. оставьте пустым, если прокси не нужен)
set "PROXY_BYPASS=<local>"      (исключения через точку с запятой)
set "PROXY_ENABLE=0"            (прокси. 1 – вкл, 0 – выкл)
:: =====================================================

echo ============================================
echo ПЕРЕКЛЮЧЕНИЕ НА ПРОФИЛЬ: %WIFI_SSID%
echo ============================================

:: Проверка прав администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ОШИБКА: Запустите скрипт от имени Администратора!
    pause
    exit /b 1
)

:: ---------- ЭТАП 1: Автоподключение ----------
echo [1/3] Настройка автоподключения...
for /f "tokens=2 delims=:" %%a in ('netsh wlan show profiles ^| findstr ":" 2^>nul') do (
    set "profile=%%a"
    set "profile=!profile:~1!"
    if not "!profile!"=="" (
        if /i not "!profile!"=="Все профили пользователей" (
            netsh wlan set profileparameter name="!profile!" connectionmode=manual >nul 2>&1
        )
    )
)
netsh wlan set profileparameter name="%WIFI_SSID%" connectionmode=auto
if %errorlevel% neq 0 (
    echo ОШИБКА: Профиль "%WIFI_SSID%" не найден. Сначала подключитесь вручную.
    pause
    exit /b 1
)
echo Автоподключение для "%WIFI_SSID%" включено.

:: ---------- ЭТАП 2: Поиск адаптера и переподключение ----------
echo [2/3] Перезапуск Wi-Fi адаптера...

:: Поиск Wi-Fi адаптера
set "WIFI_ADAPTER="
for /f "tokens=*" %%a in ('netsh interface show interface ^| findstr /i /c:"Беспроводная" /c:"Wi-Fi" /c:"Wireless" 2^>nul') do (
    set "line=%%a"
    for /f "tokens=3,*" %%b in ("!line!") do set "WIFI_ADAPTER=%%c"
)
if "%WIFI_ADAPTER%"=="" set "WIFI_ADAPTER=Беспроводная сеть"
echo Адаптер: %WIFI_ADAPTER%

:: Перезапуск адаптера (выключить → включить)
netsh interface set interface "%WIFI_ADAPTER%" admin=disabled >nul 2>&1
timeout /t 2 /nobreak >nul
netsh interface set interface "%WIFI_ADAPTER%" admin=enabled >nul 2>&1

:: Ожидание подключения (проверяем состояние адаптера)
echo Ожидаем подключения...
set "CONNECTED=0"
for /l %%i in (1,1,30) do (
    timeout /t 1 /nobreak >nul
    netsh interface show interface "%WIFI_ADAPTER%" | findstr /i /c:"Подключен" /c:"Connected" >nul
    if !errorlevel! equ 0 (
        set "CONNECTED=1"
        echo Подключено через %%i сек.
        goto :connected
    )
)

:connected
if "%CONNECTED%"=="0" (
    echo ВНИМАНИЕ: Не удалось подтвердить подключение за 30 секунд.
    echo Возможно, сеть "%WIFI_SSID%" недоступна.
    echo Настройки DNS и прокси всё равно будут применены к адаптеру.
    choice /c YN /m "Продолжить настройку? (Y - да, N - нет)"
    if errorlevel 2 exit /b 1
)

:: ---------- ЭТАП 3: DNS и прокси ----------
echo [3/3] Настройка DNS и прокси...

:: DNS
netsh interface ip set dns name="%WIFI_ADAPTER%" source=static addr=%DNS1% register=primary
if %errorlevel% equ 0 (
    netsh interface ip add dns name="%WIFI_ADAPTER%" addr=%DNS2% index=2 >nul 2>&1
    echo DNS: %DNS1%, %DNS2%
) else (
    echo ОШИБКА при установке DNS. Проверьте права администратора.
)

:: Прокси
if "%PROXY_ENABLE%"=="1" (
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f >nul 2>&1
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "%PROXY_SERVER%" /f >nul 2>&1
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /t REG_SZ /d "%PROXY_BYPASS%" /f >nul 2>&1
    netsh winhttp set proxy "%PROXY_SERVER%" "%PROXY_BYPASS%" >nul 2>&1
    echo Прокси ВКЛЮЧЕН: %PROXY_SERVER%
) else (
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >nul 2>&1
    reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /f >nul 2>&1
    reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /f >nul 2>&1
    netsh winhttp reset proxy >nul 2>&1
    echo Прокси ОТКЛЮЧЕН
)

echo ============================================
echo ГОТОВО: Профиль "%WIFI_SSID%" активирован
echo ============================================
pause
exit /b 0
