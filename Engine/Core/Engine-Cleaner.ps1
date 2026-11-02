<#
================================================================================
 TB-TOOLBOX - CLEANER ENGINE (Engine-Cleaner.ps1)
 Bản quyền: Mr. Tuấn Beo (TuanBeo)
 Mô tả: Động cơ quét & dọn dẹp hệ thống, thanh tiến trình siêu mượt, logging chi tiết
================================================================================
#>

# Nạp các module dùng chung
$coreDir = $PSScriptRoot
. (Join-Path $coreDir "Common-UI.ps1")
. (Join-Path $coreDir "Config-Manager.ps1")

# Khởi tạo đường dẫn hệ thống Engine
$engineDir = Split-Path -Parent $coreDir
$rootDir = Split-Path -Parent $engineDir
$logDir = Join-Path $engineDir "Logs"
$featureLogDir = Join-Path $logDir "[TB-01]-Don-Dep-Bo-Nho-Tam"
if (-not (Test-Path $featureLogDir)) {
    New-Item -ItemType Directory -Path $featureLogDir -Force | Out-Null
}

# Auto-Purge: Tự động giữ tối đa 30 file log gần nhất của chức năng này
try {
    $existingLogs = Get-ChildItem -Path $featureLogDir -Filter "*.log" | Sort-Object LastWriteTime -Descending
    if ($existingLogs.Count -gt 30) {
        $existingLogs | Select-Object -Skip 30 | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
} catch {}

# Self-Healing: Đảm bảo dịch vụ wuauserv không bị tắt kẹt từ trước
try {
    $wuService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    if ($wuService -and $wuService.StartType -eq "Disabled") {
        Set-Service -Name "wuauserv" -StartupType Manual -ErrorAction SilentlyContinue
    }
} catch {}

# ==============================================================================
# BẢO VỆ BẢN QUYỀN & NIÊM PHONG TÍNH TOÀN VẸN 3 TẦNG (TRIPLE-SHIELD GATE)
# ==============================================================================
if (Test-Path (Join-Path $coreDir "License-Engine.ps1")) {
    . (Join-Path $coreDir "License-Engine.ps1")
    $currentHwid = Get-MachineHWID

    # Kiểm tra xem có phải máy Admin Tuấn Beo không
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
            Write-Host "`n Vui lòng mở lại file [00]-Cai-Dat-TB-Toolbox.bat để kích hoạt lại bản quyền.`n" -ForegroundColor DarkGray
            Wait-ForUserExit
            exit 1
        }
    }
}

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}


function Get-CategoryTargetPaths {
    param ([string]$CatKey)

    $paths = @()
    switch ($CatKey) {
        "temp" {
            if ($env:TEMP -and (Test-Path $env:TEMP)) { $paths += $env:TEMP }
            $sysTemp = Join-Path $env:SystemRoot "Temp"
            if (Test-Path $sysTemp) { $paths += $sysTemp }
        }
        "prefetch" {
            $prefetch = Join-Path $env:SystemRoot "Prefetch"
            if (Test-Path $prefetch) { $paths += $prefetch }
        }
        "update_cache" {
            $dl = Join-Path $env:SystemRoot "SoftwareDistribution\Download"
            if (Test-Path $dl) { $paths += $dl }
            $cbs = Join-Path $env:SystemRoot "Logs\CBS"
            if (Test-Path $cbs) { $paths += $cbs }
        }
        "crash_dumps" {
            $crash = Join-Path $env:LOCALAPPDATA "CrashDumps"
            if (Test-Path $crash) { $paths += $crash }
            $mini = Join-Path $env:SystemRoot "Minidump"
            if (Test-Path $mini) { $paths += $mini }
        }
        "delivery_optimization" {
            $doPath = Join-Path $env:SystemRoot "SoftwareDistribution\DeliveryOptimization"
            if (Test-Path $doPath) { $paths += $doPath }
        }
        "thumbnail_cache" {
            $thumb = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"
            if (Test-Path $thumb) { $paths += $thumb }
        }
        "recycle_bin" {
            # Xử lý riêng qua Clear-RecycleBin
        }
        "browser_cache" {
            # Chrome Cache
            $chromeCache = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache"
            if (Test-Path $chromeCache) { $paths += $chromeCache }
            $chromeGpu = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\GPUCache"
            if (Test-Path $chromeGpu) { $paths += $chromeGpu }

            # Edge Cache
            $edgeCache = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache"
            if (Test-Path $edgeCache) { $paths += $edgeCache }
            $edgeGpu = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\GPUCache"
            if (Test-Path $edgeGpu) { $paths += $edgeGpu }
        }
        "dev_nuget_cache" {
            $nuget = Join-Path $env:USERPROFILE ".nuget\packages"
            if (Test-Path $nuget) { $paths += $nuget }
        }
    }
    return $paths
}

