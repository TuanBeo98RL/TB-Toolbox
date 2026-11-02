# ==============================================================================
# TB-TOOLBOX - CLIENT BOOTSTRAP & ACTIVATION ENGINE (Client-Bootstrap.ps1)
# Bản quyền thuộc về: Mr. Tuấn Beo (TuanBeoToolbox)
# Hotline: 0987.1987.92 | Email: tuanbeo.technology@gmail.com
# Chức năng: Bộ cài đặt và kích hoạt phía Client:
#            1. Tự động kiểm tra bản quyền và tải đúng chức năng được cấp phép.
#            2. Tự động thu hồi và xóa sạch file chức năng nếu không có quyền.
#            3. Hỗ trợ kích hoạt trực tiếp, qua file key.txt hoặc tải tự động từ GitHub TuanBeo98RL.
# ==============================================================================

param (
    [switch]$StatusOnly,
    [switch]$Interactive
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$ENGINE_DIR = Split-Path -Parent $PSScriptRoot
$TB_ROOT = Split-Path -Parent $ENGINE_DIR
$CORE_DIR = $PSScriptRoot
$CONFIG_DIR = Join-Path $ENGINE_DIR "Config"
$BAT_DIR = Join-Path $TB_ROOT "@Actions"
$LICENSE_KEY_FILE = Join-Path $CONFIG_DIR "license.key"

# Dot-source các thư viện cần thiết
. (Join-Path $CORE_DIR "Common-UI.ps1")
. (Join-Path $CORE_DIR "Feature-Registry.ps1")
. (Join-Path $CORE_DIR "License-Engine.ps1")

# ==============================================================================
# 1. HÀM TẢI MODULE AN TOÀN TỪ GITHUB RELEASE (ATOMIC CLOUD HYDRATION)
# ==============================================================================

function Download-ModuleFromCloud {
    param (
        [string]$RelativeUrl,
        [string]$DestinationPath
    )
    $baseUrl = "https://raw.githubusercontent.com/TuanBeo98RL/TB-Toolbox/main"
    $fullUrl = "$baseUrl/$RelativeUrl?t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "TB-Toolbox-Client")
        $dir = Split-Path -Parent $DestinationPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        
        $tempPath = "$DestinationPath.tmp"
        $wc.DownloadFile($fullUrl, $tempPath)
        
        if ((Test-Path $tempPath) -and (Get-Item $tempPath).Length -gt 0) {
            Move-Item $tempPath $DestinationPath -Force
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

# ==============================================================================
# 2. CẤP PHÁT & DỌN DẸP MODULE CHUẨN XÁC THEO MÃ (FEATURE GATED HYDRATION)
# ==============================================================================

function Sync-ClientLaunchers {
    param ([object]$AuthorizedFeatures)

    if (-not (Test-Path $BAT_DIR)) { New-Item -ItemType Directory -Path $BAT_DIR -Force | Out-Null }
    $featuresDict = @{}

    if ($AuthorizedFeatures -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $AuthorizedFeatures.PSObject.Properties) {
            $featuresDict[$p.Name] = [int]$p.Value
        }
    } elseif ($AuthorizedFeatures -is [System.Collections.IDictionary]) {
        $featuresDict = $AuthorizedFeatures
    }

    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)

    # --------------------------------------------------------------------------
    # MODULE 1: F01_CLEANER (Dọn dẹp bộ nhớ tạm hệ thống)
    # --------------------------------------------------------------------------
    $cleanerBat = Join-Path $BAT_DIR "[500]-Don-Dep-Bo-Nho-Tam-He-Thong.bat"
    $cleanerPs1 = Join-Path $CORE_DIR "Engine-Cleaner.ps1"
    $cleanerTmpl = Join-Path $ENGINE_DIR "Templates\Engine-Cleaner.ps1"

    if ($featuresDict["F01_CLEANER"] -eq 1 -or $featuresDict["FN0001"] -eq 1) {
        # ĐƯỢC PHÉP DÙNG: Kiểm tra và khôi phục module nếu chưa có
        if (-not (Test-Path -LiteralPath $cleanerPs1)) {
            if (Test-Path -LiteralPath $cleanerTmpl) {
                Copy-Item -LiteralPath $cleanerTmpl -Destination $cleanerPs1 -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host " [*] Đang tải chức năng [F01_CLEANER] từ máy chủ..." -ForegroundColor Cyan
                $dl = Download-ModuleFromCloud -RelativeUrl "Engine/Core/Engine-Cleaner.ps1" -DestinationPath $cleanerPs1
                if ($dl) { Write-Host "     -> [OK] Đã tải thành công Engine-Cleaner.ps1" -ForegroundColor Green }
            }
        }
        if (-not (Test-Path -LiteralPath $cleanerBat)) {
            $cleanerContent = "@echo off`r`n:: ==============================================================================`r`n:: Bản quyền thuộc về: Mr. ĐÀO XUÂN TUẤN (Tuấn Beo)`r`n:: Hotline: 0987.1987.92 | Email: tuanbeo.technology@gmail.com`r`n:: ==============================================================================`r`nsetlocal`r`ncd /d `"%~dp0`"`r`ntitle [500] Don Dep Bo Nho Tam He Thong - TB-Toolbox`r`nchcp 65001 >nul 2>&1`r`n`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`..\\Engine\\Core\\Engine-Cleaner.ps1`"`r`nexit /b`r`n"
            [System.IO.File]::WriteAllText($cleanerBat, $cleanerContent, $utf8WithBom)
        }
    } else {
        # KHÔNG ĐƯỢC PHÉP DÙNG / BỊ THU HỒI: XÓA SẠCH BẰNG -LiteralPath
        $hadFile = $false
        if (Test-Path -LiteralPath $cleanerBat) {
            Remove-Item -LiteralPath $cleanerBat -Force -ErrorAction SilentlyContinue
            $hadFile = $true
        }
        Get-ChildItem -LiteralPath $BAT_DIR -Filter "*500*.bat" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            $hadFile = $true
        }
        if (Test-Path -LiteralPath $cleanerPs1) {
            $tmplDir = Join-Path $ENGINE_DIR "Templates"
            if (-not (Test-Path $tmplDir)) { New-Item -ItemType Directory -Path $tmplDir -Force | Out-Null }
            Copy-Item -LiteralPath $cleanerPs1 -Destination $cleanerTmpl -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $cleanerPs1 -Force -ErrorAction SilentlyContinue
            $hadFile = $true
        }
        if ($hadFile) {
            Write-Host " [!] THU HỒI / CHƯA CẤP PHÉP: Chức năng [F01_CLEANER - Dọn dẹp bộ nhớ tạm] đã được dỡ bỏ khỏi thiết bị!" -ForegroundColor Yellow
        }
    }

    # --------------------------------------------------------------------------
    # MODULE 2: F02_SHUTDOWN_TIMER (Hẹn giờ tắt máy & Quản lý nguồn điện)
    # --------------------------------------------------------------------------
    $powerBat = Join-Path $BAT_DIR "[501]-Hen-Gio-Tat-May-Va-Quan-Ly-Nguon.bat"
    $powerPs1 = Join-Path $CORE_DIR "Engine-PowerManager.ps1"
    $powerTmpl = Join-Path $ENGINE_DIR "Templates\Engine-PowerManager.ps1"

    if ($featuresDict["F02_SHUTDOWN_TIMER"] -eq 1 -or $featuresDict["FN0002"] -eq 1) {
        # ĐƯỢC PHÉP DÙNG: Kiểm tra và khôi phục module nếu chưa có
        if (-not (Test-Path -LiteralPath $powerPs1)) {
            if (Test-Path -LiteralPath $powerTmpl) {
                Copy-Item -LiteralPath $powerTmpl -Destination $powerPs1 -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host " [*] Đang tải chức năng [F02_SHUTDOWN_TIMER] từ máy chủ..." -ForegroundColor Cyan
                $dl = Download-ModuleFromCloud -RelativeUrl "Engine/Core/Engine-PowerManager.ps1" -DestinationPath $powerPs1
                if ($dl) { Write-Host "     -> [OK] Đã tải thành công Engine-PowerManager.ps1" -ForegroundColor Green }
            }
        }
        if (-not (Test-Path -LiteralPath $powerBat)) {
            $powerContent = "@echo off`r`n:: ==============================================================================`r`n:: Bản quyền thuộc về: Mr. ĐÀO XUÂN TUẤN (Tuấn Beo)`r`n:: Hotline: 0987.1987.92 | Email: tuanbeo.technology@gmail.com`r`n:: ==============================================================================`r`nsetlocal`r`ncd /d `"%~dp0`"`r`ntitle [501] Hen Gio Tat May Va Quan Ly Nguon - TB-Toolbox`r`nchcp 65001 >nul 2>&1`r`n`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"`..\\Engine\\Core\\Engine-PowerManager.ps1`"`r`nexit /b`r`n"
            [System.IO.File]::WriteAllText($powerBat, $powerContent, $utf8WithBom)
        }
    } else {
        # KHÔNG ĐƯỢC PHÉP DÙNG / BỊ THU HỒI: XÓA SẠCH BẰNG -LiteralPath
        $hadFile = $false
        if (Test-Path -LiteralPath $powerBat) {
            Remove-Item -LiteralPath $powerBat -Force -ErrorAction SilentlyContinue
            $hadFile = $true
        }
        Get-ChildItem -LiteralPath $BAT_DIR -Filter "*501*.bat" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            $hadFile = $true
        }
        if (Test-Path -LiteralPath $powerPs1) {
            $tmplDir = Join-Path $ENGINE_DIR "Templates"
            if (-not (Test-Path $tmplDir)) { New-Item -ItemType Directory -Path $tmplDir -Force | Out-Null }
            Copy-Item -LiteralPath $powerPs1 -Destination $powerTmpl -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $powerPs1 -Force -ErrorAction SilentlyContinue
            $hadFile = $true
        }
        if ($hadFile) {
            Write-Host " [!] THU HỒI / CHƯA CẤP PHÉP: Chức năng [F02_SHUTDOWN_TIMER - Hẹn giờ tắt máy] đã được dỡ bỏ khỏi thiết bị!" -ForegroundColor Yellow
        }
    }
}

