<#
================================================================================
 TB-TOOLBOX - DYNAMIC DASHBOARD ENGINE (Dashboard-Launcher.ps1)
 Bản quyền: Mr. Tuấn Beo (TuanBeoToolbox)
 Mô tả: Bảng điều khiển trung tâm quét động 100% thư mục @Actions/,
        giao diện tiếng Việt UTF-8 sang trọng, tự thích ứng phân quyền.
================================================================================
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$Host.UI.RawUI.WindowTitle = "TB-TOOLBOX - BẢNG ĐIỀU KHIỂN TRUNG TÂM | Mr. ĐÀO XUÂN TUẤN (Tuấn Beo)"

$CoreDir = $PSScriptRoot
$EngineDir = Split-Path -Parent $CoreDir
$TbRoot = Split-Path -Parent $EngineDir
$ConfigDir = Join-Path $EngineDir "Config"
$ActionsDir = Join-Path $TbRoot "@Actions"

# Tải thư viện UI và License dùng chung nếu có
if (Test-Path (Join-Path $CoreDir "Common-UI.ps1")) {
    . (Join-Path $CoreDir "Common-UI.ps1")
}
if (Test-Path (Join-Path $CoreDir "License-Engine.ps1")) {
    . (Join-Path $CoreDir "License-Engine.ps1")
}

function Create-AppShortcut([string]$TargetDir, [string]$ShortcutName = "TB-Toolbox.lnk") {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $scPath = Join-Path $TargetDir $ShortcutName
        $shortcut = $wsh.CreateShortcut($scPath)
        $shortcut.TargetPath = Join-Path $TbRoot "TB-Toolbox.bat"
        $shortcut.WorkingDirectory = $TbRoot
        $shortcut.Description = "TB-Toolbox - Bộ Công Cụ Tiện Ích Hệ Thống | Bản quyền: Mr. ĐÀO XUÂN TUẤN (Tuấn Beo)"
        # Gán icon Toolbox từ shell32.dll (index 27) hoặc imageres.dll (index 109)
        $iconFile = "$env:SystemRoot\System32\shell32.dll"
        if (Test-Path $iconFile) {
            $shortcut.IconLocation = "$iconFile, 27"
        }
        $shortcut.Save()
        return $scPath
    } catch {
        return $null
    }
}

function Get-ActionIcon([string]$code, [string]$name) {
    if ($code -eq "500") { return "🧹" }
    if ($code -eq "501") { return "⏰" }
    if ($code -eq "000") { return "🛡️" }
    if ($code -eq "001") { return "🚀" }
    if ($code -eq "002") { return "🔑" }
    if ($code -eq "100") { return "🩺" }
    if ($code -eq "200") { return "🔄" }
    if ($name -like "*Cleaner*") { return "🧹" }
    if ($name -like "*Shutdown*" -or $name -like "*Tat-May*") { return "⏰" }
    if ($name -like "*Key*" -or $name -like "*Kich-Hoat*") { return "🔑" }
    if ($name -like "*Admin*") { return "👑" }
    return "⚡"
}

function Clean-ActionTitle([string]$rawName) {
    # Bỏ phần đuôi .bat và tiền tố [xxx]-
    $t = $rawName -replace '\.bat$', ''
    $t = $t -replace '^\[\d+\]-', ''
    $t = $t -replace '^\[[A-Z0-9_-]+\]-', ''
    $t = $t -replace '-', ' '
    return $t.Trim()
}

