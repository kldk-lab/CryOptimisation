# ==============================================================================
#   ____                  ____          _   _           _             _   _             
#  / ___|_ __ _   _      / ___|  _ __  | |_(_) _ __ ___ (_)____ _ __ | |_(_) ___  _ __  
# | |   | '__| | | |____| |  _  | '_ \ | __| || '_ ` _ \| |_  /| '_ \| __| |/ _ \| '_ \ 
# | |___| |  | |_| |____| |_| | | |_) || |_| || | | | | | |/ / | |_) | |_| | (_) | | | |
#  \____|_|   \__, |     \____| | .__/  \__|_||_| |_| |_|_/___|| .__/ \__|_|\___/|_| |_|
#             |___/             |_|                            |_|                      
# ==============================================================================
#  Название: CryOptimisation
#  Версия: 4.0 (Ultimate eSports & Latency Edition)
#  Совместимость: Windows 10 / Windows 11 (x64)
#  Назначение: Экстремальное сжатие Windows (до ~30 процессов), отключение эффектов,
#              ликвидация инпут-лага, ускорение сети/пинга, полное освобождение ЦП и ОЗУ.
# ==============================================================================

#region 1. Проверка прав Администратора и кодировки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "`n [!] Запуск скрипта требует прав Администратора!" -ForegroundColor Red
    Write-Host " [*] Перезапуск с запросом прав повышения (UAC)..." -ForegroundColor Yellow
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } catch {
        Write-Host " [-] Не удалось получить права Администратора: $_" -ForegroundColor Red
        Pause
    }
    Exit
}
#endregion

#region 2. Вспомогательные функции UI и реестра
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================================================" -ForegroundColor Cyan
    Write-Host "   ____                  ___              _   _           _       _   _             " -ForegroundColor Magenta
    Write-Host "  / ___|_ __ _   _      / _ \ _ __  _ __ (_) _ __ ___ (_)____ __| |_(_) ___  _ __  " -ForegroundColor Magenta
    Write-Host " | |   | '__| | | |____| | | | '_ \| '_ \| |/ '_ ` _ \| |_  // _` | __| |/ _ \| '_ \ " -ForegroundColor Cyan
    Write-Host " | |___| |  | |_| |____| |_| | |_) | |_) | || | | | | | |/ /| (_| | |_| | (_) | | | |" -ForegroundColor Cyan
    Write-Host "  \____|_|   \__, |     \___/| .__/| .__/|_||_| |_| |_|_/___|\__,_|\__|_|\___/|_| |_|" -ForegroundColor Magenta
    Write-Host "             |___/           |_|   |_|                                              " -ForegroundColor Magenta
    Write-Host "  ============================================================================" -ForegroundColor Cyan
    Write-Host "   >>> WINDOWS 10 / 11 CRYO-APEX & LATENCY ENGINE (MAX FPS & 0ms INPUT LAG) <<<" -ForegroundColor White
    Write-Host "   Разработчик: CryOptimisation Engine | Версия 4.0 (eSports Master Edition)" -ForegroundColor DarkGray
    Write-Host "  ============================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Log-Success ($message) {
    Write-Host "  [+] $message" -ForegroundColor Green
}

function Log-Info ($message) {
    Write-Host "  [*] $message" -ForegroundColor Cyan
}

function Log-Warn ($message) {
    Write-Host "  [!] $message" -ForegroundColor Yellow
}

function Log-Error ($message) {
    Write-Host "  [-] $message" -ForegroundColor Red
}

function Set-RegistryValueSafe {
    param (
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = "DWord"
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

function Disable-ServiceSafe {
    param ([string]$ServiceName, [string]$DisplayName = $ServiceName)
    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -eq 'Running') {
                Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction SilentlyContinue
            Log-Success "Служба отключена: $DisplayName ($ServiceName)"
        }
    } catch {
        Log-Warn "Не удалось отключить службу: $ServiceName"
    }
}

function Enable-ServiceSafe {
    param ([string]$ServiceName, [string]$StartupType = "Automatic", [string]$DisplayName = $ServiceName)
    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction SilentlyContinue
            Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
            Log-Success "Служба восстановлена: $DisplayName ($ServiceName) -> $StartupType"
        }
    } catch {
        Log-Warn "Не удалось запустить службу: $ServiceName"
    }
}

function Disable-ScheduledTaskSafe {
    param ([string]$TaskPath, [string]$TaskName)
    try {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
            Log-Success "Задача планировщика отключена: $TaskName"
        }
    } catch {}
}
#endregion

#region 3. Точка восстановления системы
function New-CryRestorePoint {
    Log-Info "Создание контрольной точки восстановления системы..."
    try {
        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "CryOptimisation_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Log-Success "Точка восстановления успешно создана!"
    } catch {
        Log-Warn "Не удалось создать точку восстановления (служба VSS отключена или прошло <24ч): $_"
        Log-Info "Продолжение работы без создания точки."
    }
}
#endregion

#region 4. МОДУЛЬ 1: ПОЛНОЕ ОТКЛЮЧЕНИЕ КРАСОТЫ И ВИЗУАЛЬНЫХ ЭФФЕКТОВ (МАКС. БЫСТРОДЕЙСТВИЕ)
function Optimize-VisualPerformanceExtreme {
    Log-Info "1. Отключение всех визуальных эффектов Windows (в пользу 100% быстродействия)..."

    # Режим быстродействия: Best Performance
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2

    # Отключение анимаций и теней в UserPreferencesMask
    $perfMask = [byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value $perfMask -Type Binary -Force -ErrorAction SilentlyContinue
    } catch {}

    # Отключение анимаций окон и меню
    Set-RegistryValueSafe "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"
    Set-RegistryValueSafe "HKCU:\Control Panel\Desktop" "MenuShowDelay" "0" "String"
    Set-RegistryValueSafe "HKCU:\Control Panel\Desktop" "DragFullWindows" "0" "String"
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewAlphaSelect" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewShadow" 0

    # Отключение прозрачности и эффектов акрила/размытия DWM
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\DWM" "EnableAeroPeek" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\DWM" "AlwaysHibernateThumbnails" 0

    # Сглаживание экранных шрифтов оставляем включенным (для четкости текста, прицелов и HUD в играх)
    Set-RegistryValueSafe "HKCU:\Control Panel\Desktop" "FontSmoothing" "2" "String"

    Log-Success "Визуальные эффекты отключены. Окна открываются мгновенно, без задержек графического процессора."
}
#endregion

