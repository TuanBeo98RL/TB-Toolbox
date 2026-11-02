<#
================================================================================
 TB-TOOLBOX - POWER MANAGER & SHUTDOWN ENGINE (Engine-PowerManager.ps1)
 Mã Chức Năng: FN0002 / Module: F02_SHUTDOWN_TIMER
 Bản quyền: Kỹ sư Đào Xuân Tuấn (Mr. Tuấn Beo)
 Mô tả: Động cơ hẹn giờ tắt máy, khởi động lại, ngủ đông, chống ngủ máy (Awake),
        quản lý cấu hình nguồn điện với giao diện trực quan, logging chi tiết
================================================================================
#>

# Thiết lập encoding UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$coreDir = $PSScriptRoot
. (Join-Path $coreDir "Common-UI.ps1")

# Khởi tạo đường dẫn hệ thống
$engineDir = Split-Path -Parent $coreDir
$rootDir = Split-Path -Parent $engineDir
$logDir = Join-Path $engineDir "Logs"
$featureLogDir = Join-Path $logDir "[TB-02]-Hen-Gio-Tat-May-Nguon-Dien"
if (-not (Test-Path -LiteralPath $featureLogDir)) {
    New-Item -ItemType Directory -Path $featureLogDir -Force | Out-Null
}

# Auto-Purge: Tự động giữ tối đa 30 file log gần nhất của chức năng này (Rule 6)
try {
    $existingLogs = Get-ChildItem -LiteralPath $featureLogDir -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($existingLogs.Count -gt 30) {
        $existingLogs | Select-Object -Skip 30 | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
} catch {}

# Khởi tạo file log phiên làm việc hiện tại
$currentUserName = if ($env:USERNAME) { $env:USERNAME } else { "User" }
$logTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFileName = "{0}_{1}.log" -f $currentUserName, $logTimestamp
$currentLogPath = Join-Path $featureLogDir $logFileName

function Write-PowerLog {
    param ([string]$Message, [string]$Level = "INFO")
    $timeStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[{0}] [{1}] {2}" -f $timeStr, $Level, $Message
    try {
        $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
        if (-not (Test-Path -LiteralPath $currentLogPath)) {
            [System.IO.File]::WriteAllText($currentLogPath, $line + "`r`n", $utf8WithBom)
        } else {
            [System.IO.File]::AppendAllText($currentLogPath, $line + "`r`n", $utf8WithBom)
        }
    } catch {}
}

Write-PowerLog -Message "=== KHỞI ĐỘNG MODULE FN0002 - HẸN GIỜ TẮT MÁY & QUẢN LÝ NGUỒN ĐIỆN ===" -Level "START"

# ==============================================================================
# BẢO VỆ BẢN QUYỀN & NIÊM PHONG TÍNH TOÀN VẸN 3 TẦNG (TRIPLE-SHIELD GATE)
# ==============================================================================
if (Test-Path (Join-Path $coreDir "License-Engine.ps1")) {
    . (Join-Path $coreDir "License-Engine.ps1")
    $currentHwid = Get-MachineHWID

    # Kiểm tra máy Admin Tuấn Beo
    $whitelistFile = Join-Path $engineDir "Config\admin-whitelist.json"
    $isAdminMachine = $false
    if (Test-Path $whitelistFile) {
        try {
            $wData = [System.IO.File]::ReadAllText($whitelistFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($wData.trustedAdmins | Where-Object { $_.hwid -eq $currentHwid }) {
                $isAdminMachine = $true
            }
        } catch {}
    }

    if (-not $isAdminMachine) {
        $licCheck = Verify-LicenseTripleAnchor -CurrentHWID $currentHwid
        if (-not $licCheck.IsValid) {
            Show-HeaderBanner -SubTitle "CẢNH BÁO BẢN QUYỀN & BẢO MẬT"
            Write-Host " [X] KHÔNG THỂ KHỞI CHẠY ỨNG DỤNG!" -ForegroundColor Red
            Write-Host " Lý do: $($licCheck.Error)" -ForegroundColor Yellow
            Write-Host "`n Vui lòng mở lại file [001]-Cai-Dat-TB-Toolbox.bat để kích hoạt lại bản quyền.`n" -ForegroundColor DarkGray
            Write-PowerLog -Message "Tu choi khoi chay do loi ban quyen: $($licCheck.Error)" -Level "SECURITY_FAIL"
            Wait-ForUserExit
            exit 1
        }
    }
}

# ==============================================================================
# IMPORT WINDOWS NATIVE API (P/INVOKE) CHO AWAKE MODE & LOCK
# ==============================================================================
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class WinPowerNative {
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool LockWorkStation();

    [DllImport("Powrprof.dll", SetLastError = true)]
    public static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);

    public const uint ES_SYSTEM_REQUIRED  = 0x00000001;
    public const uint ES_DISPLAY_REQUIRED = 0x00000002;
    public const uint ES_CONTINUOUS       = 0x80000000;
}
"@ -ErrorAction SilentlyContinue
} catch {}

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ==============================================================================
# HÀM ĐẾM NGƯỢC THỜI GIAN THỰC (LIVE COUNTDOWN CONSOLE)
# ==============================================================================
function Start-LiveCountdown {
    param (
        [int]$TotalSeconds,
        [string]$ActionName,
        [scriptblock]$ExecuteAction
    )

    Show-HeaderBanner -SubTitle "ĐANG THỰC HIỆN ĐẾM NGƯỢC HẸN GIỜ: $ActionName"
    Write-Host " [!] Nhấn phím [C] hoặc [ESC] bất kỳ lúc nào để HỦY BỎ lệnh hẹn giờ!`n" -ForegroundColor Yellow

    $remaining = $TotalSeconds
    $cancelled = $false

    while ($remaining -gt 0) {
        $hours = [int]($remaining / 3600)
        $mins  = [int](($remaining % 3600) / 60)
        $secs  = $remaining % 60
        $timeStr = "{0:D2}:{1:D2}:{2:D2}" -f $hours, $mins, $secs

        Write-Host -NoNewline ("`r >> Thời gian còn lại trước khi {0}: [ {1} ] <<   (Nhấn [C] để HỦY)   " -f $ActionName, $timeStr) -ForegroundColor Green

        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::C -or $key.Key -eq [ConsoleKey]::Escape) {
                $cancelled = $true
                break
            }
        }

        Start-Sleep -Seconds 1
        $remaining--
    }

    Write-Host ""
    if ($cancelled) {
        Write-Host "`n [!] ĐÃ HỦY BỎ LỆNH HẸN GIỜ THEO YÊU CẦU CỦA BẠN!" -ForegroundColor Yellow
        Write-PowerLog -Message "Nguoi dung da huy bo hen gio $ActionName khi con $remaining giay" -Level "CANCEL"
        # Gọi an toàn shutdown /a
        cmd.exe /c "shutdown.exe /a" 2>$null | Out-Null
        Start-Sleep -Seconds 2
        return $false
    } else {
        Write-Host "`n [*] Hết thời gian đếm ngược! Đang thực thi: $ActionName..." -ForegroundColor Red
        Write-PowerLog -Message "Ket thuc dem nguoc, bat dau thuc thi: $ActionName" -Level "EXECUTE"
        & $ExecuteAction
        return $true
    }
}

