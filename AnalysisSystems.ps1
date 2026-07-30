# ====================================================================
# Автор: RealMikoto
# Скрипт: Инструмент анализа системы (Windows)
# ====================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ОШИБКА] Запустите от имени Администратора!" -ForegroundColor Red
    exit
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ConsoleHelper {
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
}
"@ -ErrorAction SilentlyContinue
try {
    $handle = [ConsoleHelper]::GetStdHandle(-11)
    $mode = 0
    [ConsoleHelper]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    [ConsoleHelper]::SetConsoleMode($handle, $mode -bor 4) | Out-Null
} catch {}

# ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==========
function Write-Header {
    param([string]$Title)
    $width = 70
    Write-Host ("┌" + "─" * ($width - 2) + "┐") -ForegroundColor DarkGray
    Write-Host ("│ " + $Title.PadRight($width - 4) + " │") -ForegroundColor Cyan
    Write-Host ("└" + "─" * ($width - 2) + "┘") -ForegroundColor DarkGray
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n$Title" -ForegroundColor Yellow
    Write-Host ("─" * 60) -ForegroundColor DarkGray
}

function Write-KeyValue {
    param([string]$Key, [string]$Value, [ConsoleColor]$ValueColor = 'White')
    Write-Host ("  {0,-25} : " -f $Key) -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $ValueColor
}

function Write-Status {
    param([string]$Label, [bool]$OK, [string]$Extra = "")
    $icon = if ($OK) { "✔" } else { "✘" }
    $color = if ($OK) { "Green" } else { "Red" }
    Write-Host ("  {0,-30} : {1} {2}" -f $Label, $icon, $Extra) -ForegroundColor $color
}

function Write-ServiceTable {
    param($Services)
    $width = 70
    Write-Host ("┌" + "─" * ($width - 2) + "┐") -ForegroundColor DarkGray
    Write-Host ("│ {0,-12} │ {1,-42} │ {2,-10} │" -f "Имя", "Описание", "Статус") -ForegroundColor White
    Write-Host ("├" + "─" * 14 + "┼" + "─" * 44 + "┼" + "─" * 12 + "┤") -ForegroundColor DarkGray
    foreach ($s in $Services) {
        $statusColor = if ($s.Status -eq "Running") { "Green" } elseif ($s.Status -eq "Stopped") { "Red" } else { "Gray" }
        Write-Host ("│ {0,-12} │ {1,-42} │ " -f $s.Name, $s.Desc) -NoNewline -ForegroundColor White
        Write-Host ("{0,-10}" -f $s.Status) -ForegroundColor $statusColor -NoNewline
        Write-Host " │"
    }
    Write-Host ("└" + "─" * ($width - 2) + "┘") -ForegroundColor DarkGray
}

function Check-Event {
    param($log, $id, $msg)
    $e = Get-WinEvent -LogName $log -FilterXPath "*[System[EventID=$id]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($e) {
        Write-Host ("  {0,-35} : {1}" -f $msg, $e.TimeCreated.ToString("yyyy-MM-dd HH:mm")) -ForegroundColor White
    } else {
        Write-Host ("  {0,-35} : Нет записей" -f $msg) -ForegroundColor Green
    }
}

# ========== ОСНОВНАЯ ЧАСТЬ ==========
Clear-Host
Write-Header " Инструмент анализа системы "
Write-Host "  Автор: RealMikoto" -ForegroundColor Gray
Write-Host ""

# -----------------------------------------------------------------------------
Write-Section "SFC /SCANNOW (Фоновый режим)"
Write-Host "  Запуск sfc /scannow... " -NoNewline -ForegroundColor Gray
$sfcJob = Start-Job -ScriptBlock { sfc /scannow 2>&1 }

# Индикатор выполнения (точки)
while ($sfcJob.State -eq 'Running') {
    Write-Host -NoNewline "."
    Start-Sleep -Seconds 5
}
Write-Host "`r  SFC завершён.                          " -ForegroundColor Green

# -----------------------------------------------------------------------------
Write-Section "ВРЕМЯ ЗАГРУЗКИ СИСТЕМЫ"
try {
    $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    Write-KeyValue "Последняя загрузка" $bootTime.ToString("yyyy-MM-dd HH:mm:ss")
    Write-KeyValue "Время работы" ("{0}д {1:D2}:{2:D2}:{3:D2}" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds)
} catch {
    Write-Host "  Не удалось получить время загрузки" -ForegroundColor Red
}