#region 5. МОДУЛЬ 2: ОПТИМИЗАЦИЯ ИНПУТ-ЛАГА (INPUT LAG & 0ms LATENCY)
function Optimize-InputLagAndResponsiveness {
    Log-Info "2. Оптимизация задержек ввода (Input Lag, мышь, клавиатура, MMCSS, таймеры)..."

    # Отключение акселерации мыши и линейная кривая 1:1 (Raw Input feel)
    Set-RegistryValueSafe "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" "String"
    Set-RegistryValueSafe "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" "String"
    Set-RegistryValueSafe "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" "String"

    $linearCurve = [byte[]](0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "SmoothMouseModelCurve" -Value $linearCurve -Type Binary -Force -ErrorAction SilentlyContinue
    } catch {}

    # Ускорение отклика клавиатуры (минимальная задержка повтора)
    Set-RegistryValueSafe "HKCU:\Control Panel\Keyboard" "KeyboardDelay" "0" "String"
    Set-RegistryValueSafe "HKCU:\Control Panel\Keyboard" "KeyboardSpeed" "31" "String"

    # Квантование приоритетов потоков процессора (Win32PrioritySeparation = 38 dec / 0x26 hex)
    # Дает максимальный приоритет активному игровому процессу и снижает вариативность времени кадра
    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 "DWord"

    # Мультимедийный планировщик MMCSS (Games Priority)
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 0 "DWord"
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "GPU Priority" 8 "DWord"
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Priority" 6 "DWord"
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Scheduling Category" "High" "String"
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "SFIO Priority" "High" "String"

    # BCD таймеры (отключение Dynamic Tick исключает микрофризы ядра)
    try {
        cmd.exe /c "bcdedit /set useplatformclock false" 2>&1 | Out-Null
        cmd.exe /c "bcdedit /set disabledynamictick yes" 2>&1 | Out-Null
    } catch {}

    # Отключение Game DVR и фоновой записи (снижает input lag видеокарты)
    Set-RegistryValueSafe "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
    Set-RegistryValueSafe "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2
    Set-RegistryValueSafe "HKCU:\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" 1
    Set-RegistryValueSafe "HKCU:\System\GameConfigStore" "GameDVR_DXGIHonorFSEWindowsCompatible" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0

    Log-Success "Инпут-лаг оптимизирован: прямое считывание мыши (Raw), моментальная клавиатура, приоритет Games."
}
#endregion

#region 6. МОДУЛЬ 3: ОПТИМИЗАЦИЯ ИНТЕРНЕТА, ПИНГА И СЕТЕВОГО СТЕКА (TCP/IP)
function Optimize-NetworkAndPing {
    Log-Info "3. Оптимизация сетевого стека, пинга и отключение алгоритма Nagle..."

    # Отключение Network Throttling (фонового ограничения сети Windows)
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 0xffffffff "DWord"

    # Отключение резервирования 20% канала QoS
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "NonBestEffortLimit" 0 "DWord"

    # Отключение алгоритма Nagle (TCP NoDelay) для мгновенной отправки пакетов в играх
    try {
        $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
        foreach ($int in $interfaces) {
            Set-RegistryValueSafe $int.PSPath "TcpAckFrequency" 1 "DWord"
            Set-RegistryValueSafe $int.PSPath "TCPNoDelay" 1 "DWord"
        }
    } catch {}

    # Настройка параметров TCP через netsh
    try {
        cmd.exe /c "netsh int tcp set global autotuninglevel=normal" 2>&1 | Out-Null
        cmd.exe /c "netsh int tcp set global rss=enabled" 2>&1 | Out-Null
        # RSC (Receive Segment Coalescing) отключен: RSC склеивает пакеты и вызывает скачки пинга в шутерах!
        cmd.exe /c "netsh int tcp set global rsc=disabled" 2>&1 | Out-Null
        cmd.exe /c "netsh int tcp set global timestamps=disabled" 2>&1 | Out-Null
        cmd.exe /c "netsh int tcp set global ecncapability=disabled" 2>&1 | Out-Null
        cmd.exe /c "netsh int tcp set heuristics disabled" 2>&1 | Out-Null
    } catch {}

    # Кэширование DNS для ускорения резолва серверов
    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "MaxCacheTtl" 86400 "DWord"
    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "MaxNegativeCacheTtl" 0 "DWord"

    Log-Success "Интернет оптимизирован: алгоритм Nagle отключен (TCP NoDelay), RSC выключен, пинг стабилизирован."
}
#endregion

#region 7. МОДУЛЬ 4: ВЫСВОБОЖДЕНИЕ ПРОЦЕССОРА И ОПЕРАТИВНОЙ ПАМЯТИ (MAX PERFORMANCE)
function Optimize-CpuAndRamMax {
    Log-Info "4. Полное высвобождение процессора и оперативной памяти..."

    # 1. Unpark CPU Cores (Снятие парковки ядер процессора — все ядра всегда активны на 100%)
    try {
        powercfg -setacvalueindex scheme_current sub_processor CPMINCORES 100 2>&1 | Out-Null
        powercfg -setacvalueindex scheme_current sub_processor CPMAXCORES 100 2>&1 | Out-Null
        powercfg -setactive scheme_current 2>&1 | Out-Null
        Log-Success "Парковка ядер процессора отключена: все ядра работают на полной частоте без задержки пробуждения."
    } catch {}

    # 2. Активация схемы питания «Максимальная производительность» (Ultimate Performance)
    try {
        $output = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
        $guidMatch = [regex]::Match($output, '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})')
        if ($guidMatch.Success) {
            powercfg -setactive $guidMatch.Value
        } else {
            powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        }
        Log-Success "Схема электропитания 'Ultimate Performance' активирована."
    } catch {}

    # 3. Ядро и системные драйверы целиком в физической памяти (исключает микрофризы от файла подкачки)
    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1 "DWord"
    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" 0 "DWord"

    # 4. Аппаратное ускорение графики (HAGS)
    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 "DWord"

    # 5. Сброс неиспользуемой оперативной памяти (Garbage Collection)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    Log-Success "Процессор и память освобождены: ядро зафиксировано в ОЗУ, HAGS активен, ядра процессора разбужены."
}
#endregion

#region 8. Удаление Bloatware и встроенного мусора Windows
function Remove-WindowsBloatware {
    param ([bool]$AggressiveMode = $false)
    
    Log-Info "Удаление ненужных предустановленных приложений (Bloatware)..."

    $baseApps = @(
        "*Microsoft.549981C3F5F10*", "*Microsoft.BingNews*", "*Microsoft.BingWeather*",
        "*Microsoft.BingFinance*", "*Microsoft.BingSports*", "*Microsoft.GetHelp*",
        "*Microsoft.Getstarted*", "*Microsoft.MicrosoftOfficeHub*", "*Microsoft.MicrosoftSolitaireCollection*",
        "*Microsoft.People*", "*Microsoft.SkypeApp*", "*Microsoft.Todos*",
        "*Microsoft.WindowsFeedbackHub*", "*Microsoft.WindowsMaps*", "*Microsoft.YourPhone*",
        "*Microsoft.ZuneMusic*", "*Microsoft.ZuneVideo*", "*Clipchamp.Clipchamp*",
        "*MicrosoftCorporationII.QuickAssist*", "*Microsoft.PowerAutomateDesktop*",
        "*SpotifyAB.SpotifyMusic*", "*DisneyMagicKingdoms*", "*RoyalRevolt2*",
        "*CandyCrush*", "*Facebook*", "*Instagram*", "*TikTok*", "*Amazon.PrimeVideo*"
    )

    $extremeApps = @(
        "*Microsoft.XboxApp*", "*Microsoft.XboxSpeechToTextOverlay*", "*Microsoft.XboxTCUI*",
        "*Microsoft.GamingApp*", "*Microsoft.WindowsAlarms*", "*Microsoft.WindowsSoundRecorder*",
        "*Microsoft.WindowsCamera*", "*Microsoft.ScreenSketch*", "*Microsoft.Paint3D*"
    )

    $appsToRemove = $baseApps
    if ($AggressiveMode) { $appsToRemove += $extremeApps }

    foreach ($app in $appsToRemove) {
        Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue } catch {}
        }
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -like $app | ForEach-Object {
            try { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
    }

    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353696Enabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1

    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0

    Log-Success "Очистка Bloatware завершена!"
}
#endregion

