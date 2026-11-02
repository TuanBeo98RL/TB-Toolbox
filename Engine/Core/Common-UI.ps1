<#
================================================================================
 TB-TOOLBOX - COMMON UI MODULE (Common-UI.ps1)
 Bản quyền: Mr. Tuấn Beo (TuanBeo)
 Mô tả: Thư viện giao diện console tiếng Việt UTF-8, thanh tiến trình siêu mượt
================================================================================
#>

# Thiết lập bảng mã UTF-8 cho Console
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# Tự động gỡ cờ chặn (Unblock) nếu người dùng tải qua GitHub ZIP
try {
    Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" | Unblock-File -ErrorAction SilentlyContinue
} catch {}

# Tự động căn chỉnh độ rộng Console tối thiểu 85 cột để chống vỡ khung hình trên mọi máy tính
try {
    if ($Host.UI.RawUI.WindowSize.Width -lt 85) {
        $buffer = $Host.UI.RawUI.BufferSize
        if ($buffer.Width -lt 85) {
            $buffer.Width = 85
            $Host.UI.RawUI.BufferSize = $buffer
        }
        $size = $Host.UI.RawUI.WindowSize
        $size.Width = 85
        $Host.UI.RawUI.WindowSize = $size
    }
} catch {}

function Show-HeaderBanner {
    param (
        [string]$SubTitle = "HỆ THỐNG DỌN DẸP BỘ NHỚ TẠM & TỐI ƯU WINDOWS"
    )
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   TB-TOOLBOX - $SubTitle" -ForegroundColor Green
    Write-Host "   Bản quyền thuộc về: Mr. ĐÀO XUÂN TUẤN (Tuấn Beo) | Hotline: 0987.1987.92" -ForegroundColor DarkGray
    Write-Host "   Email: tuanbeo.technology@gmail.com" -ForegroundColor DarkGray
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Format-FileSize {
    param ([long]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    if ($Bytes -lt 1GB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    return "{0:N2} GB" -f ($Bytes / 1GB)
}

function Truncate-Path {
    param (
        [string]$Path,
        [int]$MaxLength = 45
    )
    if ([string]::IsNullOrEmpty($Path)) { return "" }
    if ($Path.Length -le $MaxLength) { return $Path }
    $prefixLen = [int]($MaxLength / 3)
    $suffixLen = $MaxLength - $prefixLen - 3
    return $Path.Substring(0, $prefixLen) + "..." + $Path.Substring($Path.Length - $suffixLen)
}

function Show-SmoothProgressBar {
    param (
        [int]$Current,
        [int]$Total,
        [long]$FreedBytes,
        [string]$CurrentItem,
        [int]$BarWidth = 30
    )

    if ($Total -le 0) { $Total = 1 }
    $percent = [math]::Min(100, [int](($Current / $Total) * 100))
    $filledLength = [int](($percent / 100) * $BarWidth)
    $emptyLength = $BarWidth - $filledLength

    $fullChar = [char]0x2588 # █
    $emptyChar = [char]0x2591 # ░

    $bar = ($fullChar.ToString() * $filledLength) + ($emptyChar.ToString() * $emptyLength)
    $freedFormatted = Format-FileSize -Bytes $FreedBytes
    $truncItem = Truncate-Path -Path $CurrentItem -MaxLength 38

    # Sử dụng `r để ghi đè dòng hiện tại, triệt tiêu nhấp nháy 100%
    $line = "`r Tiến độ: [$bar] {0,3}% ({1}/{2}) | +{3} | {4}" -f $percent, $Current, $Total, $freedFormatted, $truncItem
    
    # Đảm bảo xóa sạch các ký tự đuôi của dòng trước bằng cách đệm khoảng trắng
    $padLength = [math]::Max(0, 115 - $line.Length)
    $line = $line + (" " * $padLength)

    Write-Host -NoNewline $line -ForegroundColor Yellow
}

function Wait-ForUserExit {
    param([string]$Message = " Nhấn phím bất kỳ để đóng cửa sổ...")
    Write-Host "`n$Message" -ForegroundColor DarkGray
    try {
        if ([Console]::IsInputRedirected) {
            $null = [Console]::Read()
        } else {
            $null = [Console]::ReadKey($true)
        }
    } catch {
        $null = Read-Host
    }
}