# -----------------------------------------------------------------------------
Write-Section "УСТАНОВКА WINDOWS"
try {
    $raw = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").InstallDate
    if ($raw) {
        $installDate = (Get-Date "1970-01-01 00:00:00").AddSeconds($raw).ToLocalTime()
        Write-KeyValue "Дата установки" $installDate.ToString("yyyy-MM-dd HH:mm:ss")
    }
    $os = Get-CimInstance Win32_OperatingSystem
    Write-KeyValue "Версия ОС" $os.Caption
    Write-KeyValue "Сборка" $os.BuildNumber
} catch {
    Write-Host "  Ошибка чтения данных об установке" -ForegroundColor Red
}

# -----------------------------------------------------------------------------
Write-Section "ПОДКЛЮЧЕННЫЕ ДИСКИ"
$drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -ne 5 }
if ($drives) {
    foreach ($d in $drives) {
        Write-Host ("  {0,-5} : {1}" -f $d.DeviceID, $d.FileSystem) -ForegroundColor Green
    }
} else {
    Write-Host "  Диски не найдены" -ForegroundColor Gray
}

# -----------------------------------------------------------------------------
Write-Section "СТАТУС СЛУЖБ"
$services = @(
    @{Name="SysMain";    DN="SysMain"},
    @{Name="PcaSvc";     DN="Совместимость программ"},
    @{Name="DPS";        DN="Служба диагностических политик"},
    @{Name="EventLog";   DN="Журнал событий Windows"},
    @{Name="Schedule";   DN="Планировщик задач"},
    @{Name="Bam";        DN="Модератор фоновой активности"},
    @{Name="Dusmsvc";    DN="Использование данных"},
    @{Name="Appinfo";    DN="Сведения о приложениях"},
    @{Name="CDPSvc";     DN="Платформа подключённых устройств"},
    @{Name="DcomLaunch"; DN="Запуск DCOM-серверов"},
    @{Name="PlugPlay";   DN="Подключаемые устройства"},
    @{Name="wsearch";    DN="Поиск Windows"},
    @{Name="icssvc";     DN="Мобильный хот-спот (icssvc)"}
)

$svcList = @()
foreach ($svc in $services) {
    $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($s) {
        $dn = if ($svc.DN.Length -gt 40) { $svc.DN.Substring(0,37)+"..." } else { $svc.DN }
        $svcList += [PSCustomObject]@{ Name = $svc.Name; Desc = $dn; Status = $s.Status }
    } else {
        $svcList += [PSCustomObject]@{ Name = $svc.Name; Desc = "Не найдена"; Status = "Н/Д" }
    }
}
Write-ServiceTable $svcList

