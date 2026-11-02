# ==============================================================================
# TB-TOOLBOX - RSA CRYPTO & EMERGENCY RECOVERY ENGINE (Crypto-RSA.ps1)
# Bản quyền thuộc về: Mr. Tuấn Beo (TuanBeoToolbox)
# Chuc nang: Chu ky so bat doi xung RSA-2048 bit, Quan ly Khoa Rieng / Khoa Cong Khai
#            va Co che Ma Cuu Ho Khan Cap (Emergency Recovery Key).
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Security

$ENGINE_DIR = Split-Path -Parent $PSScriptRoot
$TB_ROOT = Split-Path -Parent $ENGINE_DIR
$CONFIG_DIR = Join-Path $ENGINE_DIR "Config"
$PRIVATE_KEY_FILE = Join-Path $CONFIG_DIR "admin-private.rsa"
$PUBLIC_KEY_FILE  = Join-Path $CONFIG_DIR "tb-public.rsa"
$RECOVERY_VAULT   = Join-Path $CONFIG_DIR ".recovery.vault"

if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }

# ==============================================================================
# 1. KHOI TAO VA QUAN LY CAP KHOA RSA-2048 BIT
# ==============================================================================

function Initialize-RSAKeyPair {
    <#
    .SYNOPSIS
        Khoi tao cap khoa RSA-2048 bit neu chua ton tai.
        Private Key chi luu tren may Admin, Public Key phan phoi cho Client.
    #>
    param ([switch]$ForceRegenerate)

    # Neu tren may Client chi co Public Key -> Giu nguyen tuyet doi, khong ghi de!
    if ((Test-Path $PUBLIC_KEY_FILE) -and (-not (Test-Path $PRIVATE_KEY_FILE)) -and (-not $ForceRegenerate)) {
        return $true
    }

    if ((Test-Path $PRIVATE_KEY_FILE) -and (Test-Path $PUBLIC_KEY_FILE) -and (-not $ForceRegenerate)) {
        return $true
    }

    try {
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(2048)
        $privateXml = $rsa.ToXmlString($true)
        $publicXml  = $rsa.ToXmlString($false)

        $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($PRIVATE_KEY_FILE, $privateXml, $utf8WithBom)
        [System.IO.File]::WriteAllText($PUBLIC_KEY_FILE, $publicXml, $utf8WithBom)

        # Tao Ma Cuu Ho Khan Cap mac dinh neu chua co
        if (-not (Test-Path $RECOVERY_VAULT) -or $ForceRegenerate) {
            $recoveryKey = "TB-RECOVERY-" + (Get-Random -Minimum 1000 -Maximum 9999) + "-" + `
                           (Get-Random -Minimum 1000 -Maximum 9999) + "-" + `
                           (Get-Random -Minimum 1000 -Maximum 9999) + "-2026"
            
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $recHash = [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($recoveryKey))).Replace('-', '').ToLower()
            [System.IO.File]::WriteAllText($RECOVERY_VAULT, "$recoveryKey|$recHash", $utf8WithBom)
        }

        return $true
    } catch {
        Write-Error "Loi khi khoi tao cap khoa RSA: $($_.Exception.Message)"
        return $false
    }
}

function Get-EmergencyRecoveryKey {
    if (-not (Test-Path $RECOVERY_VAULT)) {
        Initialize-RSAKeyPair | Out-Null
    }
    try {
        $raw = [System.IO.File]::ReadAllText($RECOVERY_VAULT, [System.Text.Encoding]::UTF8).Trim()
        $parts = $raw.Split('|')
        return $parts[0]
    } catch {
        return "TB-RECOVERY-DEFAULT-9999-2026"
    }
}

function Verify-EmergencyRecoveryKey {
    param ([string]$InputKey)
    if ([string]::IsNullOrWhiteSpace($InputKey)) { return $false }
    $currentKey = Get-EmergencyRecoveryKey
    return ($InputKey.Trim().ToUpper() -eq $currentKey.Trim().ToUpper())
}

# ==============================================================================
# 2. KY SO VOI PRIVATE KEY (CHỈ THỰC HIỆN TRÊN MÁY ADMIN)
# ==============================================================================

function Sign-DataRSA {
    param ([string]$Data)
    if (-not (Test-Path $PRIVATE_KEY_FILE)) {
        return $null
    }

    try {
        $privateXml = [System.IO.File]::ReadAllText($PRIVATE_KEY_FILE, [System.Text.Encoding]::UTF8)
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.FromXmlString($privateXml)

        $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
        $sigBytes = $rsa.SignData($dataBytes, [System.Security.Cryptography.CryptoConfig]::MapNameToOID("SHA256"))
        return [Convert]::ToBase64String($sigBytes)
    } catch {
        return $null
    }
}

# ==============================================================================
# 3. XAC THUC CHU KY SO VOI PUBLIC KEY (CHAY TRÊN MÁY CLIENT)
# ==============================================================================

function Verify-DataRSA {
    param (
        [string]$Data,
        [string]$SignatureBase64
    )
    if (-not (Test-Path $PUBLIC_KEY_FILE)) {
        return $false
    }

    try {
        $publicXml = [System.IO.File]::ReadAllText($PUBLIC_KEY_FILE, [System.Text.Encoding]::UTF8)
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.FromXmlString($publicXml)

        $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
        $sigBytes = [Convert]::FromBase64String($SignatureBase64)
        return $rsa.VerifyData($dataBytes, [System.Security.Cryptography.CryptoConfig]::MapNameToOID("SHA256"), $sigBytes)
    } catch {
        return $false
    }
}

# Tu dong khoi tao cap khoa lan dau neu chua co public key
if (-not (Test-Path $PUBLIC_KEY_FILE)) {
    Initialize-RSAKeyPair | Out-Null
}