# ==============================================================================
# CHỨC NĂNG 1: HẸN GIỜ TẮT MÁY SAU X PHÚT / GIỜ
# ==============================================================================
function Show-RelativeTimerMenu {
    Show-HeaderBanner -SubTitle "HẸN GIỜ TẮT MÁY THEO KHOẢNG THỜI GIAN"

    Write-Host " Chọn đơn vị thời gian:" -ForegroundColor Cyan
    Write-Host " [1] Theo số PHÚT (Ví dụ: 15, 30, 45, 60...)" -ForegroundColor White
    Write-Host " [2] Theo số GIỜ  (Ví dụ: 1, 2, 3, 5...)" -ForegroundColor White
    Write-Host " [0] Quay lại Menu chính`n" -ForegroundColor DarkGray

    $unitOpt = Read-Host " Nhập lựa chọn [0-2]"
    if ($unitOpt -eq "0" -or [string]::IsNullOrWhiteSpace($unitOpt)) { return }

    $multiplier = 60
    $unitLabel = "phút"
    if ($unitOpt -eq "2") {
        $multiplier = 3600
        $unitLabel = "giờ"
    }

    $inputNum = Read-Host "`n Nhập số $unitLabel bạn muốn máy tự động tắt (ví dụ: 30)"
    if ($inputNum -notmatch '^\d+$' -or [int]$inputNum -le 0) {
        Write-Host " [X] Giá trị không hợp lệ! Vui lòng nhập số nguyên dương." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    $totalSecs = [int]$inputNum * $multiplier
    $targetTime = (Get-Date).AddSeconds($totalSecs).ToString("HH:mm:ss dd/MM/yyyy")

    Write-Host "`n Máy tính sẽ tự động tắt lúc: " -NoNewline
    Write-Host "$targetTime" -ForegroundColor Yellow -NoNewline
    Write-Host " (sau $inputNum $unitLabel)`n"

    Write-Host " Chọn chế độ tắt máy:" -ForegroundColor Cyan
    Write-Host " [1] Tắt an toàn (Graceful - Cho phép ứng dụng lưu dữ liệu, không mất file)" -ForegroundColor Green
    Write-Host " [2] Ép buộc tắt ngay (Force /f - Đóng cưỡng chế mọi phần mềm chưa lưu)" -ForegroundColor Red
    Write-Host " [0] Hủy bỏ thao tác`n" -ForegroundColor DarkGray

    $modeOpt = Read-Host " Chọn chế độ [1/2]"
    if ($modeOpt -eq "0" -or [string]::IsNullOrWhiteSpace($modeOpt)) { return }

    $isForce = ($modeOpt -eq "2")
    $forceParam = if ($isForce) { "/f" } else { "" }

    Write-Host "`n Chọn phương thức vận hành:" -ForegroundColor Cyan
    Write-Host " [1] Giữ màn hình đếm ngược trực quan (Live Countdown - Bấm C để hủy lúc nào cũng được)" -ForegroundColor Green
    Write-Host " [2] Chạy ngầm trong hệ điều hành Windows (Có thể đóng cửa sổ này, hủy bằng lệnh [9])" -ForegroundColor Cyan
    $runOpt = Read-Host " Chọn [1/2]"

    Write-PowerLog -Message "Dat hen gio tat may sau $inputNum $unitLabel (luc $targetTime, Force: $isForce, RunMode: $runOpt)" -Level "SCHEDULE"

    if ($runOpt -eq "2") {
        # Đăng ký lệnh ngầm của Windows
        cmd.exe /c "shutdown.exe /s $forceParam /t $totalSecs"
        Write-Host "`n [OK] ĐÃ THIẾT LẬP LỆNH HẸN GIỜ TẮT MÁY CHẠY NGẦM THÀNH CÔNG!" -ForegroundColor Green
        Write-Host " Máy tính của bạn sẽ tắt vào lúc: $targetTime" -ForegroundColor Yellow
        Write-Host " Để hủy lệnh này bất cứ lúc nào, bạn chỉ cần mở lại công cụ và chọn [9] HỦY BỎ LỆNH HẸN GIỜ.`n" -ForegroundColor DarkGray
        Wait-ForUserExit
    } else {
        Start-LiveCountdown -TotalSeconds $totalSecs -ActionName "Tắt máy tính" -ExecuteAction {
            cmd.exe /c "shutdown.exe /s $forceParam /t 0"
        }
    }
}

# ==============================================================================
# CHỨC NĂNG 2: HẸN GIỜ TẮT MÁY THEO MỐC GIỜ CỐ ĐỊNH (HH:mm)
# ==============================================================================
function Show-ClockTimeTimerMenu {
    Show-HeaderBanner -SubTitle "HẸN GIỜ TẮT MÁY THEO MỐC GIỜ CỐ ĐỊNH (ĐỒNG HỒ)"

    $now = Get-Date
    Write-Host (" Thời gian hiện tại trên máy tính: {0}" -f $now.ToString("HH:mm:ss - dd/MM/yyyy")) -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " Nhập mốc giờ tắt máy theo định dạng [HH:mm] (Ví dụ: 23:30 hoặc 01:15):" -ForegroundColor White
    Write-Host " [0] Quay lại Menu chính`n" -ForegroundColor DarkGray

    $timeInput = Read-Host " Nhập giờ hẹn [HH:mm]"
    if ($timeInput -eq "0" -or [string]::IsNullOrWhiteSpace($timeInput)) { return }

    if ($timeInput -notmatch '^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$') {
        Write-Host " [X] Định dạng giờ không đúng! Vui lòng nhập đúng chuẩn HH:mm (Ví dụ: 22:45 hoặc 02:00)." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    $parts = $timeInput.Split(':')
    $h = [int]$parts[0]
    $m = [int]$parts[1]

    # Tính toán mốc thời gian mục tiêu (Target DateTime)
    $targetDate = Get-Date -Hour $h -Minute $m -Second 0
    if ($targetDate -le $now) {
        # Đã qua mốc giờ này trong ngày -> Tự động chuyển sang ngày mai (Xử lý điểm mù qua nửa đêm)
        $targetDate = $targetDate.AddDays(1)
        Write-Host " [!] Mốc giờ này đã qua trong hôm nay. Tự động hẹn sang NGÀY MAI!" -ForegroundColor Yellow
    }

    $diffSecs = [int]($targetDate - $now).TotalSeconds
    $diffHours = [int]($diffSecs / 3600)
    $diffMins = [int](($diffSecs % 3600) / 60)

    Write-Host "`n [XÁC NHẬN] Máy tính sẽ tắt vào lúc: " -NoNewline
    Write-Host ("{0}" -f $targetDate.ToString("HH:mm:ss dd/MM/yyyy")) -ForegroundColor Yellow
    Write-Host (" Còn lại khoảng: {0} giờ {1} phút nữa.`n" -f $diffHours, $diffMins) -ForegroundColor Cyan

    Write-Host " Chọn chế độ thực thi:" -ForegroundColor Cyan
    Write-Host " [1] Giữ màn hình đếm ngược trực quan (Live Countdown)" -ForegroundColor Green
    Write-Host " [2] Đặt lịch chạy ngầm Windows (Có thể đóng console này)" -ForegroundColor Cyan
    Write-Host " [0] Hủy bỏ`n" -ForegroundColor DarkGray

    $mode = Read-Host " Chọn thao tác [1/2]"
    if ($mode -eq "0" -or [string]::IsNullOrWhiteSpace($mode)) { return }

    Write-PowerLog -Message "Dat hen gio tat may vao luc $targetDate (Con $diffSecs giay, RunMode: $mode)" -Level "SCHEDULE"

    if ($mode -eq "2") {
        cmd.exe /c "shutdown.exe /s /t $diffSecs"
        Write-Host "`n [OK] ĐÃ ĐẶT LỊCH HẸN GIỜ TẮT MÁY THÀNH CÔNG!" -ForegroundColor Green
        Write-Host (" Máy sẽ tắt lúc: {0}" -f $targetDate.ToString("HH:mm:ss dd/MM/yyyy")) -ForegroundColor Yellow
        Wait-ForUserExit
    } else {
        Start-LiveCountdown -TotalSeconds $diffSecs -ActionName ("Tắt máy lúc {0}" -f $targetDate.ToString("HH:mm")) -ExecuteAction {
            cmd.exe /c "shutdown.exe /s /t 0"
        }
    }
}

# ==============================================================================
# CHỨC NĂNG 3: HẸN GIỜ KHỞI ĐỘNG LẠI / NGỦ ĐÔNG / NGỦ / KHÓA MÁY
# ==============================================================================
function Show-OtherPowerActionsMenu {
    Show-HeaderBanner -SubTitle "HẸN GIỜ KHỞI ĐỘNG LẠI, NGỦ ĐÔNG & KHÓA MÁY"

    Write-Host " Chọn hành động nguồn điện muốn thực hiện:" -ForegroundColor Cyan
    Write-Host " [1] Hẹn giờ Khởi động lại máy (Restart)" -ForegroundColor White
    Write-Host " [2] Hẹn giờ Ngủ đông (Hibernate - Lưu trạng thái ram vào ổ cứng rồi tắt hẳn)" -ForegroundColor White
    Write-Host " [3] Hẹn giờ Ngủ (Sleep - Tiết kiệm điện năng, bật lại tức thì)" -ForegroundColor White
    Write-Host " [4] Khóa máy tính ngay lập tức (Lock Workstation)" -ForegroundColor White
    Write-Host " [0] Quay lại Menu chính`n" -ForegroundColor DarkGray

    $actOpt = Read-Host " Chọn hành động [0-4]"
    if ($actOpt -eq "0" -or [string]::IsNullOrWhiteSpace($actOpt)) { return }

    if ($actOpt -eq "4") {
        Write-Host " Đang khóa máy tính..." -ForegroundColor Cyan
        Write-PowerLog -Message "Khoa may tinh tuc thi (LockWorkStation)" -Level "ACTION"
        [WinPowerNative]::LockWorkStation() | Out-Null
        return
    }

    $actionName = ""
    $actionCode = ""
    switch ($actOpt) {
        "1" { $actionName = "Khởi động lại máy tính (Restart)"; $actionCode = "RESTART" }
        "2" { $actionName = "Ngủ đông máy tính (Hibernate)"; $actionCode = "HIBERNATE" }
        "3" { $actionName = "Đưa máy vào chế độ Ngủ (Sleep)"; $actionCode = "SLEEP" }
    }

    # Điểm mù 3: Kiểm tra Hibernate hỗ trợ
    if ($actionCode -eq "HIBERNATE") {
        $avail = cmd.exe /c "powercfg /a" 2>$null
        if ($avail -match "Hibernate has not been enabled" -or $avail -notmatch "Hibernate") {
            Write-Host "`n [!] Chế độ Hibernate chưa được bật trên máy tính của bạn!" -ForegroundColor Yellow
            $enableOpt = Read-Host " Bạn có muốn thử kích hoạt Hibernate ngay không? (Cần quyền Admin) [Y/N]"
            if ($enableOpt -eq "Y" -or $enableOpt -eq "y") {
                cmd.exe /c "powercfg /hibernate on" 2>$null
                Write-Host " [OK] Đã gửi lệnh bật Hibernate." -ForegroundColor Green
            } else {
                return
            }
        }
    }

    $inputMins = Read-Host "`n Nhập số PHÚT hẹn giờ để thực hiện $actionName (ví dụ: 15)"
    if ($inputMins -notmatch '^\d+$' -or [int]$inputMins -le 0) {
        Write-Host " [X] Số phút không hợp lệ!" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    $totalSecs = [int]$inputMins * 60
    Write-PowerLog -Message "Dat hen gio $actionCode sau $inputMins phut" -Level "SCHEDULE"

    Start-LiveCountdown -TotalSeconds $totalSecs -ActionName $actionName -ExecuteAction {
        switch ($actionCode) {
            "RESTART" {
                cmd.exe /c "shutdown.exe /r /t 0"
            }
            "HIBERNATE" {
                [WinPowerNative]::SetSuspendState($true, $false, $false) | Out-Null
            }
            "SLEEP" {
                [WinPowerNative]::SetSuspendState($false, $false, $false) | Out-Null
            }
        }
    }
}

# ==============================================================================
# CHỨC NĂNG 4: CHẾ ĐỘ CHỐNG NGỦ MÁY (AWAKE / CAFFEINE MODE)
# ==============================================================================
function Show-AwakeModeMenu {
    Show-HeaderBanner -SubTitle "CHẾ ĐỘ GIỮ MÁY LUÔN THỨC (AWAKE / CAFFEINE MODE)"

    Write-Host " Chế độ này ngăn Windows tự động tắt màn hình hoặc đưa máy vào giấc ngủ (Sleep)" -ForegroundColor Green
    Write-Host " rất hữu ích khi bạn đang tải file nặng, treo game, render video hoặc build code.`n" -ForegroundColor White

    Write-Host " [1] BẬT chế độ Giữ máy luôn thức (Awake Mode)" -ForegroundColor Cyan
    Write-Host " [0] Quay lại Menu chính`n" -ForegroundColor DarkGray

    $opt = Read-Host " Chọn thao tác [0/1]"
    if ($opt -ne "1") { return }

    # Kích hoạt ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED
    $flags = [WinPowerNative]::ES_CONTINUOUS -bor [WinPowerNative]::ES_SYSTEM_REQUIRED -bor [WinPowerNative]::ES_DISPLAY_REQUIRED
    [WinPowerNative]::SetThreadExecutionState($flags) | Out-Null

    Write-PowerLog -Message "Da bat che do Awake / Caffeine Mode" -Level "AWAKE_ON"

    Show-HeaderBanner -SubTitle "CHẾ ĐỘ GIỮ MÁY LUÔN THỨC (AWAKE MODE) ĐANG HOẠT ĐỘNG"
    Write-Host " ================================================================================" -ForegroundColor Green
    Write-Host "               [✔] TRẠNG THÁI: MÁY TÍNH ĐANG ĐƯỢC GIỮ LUÔN HOẠT ĐỘNG             " -ForegroundColor Green
    Write-Host " ================================================================================" -ForegroundColor Green
    Write-Host "   - Màn hình sẽ KHÔNG tự động tắt." -ForegroundColor Yellow
    Write-Host "   - Hệ thống sẽ KHÔNG tự động chuyển sang chế độ Sleep." -ForegroundColor Yellow
    Write-Host "`n   >> Nhấn phím bất kỳ hoặc nhấn [Q] để TẮT chế độ Awake và quay lại <<`n" -ForegroundColor Cyan

    $null = [Console]::ReadKey($true)

    # Khôi phục trạng thái nguồn điện bình thường (chỉ còn ES_CONTINUOUS)
    [WinPowerNative]::SetThreadExecutionState([WinPowerNative]::ES_CONTINUOUS) | Out-Null
    Write-PowerLog -Message "Da tat che do Awake, khoi phuc trang thai nguon dien binh thuong" -Level "AWAKE_OFF"

    Write-Host " [OK] Đã tắt chế độ Awake. Hệ thống đã khôi phục quản lý nguồn điện bình thường.`n" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# ==============================================================================
# CHỨC NĂNG 5: QUẢN LÝ GÓI HIỆU NĂNG NGUỒN ĐIỆN (POWER PLANS)
# ==============================================================================
function Show-PowerPlansMenu {
    Show-HeaderBanner -SubTitle "QUẢN LÝ CẤU HÌNH GÓI NGUỒN ĐIỆN (POWER SCHEMES)"

    Write-Host " Danh sách các gói nguồn điện hiện có trên thiết bị:`n" -ForegroundColor Cyan

    $rawPlans = cmd.exe /c "powercfg /list" 2>$null
    $plans = @()
    $idx = 1

    foreach ($line in $rawPlans) {
        if ($line -match 'Power Scheme GUID:\s+([a-f0-9\-]+)\s+\(([^)]+)\)(\s+\*)?') {
            $guid = $matches[1]
            $name = $matches[2]
            $isActive = if ($matches[3]) { $true } else { $false }
            $plans += [PSCustomObject]@{
                Index    = $idx
                Guid     = $guid
                Name     = $name
                IsActive = $isActive
            }
            $idx++
        }
    }

    if ($plans.Count -eq 0) {
        Write-Host " [!] Không thể truy xuất danh sách Power Plan của hệ thống." -ForegroundColor Yellow
        Wait-ForUserExit
        return
    }

    foreach ($p in $plans) {
        if ($p.IsActive) {
            Write-Host ("  [{0}] {1,-28} (ĐANG SỬ DỤNG [*])" -f $p.Index, $p.Name) -ForegroundColor Green
        } else {
            Write-Host ("  [{0}] {1,-28}" -f $p.Index, $p.Name) -ForegroundColor White
        }
    }

    Write-Host "`n --------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " [T] Tắt nhanh màn hình sau X phút (Display Timeout)" -ForegroundColor Yellow
    Write-Host " [0] Quay lại Menu chính`n" -ForegroundColor DarkGray

    $choice = Read-Host " Nhập số thứ tự để KÍCH HOẠT gói nguồn điện đó (hoặc [T], [0])"
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }

    if ($choice -eq "T" -or $choice -eq "t") {
        $mins = Read-Host "`n Nhập số phút để tự động tắt màn hình (0 = Không bao giờ tắt)"
        if ($mins -match '^\d+$') {
            cmd.exe /c "powercfg /change monitor-timeout-ac $mins" 2>$null
            cmd.exe /c "powercfg /change monitor-timeout-dc $mins" 2>$null
            Write-Host " [OK] Đã thiết lập thời gian tắt màn hình: $mins phút." -ForegroundColor Green
            Write-PowerLog -Message "Thiet lap monitor-timeout thanh $mins phut" -Level "CONFIG"
            Start-Sleep -Seconds 2
        }
        return
    }

    $selectedPlan = $plans | Where-Object { $_.Index -eq [int]$choice }
    if ($selectedPlan) {
        cmd.exe /c "powercfg /setactive $($selectedPlan.Guid)" 2>$null
        Write-Host ("`n [OK] Đã kích hoạt gói nguồn điện: {0} ({1})" -f $selectedPlan.Name, $selectedPlan.Guid) -ForegroundColor Green
        Write-PowerLog -Message ("Chuyen power plan thanh {0} ({1})" -f $selectedPlan.Name, $selectedPlan.Guid) -Level "CONFIG"
        Start-Sleep -Seconds 2
    } else {
        Write-Host " [X] Lựa chọn không hợp lệ!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}

# ==============================================================================
# CHỨC NĂNG 9: HỦY BỎ LỆNH HẸN GIỜ ĐANG CHẠY (EMERGENCY CANCEL)
# ==============================================================================
function Cancel-ActiveShutdown {
    Show-HeaderBanner -SubTitle "HỦY BỎ LỆNH HẸN GIỜ ĐANG KÍCH HOẠT"

    Write-Host " Đang kiểm tra và hủy các lệnh hẹn giờ tắt máy..." -ForegroundColor Cyan
    $res = cmd.exe /c "shutdown.exe /a 2>&1"

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n ================================================================================" -ForegroundColor Green
        Write-Host "                  [✔] ĐÃ HỦY BỎ THÀNH CÔNG LỆNH HẸN GIỜ TẮT MÁY!                 " -ForegroundColor Green
        Write-Host " ================================================================================" -ForegroundColor Green
        Write-Host " Mọi lịch trình tắt máy hoặc khởi động lại trước đó đã được dừng hoàn toàn.`n" -ForegroundColor Yellow
        Write-PowerLog -Message "Huy thanh cong lenh hen gio dang chay (shutdown /a)" -Level "CANCEL_OK"
    } else {
        Write-Host "`n [!] Thông báo từ Windows: Hiện tại KHÔNG CÓ lệnh hẹn giờ tắt máy nào đang chạy.`n" -ForegroundColor DarkGray
        Write-PowerLog -Message "Goi shutdown /a nhung khong co tien trinh nao chay" -Level "CANCEL_INFO"
    }

    Wait-ForUserExit
}

# ==============================================================================
# VÒNG LẶP MENU ĐIỀU KHIỂN CHÍNH
# ==============================================================================
while ($true) {
    Show-HeaderBanner -SubTitle "HẸN GIỜ TẮT MÁY & QUẢN LÝ NGUỒN ĐIỆN (FN0002)"

    Write-Host " DANH MỤC TIỆN ÍCH QUẢN LÝ NGUỒN ĐIỆN:" -ForegroundColor Cyan
    Write-Host " --------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " [1] Hẹn giờ TẮT MÁY sau X phút / giờ (Đếm ngược thời gian)" -ForegroundColor Green
    Write-Host " [2] Hẹn giờ TẮT MÁY theo mốc giờ cụ thể (Ví dụ: 23:30, tự tính qua ngày)" -ForegroundColor Green
    Write-Host " [3] Hẹn giờ Khởi động lại (Restart), Ngủ đông (Hibernate) & Khóa máy" -ForegroundColor White
    Write-Host " [4] Chế độ Giữ máy luôn thức (Awake / Caffeine Mode - Chống sleep khi treo máy)" -ForegroundColor Yellow
    Write-Host " [5] Quản lý Gói Nguồn điện (High Performance, Balanced, Timeout màn hình)" -ForegroundColor White
    Write-Host " --------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " [9] HỦY BỎ LỆNH HẸN GIỜ ĐANG CHẠY (Emergency Cancel: shutdown /a)" -ForegroundColor Red
    Write-Host " [O] Mở thư mục chứa file Nhật ký (Logs) của chức năng này" -ForegroundColor DarkCyan
    Write-Host " [0] Thoát chương trình" -ForegroundColor DarkGray
    Write-Host " ================================================================================`n" -ForegroundColor DarkGray

    $mainChoice = Read-Host " Nhập lựa chọn của bạn [0-9, O]"

    switch ($mainChoice) {
        "1" { Show-RelativeTimerMenu }
        "2" { Show-ClockTimeTimerMenu }
        "3" { Show-OtherPowerActionsMenu }
        "4" { Show-AwakeModeMenu }
        "5" { Show-PowerPlansMenu }
        "9" { Cancel-ActiveShutdown }
        "O" {
            if (Test-Path -LiteralPath $featureLogDir) {
                Invoke-Item $featureLogDir
            }
        }
        "o" {
            if (Test-Path -LiteralPath $featureLogDir) {
                Invoke-Item $featureLogDir
            }
        }
        "0" {
            Write-PowerLog -Message "Nguoi dung thoat chuong trinh." -Level "EXIT"
            Write-Host "`n Cảm ơn bạn đã sử dụng TB-Toolbox! Tạm biệt.`n" -ForegroundColor Green
            exit 0
        }
        default {
            Write-Host " [X] Lựa chọn không hợp lệ, vui lòng thử lại!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
