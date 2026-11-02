param ([switch]$RunInteractive, [switch]$AutoConfirm)
# ==============================================================================
# TB-TOOLBOX - SERVER CLOUD ANCHOR & CLIENT UPDATE ENGINE (Server-Sync.ps1)
# Bản quyền thuộc về: Mr. ĐÀO XUÂN TUẤN (Tuấn Beo)
# Hotline: 0987.1987.92 | Email: tuanbeo.technology@gmail.com
# Chức năng: Đồng bộ trạng thái bản quyền, tự động tải chức năng mới được cấp phép,
#            tự động dỡ bỏ triệt để các chức năng không được phép / bị thu hồi.
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$CORE_DIR = $PSScriptRoot
$ENGINE_DIR = Split-Path -Parent $CORE_DIR
$TB_ROOT = Split-Path -Parent $ENGINE_DIR
$CONFIG_DIR = Join-Path $ENGINE_DIR "Config"
$ACTIONS_DIR = Join-Path $TB_ROOT "@Actions"
$TELEMETRY_QUEUE_FILE = Join-Path $CONFIG_DIR ".telemetry-queue"
$LICENSE_KEY_FILE = Join-Path $CONFIG_DIR "license.key"
$LICENSE_DPAPI_FILE = Join-Path $CONFIG_DIR ".license.dpapi"

# Nạp các module thư viện nền tảng
if (Test-Path (Join-Path $CORE_DIR "Common-UI.ps1")) { . (Join-Path $CORE_DIR "Common-UI.ps1") }
if (Test-Path (Join-Path $CORE_DIR "Crypto-RSA.ps1")) { . (Join-Path $CORE_DIR "Crypto-RSA.ps1") }
if (Test-Path (Join-Path $CORE_DIR "License-Engine.ps1")) { . (Join-Path $CORE_DIR "License-Engine.ps1") }
if (Test-Path (Join-Path $CORE_DIR "Client-Bootstrap.ps1")) { . (Join-Path $CORE_DIR "Client-Bootstrap.ps1") }

$script:TB_MASTER_KEY = "Tuanbeo1998@"
$script:MAX_OFFLINE_DAYS = 14

function Test-InternetConnection {
    try {
        $ping = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue
        return $ping
    } catch {
        return $false
    }
}

