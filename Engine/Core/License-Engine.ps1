# ==============================================================================
# TB-TOOLBOX - LICENSE & CRYPTOGRAPHY ENGINE (License-Engine.ps1)
# Bản quyền thuộc về: Mr. Tuấn Beo (TuanBeoToolbox)
# Chuc nang: Thuat toan Hybrid HWID, Ky so HMAC-SHA256 (MasterKey), Time-Vault,
#            Khoa 3 diem (Triple-Anchor: File + DPAPI + Registry) va Niem phong ma nguon.
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Security

# Hang so Khoa Chu Toi Cao cua he thong
$script:TB_MASTER_KEY = "Tuanbeo1998@"

$ENGINE_DIR = Split-Path -Parent $PSScriptRoot
$TB_ROOT = Split-Path -Parent $ENGINE_DIR
$CORE_DIR = $PSScriptRoot
$CONFIG_DIR = Join-Path $ENGINE_DIR "Config"
$VAULT_FILE = Join-Path $CONFIG_DIR ".time-vault"
$DPAPI_ANCHOR_FILE = Join-Path $CONFIG_DIR ".license.dpapi"
$REGISTRY_ANCHOR_PATH = "HKCU:\Software\Classes\CLSID\{D4A1B2C3-E5F6-4A7B-8C9D-0E1F2A3B4C5D}"

# Dot-source Crypto-RSA, Integrity-Guard va Server-Sync neu co
if (Test-Path (Join-Path $CORE_DIR "Crypto-RSA.ps1")) {
    . (Join-Path $CORE_DIR "Crypto-RSA.ps1")
}
if (Test-Path (Join-Path $CORE_DIR "Integrity-Guard.ps1")) {
    . (Join-Path $CORE_DIR "Integrity-Guard.ps1")
}
# Server-Sync is dot-sourced downstream when needed to prevent circular dependency

# ==============================================================================
# 1. THUAT TOAN SINH MA PHAN CUNG LAI (HYBRID HWID ALGORITHM)
# ==============================================================================

function Get-MachineHWID {
    <#
    .SYNOPSIS
        Trich xuat Hybrid HWID = SHA256(BaseBoard_Serial + CPU_ProcessorId + Windows_MachineGuid).
        Dam bao 100% duy nhat theo tung may tinh vat ly, bat bien khi doi ten may/user.
    #>
    try {
        $bb = (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).SerialNumber
        if ([string]::IsNullOrWhiteSpace($bb)) { $bb = "BB_GENERIC_DEFAULT" }
    } catch { $bb = "BB_FALLBACK" }

    try {
        $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).ProcessorId
        if ([string]::IsNullOrWhiteSpace($cpu)) { $cpu = "CPU_GENERIC_DEFAULT" }
    } catch { $cpu = "CPU_FALLBACK" }

    try {
        $guid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -ErrorAction SilentlyContinue).MachineGuid
        if ([string]::IsNullOrWhiteSpace($guid)) { $guid = "GUID_GENERIC_DEFAULT" }
    } catch { $guid = "GUID_FALLBACK" }

    $combined = "$($bb.Trim())_$($cpu.Trim())_$($guid.Trim())"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($combined))
    $hwid = [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 32)
    return $hwid
}

# ==============================================================================
# 2. CO CHE KY SO VA XAC THUC HMAC-SHA256 VOI MASTERKEY
# ==============================================================================