# -----------------------------------------------------------------------------
Write-Section "ПОЛИТИКИ РЕЕСТРА"
$regs = @(
    @{Name="CMD";              Path="HKCU:\Software\Policies\Microsoft\Windows\System";                                                                Key="DisableCMD";               OK=$false; Desc="Отключена"},
    @{Name="PS Logging";       Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging";                                         Key="EnableScriptBlockLogging"; OK=$false; Desc="Отключена"},
    @{Name="Activities Cache"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                                                                Key="EnableActivityFeed";       OK=$false; Desc="Отключена"},
    @{Name="Prefetch";         Path="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Key="EnablePrefetcher"; OK=$false; Desc="Отключена"}
)
foreach ($r in $regs) {
    $val = Get-ItemProperty -Path $r.Path -Name $r.Key -ErrorAction SilentlyContinue
    $isOK = ($val -and $val.$($r.Key) -eq 0)
    Write-Status $r.Name -OK $isOK -Extra $(if ($isOK) { " (Отключена – безопасно)" } else { " (Включена – по умолчанию)" })
}

# -----------------------------------------------------------------------------
Write-Section "ЖУРНАЛЫ СОБЫТИЙ (Последние)"
Check-Event "Application" 3079        "Очистка USN-журнала"
Check-Event "System"      1074        "Последнее выключение ПК"
Check-Event "System"      6005        "Запуск службы журнала событий"

# Несколько ID
$e = Get-WinEvent -LogName "System" -FilterXPath "*[System[EventID=104 or EventID=1102]]" -MaxEvents 1 -ErrorAction SilentlyContinue
if ($e) {
    Write-Host ("  {0,-35} : {1} (ID:{2})" -f "Очистка журналов событий", $e.TimeCreated.ToString("MM/dd HH:mm"), $e.Id) -ForegroundColor White
} else {
    Write-Host "  Очистка журналов событий            : Нет записей" -ForegroundColor Green
}

$e = Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Configuration" -FilterXPath "*[System[EventID=400]]" -MaxEvents 1 -ErrorAction SilentlyContinue
if ($e) {
    Write-Host ("  {0,-35} : {1}" -f "Изменение конфигурации устройств", $e.TimeCreated.ToString("MM/dd HH:mm")) -ForegroundColor White
} else {
    Write-Host "  Изменение конфигурации устройств    : Нет записей" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
Write-Section "ЖУРНАЛ USN"
try {
    $usn = fsutil usn queryjournal C: 2>&1
    if ($usn -match "Invalid") {
        Write-Status "USN-журнал" -OK $false -Extra "Отключён"
    } elseif ($usn -match "Usn Journal ID") {
        Write-Status "USN-журнал" -OK $true -Extra "Включён"
        $usnClear = Get-WinEvent -LogName "Application" -FilterXPath "*[System[EventID=3079]]" -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($usnClear) {
            Write-Host ("  {0,-35} : {1}" -f "Последняя очистка", $usnClear.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Red
        } else {
            Write-Host "  Последняя очистка                 : Никогда не очищался вручную" -ForegroundColor Green
        }
        $fu = $usn | Select-String "First Usn"
        if ($fu) {
            Write-Host ("  {0,-35} : {1}" -f "Первый USN", $fu.Line.Trim()) -ForegroundColor Gray
        }
    } else {
        Write-Status "USN-журнал" -OK $false -Extra "Неизвестно"
    }
} catch {
    Write-Host "  Ошибка чтения USN-журнала" -ForegroundColor Red
}

# -----------------------------------------------------------------------------
Write-Section "ЦЕЛОСТНОСТЬ PREFETCH"
$pfPath = "$env:SystemRoot\Prefetch"
if (Test-Path $pfPath) {
    $files = Get-ChildItem $pfPath -Filter *.pf -Force -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Host "  Файлы Prefetch не найдены" -ForegroundColor Gray
    } else {
        $total = $files.Count
        $ht = @{}
        $sus = @{}
        $hid = @(); $ro = @(); $hidro = @()
        foreach ($f in $files) {
            try {
                $isH = $f.Attributes -band [System.IO.FileAttributes]::Hidden
                $isR = $f.Attributes -band [System.IO.FileAttributes]::ReadOnly
                if ($isH -and $isR) { $hidro += $f; $sus[$f.Name] = "Скрытый+ТолькоЧтение" }
                elseif ($isH)       { $hid   += $f; $sus[$f.Name] = "Скрытый" }
                elseif ($isR)       { $ro    += $f; $sus[$f.Name] = "ТолькоЧтение" }
                $h = Get-FileHash $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue
                if ($h) {
                    if ($ht.ContainsKey($h.Hash)) { $ht[$h.Hash].Add($f.Name) }
                    else { $ht[$h.Hash] = [System.Collections.Generic.List[string]]::new(); $ht[$h.Hash].Add($f.Name) }
                }
            } catch { $sus[$f.Name] = "Ошибка" }
        }
        Write-Host ("  Всего файлов   : {0}" -f $total) -ForegroundColor White
        Write-Host ("  Скрытые+RO     : {0}" -f $hidro.Count) -ForegroundColor $(if ($hidro.Count -gt 0) { "Yellow" } else { "Green" })
        Write-Host ("  Только скрытые : {0}" -f $hid.Count) -ForegroundColor $(if ($hid.Count -gt 0) { "Yellow" } else { "Green" })
        Write-Host ("  Только чтение  : {0}" -f $ro.Count) -ForegroundColor $(if ($ro.Count -gt 0) { "Yellow" } else { "Green" })
        $dupes = $ht.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($dupes) {
            Write-Host "  Дубликаты      : Обнаружены" -ForegroundColor Yellow
            foreach ($e in $dupes) {
                Write-Host ("    {0}" -f ($e.Value -join ', ')) -ForegroundColor White
            }
        } else {
            Write-Host "  Дубликаты      : Нет" -ForegroundColor Green
        }
        if ($sus.Count -gt 0) {
            Write-Host ("  Подозрительные : {0}/{1}" -f $sus.Count, $total) -ForegroundColor Red
            foreach ($e in $sus.GetEnumerator() | Sort-Object Key) {
                Write-Host ("    {0} : {1}" -f $e.Key, $e.Value) -ForegroundColor White
            }
        } else {
            Write-Host "  Подозрительные : Нет – чисто" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  Папка Prefetch не найдена" -ForegroundColor Red
}

# -----------------------------------------------------------------------------
Write-Section "КОРЗИНА"
try {
    $rbPath = "$env:SystemDrive\`$Recycle.Bin"
    if (Test-Path $rbPath) {
        $rbF = Get-Item -LiteralPath $rbPath -Force
        $ufs = Get-ChildItem -LiteralPath $rbPath -Directory -Force -ErrorAction SilentlyContinue
        $all = @(); $lat = $rbF.LastWriteTime
        foreach ($uf in $ufs) {
            if ($uf.LastWriteTime -gt $lat) { $lat = $uf.LastWriteTime }
            $ui = Get-ChildItem -LiteralPath $uf.FullName -File -Force -ErrorAction SilentlyContinue
            if ($ui) {
                $all += $ui
                $lf = $ui | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($lf -and $lf.LastWriteTime -gt $lat) { $lat = $lf.LastWriteTime }
            }
        }
        Write-KeyValue "Последнее изменение" $lat.ToString("yyyy-MM-dd HH:mm:ss")
        Write-KeyValue "Всего элементов" $all.Count
        if ($all.Count -gt 0) {
            $lt = $all | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Write-KeyValue "Самый новый" $lt.Name
        } else {
            Write-Host "  Статус                          : Пусто" -ForegroundColor Green
        }
    } else {
        Write-Host "  Корзина не найдена" -ForegroundColor Gray
    }
} catch {
    Write-Host ("  Ошибка: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

# -----------------------------------------------------------------------------
Write-Section "ИСТОРИЯ POWERSHELL"
$hPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
if (Test-Path $hPath) {
    $hf = Get-Item $hPath -Force
    Write-KeyValue "Последнее изменение" $hf.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    Write-KeyValue "Размер" ("{0} КБ" -f [math]::Round($hf.Length/1024,2))
    $attrib = $hf.Attributes
    if ($attrib -eq "Archive") { Write-KeyValue "Атрибуты" "Обычный" -ValueColor Green }
    else { Write-KeyValue "Атрибуты" $attrib }
} else {
    Write-Host "  Файл истории не найден" -ForegroundColor Gray
}

# -----------------------------------------------------------------------------
Write-Section "ОБНАРУЖЕНИЕ HOTSPOT / ФЕЙКЕРОВ"
$suspAct = @(); $fakerDetected = $false; $fakerIndicators = @(); $networkProfiles = @()
# 1. WiFi-профили
try {
    $po = netsh wlan show profiles
    $pn = $po | Select-String "All User Profile\s+:\s+(.+)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
    foreach ($p in $pn) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $isHs = $p -match "Android|iPhone|iPad|Galaxy|Pixel|OnePlus|Xiaomi|DIRECT-|SM-|GT-"
        $networkProfiles += [PSCustomObject]@{ SSID=$p; IsHotspot=$isHs }
    }
    $hsp = $networkProfiles | Where-Object { $_.IsHotspot }
    Write-Host ("  Профилей хот-спота : {0}" -f $hsp.Count) -ForegroundColor $(if ($hsp.Count -gt 0) { "Yellow" } else { "Green" })
    if ($hsp.Count -gt 0) {
        $hsp | ForEach-Object { Write-Host ("    - {0}" -f $_.SSID) -ForegroundColor White }
    }
} catch {}

# 2. Текущее подключение
try {
    $iface = netsh wlan show interfaces
    $ssidM = $iface | Select-String "^\s+SSID\s+:\s+(.+)$"
    $stateM = $iface | Select-String "^\s+State\s+:\s+(.+)$"
    $bssidM = $iface | Select-String "^\s+BSSID\s+:\s+(.+)$"
    $chanM = $iface | Select-String "^\s+Channel\s+:\s+(.+)$"
    $sigM = $iface | Select-String "^\s+Signal\s+:\s+(.+)$"
    if ($ssidM -and $stateM) {
        $curSSID = $ssidM.Matches.Groups[1].Value.Trim()
        $curState = $stateM.Matches.Groups[1].Value.Trim()
        $bssid = if ($bssidM) { $bssidM.Matches.Groups[1].Value.Trim() } else { "Н/Д" }
        $chan = if ($chanM) { $chanM.Matches.Groups[1].Value.Trim() } else { "Н/Д" }
        $sig = if ($sigM) { $sigM.Matches.Groups[1].Value.Trim() } else { "Н/Д" }
        if ($curState -eq "connected") {
            $isHs = $false; $hsInd = @()
            $pats = @("Android","iPhone","iPad","Galaxy","Pixel","OnePlus","Xiaomi","Huawei","Oppo","Vivo","Realme","Nokia","DIRECT-","SM-[A-Z0-9]","GT-[A-Z0-9]","Redmi","'s iPhone","'s Galaxy","'s Pixel")
            foreach ($pat in $pats) { if ($curSSID -match $pat) { $isHs=$true; $hsInd+="SSID совпадает: $pat"; break } }
            if ($bssid -ne "Н/Д") { $sc=$bssid.Substring(1,1); if ($sc -match "[26AEae]") { $isHs=$true; $hsInd+="BSSID локально администрируемый" } }
            try {
                $gw = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -and $_.DefaultIPGateway }).DefaultIPGateway | Select-Object -First 1
                if ($gw) {
                    if ($gw -like "192.168.137.*") { $isHs=$true; $fakerDetected=$true; $fakerIndicators+="Шлюз Windows Mobile Hotspot (192.168.137.x)"; $hsInd+="Шлюз = Windows Mobile Hotspot - ФЕЙКЕР" }
                    elseif ($gw -eq "192.168.43.1") { $isHs=$true; $hsInd+="Шлюз = Android-хот-спот" }
                    elseif ($gw -eq "192.168.49.1") { $isHs=$true; $hsInd+="Шлюз = Android-хот-спот" }
                }
            } catch {}
            Write-Host ("  Подключено к      : {0}" -f $curSSID) -ForegroundColor $(if ($isHs) { "Red" } else { "Green" })
            Write-Host ("    BSSID: {0} | Канал: {1} | Сигнал: {2}" -f $bssid, $chan, $sig) -ForegroundColor Gray
            if ($isHs) {
                Write-Host "  ВНИМАНИЕ: ОБНАРУЖЕН ХОТ-СПОТ!" -ForegroundColor Red
                $hsInd | ForEach-Object { Write-Host ("    - {0}" -f $_) -ForegroundColor White }
                $suspAct += "Подключение к хот-споту: $curSSID"
            }
        }
    }
} catch {}

# 3. Hosted network
try {
    $hn = netsh wlan show hostednetwork
    $hnSt = $hn | Select-String "Status\s+:\s+(.+)"
    if ($hnSt -and $hnSt.Matches.Groups[1].Value.Trim() -eq "Started") {
        $hnSM = $hn | Select-String 'SSID name\s+:\s+"(.+)"'
        $hnSSID = if ($hnSM) { $hnSM.Matches.Groups[1].Value } else { "Неизвестно" }
        Write-Host ("  Размещённая сеть   : АКТИВНА (SSID: {0})" -f $hnSSID) -ForegroundColor Red
        $suspAct += "Размещённая сеть активна: $hnSSID"
    } else {
        Write-Host "  Размещённая сеть   : Неактивна" -ForegroundColor Green
    }
} catch {}

# 4. icssvc
$ics = Get-Service -Name "icssvc" -ErrorAction SilentlyContinue
if ($ics) {
    if ($ics.Status -eq "Running") {
        Write-Host "  Мобильный хот-спот : РАБОТАЕТ" -ForegroundColor Red
        $suspAct += "icssvc запущена"
    } else {
        Write-Host "  Мобильный хот-спот : Остановлен" -ForegroundColor Green
    }
}

# 5. Виртуальные адаптеры
try {
    $va = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true -and $_.Description -match "Virtual|Hosted|Wi-Fi Direct|TAP" }
    if ($va) {
        Write-Host ("  Виртуальных адаптеров : {0}" -f $va.Count) -ForegroundColor Yellow
        $va | ForEach-Object { Write-Host ("    - {0}" -f $_.Description) -ForegroundColor White }
        $suspAct += "$($va.Count) виртуальных адаптеров"
    } else {
        Write-Host "  Виртуальных адаптеров : Нет" -ForegroundColor Green
    }
} catch {}

# -----------------------------------------------------------------------------
Write-Section "РЕЗУЛЬТАТ SFC /SCANNOW"
$sfcResult = Receive-Job $sfcJob
Remove-Job $sfcJob
$sfcSum = $sfcResult | Where-Object { $_ -match "protection|found|repair|did not find|resource" } | Select-Object -Last 1
if ($sfcSum) {
    $col = if ($sfcSum -match "did not find") { "Green" } else { "White" }
    Write-Host ("  Результат: {0}" -f $sfcSum.ToString().Trim()) -ForegroundColor $col
} else {
    Write-Host "  Результат: завершён (смотрите CBS.log)" -ForegroundColor White
}

# --- Сохранение CBS.log в папку "RealMikoto папа" на рабочем столе ---
$cbsLog = "$env:windir\Logs\CBS\CBS.log"
$destFolder = "$env:USERPROFILE\Desktop\RealMikoto папа"
if (Test-Path $cbsLog) {
    if (-not (Test-Path $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
    }
    Copy-Item -Path $cbsLog -Destination $destFolder -Force
    Write-Host ("  CBS.log сохранён в: {0}" -f $destFolder) -ForegroundColor Green
} else {
    Write-Host "  CBS.log не найден" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
Write-Section "ПРОЦЕССЫ JAVA"
$jProcs = Get-Process -Name @("java","javaw") -ErrorAction SilentlyContinue
if (-not $jProcs) {
    Write-Host "  Процессы java/javaw не запущены" -ForegroundColor Green
} else {
    Write-Host ("  Всего процессов Java: {0}" -f $jProcs.Count) -ForegroundColor White
    $nsLines = netstat -ano | Select-String "LISTENING|ESTABLISHED"
    foreach ($jp in $jProcs) {
        Write-Host ""
        Write-Host ("  PID {0} | Запущен: {1}" -f $jp.Id, $jp.StartTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
        try {
            $cl = (Get-WmiObject Win32_Process -Filter "ProcessId=$($jp.Id)").CommandLine
            if ($cl) {
                $sh = if ($cl.Length -gt 120) { $cl.Substring(0,117)+"..." } else { $cl }
                Write-Host ("    CMD: {0}" -f $sh) -ForegroundColor Gray
            }
        } catch {}
        $pp = $nsLines | Where-Object { $_ -match "\s+$($jp.Id)\s*$" }
        if ($pp) {
            Write-Host "    Порты:" -ForegroundColor White
            $pp | ForEach-Object { Write-Host ("      {0}" -f $_.Line.Trim()) -ForegroundColor White }
        } else {
            Write-Host "    Порты: не найдены" -ForegroundColor Gray
        }
    }
}

# ========== СВОДКА ==========
Write-Host ""
Write-Header " СВОДКА "
Write-Host ("  Подозрительных действий : {0}" -f $suspAct.Count) -ForegroundColor $(if ($suspAct.Count -gt 0) {"Red"} else {"Green"})
Write-Host ("  Фейкер обнаружен        : {0}" -f $(if ($fakerDetected) {'ДА'} else {'Нет'})) -ForegroundColor $(if ($fakerDetected) {"Red"} else {"Green"})
Write-Host ("  Профилей хот-спота      : {0}" -f $(($networkProfiles | Where-Object {$_.IsHotspot}).Count)) -ForegroundColor White
if ($suspAct.Count -gt 0) {
    Write-Host "`n  Предупреждения:" -ForegroundColor Red
    $suspAct | ForEach-Object { Write-Host ("    - {0}" -f $_) -ForegroundColor White }
}
if ($fakerIndicators.Count -gt 0) {
    Write-Host "`n  Признаки фейкера:" -ForegroundColor Red
    $fakerIndicators | ForEach-Object { Write-Host ("    - {0}" -f $_) -ForegroundColor White }
}

Write-Host "`nПроверка завершена. Разработано RealMikoto" -ForegroundColor DarkGray
Write-Host ""