function Check-CloudUpdateQuick {
    param(
        [string]$CurrentHWID,
        [string]$LicenseKeyFile,
        [int]$TimeoutMs = 1500
    )
    $res = [PSCustomObject]@{
        HasUpdate = $false
        UpdateType = ""
        Message = ""
        CloudKey = ""
        LocalKey = ""
    }
    
    try {
        $localKey = ""
        if (Test-Path -LiteralPath $LicenseKeyFile) {
            $localKey = [System.IO.File]::ReadAllText($LicenseKeyFile, [System.Text.Encoding]::UTF8).Trim()
        }
        $res.LocalKey = $localKey

        $cloudEntry = $null

        # Kênh 1: GitHub REST API trực tiếp (0s cache delay)
        try {
            $apiResp = Invoke-RestMethod -Uri "https://api.github.com/repos/TuanBeo98RL/TB-Toolbox/contents/licenses.json" -Headers @{"User-Agent"="TB-Toolbox-Client"; "Cache-Control"="no-cache"} -TimeoutSec 3 -ErrorAction Stop
            if ($apiResp -and $apiResp.content) {
                $rawBytes = [Convert]::FromBase64String($apiResp.content)
                $decoded = [System.Text.Encoding]::UTF8.GetString($rawBytes).Trim([char]0xFEFF)
                $cloudRegistry = $decoded | ConvertFrom-Json
                if ($cloudRegistry.licenses -and $cloudRegistry.licenses.PSObject.Properties[$CurrentHWID]) {
                    $cloudEntry = $cloudRegistry.licenses.$CurrentHWID
                } elseif ($cloudRegistry.PSObject.Properties[$CurrentHWID]) {
                    $cloudEntry = $cloudRegistry.$CurrentHWID
                }
            }
        } catch {
            # Kênh 2: CDN raw.githubusercontent.com dự phòng
            try {
                $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                $url = "https://raw.githubusercontent.com/TuanBeo98RL/TB-Toolbox/main/licenses.json?t=$ts"
                
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "TB-Toolbox-Client")
                $wc.Headers.Add("Cache-Control", "no-cache")
                $rawText = $wc.DownloadString($url).Trim([char]0xFEFF)
                $cloudRegistry = $rawText | ConvertFrom-Json
                if ($cloudRegistry.licenses -and $cloudRegistry.licenses.PSObject.Properties[$CurrentHWID]) {
                    $cloudEntry = $cloudRegistry.licenses.$CurrentHWID
                } elseif ($cloudRegistry.PSObject.Properties[$CurrentHWID]) {
                    $cloudEntry = $cloudRegistry.$CurrentHWID
                }
            } catch { }
        }

        if ($null -ne $cloudEntry) {
            $cloudKey = ""
            if ($cloudEntry -is [string]) { $cloudKey = $cloudEntry }
            elseif ($cloudEntry.key) { $cloudKey = $cloudEntry.key }
            
            $res.CloudKey = $cloudKey

            # Trường hợp 1: Bị thu hồi
            if ($cloudEntry.status -eq 0 -and -not [string]::IsNullOrWhiteSpace($localKey)) {
                $res.HasUpdate = $true
                $res.UpdateType = "REVOKED"
                $res.Message = "Bản quyền thiết bị đã được thu hồi trên máy chủ!"
                return $res
            }

            # Trường hợp 2: Có Key mới / Phân quyền mới
            if (-not [string]::IsNullOrWhiteSpace($cloudKey) -and $cloudKey -ne $localKey) {
                $res.HasUpdate = $true
                $res.UpdateType = "LICENSE"
                $res.Message = "Phát hiện bản quyền / phân quyền tính năng mới đã được Admin cập nhật trên máy chủ!"
                return $res
            }
        }
    } catch {
        # Không có mạng, timeout hoặc lỗi kết nối -> Bỏ qua êm đẹp
    }

    return $res
}

# ==============================================================================
# KIỂM TRA CẬP NHẬT TỪ MÁY CHỦ KHI KHỞI ĐỘNG (STARTUP UPDATE CHECK)
# ==============================================================================
$script:HasPendingUpdate = $false
$localKeyFile = Join-Path $ConfigDir "license.key"