function Generate-HMACSignature {
    param (
        [string]$Data,
        [string]$Secret = $script:TB_MASTER_KEY
    )
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
    $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList @(,$keyBytes)
    $hashBytes = $hmac.ComputeHash($dataBytes)
    return [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
}

function Create-LicenseKey {
    param (
        [string]$HWID,
        [string]$FullName,
        [string]$Email,
        [string]$GroupId = "GRP_DEFAULT",
        [hashtable]$Features,
        [int]$DurationDays = 0,
        [string]$Mode = "INTERACTIVE"
    )
    $now = Get-Date
    $keyId = "TBK-" + $now.ToString("yyyyMMdd-HHmmss") + "-" + (Get-Random -Minimum 1000 -Maximum 9999)

    $expiryDate = if ($DurationDays -gt 0) {
        $now.AddDays($DurationDays).ToString("yyyy-MM-dd HH:mm:ss")
    } else {
        "LIFETIME"
    }

    $payloadObj = [PSCustomObject]@{
        keyId        = $keyId
        hwid         = if ($HWID) { $HWID.Trim().ToUpper() } else { "" }
        fullName     = $FullName
        email        = $Email
        groupId      = $GroupId
        features     = $Features
        issuedAt     = $now.ToString("yyyy-MM-dd HH:mm:ss")
        expiresAt    = $expiryDate
        mode         = $Mode
        isLocked     = if ($HWID) { $true } else { $false }
    }

    $json = $payloadObj | ConvertTo-Json -Compress
    $payloadBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
    
    # Uu tien ky so bang RSA-2048 Private Key
    $signature = Sign-DataRSA -Data $payloadBase64
    if ([string]::IsNullOrWhiteSpace($signature)) {
        $signature = Generate-HMACSignature -Data $payloadBase64
        return "TBKEY.$payloadBase64.$signature"
    }

    return "TBKEY-RSA.$payloadBase64.$signature"
}

function Verify-LicenseKey {
    param (
        [string]$LicenseKeyString,
        [string]$CurrentHWID
    )
    if ([string]::IsNullOrWhiteSpace($LicenseKeyString)) {
        return [PSCustomObject]@{ IsValid = $false; Error = "Ma Key trong!" }
    }

    $parts = $LicenseKeyString.Trim().Split('.')
    if ($parts.Length -ne 3 -or ($parts[0] -ne "TBKEY" -and $parts[0] -ne "TBKEY-RSA")) {
        return [PSCustomObject]@{ IsValid = $false; Error = "Dinh dang Key khong hop le!" }
    }

    $keyScheme = $parts[0]
    $payloadBase64 = $parts[1]
    $receivedSig = $parts[2]

    # Kiem tra chu ky
    if ($keyScheme -eq "TBKEY-RSA") {
        # Kiem tra bang RSA-2048 Public Key
        $isSigValid = Verify-DataRSA -Data $payloadBase64 -SignatureBase64 $receivedSig
        if (-not $isSigValid) {
            return [PSCustomObject]@{ IsValid = $false; Error = "Chu ky RSA khong hop le! Key da bi can thiep hoac gia mao." }
        }
    } else {
        # Kiem tra bang HMAC MasterKey (che do cu)
        $expectedSig = Generate-HMACSignature -Data $payloadBase64
        if ($receivedSig.ToLower() -ne $expectedSig.ToLower()) {
            return [PSCustomObject]@{ IsValid = $false; Error = "Chu ky khong hop le! Key da bi can thiep hoac gia mao." }
        }
    }

    try {
        $jsonBytes = [Convert]::FromBase64String($payloadBase64)
        $jsonStr = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
        $payload = $jsonStr | ConvertFrom-Json
    } catch {
        return [PSCustomObject]@{ IsValid = $false; Error = "Loi giai ma noi dung Key: $($_.Exception.Message)" }
    }

    # Kiem tra Time-Vault (Chong gian lan lui gio dong ho)
    $tamperCheck = Test-TimeVault
    if (-not $tamperCheck.IsValid) {
        return [PSCustomObject]@{ IsValid = $false; Error = $tamperCheck.Error }
    }

    # Kiem tra thoi han
    if ($payload.expiresAt -ne "LIFETIME") {
        try {
            $expDate = [DateTime]::ParseExact($payload.expiresAt, "yyyy-MM-dd HH:mm:ss", $null)
            if ((Get-Date) -gt $expDate) {
                return [PSCustomObject]@{ IsValid = $false; Error = "Ban quyen da het han vao luc $($payload.expiresAt)!" }
            }
        } catch {
            return [PSCustomObject]@{ IsValid = $false; Error = "Ngay het han trong Key khong dung dinh dang!" }
        }
    }

    # Kiem tra khoa phan cung (HWID Lock - Bo qua cho Admin hoac Token ALL)
    if (-not [string]::IsNullOrWhiteSpace($payload.hwid)) {
        $isBypassHwid = ($payload.hwid.ToUpper() -eq "ALL" -or $payload.groupId -eq "GF9999" -or $payload.role -eq "Admin")
        if (-not $isBypassHwid -and ($payload.hwid.ToUpper() -ne $CurrentHWID.ToUpper())) {
            return [PSCustomObject]@{ 
                IsValid = $false; 
                Error   = "Vi pham ban quyen: Key nay da duoc dang ky cho mot may tinh khac! (HWID: $($payload.hwid))" 
            }
        }
    }

    return [PSCustomObject]@{
        IsValid = $true
        Payload = $payload
        Error   = ""
    }
}

# ==============================================================================
# 3. KHOA BAN QUYEN 3 DIEM (TRIPLE-ANCHOR: FILE + DPAPI + REGISTRY)
# ==============================================================================

function Save-LicenseTripleAnchor {
    param (
        [string]$KeyString,
        [PSCustomObject]$Payload,
        [string]$CurrentHWID,
        [string]$TargetKeyFilePath = ""
    )
    if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }

    # 1. ANCHOR 1: Tep license.key
    $keyFile = if (-not [string]::IsNullOrWhiteSpace($TargetKeyFilePath)) { $TargetKeyFilePath } else { Join-Path $CONFIG_DIR "license.key" }
    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($keyFile, $KeyString, $utf8WithBom)

    # 2. ANCHOR 2: Windows DPAPI Blob (Ma hoa cap Profile User & Hardware)
    try {
        $dpapiFile = Join-Path (Split-Path -Parent $keyFile) ".license.dpapi"
        $secretBytes = [System.Text.Encoding]::UTF8.GetBytes("$($Payload.keyId)|$CurrentHWID|$($Payload.fullName)")
        $entropy = [System.Text.Encoding]::UTF8.GetBytes("TuanBeoTBToolbox2026")
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect($secretBytes, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        [System.IO.File]::WriteAllBytes($dpapiFile, $protectedBytes)
    } catch {}

    # 3. ANCHOR 3: Windows Registry CLSID Anchor (Nhanh an khong can Admin)
    try {
        if (-not (Test-Path $REGISTRY_ANCHOR_PATH)) {
            New-Item -Path $REGISTRY_ANCHOR_PATH -Force | Out-Null
        }
        $regToken = Generate-HMACSignature -Data "$($Payload.keyId)_$CurrentHWID"
        Set-ItemProperty -Path $REGISTRY_ANCHOR_PATH -Name "SystemSecurityToken" -Value $regToken -Force
    } catch {}

    # Gui / Ghi nhan Telemetry phuc vu dong bo len Server
    try {
        if (Get-Command Queue-TelemetryRecord -ErrorAction SilentlyContinue) {
            Queue-TelemetryRecord -KeyId $Payload.keyId -HWID $CurrentHWID -Action "ACTIVATED"
            Sync-TelemetryToServer | Out-Null
        }
    } catch {}
}

function Verify-LicenseTripleAnchor {
    param (
        [string]$CurrentHWID,
        [string]$TargetKeyFilePath = ""
    )

    # TANG 1: Kiem tra niem phong ma nguon
    if (Get-Command Test-CodeIntegrity -ErrorAction SilentlyContinue) {
        $sealCheck = Test-CodeIntegrity
        if (-not $sealCheck.IsValid) {
            return [PSCustomObject]@{
                IsValid = $false
                Error   = $sealCheck.Error
            }
        }
    }

    # TANG 2: Kiem tra ANCHOR 1 (File license.key)
    $keyFile = if (-not [string]::IsNullOrWhiteSpace($TargetKeyFilePath)) { $TargetKeyFilePath } else { Join-Path $CONFIG_DIR "license.key" }
    if (-not (Test-Path $keyFile)) {
        return [PSCustomObject]@{ IsValid = $false; Error = "Không tìm thấy tập tin bản quyền (license.key)!" }
    }

    $keyStr = [System.IO.File]::ReadAllText($keyFile, [System.Text.Encoding]::UTF8).Trim()
    $fileVerify = Verify-LicenseKey -LicenseKeyString $keyStr -CurrentHWID $CurrentHWID
    if (-not $fileVerify.IsValid) {
        return $fileVerify
    }
    $payload = $fileVerify.Payload

    # Kiểm tra ANCHOR 2: DPAPI
    $dpapiFile = Join-Path (Split-Path -Parent $keyFile) ".license.dpapi"
    if (Test-Path $dpapiFile) {
        try {
            $protectedBytes = [System.IO.File]::ReadAllBytes($dpapiFile)
            $entropy = [System.Text.Encoding]::UTF8.GetBytes("TuanBeoTBToolbox2026")
            $unprotected = [System.Security.Cryptography.ProtectedData]::Unprotect($protectedBytes, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
            $recovered = [System.Text.Encoding]::UTF8.GetString($unprotected)
            $parts = $recovered.Split('|')
            if ($parts[0] -ne $payload.keyId -or $parts[1].ToUpper() -ne $CurrentHWID.ToUpper()) {
                return [PSCustomObject]@{
                    IsValid = $false
                    Error   = "CẢNH BÁO CAN THIỆP: Dữ liệu mã hóa phần cứng DPAPI không khớp với bản quyền máy này!"
                }
            }
        } catch {
            return [PSCustomObject]@{
                IsValid = $false
                Error   = "Lỗi giải mã DPAPI phần cứng! Tập tin có thể đã bị sao chép sang máy tính hoặc người dùng khác."
            }
        }
    }

    # Kiểm tra ANCHOR 3: Registry CLSID
    if (Test-Path $REGISTRY_ANCHOR_PATH) {
        try {
            $regToken = (Get-ItemProperty -Path $REGISTRY_ANCHOR_PATH -Name "SystemSecurityToken" -ErrorAction SilentlyContinue).SystemSecurityToken
            $expectedToken = Generate-HMACSignature -Data "$($payload.keyId)_$CurrentHWID"
            if ($regToken.ToLower() -ne $expectedToken.ToLower()) {
                return [PSCustomObject]@{
                    IsValid = $false
                    Error   = "CẢNH BÁO CAN THIỆP: Mã xác thực Registry Windows không hợp lệ!"
                }
            }
        } catch {}
    }

    return [PSCustomObject]@{
        IsValid = $true
        Payload = $payload
        Error   = ""
    }
}

# ==============================================================================
# 4. TIME-VAULT ENGINE (CHONG GIAN LAN LUI DONG HO WINDOWS)
# ==============================================================================

function Update-TimeVault {
    try {
        if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }
        $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $sig = Generate-HMACSignature -Data $nowStr
        $vaultContent = "$nowStr|$sig"
        [System.IO.File]::WriteAllText($VAULT_FILE, $vaultContent, [System.Text.Encoding]::UTF8)
    } catch {}
}

function Test-TimeVault {
    if (-not (Test-Path $VAULT_FILE)) {
        Update-TimeVault
        return [PSCustomObject]@{ IsValid = $true; Error = "" }
    }

    try {
        $raw = [System.IO.File]::ReadAllText($VAULT_FILE, [System.Text.Encoding]::UTF8).Trim()
        $parts = $raw.Split('|')
        if ($parts.Length -ne 2) {
            Update-TimeVault
            return [PSCustomObject]@{ IsValid = $true; Error = "" }
        }

        $recordedTimeStr = $parts[0]
        $recordedSig = $parts[1]

        $checkSig = Generate-HMACSignature -Data $recordedTimeStr
        if ($recordedSig.ToLower() -ne $checkSig.ToLower()) {
            return [PSCustomObject]@{ 
                IsValid = $false; 
                Error   = "Phat hien can thiep tap tin thoi gian bao mat (.time-vault)!" 
            }
        }

        $lastRecorded = [DateTime]::ParseExact($recordedTimeStr, "yyyy-MM-dd HH:mm:ss", $null)
        $now = Get-Date

        if ($now -lt $lastRecorded.AddMinutes(-5)) {
            return [PSCustomObject]@{ 
                IsValid = $false; 
                Error   = "Phat hien gian lan thoi gian: Dong ho may tinh da bi chinh lui ve qua khu! (Moc truoc do: $recordedTimeStr)" 
            }
        }

        if ($now -gt $lastRecorded) {
            Update-TimeVault
        }

        return [PSCustomObject]@{ IsValid = $true; Error = "" }
    } catch {
        Update-TimeVault
        return [PSCustomObject]@{ IsValid = $true; Error = "" }
    }
}

# ==============================================================================
# 5. FIRST-RUN HWID LOCK CHO GOI DONG GOI SAN (PRE-PACKAGED / ZERO-TOUCH)
# ==============================================================================

function Lock-PrePackagedKeyToCurrentMachine {
    param (
        [string]$KeyFilePath,
        [string]$CurrentHWID
    )
    if (-not (Test-Path $KeyFilePath)) {
        return [PSCustomObject]@{ Success = $false; Message = "Khong tim thay tap tin key tai $KeyFilePath" }
    }

    $keyContent = [System.IO.File]::ReadAllText($KeyFilePath, [System.Text.Encoding]::UTF8).Trim()
    $verify = Verify-LicenseKey -LicenseKeyString $keyContent -CurrentHWID $CurrentHWID

    if (-not $verify.IsValid) {
        return [PSCustomObject]@{ Success = $false; Message = $verify.Error }
    }

    $payload = $verify.Payload

    # Truong hop 1: Key chua bind HWID (Chay lan dau tien tren may A)
    if ([string]::IsNullOrWhiteSpace($payload.hwid)) {
        $payload.hwid = $CurrentHWID.ToUpper()
        $payload.isLocked = $true
        $payload | Add-Member -MemberType NoteProperty -Name "activatedAt" -Value ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Force

        $newJson = $payload | ConvertTo-Json -Compress
        $newBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($newJson))
        
        $newSig = Sign-DataRSA -Data $newBase64
        if ([string]::IsNullOrWhiteSpace($newSig)) {
            $newSig = Generate-HMACSignature -Data $newBase64
            $lockedKey = "TBKEY.$newBase64.$newSig"
        } else {
            $lockedKey = "TBKEY-RSA.$newBase64.$newSig"
        }

        # Luu va khoa chat 3 neo phan cung
        Save-LicenseTripleAnchor -KeyString $lockedKey -Payload $payload -CurrentHWID $CurrentHWID -TargetKeyFilePath $KeyFilePath

        return [PSCustomObject]@{
            Success       = $true
            IsFirstRun    = $true
            Message       = "Kích hoạt thành công và đã khóa chặt 3 neo phần cứng vào máy tính này!"
            Payload       = $payload
            LicenseString = $lockedKey
        }
    }

    # Trường hợp 2: Key đã bind HWID -> Kiểm tra xem có phải máy này không
    if ($payload.hwid.ToUpper() -eq $CurrentHWID.ToUpper()) {
        # Kiểm tra đối soát 3 neo
        $anchorCheck = Verify-LicenseTripleAnchor -CurrentHWID $CurrentHWID
        if (-not $anchorCheck.IsValid) {
            return [PSCustomObject]@{
                Success    = $false
                IsFirstRun = $false
                Message    = $anchorCheck.Error
            }
        }

        return [PSCustomObject]@{
            Success       = $true
            IsFirstRun    = $false
            Message       = "Key đã được kích hoạt hợp lệ trên máy tính này."
            Payload       = $payload
            LicenseString = $keyContent
        }
    } else {
        return [PSCustomObject]@{
            Success    = $false
            IsFirstRun = $false
            Message    = "Vi phạm bản quyền: Gói cài đặt này đã được khóa vào máy khác (HWID: $($payload.hwid)). Không được phép sao chép sử dụng!"
        }
    }
}

# ==============================================================================
# 6. BANNER CANH BAO DO CHO GOI DONG GOI SAN (RED WARNING BANNER)
# ==============================================================================

function Show-PrePackagedWarningBanner {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host "                       [CẢNH BÁO BẢN QUYỀN NGHIÊM NGẶT]                         " -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host " Tệp cài đặt này được đóng gói và cấp quyền sử dụng riêng cho máy tính của bạn!  " -ForegroundColor Red
    Write-Host " Tuyệt đối KHÔNG ĐƯỢC chia sẻ hoặc sao chép cho bất kỳ ai hay máy tính nào khác." -ForegroundColor Red
    Write-Host " Nếu cố tình phát tán, bạn có thể bị TƯỚC VĨNH VIỄN toàn bộ quyền sử dụng       " -ForegroundColor Red
    Write-Host " và hệ thống sẽ tự động khóa toàn bộ các tiện ích trên mọi thiết bị liên quan!  " -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host ""
}