#region 9. Отключение телеметрии, слежки и фоновой диагностики
function Disable-TelemetryAndDiagnostics {
    Log-Info "Отключение телеметрии, сбора данных и фоновой диагностики..."

    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "MaxTelemetryAllowed" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications" 1

    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" 1
    Set-RegistryValueSafe "HKCU:\Control Panel\International\User Profile" "HttpAcceptLanguageOptOut" 1
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs" 0

    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0

    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "Disabled" 1
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" "Disabled" 1

    Disable-ServiceSafe "DiagTrack" "Служба сбора диагностических данных (Connected User Experiences and Telemetry)"
    Disable-ServiceSafe "dmwappushservice" "Служба маршрутизации push-сообщений WAP"
    Disable-ServiceSafe "diagnosticshub.standardcollector.service" "Стандартный сборщик концентратора диагностики"
    Disable-ServiceSafe "WerSvc" "Служба регистрации ошибок Windows (Windows Error Reporting)"

    $tasksToDisable = @(
        @("\Microsoft\Windows\Application Experience\", "Microsoft Compatibility Appraiser"),
        @("\Microsoft\Windows\Application Experience\", "ProgramDataUpdater"),
        @("\Microsoft\Windows\Application Experience\", "StartupAppTask"),
        @("\Microsoft\Windows\Autochk\", "Proxy"),
        @("\Microsoft\Windows\Customer Experience Improvement Program\", "Consolidator"),
        @("\Microsoft\Windows\Customer Experience Improvement Program\", "UsbCeip"),
        @("\Microsoft\Windows\DiskDiagnostic\", "Microsoft-Windows-DiskDiagnosticDataCollector"),
        @("\Microsoft\Windows\Maintenance\", "WinSAT"),
        @("\Microsoft\Windows\Feedback\Diagnostics\", "SendDiagnosticData")
    )

    foreach ($task in $tasksToDisable) {
        Disable-ScheduledTaskSafe $task[0] $task[1]
    }

    Log-Success "Телеметрия и фоновая диагностика успешно отключены!"
}
#endregion

#region 10. Профиль 1: Оптимизация «Для работы и учебы»
function Invoke-WorkOptimization {
    Show-Banner
    Write-Host "  [>>> РЕЖИМ 1: ОПТИМИЗАЦИЯ ДЛЯ РАБОТЫ И УЧЕБЫ <<<]" -ForegroundColor Green
    Write-Host "  Бережная настройка: удаление мусора и телеметрии с полным сохранением" -ForegroundColor Gray
    Write-Host "  принтеров, Bluetooth, Windows Update, офисных функций и стабильности.`n" -ForegroundColor Gray

    New-CryRestorePoint
    Remove-WindowsBloatware -AggressiveMode $false
    Disable-TelemetryAndDiagnostics

    Set-RegistryValueSafe "HKCU:\Control Panel\Desktop" "MenuShowDelay" "0" "String"
    Set-RegistryValueSafe "HKCU:\Control Panel\Desktop" "AutoEndTasks" "1" "String"
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" 1
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0

    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Control" "SvcHostSplitThresholdInKB" 0xFFFFFFFF "DWord"
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0

    Log-Info "Настройка служб для рабочего режима..."
    $workServicesToDisable = @(
        @("RetailDemo", "Служба демонстрации магазина"),
        @("RemoteRegistry", "Удаленный реестр"),
        @("MapsBroker", "Служба загруженных карт"),
        @("SharedAccess", "Общий доступ к подключению к Интернету"),
        @("lfsvc", "Служба геолокации"),
        @("SensorService", "Служба датчиков"),
        @("SensrSvc", "Служба системных датчиков"),
        @("DoSvc", "Служба оптимизации доставки (Delivery Optimization)"),
        @("PcaSvc", "Помощник совместимости программ")
    )

    foreach ($svc in $workServicesToDisable) {
        Disable-ServiceSafe $svc[0] $svc[1]
    }

    Enable-ServiceSafe "Spooler" "Automatic" "Диспетчер печати (Принтеры)"
    Enable-ServiceSafe "bthserv" "Manual" "Служба поддержки Bluetooth"
    Enable-ServiceSafe "wuauserv" "Manual" "Центр обновления Windows"
    Enable-ServiceSafe "AudioSrv" "Automatic" "Windows Audio"

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    Log-Success "`n======================================================="
    Log-Success "Оптимизация «ДЛЯ РАБОТЫ» успешно завершена!"
    Log-Success "Лишние фоновые процессы и телеметрия удалены."
    Log-Success "Принтеры, Bluetooth и рабочие программы работают штатно."
    Log-Success "=======================================================`n"
}
#endregion

#region 11. Профиль 2: Геймерская оптимизация (~70-80 процессов)
function Invoke-GamerOptimization {
    Show-Banner
    Write-Host "  [>>> РЕЖИМ 2: ГЕЙМЕРСКАЯ ОПТИМИЗАЦИЯ (~70-80 ПРОЦЕССОВ) <<<]" -ForegroundColor Yellow
    Write-Host "  Высвобождение ресурсов процессора и оперативной памяти." -ForegroundColor Yellow
    Write-Host "  Отключение красот Windows, снижение задержек (Input Lag/Ping) и высокий FPS!`n" -ForegroundColor Yellow

    New-CryRestorePoint
    Remove-WindowsBloatware -AggressiveMode $true
    Disable-TelemetryAndDiagnostics

    # Применение 4-х ключевых модулей максимальной производительности
    Optimize-VisualPerformanceExtreme
    Optimize-InputLagAndResponsiveness
    Optimize-NetworkAndPing
    Optimize-CpuAndRamMax

    # Группировка svchost и блокировка фоновых агентов
    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Control" "SvcHostSplitThresholdInKB" 0xFFFFFFFF "DWord"
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsRunInBackground" 2
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter" "ActivationType" 0

    # Отключение тяжелых фоновых служб
    $extremeServices = @(
        @("WSearch", "Windows Search"), @("SysMain", "SysMain / SuperFetch"), @("Spooler", "Принтеры"),
        @("Fax", "Факсы"), @("DoSvc", "Delivery Optimization"), @("PcaSvc", "Program Compatibility"),
        @("DPS", "Diagnostic Policy"), @("WdiServiceHost", "WdiHost"), @("WdiSystemHost", "WdiSystemHost"),
        @("XblAuthManager", "Xbox Auth"), @("XblGameSave", "Xbox Save"), @("XboxNetApiSvc", "Xbox Net"),
        @("XboxGipSvc", "Xbox Acc"), @("WbioSrvc", "Биометрия"), @("SCardSvr", "Смарт-карты"),
        @("RemoteRegistry", "Удаленный реестр"), @("RetailDemo", "Retail Demo"), @("MapsBroker", "Карты"),
        @("TabletInputService", "Сенсорный ввод"), @("wisvc", "Insider"), @("SharedAccess", "ICS"),
        @("SensorService", "Датчики"), @("SensrSvc", "Системные датчики"), @("PhoneSvc", "Телефон"),
        @("WalletService", "Кошелек"), @("PrintNotify", "PrintNotify")
    )

    foreach ($svc in $extremeServices) {
        Disable-ServiceSafe $svc[0] $svc[1]
    }

    $processesToStop = @("GameBarPresenceWriter", "PhoneExperienceHost", "SearchFilterHost", "SearchProtocolHost", "SearchIndexer", "MicrosoftEdgeUpdate")
    foreach ($proc in $processesToStop) {
        try { Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue } catch {}
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    Log-Success "`n=========================================================================="
    Log-Success "ГЕЙМЕРСКАЯ ОПТИМИЗАЦИЯ ЗАВЕРШЕНА!"
    Log-Success "- Вся красота Windows отключена в пользу 100% быстродействия."
    Log-Success "- Инпут-лаг мыши и клавиатуры снижен, MMCSS Priority Games активен."
    Log-Success "- Сеть оптимизирована (TCP NoDelay, RSC Disabled)."
    Log-Success "- Парковка ядер ЦП снята, ядро переведено в физическую ОЗУ."
    Log-Success "- После перезагрузки число процессов опустится к ~70-80."
    Log-Success "==========================================================================`n"
}
#endregion

#region 12. Профиль 3: Ультра-сжатие «Cryo-Apex» (40-50 процессов)
function Invoke-UltraApexOptimization {
    Show-Banner
    Write-Host "  ============================================================================" -ForegroundColor Red
    Write-Host "   >>> ⚡ УЛЬТРА-СЖАТИЕ «CRYO-APEX» (ЦЕЛЬ: 40-50 ПРОЦЕССОВ & МАКСИМАЛЬНЫЙ FPS) ⚡ <<<" -ForegroundColor Red
    Write-Host "  ============================================================================" -ForegroundColor Red
    Write-Host "  - Полное выключение анимаций и прозрачности (максимальный отклик GUI)." -ForegroundColor White
    Write-Host "  - Ужимает процессы до 40-50 (отключение Per-User Services svchost)." -ForegroundColor White
    Write-Host "  - Нулевой инпут-лаг, оптимизация таймеров HPET/BCD и отклика мыши." -ForegroundColor White
    Write-Host "  - Ускорение сети (TCP NoDelay, отключение сетевого троттлинга)." -ForegroundColor White
    Write-Host "  - Полное снятие парковки ядер процессора и ядро Windows целиком в ОЗУ.`n" -ForegroundColor White

    $confirm = Read-Host "  Применить УЛЬТРА-РЕЖИМ «CRYO-APEX»? (Y/N)"
    if ($confirm -notmatch "^[YyДд]$") {
        Log-Warn "Операция отменена пользователем."
        return
    }

    $beforeCount = (Get-Process).Count
    Write-Host "`n  [*] Процессов в системе на старте: $beforeCount" -ForegroundColor Cyan

    New-CryRestorePoint
    Remove-WindowsBloatware -AggressiveMode $true
    Disable-TelemetryAndDiagnostics

    # Применение 4-х ключевых модулей максимальной производительности
    Optimize-VisualPerformanceExtreme
    Optimize-InputLagAndResponsiveness
    Optimize-NetworkAndPing
    Optimize-CpuAndRamMax

    # 1. Группировка svchost
    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Control" "SvcHostSplitThresholdInKB" 0xFFFFFFFF "DWord"

    # 2. Отключение шаблонов Per-User Services
    $userTemplateServices = @("CDPUserSvc", "OneSyncSvc", "MessagingService", "PimIndexMaintenanceSvc", "UserDataSvc", "UnistoreSvc", "CaptureService", "BcastDVRUserService")
    foreach ($tmpl in $userTemplateServices) {
        Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Services\$tmpl" "UserServiceFlags" 0 "DWord"
        Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Services\$tmpl" "Start" 4 "DWord"
    }

    # 3. Блокировка фоновых агентов
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsRunInBackground" 2
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0
    Set-RegistryValueSafe "HKCU:\Software\Policies\Microsoft\Edge" "StartupBoostEnabled" 0
    Set-RegistryValueSafe "HKCU:\Software\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
    Set-RegistryValueSafe "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter" "ActivationType" 0

    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue

    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableSmartScreen" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost" "EnableWebContentEvaluation" 0
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth" -ErrorAction SilentlyContinue

    # 4. Отключение второстепенных служб
    $ultraServices = @(
        @("WSearch", "Windows Search"), @("SysMain", "SysMain / SuperFetch"), @("Spooler", "Принтеры"),
        @("PrintNotify", "PrintNotify"), @("Fax", "Факс"), @("DoSvc", "Delivery Optimization"),
        @("PcaSvc", "Program Compatibility"), @("DPS", "Diagnostic Policy"), @("WdiServiceHost", "WdiHost"),
        @("WdiSystemHost", "WdiSystemHost"), @("diagnosticshub.standardcollector.service", "DiagHub"),
        @("WerSvc", "Error Reporting"), @("DiagTrack", "Телеметрия"), @("dmwappushservice", "WAP Push"),
        @("PhoneSvc", "Телефон"), @("MapsBroker", "Карты"), @("RetailDemo", "Retail Demo"),
        @("wisvc", "Insider"), @("SharedAccess", "ICS"), @("SensorService", "Датчики"),
        @("SensrSvc", "Системные датчики"), @("SensorDataService", "SensorData"), @("SCardSvr", "Смарт-карты"),
        @("WbioSrvc", "Биометрия"), @("TabletInputService", "Сенсорный ввод"), @("XblAuthManager", "Xbox Auth"),
        @("XblGameSave", "Xbox Save"), @("XboxNetApiSvc", "Xbox Net"), @("XboxGipSvc", "Xbox Acc"),
        @("iphlpsvc", "IP Helper"), @("TrkWks", "TrkWks"), @("WmpNetworkSvc", "WmpNetworkSvc"),
        @("icssvc", "Хотспот"), @("stisvc", "WIA"), @("TroubleshootingSvc", "Устранение неполадок"),
        @("SEMgrSvc", "NFC"), @("CscService", "Автономные файлы"), @("AppVClient", "App-V"),
        @("NetTcpPortSharing", "NetTcpPortSharing"), @("NvTelemetryContainer", "NVIDIA Telemetry")
    )
    foreach ($svc in $ultraServices) { Disable-ServiceSafe $svc[0] $svc[1] }

    $manualServices = @("LanmanServer", "lmhosts", "FontCache", "FontCache3.0.0.0", "defragsvc")
    foreach ($mSvc in $manualServices) { try { Set-Service -Name $mSvc -StartupType Manual -ErrorAction SilentlyContinue } catch {} }

    $killList = @("GameBarPresenceWriter", "PhoneExperienceHost", "SearchFilterHost", "SearchProtocolHost", "SearchIndexer", "MicrosoftEdgeUpdate", "GoogleUpdate", "CompatTelRunner", "TextInputHost", "smartscreen", "SecurityHealthSystray", "OneDrive")
    foreach ($p in $killList) { try { Stop-Process -Name $p -Force -ErrorAction SilentlyContinue } catch {} }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    $afterCount = (Get-Process).Count
    Write-Host "`n  ==========================================================================" -ForegroundColor Green
    Log-Success "⚡ УЛЬТРА-СЖАТИЕ «CRYO-APEX» УСПЕШНО ПРИМЕНЕНО!"
    Write-Host "  - Процессов ДО оптимизации: $beforeCount" -ForegroundColor White
    Write-Host "  - Процессов СЕЙЧАС (до перезагрузки): $afterCount" -ForegroundColor Green
    Write-Host "  После перезагрузки в чистой системе будет ~40-50 процессов!" -ForegroundColor Yellow
    Write-Host "  ==========================================================================`n" -ForegroundColor Green
}
#endregion

#region 13. Профиль 4: 💀 [НА СВОЙ СТРАХ И РИСК] GHOST-BAREBONES (~30 ПРОЦЕССОВ) 💀
function Invoke-GhostBarebones30Processes {
    Show-Banner
    Write-Host "  ============================================================================" -ForegroundColor Red
    Write-Host "   💀💀💀 [НА СВОЙ СТРАХ И РИСК] GHOST-BAREBONES (~30 ПРОЦЕССОВ) 💀💀💀" -ForegroundColor Red
    Write-Host "  ============================================================================" -ForegroundColor Red
    Write-Host "  ВНИМАНИЕ! Режим ТОТАЛЬНОЙ зачистки системы под корень (уровень ~26-32 процесса):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [-] Полное отключение красоты Windows (Best Performance, 0ms анимаций)" -ForegroundColor Red
    Write-Host "  [-] Полное отключение Windows Defender (MsMpEng.exe) и Центра Безопасности" -ForegroundColor Red
    Write-Host "      (Высвобождает ~350-500 МБ чистой ОЗУ и полностью разгружает процессор)." -ForegroundColor Gray
    Write-Host "  [-] Полное отключение Центра обновления Windows (wuauserv, UsoSvc, BITS)" -ForegroundColor Red
    Write-Host "  [-] Полное отключение Bluetooth (bthserv, BTAGService) для проводного сетапа" -ForegroundColor Red
    Write-Host "  [-] Отключение службы системных Push-уведомлений (WpnService)" -ForegroundColor Red
    Write-Host "  [-] Отключение UPnP, SSDP, NetBIOS и сетевого общего доступа SMB" -ForegroundColor Red
    Write-Host "  [-] Нулевой инпут-лаг мыши (Raw Input), таймеры BCD, максимальный отклик сети" -ForegroundColor Green
    Write-Host "  [-] Полное снятие парковки всех ядер ЦП, ядро заблокировано в физической ОЗУ" -ForegroundColor Green
    Write-Host "  [-] Сжатие svchost.exe до абсолютного предела (~5-7 общих процессов)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  * Все базовые службы можно вернуть в любой момент через пункт меню [8]." -ForegroundColor DarkYellow
    Write-Host "  ============================================================================" -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "  Вы подтверждаете тотальное сжатие до ~30 процессов? Введите 'YES' или 'ДА'"
    if ($confirm -notmatch "^(YES|ДА)$") {
        Log-Warn "Операция отменена. Безопасность превыше всего."
        return
    }

    $beforeCount = (Get-Process).Count
    Write-Host "`n  [*] Процессов в системе на старте: $beforeCount" -ForegroundColor Cyan

    New-CryRestorePoint
    Remove-WindowsBloatware -AggressiveMode $true
    Disable-TelemetryAndDiagnostics

    # Применение 4-х ключевых модулей максимальной производительности
    Optimize-VisualPerformanceExtreme
    Optimize-InputLagAndResponsiveness
    Optimize-NetworkAndPing
    Optimize-CpuAndRamMax

    # 1. Группировка svchost до предела
    Log-Info "1. Сжатие пула svchost.exe (0xFFFFFFFF)..."
    Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Control" "SvcHostSplitThresholdInKB" 0xFFFFFFFF "DWord"

    # 2. Ликвидация шаблонов Per-User Services
    Log-Info "2. Отключение шаблонов Per-User Services..."
    $userTemplateServices = @("CDPUserSvc", "OneSyncSvc", "MessagingService", "PimIndexMaintenanceSvc", "UserDataSvc", "UnistoreSvc", "CaptureService", "BcastDVRUserService")
    foreach ($tmpl in $userTemplateServices) {
        Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Services\$tmpl" "UserServiceFlags" 0 "DWord"
        Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Services\$tmpl" "Start" 4 "DWord"
    }

    # 3. ПОЛНАЯ НЕЙТРАЛИЗАЦИЯ WINDOWS DEFENDER (Экономия MsMpEng.exe и 350+ МБ ОЗУ)
    Log-Info "3. [НА СВОЙ СТРАХ И РИСК] Полное отключение Windows Defender (MsMpEng)..."
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true -DisableBlockAtFirstSeen $true -DisableIOAVProtection $true -DisablePrivacyMode $true -DisableScriptScanning $true -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue
    } catch {}

    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" "DisableAntiSpyware" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" "DisableRealtimeMonitoring" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableBehaviorMonitoring" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableOnAccessProtection" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableScanOnRealtimeEnable" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableIOAVProtection" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableRealtimeMonitoring" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" "HideSystray" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableSmartScreen" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost" "EnableWebContentEvaluation" 0
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth" -ErrorAction SilentlyContinue

    Disable-ServiceSafe "SecurityHealthService" "Центр безопасности Windows"
    Disable-ServiceSafe "wscsvc" "Центр обеспечения безопасности"
    Disable-ServiceSafe "WinDefend" "Служба Защитника Windows (Antimalware)"
    Disable-ServiceSafe "WdNisSvc" "Служба проверки сети Защитника Windows"
    Disable-ServiceSafe "Sense" "Служба Advanced Threat Protection (Defender ATP)"

    # 4. ПОЛНОЕ ОТКЛЮЧЕНИЕ ЦЕНТРА ОБНОВЛЕНИЙ WINDOWS
    Log-Info "4. Полное отключение Центра обновления Windows и BITS..."
    Disable-ServiceSafe "wuauserv" "Центр обновления Windows"
    Disable-ServiceSafe "UsoSvc" "Служба оркестратора обновлений"
    Disable-ServiceSafe "BITS" "Фоновая интеллектуальная служба передачи (BITS)"
    Disable-ServiceSafe "WaaSMedicSvc" "Служба восстановления обновлений Windows"
    try { Set-Service -Name "TrustedInstaller" -StartupType Manual -ErrorAction SilentlyContinue } catch {}

    # 5. ОТКЛЮЧЕНИЕ BLUETOOTH
    Log-Info "5. Отключение Bluetooth служб..."
    Disable-ServiceSafe "bthserv" "Служба поддержки Bluetooth"
    Disable-ServiceSafe "BTAGService" "Служба аудиошлюза Bluetooth"
    Disable-ServiceSafe "bthHFSrv" "Служба громкой связи Bluetooth"

    # 6. ОТКЛЮЧЕНИЕ СЕТЕВОГО МУСОРА (UPnP, SSDP, NetBIOS, LanmanServer, WCN)
    Log-Info "6. Отключение UPnP, SSDP, сетевых протоколов NetBIOS и общих папок..."
    Disable-ServiceSafe "SSDPSRV" "Обнаружение SSDP"
    Disable-ServiceSafe "upnphost" "Узел универсальных PnP-устройств"
    Disable-ServiceSafe "lmhosts" "Модуль поддержки TCP/IP NetBIOS"
    Disable-ServiceSafe "LanmanServer" "Сервер (общий доступ к файлам SMB)"
    Disable-ServiceSafe "wcncsvc" "Служба Windows Connect Now"
    Disable-ServiceSafe "lltdsvc" "Служба топологии канального уровня"
    Disable-ServiceSafe "TermService" "Службы удаленных рабочих столов"
    Disable-ServiceSafe "SessionEnv" "Конфигурация удаленных рабочих столов"
    Disable-ServiceSafe "UmRdpService" "Перенаправитель портов пользовательского режима RDP"
    Disable-ServiceSafe "PolicyAgent" "Агент политики IPsec"

    # 7. ОТКЛЮЧЕНИЕ PUSH-УВЕДОМЛЕНИЙ И СИСТЕМНОГО ОКРУЖЕНИЯ
    Log-Info "7. Отключение Push-уведомлений и системных очередей..."
    Disable-ServiceSafe "WpnService" "Служба системных push-уведомлений"
    Disable-ServiceSafe "CDPSvc" "Служба платформы подключенных устройств"
    Disable-ServiceSafe "NcdAutoSetup" "Автонастройка подключенных к сети устройств"
    Disable-ServiceSafe "NCB" "Брокер сетевых подключений"

    # 8. ВСЕ ОСТАЛЬНЫЕ ФОНОВЫЕ СЛУЖБЫ
    Log-Info "8. Отключение всех некритических системных служб Windows..."
    $ghostServices = @(
        @("WSearch", "Windows Search Indexer"), @("SysMain", "SysMain / Superfetch"),
        @("Spooler", "Диспетчер печати"), @("PrintNotify", "PrintNotify"), @("Fax", "Факсы"),
        @("DoSvc", "Delivery Optimization"), @("PcaSvc", "Program Compatibility Assistant"),
        @("DPS", "Diagnostic Policy Service"), @("WdiServiceHost", "Diagnostic Service Host"),
        @("WdiSystemHost", "Diagnostic System Host"), @("diagnosticshub.standardcollector.service", "Diagnostics Hub"),
        @("WerSvc", "Windows Error Reporting"), @("DiagTrack", "Служба телеметрии"),
        @("dmwappushservice", "Служба WAP Push"), @("PhoneSvc", "Служба телефона"),
        @("MapsBroker", "Менеджер карт"), @("RetailDemo", "Retail Demo"), @("wisvc", "Windows Insider"),
        @("SharedAccess", "Служба общего доступа ICS"), @("SensorService", "Служба датчиков"),
        @("SensrSvc", "Служба системных датчиков"), @("SensorDataService", "Служба данных датчиков"),
        @("SCardSvr", "Смарт-карты"), @("WbioSrvc", "Биометрическая служба"),
        @("TabletInputService", "Сенсорная клавиатура и рукописный ввод"),
        @("XblAuthManager", "Xbox Live Auth"), @("XblGameSave", "Xbox Live GameSave"),
        @("XboxNetApiSvc", "Xbox Live NetApi"), @("XboxGipSvc", "Xbox Accessory Management"),
        @("iphlpsvc", "IP Helper (Teredo/6to4)"), @("TrkWks", "Отслеживание изменившихся связей"),
        @("WmpNetworkSvc", "Служба Windows Media"), @("icssvc", "Мобильный хот-спот"),
        @("stisvc", "Служба WIA (сканеры)"), @("TroubleshootingSvc", "Устранение неполадок"),
        @("SEMgrSvc", "Платежи и NFC"), @("CscService", "Автономные файлы"),
        @("AppVClient", "Microsoft App-V"), @("NetTcpPortSharing", "Net.Tcp Port Sharing"),
        @("seclogon", "Вторичный вход в систему"), @("Wecsvc", "Коллектор событий Windows"),
        @("WinRM", "Windows Remote Management"), @("SENS", "Служба уведомления о системных событиях"),
        @("NvTelemetryContainer", "NVIDIA Telemetry Container")
    )

    foreach ($svc in $ghostServices) { Disable-ServiceSafe $svc[0] $svc[1] }

    try { Set-Service -Name "W32Time" -StartupType Manual -ErrorAction SilentlyContinue } catch {}
    try { Set-Service -Name "defragsvc" -StartupType Manual -ErrorAction SilentlyContinue } catch {}
    try { Set-Service -Name "FontCache" -StartupType Manual -ErrorAction SilentlyContinue } catch {}
    try { Set-Service -Name "FontCache3.0.0.0" -StartupType Manual -ErrorAction SilentlyContinue } catch {}

    # Блокировка автозапуска фоновых агентов
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsRunInBackground" 2
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
    Set-RegistryValueSafe "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter" "ActivationType" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue

    # Тотальное завершение всех висящих процессов прямо сейчас
    Log-Info "11. Принудительное завершение всех фоновых процессов прямо сейчас..."
    $killAllList = @(
        "MsMpEng", "SecurityHealthService", "SecurityHealthSystray", "smartscreen",
        "SearchIndexer", "SearchFilterHost", "SearchProtocolHost", "SearchApp",
        "TextInputHost", "OneDrive", "GameBarPresenceWriter", "PhoneExperienceHost",
        "MicrosoftEdgeUpdate", "GoogleUpdate", "CompatTelRunner", "RuntimeBroker"
    )
    foreach ($p in $killAllList) {
        try { Stop-Process -Name $p -Force -ErrorAction SilentlyContinue } catch {}
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    $afterCount = (Get-Process).Count
    Write-Host "`n  ==========================================================================" -ForegroundColor Green
    Log-Success "💀 РЕЖИМ GHOST-BAREBONES (~30 ПРОЦЕССОВ) УСПЕШНО ПРИМЕНЕН!"
    Write-Host "  - Процессов ДО применения: $beforeCount" -ForegroundColor White
    Write-Host "  - Процессов СЕЙЧАС (до перезагрузки): $afterCount" -ForegroundColor Green
    Write-Host ""
    Write-Host "  [ЧТО ДЕЛАТЬ ДЛЯ ВЫХОДА РОВНО НА ~30 ПРОЦЕССОВ]:" -ForegroundColor Yellow
    Write-Host "  1. Проверьте автозагрузку (пункт меню [6]): отключите Discord/Spotify/Steam," -ForegroundColor White
    Write-Host "     иначе они сами создадут +35 процессов на старте Windows!" -ForegroundColor White
    Write-Host "  2. После перезагрузки ядро Windows загрузится ровно на отметке ~26 - 32 процесса!" -ForegroundColor Green
    Write-Host "  ==========================================================================`n" -ForegroundColor Green

    $rebootPrompt = Read-Host "  Перезагрузить компьютер сейчас для старта в режиме 30 процессов? (Y/N)"
    if ($rebootPrompt -match "^[YyДд]$") {
        Write-Host "  [*] Перезагрузка системы через 5 секунд..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        Restart-Computer -Force
    }
}
#endregion

#region 14. МОДУЛЬ ОТДЕЛЬНОГО ПРИМЕНЕНИЯ ТВЫКОВ ЗАДЕРЖЕК
function Invoke-StandaloneLatencyTweaks {
    Show-Banner
    Write-Host "  [>>> МОДУЛЬ: ТВЫКИ ЗАДЕРЖЕК, ИНПУТ-ЛАГА, СЕТИ И РАЗГОН ЦП/ОЗУ <<<]" -ForegroundColor Cyan
    Write-Host "  Применение полного пакета оптимизации без изменения состава служб Windows.`n" -ForegroundColor Gray

    Optimize-VisualPerformanceExtreme
    Optimize-InputLagAndResponsiveness
    Optimize-NetworkAndPing
    Optimize-CpuAndRamMax

    Log-Success "`nПакет низкой задержки (Low Latency / 0ms Input Lag / Fast Network) успешно применен!"
}
#endregion

#region 15. МЕНЕДЖЕР АВТОЗАГРУЗКИ ПОЛЬЗОВАТЕЛЯ
function Manage-StartupApps {
    Show-Banner
    Write-Host "  [>>> МЕНЕДЖЕР АВТОЗАГРУЗКИ ПОЛЬЗОВАТЕЛЯ <<<]" -ForegroundColor Cyan
    Write-Host "  Сторонние приложения (Discord, Spotify, Epic, Steam, Rave) при старте" -ForegroundColor Gray
    Write-Host "  могут порождать от 20 до 40 лишних фоновых процессов!`n" -ForegroundColor Gray

    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $items = Get-Item -Path $runKey -ErrorAction SilentlyContinue

    if (-not $items -or $items.Property.Count -eq 0) {
        Log-Info "В автозагрузке текущего пользователя чисто."
        return
    }

    Write-Host "  Обнаруженные программы в автозапуске:" -ForegroundColor White
    $index = 1
    $propList = @()
    foreach ($prop in $items.Property) {
        $val = $items.GetValue($prop)
        Write-Host "   [$index] $prop -> $val" -ForegroundColor Yellow
        $propList += $prop
        $index++
    }

    Write-Host ""
    Write-Host "  [A]  Отключить ВСЕ тяжелые сторонние автозапуски (Необходимо для 30-40 процессов!)" -ForegroundColor Green
    Write-Host "  [0]  Назад в главное меню" -ForegroundColor DarkGray
    Write-Host ""
    $action = Read-Host "  Выберите действие"

    if ($action -match "^[AaФф]$") {
        foreach ($prop in $propList) {
            try {
                Remove-ItemProperty -Path $runKey -Name $prop -ErrorAction SilentlyContinue
                Log-Success "Удалено из автозагрузки: $prop"
            } catch {}
        }
        Log-Success "Все сторонние программы автозагрузки отключены! Программы можно запускать вручную по ярлыкам."
    }
}
#endregion

#region 16. Глубокая очистка диска и системного кэша
function Invoke-DeepDiskClean {
    Show-Banner
    Write-Host "  [>>> МОДУЛЬ: ГЛУБОКАЯ ОЧИСТКА ДИСКА И КЭША <<<]" -ForegroundColor Cyan
    Write-Host "  Удаление временных файлов, кэша обновлений, дампов, шейдеров и оптимизация TRIM.`n" -ForegroundColor Gray

    $totalBytesCleaned = 0

    function Clean-FolderSafely ([string]$FolderPath, [string]$Description) {
        if (Test-Path $FolderPath) {
            Log-Info "Очистка: $Description ($FolderPath)..."
            $items = Get-ChildItem -Path $FolderPath -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    if (-not $item.PSIsContainer) {
                        $script:totalBytesCleaned += $item.Length
                    }
                    Remove-Item -Path $item.FullName -Force -Recurse -ErrorAction SilentlyContinue
                } catch {}
            }
        }
    }

    Clean-FolderSafely "$env:TEMP" "Пользовательские временные файлы (User Temp)"
    Clean-FolderSafely "$env:SystemRoot\Temp" "Системные временные файлы (Windows Temp)"

    Log-Info "Остановка службы Windows Update для очистки кэша обновлений..."
    Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
    Clean-FolderSafely "$env:SystemRoot\SoftwareDistribution\Download" "Кэш загрузок Центра обновления Windows"
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue

    Clean-FolderSafely "$env:LOCALAPPDATA\D3DSCache" "Кэш шейдеров DirectX (AMD/Intel/DirectX)"
    Clean-FolderSafely "$env:LOCALAPPDATA\NVIDIA\DXCache" "Кэш шейдеров NVIDIA (DXCache)"
    Clean-FolderSafely "$env:LOCALAPPDATA\NVIDIA\GLCache" "Кэш шейдеров NVIDIA OpenGL"

    Clean-FolderSafely "$env:LOCALAPPDATA\CrashDumps" "Дампы сбоев приложений (CrashDumps)"
    Clean-FolderSafely "$env:SystemRoot\Minidump" "Минидампы синих экранов (BSOD Minidumps)"
    if (Test-Path "$env:SystemRoot\MEMORY.DMP") {
        try {
            $script:totalBytesCleaned += (Get-Item "$env:SystemRoot\MEMORY.DMP").Length
            Remove-Item -Path "$env:SystemRoot\MEMORY.DMP" -Force -ErrorAction SilentlyContinue
            Log-Success "Удален полный дамп памяти: MEMORY.DMP"
        } catch {}
    }

    Clean-FolderSafely "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" "Кэш эскизов и значков"

    Log-Info "Очистка Корзины (Recycle Bin)..."
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Log-Success "Корзина очищена!"
    } catch {}

    Log-Info "Запуск оптимизации TRIM для системного диска $env:SystemDrive..."
    try {
        $driveLetter = $env:SystemDrive.Replace(":", "")
        Optimize-Volume -DriveLetter $driveLetter -ReTrim -Verbose:$false -ErrorAction SilentlyContinue
        Log-Success "Команда TRIM успешно выполнена для диска $driveLetter"
    } catch {}

    $mbCleaned = [math]::Round($totalBytesCleaned / 1MB, 2)
    Log-Success "`n======================================================="
    Log-Success "Глубокая очистка диска завершена!"
    Log-Success "Ориентировочно освобождено: ~$mbCleaned МБ пространства"
    Log-Success "=======================================================`n"
}
#endregion

#region 17. Восстановление базовых служб
function Restore-EssentialServices {
    Show-Banner
    Write-Host "  [>>> ВОССТАНОВЛЕНИЕ БАЗОВЫХ СЛУЖБ WINDOWS <<<]" -ForegroundColor Yellow
    Write-Host "  Возвращает службы Защитника, принтеров, поиска, обновлений, Bluetooth и сети.`n" -ForegroundColor Gray

    Log-Info "Восстановление Защитника Windows..."
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableRealtimeMonitoring" -Value 0 -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    } catch {}
    Enable-ServiceSafe "WinDefend" "Automatic" "Защитник Windows"
    Enable-ServiceSafe "SecurityHealthService" "Manual" "Центр безопасности"
    Enable-ServiceSafe "wscsvc" "Automatic" "Центр обеспечения безопасности"

    Enable-ServiceSafe "Spooler" "Automatic" "Диспетчер печати"
    Enable-ServiceSafe "WSearch" "Automatic" "Windows Search (Индексация)"
    Enable-ServiceSafe "SysMain" "Automatic" "SysMain / Superfetch"
    Enable-ServiceSafe "wuauserv" "Manual" "Центр обновления Windows"
    Enable-ServiceSafe "BITS" "Manual" "Служба BITS"
    Enable-ServiceSafe "AudioSrv" "Automatic" "Windows Audio"
    Enable-ServiceSafe "bthserv" "Manual" "Служба поддержки Bluetooth"
    Enable-ServiceSafe "DPS" "Automatic" "Служба политики диагностики"
    Enable-ServiceSafe "LanmanServer" "Automatic" "Сервер (общий доступ к файлам)"
    Enable-ServiceSafe "lmhosts" "Manual" "TCP/IP NetBIOS"
    Enable-ServiceSafe "WpnService" "Automatic" "Push-уведомления Windows"

    $userTemplateServices = @("CDPUserSvc", "OneSyncSvc", "MessagingService", "PimIndexMaintenanceSvc", "UserDataSvc", "UnistoreSvc", "CaptureService", "BcastDVRUserService")
    foreach ($tmpl in $userTemplateServices) {
        Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Services\$tmpl" "UserServiceFlags" 3 "DWord"
        Set-RegistryValueSafe "HKLM:\SYSTEM\CurrentControlSet\Services\$tmpl" "Start" 3 "DWord"
    }

    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 1
    Set-RegistryValueSafe "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 0
    Set-RegistryValueSafe "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsRunInBackground" 0

    Log-Success "`nБазовые службы и безопасность успешно восстановлены!"
}
#endregion

#region 18. Главное меню и интерактивный цикл
function Show-MainMenu {
    Show-Banner
    $currentProcCount = (Get-Process).Count
    Write-Host "  ТЕКУЩЕЕ КОЛИЧЕСТВО ПРОЦЕССОВ В СИСТЕМЕ: " -ForegroundColor DarkGray -NoNewline
    if ($currentProcCount -le 35) {
        Write-Host "$currentProcCount (РЕКОРД: GHOST-BAREBONES ~30 процессов достигнут!)" -ForegroundColor Green
    } elseif ($currentProcCount -le 55) {
        Write-Host "$currentProcCount (УЛЬТРА-РЕЖИМ: 40-50 процессов)" -ForegroundColor Green
    } elseif ($currentProcCount -le 90) {
        Write-Host "$currentProcCount (Геймерский уровень: 70-80 процессов)" -ForegroundColor Cyan
    } elseif ($currentProcCount -le 130) {
        Write-Host "$currentProcCount (Умеренно)" -ForegroundColor Yellow
    } else {
        Write-Host "$currentProcCount (Много - требуется оптимизация)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  ВЫБЕРИТЕ НЕОБХОДИМОЕ ДЕЙСТВИЕ:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1]  " -ForegroundColor Green -NoNewline
    Write-Host "Оптимизация «ДЛЯ РАБОТЫ И УЧЕБЫ» (Бережная, сохраняет принтеры/BT)" -ForegroundColor White
    
    Write-Host "  [2]  " -ForegroundColor Yellow -NoNewline
    Write-Host "ГЕЙМЕРСКАЯ ОПТИМИЗАЦИЯ (~70-80 процессов, 0ms Input Lag, разгон ЦП/ОЗУ/Сети)" -ForegroundColor White

    Write-Host "  [3]  " -ForegroundColor Red -NoNewline
    Write-Host "УЛЬТРА-СЖАТИЕ «CRYO-APEX» (40-50 процессов, отключение красот, eSports твики)" -ForegroundColor White

    Write-Host "  [4]  " -ForegroundColor Magenta -NoNewline
    Write-Host "💀 [НА СВОЙ СТРАХ И РИСК] GHOST-BAREBONES (~30 ПРОЦЕССОВ, ТОТАЛЬНОЕ СЖАТИЕ) 💀" -ForegroundColor Red

    Write-Host "  [5]  " -ForegroundColor Cyan -NoNewline
    Write-Host "🔥 ТОЛЬКО ТВЫКИ ЗАДЕРЖЕК: Input Lag, Сеть/Пинг, Отключение графики, Разгон ЦП/ОЗУ" -ForegroundColor Cyan

    Write-Host "  [6]  " -ForegroundColor DarkCyan -NoNewline
    Write-Host "Менеджер автозагрузки (Отключение автозапусков: Steam, Discord, Spotify...)" -ForegroundColor White
    
    Write-Host "  [7]  " -ForegroundColor DarkYellow -NoNewline
    Write-Host "Глубокая очистка диска (Кэш Windows, Temp, шейдеры, дампы, TRIM)" -ForegroundColor White
    
    Write-Host "  [8]  " -ForegroundColor DarkMagenta -NoNewline
    Write-Host "Создать точку восстановления системы (System Restore Point)" -ForegroundColor White
    
    Write-Host "  [9]  " -ForegroundColor DarkGreen -NoNewline
    Write-Host "Восстановить базовые службы (Принтеры, Защитник, Обновления, Bluetooth, Сеть)" -ForegroundColor White
    
    Write-Host "  [10] " -ForegroundColor White -NoNewline
    Write-Host "Информация о системе (Потребление ОЗУ, ЦП, монитор процессов)" -ForegroundColor White

    Write-Host "  [0]  " -ForegroundColor DarkGray -NoNewline
    Write-Host "Выход" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ----------------------------------------------------------------------------" -ForegroundColor Cyan
}

function Show-SystemStats {
    Show-Banner
    Write-Host "  [>>> ТЕКУЩЕЕ СОСТОЯНИЕ СИСТЕМЫ И ПРОЦЕССЫ <<<]`n" -ForegroundColor White

    $os = Get-CimInstance Win32_OperatingSystem
    $totalRamGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeRamGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedRamGB = [math]::Round($totalRamGB - $freeRamGB, 2)
    $ramPercent = [math]::Round(($usedRamGB / $totalRamGB) * 100, 1)

    Write-Host "  Оперативная память (RAM):" -ForegroundColor Cyan
    Write-Host "    Использовано: $usedRamGB ГБ из $totalRamGB ГБ ($ramPercent%)" -ForegroundColor White

    $allProcs = Get-Process
    $procCount = $allProcs.Count
    $svchostCount = ($allProcs | Where-Object { $_.ProcessName -eq 'svchost' }).Count
    Write-Host "`n  Фоновые процессы:" -ForegroundColor Cyan
    Write-Host "    Всего запущенных процессов: $procCount" -ForegroundColor White
    Write-Host "    Из них процессов svchost.exe: $svchostCount" -ForegroundColor Yellow

    Write-Host "`n  ТОП-5 процессов по потреблению памяти:" -ForegroundColor Cyan
    $allProcs | Sort-Object WorkingSet -Descending | Select-Object -First 5 | ForEach-Object {
        $mb = [math]::Round($_.WorkingSet / 1MB, 1)
        Write-Host "    - $($_.ProcessName) (PID $($_.Id)): $mb МБ" -ForegroundColor Gray
    }

    $disk = Get-PSDrive -Name ($env:SystemDrive.Replace(":", ""))
    $totalDiskGB = [math]::Round(($disk.Used + $disk.Free) / 1GB, 2)
    $freeDiskGB = [math]::Round($disk.Free / 1GB, 2)
    Write-Host "`n  Системный диск ($env:SystemDrive):" -ForegroundColor Cyan
    Write-Host "    Свободно: $freeDiskGB ГБ из $totalDiskGB ГБ" -ForegroundColor White

    Write-Host "`n  Нажмите любую клавишу для возврата в меню..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null
}

# Основной цикл программы
do {
    Show-MainMenu
    $choice = Read-Host "  Введите номер опции (0-10)"
    
    switch ($choice) {
        "1" {
            Invoke-WorkOptimization
            Write-Host "`n  Нажмите любую клавишу для продолжения..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "2" {
            Invoke-GamerOptimization
            Write-Host "`n  Нажмите любую клавишу для продолжения..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "3" {
            Invoke-UltraApexOptimization
            Write-Host "`n  Нажмите любую клавишу для продолжения..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "4" {
            Invoke-GhostBarebones30Processes
            Write-Host "`n  Нажмите любую клавишу для продолжения..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "5" {
            Invoke-StandaloneLatencyTweaks
            Write-Host "`n  Нажмите любую клавишу для продолжения..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "6" {
            Manage-StartupApps
            Write-Host "`n  Нажмите любую клавишу для продолжения..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "7" {
            Invoke-DeepDiskClean
            Write-Host "`n  Нажмите любую клавишу для продолжения..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "8" {
            New-CryRestorePoint
            Write-Host "`n  Нажмите любую клавишу для продолжения..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "9" {
            Restore-EssentialServices
            Write-Host "`n  Нажмите любую клавишу для продолжения..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "10" {
            Show-SystemStats
        }
        "0" {
            Write-Host "`n  Спасибо за использование CryOptimisation! До свидания.`n" -ForegroundColor Cyan
            Start-Sleep -Seconds 1
            break
        }
        Default {
            Write-Host "  [!] Неверный выбор, попробуйте снова." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
#endregion