if (Get-Command Get-MachineHWID -ErrorAction SilentlyContinue) {
    Write-Host " [*] Đang kiểm tra cập nhật từ Máy chủ..." -ForegroundColor DarkGray
    $currentHWID = Get-MachineHWID
    $updateInfo = Check-CloudUpdateQuick -CurrentHWID $currentHWID -LicenseKeyFile $localKeyFile -TimeoutMs 1500

    if ($updateInfo.HasUpdate) {
        $script:HasPendingUpdate = $true
        Clear-Host
        Write-Host "================================================================================" -ForegroundColor Yellow
        Write-Host " [!] PHÁT HIỆN BẢN QUYỀN / TÍNH NĂNG MỚI ĐÃ ĐƯỢC ADMIN CẬP NHẬT TRÊN MÁY CHỦ!" -ForegroundColor Yellow
        Write-Host "     $($updateInfo.Message)" -ForegroundColor White
        Write-Host "================================================================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host " 👉 Bạn có muốn đồng bộ ngay bây giờ không? (Y/N, Nhấn ENTER để Đồng bộ ngay): " -ForegroundColor Cyan -NoNewline
        $quickSync = (Read-Host).Trim()
        if ($quickSync -eq "" -or $quickSync -eq "Y" -or $quickSync -eq "y") {
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "TB-Toolbox-Client")
                $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                $rawBase = "https://raw.githubusercontent.com/TuanBeo98RL/TB-Toolbox/main/Engine/Core"
                foreach ($cf in @("Server-Sync.ps1", "Client-Bootstrap.ps1", "License-Engine.ps1", "Crypto-RSA.ps1", "Dashboard-Launcher.ps1")) {
                    $code = $wc.DownloadString("$rawBase/$cf?t=$ts")
                    if (-not [string]::IsNullOrWhiteSpace($code) -and $code.Contains("Bản quyền thuộc về")) {
                        [System.IO.File]::WriteAllText((Join-Path $CoreDir $cf), $code, (New-Object System.Text.UTF8Encoding($true)))
                    }
                }
            } catch {}
            Write-Host "`n[*] Đang khởi chạy quy trình đồng bộ cập nhật..." -ForegroundColor Green
            Start-Sleep -Milliseconds 400
            & "$CoreDir\Server-Sync.ps1" -RunInteractive -AutoConfirm
            $script:HasPendingUpdate = $false
        } else {
            Write-Host "`n[*] Đã tạm hoãn cập nhật. Bạn có thể chọn mục [Cập Nhật Toolbox Từ Server] trong Menu bất kỳ lúc nào." -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 800
        }
    }
}