# ==============================================================================
# 3. XỬ LÝ HÌNH THỨC PRE-PACKAGED / ZERO-TOUCH
# ==============================================================================

function Process-PrePackagedFlow {
    Show-HeaderBanner -SubTitle "KÍCH HOẠT BẢN QUYỀN ĐÓNG GÓI SẴN (PRE-PACKAGED)"

    Show-PrePackagedWarningBanner
    Write-Host " Hệ thống đang tiến hành kiểm tra và kích hoạt bản quyền cho thiết bị..." -ForegroundColor Cyan
    $currentHWID = Get-MachineHWID

    $lockRes = Lock-PrePackagedKeyToCurrentMachine -KeyFilePath $LICENSE_KEY_FILE -CurrentHWID $currentHWID

    if ($lockRes.Success) {
        Write-Host "`n [OK] $($lockRes.Message)" -ForegroundColor Green
        Write-Host ("      Người sở hữu : {0}" -f $lockRes.Payload.fullName) -ForegroundColor Cyan
        Write-Host ("      HWID Máy     : {0}" -f $currentHWID) -ForegroundColor DarkGray
        Write-Host ("      Thời hạn     : {0}" -f $lockRes.Payload.expiresAt) -ForegroundColor Yellow

        # Đồng bộ và tải các chức năng được phép dùng
        Sync-ClientLaunchers -AuthorizedFeatures $lockRes.Payload.features

        Write-Host "`n ================================================================================" -ForegroundColor Green
        Write-Host "                      CÀI ĐẶT & KÍCH HOẠT HOÀN TẤT!                             " -ForegroundColor Green
        Write-Host " ================================================================================" -ForegroundColor Green
        Write-Host " Bạn đã có thể sử dụng các công cụ được cấp phép trong thư mục @Actions." -ForegroundColor Yellow
        Write-Host "================================================================================`n" -ForegroundColor DarkGray
    } else {
        Write-Host "`n [X] THẤT BẠI: $($lockRes.Message)" -ForegroundColor Red
        Write-Host " Bản quyền không hợp lệ hoặc thư mục này đã bị sao chép sang máy tính khác sử dụng." -ForegroundColor Red
        Write-Host " Vui lòng liên hệ: Mr. ĐÀO XUÂN TUẤN (Tuấn Beo) - Hotline: 0987.1987.92 | Email: tuanbeo.technology@gmail.com để được hỗ trợ cấp lại Key!`n" -ForegroundColor Yellow
    }

    Wait-ForUserExit -Message " Nhấn phím bất kỳ để đóng..."
}