function Invoke-SystemCleaning {
    param ([PSCustomObject]$Config)

    $isAdmin = Test-IsAdmin
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $userPrefix = if ($env:USERNAME) { $env:USERNAME } else { "User" }
    $logFile = Join-Path $featureLogDir "${userPrefix}_${timestamp}.log"
    $logBuilder = New-Object System.Text.StringBuilder

    # Ghi nhận Header Log
    $logBuilder.AppendLine("================================================================================") | Out-Null
    $logBuilder.AppendLine(" TB-TOOLBOX - NHẬT KÝ THỰC THI DỌN DẸP HỆ THỐNG") | Out-Null
    $logBuilder.AppendLine(" Bản quyền: Mr. Tuấn Beo (TuanBeoToolbox)") | Out-Null
    $logBuilder.AppendLine(" Thời gian bắt đầu: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')") | Out-Null
    $logBuilder.AppendLine(" Tên máy: $env:COMPUTERNAME | Người dùng: $env:USERNAME") | Out-Null
    $logBuilder.AppendLine(" Quyền Administrator: $(if ($isAdmin) {'CÓ (Đầy đủ)'} else {'KHÔNG (Bị giới hạn)'})") | Out-Null
    $logBuilder.AppendLine("================================================================================") | Out-Null
    $logBuilder.AppendLine("DANH MỤC HẠNG MỤC ĐÃ CHỌN:") | Out-Null

    $selectedCategories = @()
    foreach ($prop in $Config.Categories.PSObject.Properties) {
        if ($prop.Value.Enabled -eq 1) {
            $selectedCategories += $prop
            $logBuilder.AppendLine(" - [$($prop.Name)] $($prop.Value.Name)") | Out-Null
        }
    }
    $logBuilder.AppendLine("--------------------------------------------------------------------------------") | Out-Null
    $logBuilder.AppendLine("CHI TIẾT TIẾN TRÌNH XỬ LÝ:") | Out-Null

    Show-HeaderBanner -SubTitle "TIẾN TRÌNH DỌN DẸP HỆ THỐNG"

    $totalDeletedFiles = 0
    $totalSkippedFiles = 0
    $totalFreedBytes = 0
    $startTime = [System.Diagnostics.Stopwatch]::StartNew()

    # Dịch vụ Windows Update cần quản lý an toàn
    $serviceStopped = $false
    $updateCatSelected = ($selectedCategories | Where-Object { $_.Name -eq "update_cache" })

    try {
        if ($updateCatSelected -and $isAdmin) {
            Write-Host " [!] Đang tạm dừng dịch vụ Windows Update để giải phóng tệp tải..." -ForegroundColor Cyan
            Stop-Service -Name "wuauserv", "bits" -Force -ErrorAction SilentlyContinue
            $serviceStopped = $true
        }

        $catIndex = 0
        $catTotal = $selectedCategories.Count

        foreach ($cat in $selectedCategories) {
            $catIndex++
            Write-Host "`n [$catIndex/$catTotal] Đang xử lý: $($cat.Value.Name)..." -ForegroundColor Green

            # Xử lý đặc thù: Thùng rác
            if ($cat.Name -eq "recycle_bin") {
                try {
                    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                    Write-Host "   [✓] Đã làm rỗng Thùng rác (Recycle Bin) thành công." -ForegroundColor Green
                    $logBuilder.AppendLine(" [XÓA THÀNH CÔNG] Dọn sạch Thùng rác (Recycle Bin)") | Out-Null
                    $totalDeletedFiles++
                } catch {
                    $logBuilder.AppendLine(" [BỎ QUA] Lỗi dọn Thùng rác: $($_.Exception.Message)") | Out-Null
                    $totalSkippedFiles++
                }
                continue
            }

            # Lấy danh sách đường dẫn mục tiêu
            $targetDirs = Get-CategoryTargetPaths -CatKey $cat.Name
            if ($targetDirs.Count -eq 0) {
                Write-Host "   [-] Thư mục không tồn tại hoặc đã trống." -ForegroundColor DarkGray
                continue
            }

            # Thu thập danh sách tệp tin
            $filesToClean = @()
            foreach ($dir in $targetDirs) {
                if (Test-Path $dir) {
                    try {
                        # Lấy tất cả file con
                        $found = Get-ChildItem -Path $dir -Recurse -File -Force -ErrorAction SilentlyContinue
                        # Rào chắn an toàn cho Temp: Giữ lại các file mới tạo hoặc chỉnh sửa trong vòng 24 giờ qua
                        if ($cat.Name -eq "temp" -and $found) {
                            $safeThreshold = (Get-Date).AddHours(-24)
                            $found = $found | Where-Object { $_.LastWriteTime -lt $safeThreshold }
                        }
                        if ($found) { $filesToClean += $found }
                    } catch {}
                }
            }

            $countInCat = $filesToClean.Count
            if ($countInCat -eq 0) {
                Write-Host "   [✓] Hạng mục này hiện tại đã sạch sẽ (0 tệp rác)." -ForegroundColor DarkGray
                continue
            }

            # Xóa với thanh tiến trình siêu mượt & Throttle
            $currentFileIndex = 0
            $lastUpdate = [System.Diagnostics.Stopwatch]::StartNew()

            foreach ($file in $filesToClean) {
                $currentFileIndex++
                $fileSize = $file.Length
                $filePath = $file.FullName

                # Cập nhật UI mượt mà (Throttle 50 tệp hoặc 80ms)
                if ($lastUpdate.ElapsedMilliseconds -ge 80 -or $currentFileIndex -eq $countInCat) {
                    Show-SmoothProgressBar -Current $currentFileIndex -Total $countInCat -FreedBytes $totalFreedBytes -CurrentItem $filePath
                    $lastUpdate.Restart()
                }

                # Try-catch per-file: An toàn tuyệt đối chống crash
                try {
                    # Tháo thuộc tính ReadOnly nếu có
                    if ($file.IsReadOnly) { $file.IsReadOnly = $false }
                    Remove-Item -LiteralPath $filePath -Force -ErrorAction Stop

                    $totalDeletedFiles++
                    $totalFreedBytes += $fileSize
                    $logBuilder.AppendLine(" [XÓA THÀNH CÔNG] [$(Format-FileSize -Bytes $fileSize)] $filePath") | Out-Null
                }
                catch {
                    # File đang bị khóa hoặc không đủ quyền -> Bỏ qua an toàn
                    $totalSkippedFiles++
                    $logBuilder.AppendLine(" [BỎ QUA - ĐANG DÙNG] $filePath") | Out-Null
                }
            }

            # Xóa các thư mục con rỗng
            foreach ($dir in $targetDirs) {
                if (Test-Path $dir) {
                    Get-ChildItem -Path $dir -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                        Sort-Object -Property FullName -Descending |
                        ForEach-Object {
                            try { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue } catch {}
                        }
                }
            }

            Write-Host "" # Xuống dòng sau khi hoàn thành hạng mục
        }
    }
    finally {
        # Đảm bảo 100% dịch vụ Windows Update luôn được kích hoạt lại dù có lỗi hay Ctrl+C
        if ($serviceStopped) {
            Write-Host "`n [!] Đang kích hoạt lại dịch vụ Windows Update..." -ForegroundColor Cyan
            Start-Service -Name "wuauserv", "bits" -ErrorAction SilentlyContinue
        }
        $startTime.Stop()
    }

    # Báo cáo tổng kết
    $elapsed = $startTime.Elapsed
    $elapsedFormatted = "{0:D2}m {1:D2}s" -f $elapsed.Minutes, $elapsed.Seconds
    $freedTotalFormatted = Format-FileSize -Bytes $totalFreedBytes

    $logBuilder.AppendLine("================================================================================") | Out-Null
    $logBuilder.AppendLine("TỔNG KẾT KẾT QUẢ DỌN DẸP:") | Out-Null
    $logBuilder.AppendLine(" - Số tệp đã xóa thành công: $totalDeletedFiles") | Out-Null
    $logBuilder.AppendLine(" - Số tệp bỏ qua (đang dùng): $totalSkippedFiles") | Out-Null
    $logBuilder.AppendLine(" - TỔNG DUNG LƯỢNG GIẢI PHÓNG : $freedTotalFormatted") | Out-Null
    $logBuilder.AppendLine(" - Tổng thời gian thực hiện : $elapsedFormatted") | Out-Null
    $logBuilder.AppendLine("================================================================================") | Out-Null

    # Lưu file Log UTF-8 with BOM
    [System.IO.File]::WriteAllText($logFile, $logBuilder.ToString(), [System.Text.Encoding]::UTF8)

    # Hiển thị màn hình hoàn tất
    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host "   DỌN DẸP HỆ THỐNG HOÀN TẤT THÀNH CÔNG!" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " [✓] Số tệp đã xóa thành công : $totalDeletedFiles tệp" -ForegroundColor Green
    Write-Host " [!] Số tệp bỏ qua (đang dùng) : $totalSkippedFiles tệp" -ForegroundColor DarkGray
    Write-Host " [★] TỔNG DUNG LƯỢNG GIẢI PHÓNG : $freedTotalFormatted" -ForegroundColor Yellow
    Write-Host " [⏱] Thời gian thực hiện       : $elapsedFormatted" -ForegroundColor White
    Write-Host " [📁] Tệp nhật ký chi tiết     : $logFile" -ForegroundColor DarkCyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " LỰA CHỌN TIẾP THEO:" -ForegroundColor White
    Write-Host "  [O] Mở xem file Nhật ký (Log) chi tiết" -ForegroundColor Yellow
    Write-Host "  [B] Quay lại Menu chính để dọn tiếp" -ForegroundColor Cyan
    Write-Host "  [Q / Enter] Thoát chương trình" -ForegroundColor DarkGray
    Write-Host ""

    $choice = (Read-Host " Nhập lựa chọn [O/B/Q]").Trim().ToUpper()
    if ($choice -eq "O") {
        Start-Process "notepad.exe" -ArgumentList "`"$logFile`""
    }
    elseif ($choice -eq "B") {
        return "BACK"
    }

    Write-Host "`n [✓] Đã hoàn tất phiên làm việc. Cảm ơn bạn đã sử dụng TB-Toolbox!" -ForegroundColor Green
    Wait-ForUserExit
    return "QUIT"
}

# ==============================================================================
# VÒNG LẶP MENU ĐIỀU HƯỚNG CHÍNH (MAIN INTERACTIVE LOOP)
# ==============================================================================
function Start-CleanerApp {
    $config = Get-CleanerConfig

    while ($true) {
        Show-HeaderBanner -SubTitle "HỆ THỐNG DỌN DẸP BỘ NHỚ TẠM & TỐI ƯU WINDOWS"

        # Hiển thị quyền Admin
        $isAdmin = Test-IsAdmin
        if ($isAdmin) {
            Write-Host " [Quyền hạn: Administrator (Đầy đủ)]" -ForegroundColor Green
        } else {
            Write-Host " [Cảnh báo: Đang chạy quyền Thường - Một số mục như Prefetch sẽ bị hạn chế]" -ForegroundColor Yellow
        }
        Write-Host ""

        # Hiển thị danh sách các mục
        Write-Host " DANH SÁCH HẠNG MỤC DỌN DẸP:" -ForegroundColor White

        $catList = @()
        $idx = 0
        $targetCol = 67 # Can le phai thang tap sat mep thanh ===== (cot 78)

        foreach ($prop in $config.Categories.PSObject.Properties) {
            $idx++
            $catList += $prop
            $isEnabled = ($prop.Value.Enabled -eq 1)

            # To mau toan bo dong khi duoc chon (Bat: Xanh Green | Tat: Xam DarkGray)
            $numColor   = if ($isEnabled) { "Cyan" } else { "DarkGray" }
            $rowColor   = if ($isEnabled) { "Green" } else { "DarkGray" }
            $statusText = if ($isEnabled) { "[ 1 - BẬT ]" } else { "[ 0 - TẮT ]" }

            $prefix = "  [{0}] " -f $idx
            $name   = $prop.Value.Name
            $padLen = [math]::Max(2, $targetCol - $prefix.Length - $name.Length)
            $pad    = " " * $padLen

            Write-Host $prefix -NoNewline -ForegroundColor $numColor
            Write-Host $name -NoNewline -ForegroundColor $rowColor
            Write-Host $pad -NoNewline
            Write-Host $statusText -ForegroundColor $rowColor
        }

        Write-Host ""
        Write-Host " PHÍM ĐIỀU HƯỚNG:" -ForegroundColor DarkCyan
        Write-Host "  [1..$($catList.Count)] Bật/Tắt từng mục (VD: 1 hoặc 1, 7) │ [A] Chọn TẤT CẢ │ [C] Hủy TẤT CẢ" -ForegroundColor White
        Write-Host "  [S / Enter] Bắt đầu dọn dẹp                       │ [Q] Thoát an toàn" -ForegroundColor Yellow
        Write-Host ""

        $inputVal = (Read-Host " Nhập lựa chọn của bạn").Trim().ToUpper()

        # Xử lý phím chức năng
        if ($inputVal -eq "Q") {
            Write-Host "`n [✓] Đã thoát an toàn. Cảm ơn bạn đã sử dụng TB-Toolbox!" -ForegroundColor Green
            Wait-ForUserExit
            break
        }
        elseif ($inputVal -eq "A") {
            Set-AllCategories -Config $config -Status 1
            continue
        }
        elseif ($inputVal -eq "C") {
            Set-AllCategories -Config $config -Status 0
            continue
        }
        elseif ($inputVal -match "^\d+([,\s]+\d+)*$") {
            $numbers = ($inputVal -split "[,;\s]+") | Where-Object { $_ -match "^\d+$" }
            foreach ($n in $numbers) {
                $selNum = [int]$n
                if ($selNum -ge 1 -and $selNum -le $catList.Count) {
                    $targetProp = $catList[$selNum - 1]
                    $targetProp.Value.Enabled = if ($targetProp.Value.Enabled -eq 1) { 0 } else { 1 }
                }
            }
            Save-CleanerConfig -Config $config
            continue
        }
        elseif ($inputVal -eq "S" -or $inputVal -eq "") {
            # ==================================================================
            # CỔNG XÁC NHẬN KẾT QUẢ TRƯỚC KHI CHẠY (PRE-EXECUTION GATE)
            # ==================================================================
            $selected = @()
            foreach ($prop in $config.Categories.PSObject.Properties) {
                if ($prop.Value.Enabled -eq 1) { $selected += $prop }
            }

            if ($selected.Count -eq 0) {
                Write-Host "`n [!] CẢNH BÁO: Anh chưa chọn bất kỳ hạng mục nào để dọn dẹp!" -ForegroundColor Yellow
                Write-Host " Vui lòng bấm phím số tương ứng hoặc bấm [A] để chọn trước khi Start.`n" -ForegroundColor DarkGray
                Start-Sleep -Seconds 2
                continue
            }

            # Hiển thị bảng tóm tắt xác nhận
            Show-HeaderBanner -SubTitle "XÁC NHẬN DANH SÁCH HẠNG MỤC TRƯỚC KHI THỰC HIỆN"
            Write-Host " CÁC HẠNG MỤC ĐÃ ĐƯỢC CHỌN ĐỂ DỌN DẸP:" -ForegroundColor White
            $sIdx = 0
            foreach ($item in $selected) {
                $sIdx++
                Write-Host ("  {0}. [BẬT] {1}" -f $sIdx, $item.Value.Name) -ForegroundColor Green
                Write-Host ("     Phạm vi: {0}" -f $item.Value.Description) -ForegroundColor DarkGray
            }
            Write-Host ""
            Write-Host (" (Tổng cộng: {0}/{1} hạng mục được chọn)" -f $selected.Count, $catList.Count) -ForegroundColor Cyan
            Write-Host ""
            Write-Host " ⚠️  CẢNH BÁO: Các file rác trong những mục trên sẽ được xóa vĩnh viễn." -ForegroundColor Yellow
            Write-Host " Các file đang được ứng dụng mở sẽ được tự động bỏ qua an toàn." -ForegroundColor DarkGray
            Write-Host ""
            Write-Host " BẠN CÓ CHẮC CHẮN MUỐN TIẾN HÀNH KHÔNG?" -ForegroundColor White
            Write-Host "  [Y / Enter] : ĐỒNG Ý TIẾN HÀNH" -ForegroundColor Green
            Write-Host "  [B]         : QUAY LẠI MÀN HÌNH CHỌN" -ForegroundColor Cyan
            Write-Host "  [Q / N]     : HỦY BỎ VÀ THOÁT" -ForegroundColor DarkGray
            Write-Host ""

            $confirmChoice = (Read-Host " Nhập xác nhận [Y/B/Q]").Trim().ToUpper()

            if ($confirmChoice -eq "B") {
                continue
            }
            elseif ($confirmChoice -eq "Q" -or $confirmChoice -eq "N") {
                Write-Host "`n [!] Đã hủy thao tác an toàn. Không có tệp nào bị thay đổi." -ForegroundColor Yellow
                Wait-ForUserExit
                break
            }
            elseif ($confirmChoice -eq "Y" -or $confirmChoice -eq "") {
                # Tiến hành dọn dẹp
                $result = Invoke-SystemCleaning -Config $config
                if ($result -eq "BACK") {
                    continue
                } else {
                    break
                }
            }
        }
    }
}

# Khởi chạy ứng dụng với bẫy lỗi toàn cục chống tắt cửa sổ đột ngột
try {
    Start-CleanerApp
}
catch {
    Write-Host "`n [LỖI HỆ THỐNG]: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host " Vị trí: Dòng $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkGray
    Wait-ForUserExit
}