# VÒNG LẶP ĐIỀU KHIỂN CHÍNH
while ($true) {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "                TB-TOOLBOX - TRUNG TÂM ĐIỀU HÀNH TIỆN ÍCH                      " -ForegroundColor Yellow
    Write-Host "             Bản quyền thuộc về: Mr. ĐÀO XUÂN TUẤN (Tuấn Beo)                   " -ForegroundColor Green
    Write-Host "        Hotline: 0987.1987.92 | Email: tuanbeo.technology@gmail.com             " -ForegroundColor DarkGray
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""

    # Bảng thông báo có cập nhật mới nếu người dùng hoãn cập nhật
    if ($script:HasPendingUpdate) {
        Write-Host "  ╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "  ║  ⚡ THÔNG BÁO: ĐÃ CÓ BẢN CẬP NHẬT / TÍNH NĂNG MỚI TỪ ADMIN TRÊN MÁY CHỦ!      ║" -ForegroundColor Yellow
        Write-Host "  ║  👉 Vui lòng chọn mục [Cập Nhật Toolbox Từ Server] để đồng bộ ngay lập tức!   ║" -ForegroundColor Cyan
        Write-Host "  ╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
    }

    # Quét động toàn bộ file .bat trong @Actions/
    $batFiles = @()
    if (Test-Path -LiteralPath $ActionsDir) {
        $batFiles = Get-ChildItem -LiteralPath $ActionsDir -Filter "*.bat" | Sort-Object Name
    }

    if ($batFiles.Count -eq 0) {
        Write-Host "  [!] Không tìm thấy công cụ nào trong thư mục @Actions/." -ForegroundColor Yellow
        Write-Host "  Vui lòng kiểm tra lại cấu hình hệ thống." -ForegroundColor DarkGray
    } else {
        # Phân loại thành 2 nhóm: Tiện ích hàng ngày [5xx] và Cấu hình hệ thống [0xx, 1xx, 2xx]
        $utilities = @()
        $systemTools = @()

        foreach ($bf in $batFiles) {
            $code = ""
            if ($bf.Name -match '^\[([0-9A-Za-z_-]+)\]') {
                $code = $matches[1]
            }
            $item = [PSCustomObject]@{
                Code = $code
                FileName = $bf.Name
                FullPath = $bf.FullName
                Title = (Clean-ActionTitle $bf.Name)
                Icon = (Get-ActionIcon $code $bf.Name)
            }
            if ($code -like "5*") {
                $utilities += $item
            } else {
                $systemTools += $item
            }
        }

        $menuMap = @{}

        # Phân vùng 1 (Dải 1 - 999): CÔNG CỤ TIỆN ÍCH HÀNG NGÀY
        if ($utilities.Count -gt 0) {
            Write-Host "  🛠️  CÔNG CỤ TIỆN ÍCH HÀNG NGÀY:" -ForegroundColor Green
            $utilIdx = 1
            foreach ($u in $utilities) {
                $key = "$utilIdx"
                $menuMap[$key] = $u
                $menuMap[$u.Code] = $u
                Write-Host ("   [{0}] {1} {2}" -f $key, $u.Icon, $u.Title) -NoNewline -ForegroundColor White
                Write-Host (" (Mã: [{0}])" -f $u.Code) -ForegroundColor DarkGray
                $utilIdx++
            }
            Write-Host ""
        }

        # Phân vùng 2 (Dải 1000+): CẤU HÌNH HỆ THỐNG & BẢN QUYỀN (Cố định không bao giờ bị xô lệch)
        if ($systemTools.Count -gt 0) {
            Write-Host "  ⚙️  CẤU HÌNH HỆ THỐNG & BẢN QUYỀN:" -ForegroundColor Cyan
            $sysIdx = 1000
            foreach ($s in $systemTools) {
                $key = "$sysIdx"
                $menuMap[$key] = $s
                $menuMap[$s.Code] = $s
                Write-Host ("   [{0}] {1} {2}" -f $key, $s.Icon, $s.Title) -NoNewline -ForegroundColor White
                Write-Host (" (Mã: [{0}])" -f $s.Code) -NoNewline -ForegroundColor DarkGray
                if ($script:HasPendingUpdate -and $s.Code -eq "200") {
                    Write-Host "  [⚡ CÓ BẢN MỚI]" -ForegroundColor Yellow
                } else {
                    Write-Host ""
                }
                $sysIdx++
            }
            Write-Host ""
        }

        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  [S] 📌 Tạo phím tắt TB-Toolbox ra màn hình Desktop (Có Icon chuẩn)" -ForegroundColor Yellow
        Write-Host "  [H] 📖 Xem hướng dẫn sử dụng chi tiết" -ForegroundColor Magenta
        Write-Host "  [0] 🚪 Thoát chương trình" -ForegroundColor DarkGray
        Write-Host "================================================================================" -ForegroundColor Cyan

        $choice = (Read-Host "👉 Mời bạn chọn chức năng (Gõ số thứ tự hoặc mã lệnh)").Trim()

        if ($choice -eq "0" -or $choice -eq "Q" -or $choice -eq "q" -or $choice -eq "exit") {
            Write-Host "`nCảm ơn bạn đã sử dụng TB-Toolbox. Tạm biệt!`n" -ForegroundColor Green
            Start-Sleep -Milliseconds 800
            break
        }

        if ($choice -eq "S" -or $choice -eq "s") {
            Write-Host "`nĐang tạo phím tắt có Icon ra màn hình Desktop..." -ForegroundColor Cyan
            $desktopDir = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
            $sc1 = Create-AppShortcut -TargetDir $desktopDir -ShortcutName "TB-Toolbox.lnk"
            $sc2 = Create-AppShortcut -TargetDir $TbRoot -ShortcutName "TB-Toolbox.lnk"
            if ($sc1) {
                Write-Host " [OK] Đã tạo thành công biểu tượng TB-Toolbox trên Màn hình Desktop!" -ForegroundColor Green
            }
            if ($sc2) {
                Write-Host " [OK] Đã tạo thành công biểu tượng 'TB-Toolbox' tại thư mục gốc!" -ForegroundColor Green
            }
            Write-Host "Bạn có thể bấm đúp vào biểu tượng đó bất cứ lúc nào để mở nhanh.`n" -ForegroundColor Yellow
            pause
            continue
        }

        if ($choice -eq "H" -or $choice -eq "h") {
            $docFile = Join-Path $TbRoot "!00-HUONG-DAN-SU-DUNG-CHO-NGUOI-DUNG.md"
            if (Test-Path $docFile) {
                Write-Host "`nĐang mở tài liệu hướng dẫn sử dụng..." -ForegroundColor Cyan
                Start-Process notepad.exe $docFile
            } else {
                Write-Host "`nKhông tìm thấy tệp hướng dẫn." -ForegroundColor Yellow
            }
            continue
        }

        if ($menuMap.ContainsKey($choice)) {
            $target = $menuMap[$choice]
            Write-Host "`nĐang khởi chạy: " -NoNewline -ForegroundColor Cyan
            Write-Host "$($target.Icon) $($target.Title) ..." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 500

            # Nếu là tác vụ cập nhật [200]/[1003], tự động kéo mã nguồn đồng bộ mới nhất từ Server trước
            if ($target.Code -eq "200" -or $choice -eq "1003") {
                try {
                    foreach ($cf in @("Server-Sync.ps1", "Client-Bootstrap.ps1", "License-Engine.ps1", "Crypto-RSA.ps1", "Dashboard-Launcher.ps1")) {
                        if (Get-Command Download-ModuleFromCloud -ErrorAction SilentlyContinue) {
                            Download-ModuleFromCloud -RelativeUrl "Engine/Core/$cf" -DestinationPath (Join-Path $CoreDir $cf) | Out-Null
                        }
                    }
                } catch {}
            }

            # Cơ chế Tự Chữa Lành (Self-Healing Guard): Kiểm tra và tự kéo script Core nếu bị thiếu
            if ($target.Code -eq "500") {
                $cleanerPs1 = Join-Path $CoreDir "Engine-Cleaner.ps1"
                if (-not (Test-Path -LiteralPath $cleanerPs1)) {
                    Write-Host " [*] Phát hiện thiếu tệp Engine-Cleaner.ps1! Đang tự động tải về từ máy chủ..." -ForegroundColor Cyan
                    if (Get-Command Download-ModuleFromCloud -ErrorAction SilentlyContinue) {
                        Download-ModuleFromCloud -RelativeUrl "Engine/Core/Engine-Cleaner.ps1" -DestinationPath $cleanerPs1 | Out-Null
                    }
                }
            } elseif ($target.Code -eq "501") {
                $powerPs1 = Join-Path $CoreDir "Engine-PowerManager.ps1"
                if (-not (Test-Path -LiteralPath $powerPs1)) {
                    Write-Host " [*] Phát hiện thiếu tệp Engine-PowerManager.ps1! Đang tự động tải về từ máy chủ..." -ForegroundColor Cyan
                    if (Get-Command Download-ModuleFromCloud -ErrorAction SilentlyContinue) {
                        Download-ModuleFromCloud -RelativeUrl "Engine/Core/Engine-PowerManager.ps1" -DestinationPath $powerPs1 | Out-Null
                    }
                }
            }

            # Kích hoạt tệp .bat
            Push-Location (Split-Path -Parent $target.FullPath)
            try {
                cmd.exe /c call "`"$($target.FullPath)`""
            } finally {
                Pop-Location
            }
            if ($target.Code -eq "200") {
                $script:HasPendingUpdate = $false
            }
            Write-Host "`nĐã hoàn tất tác vụ. Nhấn phím bất kỳ để quay lại Bảng điều khiển..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
            continue
        }

        Write-Host "`n[!] Lựa chọn '$choice' không hợp lệ. Vui lòng chọn lại!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}