# ==============================================================================
# 4. XỬ LÝ HÌNH THỨC TƯƠNG TÁC & TỰ ĐỘNG LẤY KEY TỪ SERVER
# ==============================================================================

function Process-InteractiveActivationFlow {
    Show-HeaderBanner -SubTitle "KÍCH HOẠT BẢN QUYỀN TB-TOOLBOX"

    $currentHWID = Get-MachineHWID
    Write-Host " Mã định danh phần cứng (HWID) của máy bạn:" -ForegroundColor Yellow
    Write-Host " >> $currentHWID <<" -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " [1] Nhập chuỗi Mã Key trực tiếp" -ForegroundColor Cyan
    Write-Host " [2] Nạp từ tệp key.txt có sẵn" -ForegroundColor Cyan
    Write-Host " [3] Gửi yêu cầu cấp Key mới tới Tác giả (Mr. ĐÀO XUÂN TUẤN)" -ForegroundColor Cyan
    Write-Host " [4] Tự động kích hoạt key từ máy chủ (GitHub TuanBeo98RL)" -ForegroundColor Green
    Write-Host " [0] Thoát chương trình`n" -ForegroundColor DarkGray

    $opt = Read-Host " Chọn thao tác [0-4]"
    if ($opt -eq "0" -or [string]::IsNullOrWhiteSpace($opt)) { return }
    $inputKeyString = ""

    switch ($opt) {
        "1" {
            $inputKeyString = Read-Host "`n Dán chuỗi Mã Key của bạn vào đây (hoặc nhấn [0] để Quay lại)"
            if ($inputKeyString -eq "0" -or [string]::IsNullOrWhiteSpace($inputKeyString)) {
                Write-Host " Đã hủy thao tác nhập Key." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                return
            }
        }
        "2" {
            $filePath = Read-Host "`n Nhập đường dẫn tệp key (Mặc định: key.txt, hoặc nhấn [0] để Quay lại)"
            if ($filePath -eq "0") {
                Write-Host " Đã hủy thao tác." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                return
            }
            if ([string]::IsNullOrWhiteSpace($filePath)) { $filePath = "key.txt" }
            if (Test-Path $filePath) {
                $inputKeyString = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8).Trim()
            } else {
                Write-Host " Không tìm thấy tệp tại: $filePath" -ForegroundColor Red
                Wait-ForUserExit -Message " Nhấn phím bất kỳ để quay lại..."
                return
            }
        }
        "3" {
            Show-HeaderBanner -SubTitle "ĐĂNG KÝ CẤP BẢN QUYỀN MỚI"
            $name = Read-Host " Họ và tên của bạn (hoặc nhấn [0] để Hủy)"
            if ($name -eq "0" -or [string]::IsNullOrWhiteSpace($name)) {
                Write-Host " Đã hủy thao tác đăng ký." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                return
            }
            $email = Read-Host " Email hoặc Số điện thoại (hoặc nhấn [0] để Hủy)"
            if ($email -eq "0") {
                Write-Host " Đã hủy thao tác đăng ký." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                return
            }
            if ([string]::IsNullOrWhiteSpace($email)) { $email = "Chưa cung cấp" }

            $note = Read-Host " Nhu cầu sử dụng (để trống để cấp mặc định, hoặc [0] để Hủy)"
            if ($note -eq "0") {
                Write-Host " Đã hủy thao tác đăng ký." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                return
            }

            # Sao chép mã HWID vào Clipboard
            try {
                Set-Clipboard -Value $currentHWID -ErrorAction SilentlyContinue
            } catch {}

            # Ghi vào hàng đợi yêu cầu chờ cục bộ (pending-requests)
            $reqFile = Join-Path $CONFIG_DIR "pending-requests.json"
            $reqStore = Read-JsonWithBom -Path $reqFile
            if ($null -eq $reqStore -or -not $reqStore.requests) {
                $reqStore = [PSCustomObject]@{
                    metadata = [PSCustomObject]@{ system = "TB-Toolbox Requests Queue"; lastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
                    requests = @()
                }
            }

            $newReq = [PSCustomObject]@{
                hwid        = $currentHWID
                fullName    = $name
                email       = $email
                note        = $note
                submittedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                status      = 0 # 0 = Chờ duyệt
            }
            $reqStore.requests += $newReq
            Save-JsonWithBom -Path $reqFile -Data $reqStore | Out-Null

            # Tự động mở trình duyệt gửi yêu cầu lên GitHub Issues
            $encodedTitle = [System.Uri]::EscapeDataString("[Yêu Cầu Cấp Key] $name - $currentHWID")
            $issueBodyText = @"
### THÔNG TIN ĐĂNG KÝ BẢN QUYỀN TB-TOOLBOX
- **Họ và tên**: $name
- **Email / SĐT**: $email
- **Mã phần cứng (HWID)**: `$currentHWID`
- **Nhu cầu sử dụng**: $note
- **Thời gian gửi**: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
"@
            $encodedBody = [System.Uri]::EscapeDataString($issueBodyText)
            $issueUrl = "https://github.com/TuanBeo98RL/TB-Toolbox/issues/new?title=$encodedTitle&body=$encodedBody"

            Write-Host "`n [OK] ĐÃ THIẾT LẬP YÊU CẦU CẤP BẢN QUYỀN!" -ForegroundColor Green
            Write-Host " [*] Đã tự động sao chép mã HWID vào bộ nhớ tạm (Clipboard)." -ForegroundColor Cyan
            Write-Host " [*] Đang tự động mở trình duyệt web gửi yêu cầu lên Máy chủ Trung tâm..." -ForegroundColor Cyan

            try {
                Start-Process $issueUrl
                Write-Host "`n [HƯỚNG DẪN] Cửa sổ trình duyệt đã mở ra trang Đăng ký trên GitHub." -ForegroundColor Yellow
                Write-Host "             Bạn chỉ cần nhấn nút xanh `"Submit new issue`" là hoàn tất!" -ForegroundColor Yellow
            } catch {
                Write-Host "`n [!] Không thể tự động mở trình duyệt. Bạn có thể mở liên kết sau:`n     $issueUrl" -ForegroundColor Yellow
            }

            Write-Host "`n --------------------------------------------------------------------------------" -ForegroundColor DarkGray
            Write-Host " Mã HWID máy của bạn: $currentHWID" -ForegroundColor White
            Write-Host " Hotline / Zalo Tác giả: Mr. ĐÀO XUÂN TUẤN (Tuấn Beo) - 0987.1987.92" -ForegroundColor DarkGray
            Write-Host " Sau khi Admin duyệt xong, bạn mở lại công cụ và chọn [4] để Tự động kích hoạt.`n" -ForegroundColor Green
            Wait-ForUserExit -Message " Nhấn phím bất kỳ để tiếp tục..."
            return
        }
        "4" {
            Show-HeaderBanner -SubTitle "TỰ ĐỘNG KÍCH HOẠT TỪ MÁY CHỦ GITHUB"
            Write-Host " [*] Đang kết nối tới máy chủ GitHub (TuanBeo98RL/TB-Toolbox)..." -ForegroundColor Cyan
            Write-Host " [*] Mã phần cứng thiết bị của bạn: $currentHWID" -ForegroundColor DarkGray
            
            $serverUrl = "https://raw.githubusercontent.com/TuanBeo98RL/TB-Toolbox/main/licenses.json?t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "TB-Toolbox-Client")
                $rawJson = $wc.DownloadString($serverUrl)
                $registry = $rawJson | ConvertFrom-Json
                
                $foundKey = $null
                $isRevoked = $false
                if ($registry -is [System.Management.Automation.PSCustomObject]) {
                    $entry = $null
                    if ($registry.PSObject.Properties[$currentHWID]) {
                        $entry = $registry.$currentHWID
                    } elseif ($registry.licenses -and $registry.licenses.PSObject.Properties[$currentHWID]) {
                        $entry = $registry.licenses.$currentHWID
                    }

                    if ($null -ne $entry) {
                        if ($entry -is [string]) {
                            $foundKey = $entry
                        } elseif ($entry.key) {
                            if ($entry.status -eq 0) {
                                $isRevoked = $true
                            } else {
                                $foundKey = $entry.key
                            }
                        }
                    }
                }
                
                if ($isRevoked) {
                    Write-Host "`n [X] BẢN QUYỀN CỦA THIẾT BỊ NÀY ĐÃ BỊ THU HỒI HOẶC VÔ HIỆU HÓA TRÊN MÁY CHỦ!" -ForegroundColor Red
                    Write-Host "     Vui lòng liên hệ Tác giả: Mr. ĐÀO XUÂN TUẤN (Hotline: 0987.1987.92) để được hỗ trợ." -ForegroundColor Yellow
                    Wait-ForUserExit -Message "`n Nhấn phím bất kỳ để quay lại menu..."
                    return
                }

                if (-not [string]::IsNullOrWhiteSpace($foundKey)) {
                    Write-Host "`n [OK] ĐÃ TÌM THẤY BẢN QUYỀN ĐƯỢC CẤP TRÊN MÁY CHỦ GITHUB!" -ForegroundColor Green
                    $inputKeyString = $foundKey
                } else {
                    Write-Host "`n [!] Thiết bị của bạn (HWID: $currentHWID) chưa được cấp bản quyền trên máy chủ." -ForegroundColor Yellow
                    Write-Host "     Vui lòng liên hệ Tác giả: Mr. ĐÀO XUÂN TUẤN (Hotline: 0987.1987.92) để được phê duyệt." -ForegroundColor DarkGray
                    Wait-ForUserExit -Message "`n Nhấn phím bất kỳ để quay lại menu..."
                    return
                }
            } catch {
                Write-Host "`n [X] Không thể kết nối tới máy chủ GitHub hoặc máy chưa có Internet!" -ForegroundColor Red
                Write-Host "     Chi tiết: $($_.Exception.Message)" -ForegroundColor DarkGray
                Wait-ForUserExit -Message "`n Nhấn phím bất kỳ để quay lại menu..."
                return
            }
        }
        default { return }
    }

    if ([string]::IsNullOrWhiteSpace($inputKeyString)) {
        Write-Host " Mã Key không được để trống!" -ForegroundColor Red
        Wait-ForUserExit -Message " Nhấn phím bất kỳ để tiếp tục..."
        return
    }

    # Kiểm tra tính hợp lệ của Key
    $verify = Verify-LicenseKey -LicenseKeyString $inputKeyString -CurrentHWID $currentHWID
    if ($verify.IsValid) {
        # Lưu và khóa chặt 3 neo phần cứng (File + DPAPI + Registry)
        Save-LicenseTripleAnchor -KeyString $inputKeyString -Payload $verify.Payload -CurrentHWID $currentHWID

        Write-Host "`n ================================================================================" -ForegroundColor Green
        Write-Host "                      KÍCH HOẠT BẢN QUYỀN THÀNH CÔNG!                           " -ForegroundColor Green
        Write-Host " ================================================================================" -ForegroundColor Green
        Write-Host ("      Người sở hữu : {0}" -f $verify.Payload.fullName) -ForegroundColor Cyan
        Write-Host ("      Thời hạn     : {0}" -f $verify.Payload.expiresAt) -ForegroundColor Yellow
        Write-Host "      Xác thực chữ ký số: RSA-2048 HỢP LỆ (Chính chủ Tuanbeo98)`n" -ForegroundColor Green

        # Tải các module được cấp phép và dỡ bỏ các module không có quyền
        Sync-ClientLaunchers -AuthorizedFeatures $verify.Payload.features

        Write-Host "`n [OK] Bạn đã có thể sử dụng các công cụ được cấp phép trong thư mục @Actions.`n" -ForegroundColor Green
    } else {
        Write-Host "`n [X] KÍCH HOẠT THẤT BẠI: $($verify.Error)" -ForegroundColor Red
    }

    Wait-ForUserExit -Message " Nhấn phím bất kỳ để hoàn tất..."
}

# ==============================================================================
# 5. ENTRY POINT
# ==============================================================================

function Start-ClientBootstrap {
    if ($StatusOnly) {
        Process-PrePackagedFlow
        return
    }
    if ($Interactive) {
        Process-InteractiveActivationFlow
        return
    }
    if (Test-Path $LICENSE_KEY_FILE) {
        Process-PrePackagedFlow
    } else {
        Process-InteractiveActivationFlow
    }
}

if ($MyInvocation.InvocationName -ne '.' -and (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path))) {
    Start-ClientBootstrap
}