function Start-ServerSyncInteractive {
    param ([switch]$AutoConfirm)
    Show-HeaderBanner -SubTitle "CẬP NHẬT TB-TOOLBOX & ĐỒNG BỘ CHỨC NĂNG TỪ MÁY CHỦ"

    Write-Host "  * Thư mục TB-Toolbox cục bộ: $TB_ROOT" -ForegroundColor White
    Write-Host "  * Máy chủ phát hành        : GitHub (TuanBeo98RL/TB-Toolbox)" -ForegroundColor White
    Write-Host ""

    if (-not $AutoConfirm) {
        Write-Host "👉 Bạn có muốn kiểm tra và đồng bộ bản quyền & tính năng mới nhất? (Y/N, Nhấn Enter hoặc Y để chạy): " -ForegroundColor Yellow -NoNewline
        $confirm = (Read-Host).Trim()
        if ($confirm -ne "Y" -and $confirm -ne "y" -and $confirm -ne "") {
            Write-Host "`n[!] Đã hủy thao tác cập nhật theo yêu cầu." -ForegroundColor Gray
            Wait-ForUserExit -Message "`nNhấn phím bất kỳ để đóng cửa sổ..."
            return
        }
    }

    Write-Host "`n[*] Đang kiểm tra kết nối mạng Internet..." -ForegroundColor Cyan
    if (-not (Test-InternetConnection)) {
        Write-Host "`n[X] Không có kết nối mạng Internet hoặc mạng nội bộ đã chặn kết nối!" -ForegroundColor Red
        Write-Host "    Vui lòng kiểm tra lại đường truyền mạng của máy tính." -ForegroundColor Yellow
        Wait-ForUserExit -Message "`nNhấn phím bất kỳ để đóng cửa sổ..."
        return
    }
    Write-Host " [OK] Kết nối Internet hoạt động tốt." -ForegroundColor Green

    $currentHWID = Get-MachineHWID
    Write-Host "[*] Mã phần cứng thiết bị (HWID): $currentHWID" -ForegroundColor DarkGray

    # 1. Kết nối Cloud License Registry để kiểm tra trạng thái bản quyền mới nhất
    Write-Host "[*] Đang kết nối Máy chủ Đám mây để đối soát bản quyền..." -ForegroundColor Cyan
    $cloudEntry = $null

    # Ưu tiên 1 (Kênh thời gian thực, 0 giây delay): GitHub REST API trực tiếp
    try {
        $apiResp = Invoke-RestMethod -Uri "https://api.github.com/repos/TuanBeo98RL/TB-Toolbox/contents/licenses.json" -Headers @{"User-Agent"="TB-Toolbox-Client"; "Cache-Control"="no-cache"} -TimeoutSec 6 -ErrorAction Stop
        if ($apiResp -and $apiResp.content) {
            $rawBytes = [Convert]::FromBase64String($apiResp.content)
            $decoded = [System.Text.Encoding]::UTF8.GetString($rawBytes).Trim([char]0xFEFF)
            $registry = $decoded | ConvertFrom-Json
            if ($registry.licenses -and $registry.licenses.PSObject.Properties[$currentHWID]) {
                $cloudEntry = $registry.licenses.$currentHWID
            } elseif ($registry.PSObject.Properties[$currentHWID]) {
                $cloudEntry = $registry.$currentHWID
            }
        }
    } catch {
        # Ưu tiên 2 (Kênh dự phòng nếu API nghẽn / vượt hạn ngạch): CDN raw.githubusercontent.com
        try {
            $serverUrl = "https://raw.githubusercontent.com/TuanBeo98RL/TB-Toolbox/main/licenses.json?t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "TB-Toolbox-Client")
            $wc.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
            $wc.Headers.Add("Pragma", "no-cache")
            $rawJson = $wc.DownloadString($serverUrl).Trim([char]0xFEFF)
            $registry = $rawJson | ConvertFrom-Json

            if ($registry.licenses -and $registry.licenses.PSObject.Properties[$currentHWID]) {
                $cloudEntry = $registry.licenses.$currentHWID
            } elseif ($registry.PSObject.Properties[$currentHWID]) {
                $cloudEntry = $registry.$currentHWID
            }
        } catch {
            Write-Host " [!] Tạm thời không thể tải danh sách bản quyền từ máy chủ: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # 2. Xử lý trường hợp Bị thu hồi từ xa trên Server
    if ($null -ne $cloudEntry -and $cloudEntry.status -eq 0) {
        Write-Host "`n================================================================================" -ForegroundColor Red
        Write-Host "   [!] CẢNH BÁO: BẢN QUYỀN THIẾT BỊ NÀY ĐÃ BỊ THU HỒI BỞI QUẢN TRỊ VIÊN!         " -ForegroundColor Yellow
        Write-Host "================================================================================" -ForegroundColor Red
        Write-Host " Hệ thống sẽ dỡ bỏ toàn bộ các công cụ đã được cấp phép trên máy..." -ForegroundColor Yellow
        
        # Xóa key và dỡ bỏ toàn bộ chức năng
        if (Test-Path $LICENSE_KEY_FILE) { Remove-Item $LICENSE_KEY_FILE -Force -ErrorAction SilentlyContinue }
        if (Test-Path $LICENSE_DPAPI_FILE) { Remove-Item $LICENSE_DPAPI_FILE -Force -ErrorAction SilentlyContinue }
        Sync-ClientLaunchers -AuthorizedFeatures @()
        
        Write-Host "`n [OK] Đã hoàn tất việc thu hồi và dọn dẹp sạch thiết bị." -ForegroundColor Red
        Write-Host " Liên hệ Tác giả: Mr. ĐÀO XUÂN TUẤN (0987.1987.92) để biết thêm chi tiết." -ForegroundColor DarkGray
        Wait-ForUserExit -Message "`nNhấn phím bất kỳ để đóng cửa sổ..."
        return
    }

    # 3. Xử lý trường hợp có Key mới trên Server
    $localKeyString = ""
    if (Test-Path $LICENSE_KEY_FILE) {
        $localKeyString = [System.IO.File]::ReadAllText($LICENSE_KEY_FILE, [System.Text.Encoding]::UTF8).Trim()
    }

    $cloudKeyString = ""
    if ($null -ne $cloudEntry) {
        if ($cloudEntry -is [string]) { $cloudKeyString = $cloudEntry }
        elseif ($cloudEntry.key) { $cloudKeyString = $cloudEntry.key }
    }

    if (-not [string]::IsNullOrWhiteSpace($cloudKeyString) -and $cloudKeyString -ne $localKeyString) {
        Write-Host " [OK] Phát hiện bản quyền mới được cập nhật trên máy chủ! Đang áp dụng..." -ForegroundColor Green
        $verifyCloud = Verify-LicenseKey -LicenseKeyString $cloudKeyString -CurrentHWID $currentHWID
        if ($verifyCloud.IsValid) {
            Save-LicenseTripleAnchor -KeyString $cloudKeyString -Payload $verifyCloud.Payload -CurrentHWID $currentHWID
            $localKeyString = $cloudKeyString
            Write-Host "      -> Người sở hữu: $($verifyCloud.Payload.fullName)" -ForegroundColor Cyan
            Write-Host "      -> Hạn sử dụng : $($verifyCloud.Payload.expiresAt)" -ForegroundColor Yellow
        }
    }

    # 4. Xác thực Key hiện tại của máy
    if ([string]::IsNullOrWhiteSpace($localKeyString)) {
        Write-Host "`n[!] Thiết bị này chưa được cài đặt bản quyền TB-Toolbox." -ForegroundColor Yellow
        Write-Host "    Vui lòng chạy '[001]-Dang-Ky-Va-Kich-Hoat-Ban-Quyen.bat' để kích hoạt." -ForegroundColor Cyan
        Wait-ForUserExit -Message "`nNhấn phím bất kỳ để đóng cửa sổ..."
        return
    }

    $verify = Verify-LicenseKey -LicenseKeyString $localKeyString -CurrentHWID $currentHWID
    if (-not $verify.IsValid) {
        Write-Host "`n[X] BẢN QUYỀN KHÔNG HỢP LỆ HOẶC ĐÃ HẾT HẠN: $($verify.Error)" -ForegroundColor Red
        Write-Host "    Hệ thống sẽ dỡ bỏ các chức năng không được phép..." -ForegroundColor Yellow
        Sync-ClientLaunchers -AuthorizedFeatures @()
        Wait-ForUserExit -Message "`nNhấn phím bất kỳ để đóng cửa sổ..."
        return
    }

    Write-Host " [OK] Bản quyền thiết bị hợp lệ: $($verify.Payload.fullName) (Gói: $($verify.Payload.groupId))" -ForegroundColor Green

    # 5. Đồng bộ các chức năng được phép dùng & dỡ bỏ chức năng vi phạm
    Write-Host "[*] Đang đối soát và đồng bộ các chức năng theo gói bản quyền..." -ForegroundColor Cyan
    Sync-ClientLaunchers -AuthorizedFeatures $verify.Payload.features

    # Chốt chặn an toàn (Failsafe): Quét dọn triệt để bằng -LiteralPath
    $feats = $verify.Payload.features
    $cleanerAllowed = ($feats.F01_CLEANER -eq 1 -or $feats.FN0001 -eq 1)
    if (-not $cleanerAllowed) {
        Get-ChildItem -LiteralPath $ACTIONS_DIR -Filter "*500*.bat" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    $powerAllowed = ($feats.F02_SHUTDOWN_TIMER -eq 1 -or $feats.FN0002 -eq 1)
    if (-not $powerAllowed) {
        Get-ChildItem -LiteralPath $ACTIONS_DIR -Filter "*501*.bat" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    # 5.1. Tự động đồng bộ các tệp giao diện & kịch bản lõi mới nhất từ Server
    try {
        $wcSync = New-Object System.Net.WebClient
        $wcSync.Headers.Add("User-Agent", "TB-Toolbox-Client")
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $baseSyncUrl = "https://raw.githubusercontent.com/TuanBeo98RL/TB-Toolbox/main/Engine/Core"
        foreach ($cf in @("Dashboard-Launcher.ps1", "Client-Bootstrap.ps1", "Server-Sync.ps1", "Crypto-RSA.ps1", "License-Engine.ps1")) {
            $txt = $wcSync.DownloadString("$baseSyncUrl/$cf?t=$ts")
            if (-not [string]::IsNullOrWhiteSpace($txt) -and ($txt.Contains("Bản quyền") -or $txt.Contains("Ban quyen"))) {
                [System.IO.File]::WriteAllText((Join-Path $CORE_DIR $cf), $txt, (New-Object System.Text.UTF8Encoding($true)))
            }
        }
    } catch { }

    # 6. Kiểm tra phiên bản mới của TB-Toolbox trên GitHub Releases
    Write-Host "[*] Đang kiểm tra phiên bản phát hành mới của TB-Toolbox..." -ForegroundColor Cyan
    try {
        $relUrl = "https://api.github.com/repos/TuanBeo98RL/TB-Toolbox/releases/latest"
        $rel = Invoke-RestMethod -Uri $relUrl -Headers @{"User-Agent"="TB-Toolbox-Client"} -TimeoutSec 5 -ErrorAction Stop
        if ($rel -and $rel.tag_name) {
            Write-Host " [✓] Phiên bản mới nhất trên máy chủ: $($rel.tag_name)" -ForegroundColor DarkGray
        }
    } catch {
        # Bỏ qua nếu rate-limit hoặc timeout
    }

    Write-Host "`n================================================================================" -ForegroundColor Green
    Write-Host "   🎉 ĐÃ ĐỒNG BỘ VÀ CẬP NHẬT TB-TOOLBOX THÀNH CÔNG RỰC RỠ!                      " -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host " Các công cụ được cấp phép của bạn đã sẵn sàng sử dụng trong thư mục @Actions." -ForegroundColor Cyan
    Write-Host ""
    Wait-ForUserExit -Message "Nhấn phím bất kỳ để đóng cửa sổ..."
}

if ($RunInteractive) {
    Start-ServerSyncInteractive -AutoConfirm:$AutoConfirm
}
