# ==============================================================================
# TB-TOOLBOX - FEATURE REGISTRY & MATRIX ENGINE (Feature-Registry.ps1)
# Bản quyền thuộc về: Mr. Tuấn Beo (TuanBeoToolbox)
# Chuc nang: Quan ly danh muc chuc nang, tu dong dong bo ma tran nhom ban quyen,
#            bao toan trang thai [0/1] va ho tro ghi de quyen theo tung nguoi dung.
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$ENGINE_DIR = Split-Path -Parent $PSScriptRoot
$TB_ROOT = Split-Path -Parent $ENGINE_DIR
$CORE_DIR = $PSScriptRoot
$CONFIG_DIR = Join-Path $ENGINE_DIR "Config"
$MODULES_DIR = Join-Path $CORE_DIR "Modules"
$GROUPS_FILE = Join-Path $CONFIG_DIR "feature-groups.json"
$USER_PERMS_FILE = Join-Path $CONFIG_DIR "user-permissions.json"

if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }
if (-not (Test-Path $MODULES_DIR)) { New-Item -ItemType Directory -Path $MODULES_DIR -Force | Out-Null }

# ==============================================================================
# 1. HAM TIEN ICH DOC / GHI JSON VOI UTF-8 BOM
# ==============================================================================

function Read-JsonWithBom {
    param ([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($content)) { return $null }
        return ($content | ConvertFrom-Json)
    } catch {
        Write-Warning "Khong the doc tep JSON tai $Path : $($_.Exception.Message)"
        return $null
    }
}

function Save-JsonWithBom {
    param (
        [string]$Path,
        [object]$Data
    )
    try {
        $json = $Data | ConvertTo-Json -Depth 10
        $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($Path, $json, $utf8WithBom)
        return $true
    } catch {
        Write-Error "Loi khi luu tep JSON tai $Path : $($_.Exception.Message)"
        return $false
    }

function Get-RoleGroupName {
    param ([string]$GroupId)
    if ([string]::IsNullOrWhiteSpace($GroupId)) { return "N/A" }
    
    if (Test-Path $GROUPS_FILE) {
        $gData = Read-JsonWithBom -Path $GROUPS_FILE
        if ($gData -and $gData.groups) {
            $found = $gData.groups | Where-Object { $_.groupId -eq $GroupId }
            if ($found -and $found.groupName) { return $found.groupName }
        }
    }

    $nameMap = @{
        "GF0000" = "NhÃ³m Miá»…n PhÃ­ (Free)"
        "GF0050" = "NhÃ³m DÃ¹ng Thá»­ (Trial)"
        "GF0100" = "NhÃ³m Máº·c Äá»‹nh (Default)"
        "GF0150" = "NhÃ³m GiÃ¡o Dá»¥c (Education)"
        "GF0200" = "NhÃ³m Basic"
        "GF0300" = "NhÃ³m Plus"
        "GF0400" = "NhÃ³m Standard"
        "GF0500" = "NhÃ³m Pro (Professional)"
        "GF0600" = "NhÃ³m Growth"
        "GF0650" = "NhÃ³m Developer"
        "GF0700" = "NhÃ³m Business"
        "GF0800" = "NhÃ³m Ultra"
        "GF0850" = "NhÃ³m Enterprise"
        "GF0900" = "NhÃ³m VIP (Executive)"
        "GF9999" = "NhÃ³m Master (Admin Chá»§)"
        "GRP_FULL" = "ToÃ n Quyá»n (Full)"
        "GRP_DEFAULT" = "GÃ³i Máº·c Äá»‹nh"
        "GRP_ADVANCED" = "GÃ³i ChuyÃªn SÃ¢u"
    }

    if ($nameMap.ContainsKey($GroupId)) { return $nameMap[$GroupId] }
    return $GroupId
}
}

# ==============================================================================
# 2. QUET VA THU THAP DANH MUC TINH NANG THUC TE (DYNAMIC DISCOVERY)
# ==============================================================================

function Scan-AvailableFeatures {
    <#
    .SYNOPSIS
        Quet toan bo thu muc Core/Modules de tim cac module.json hop le.
        Moi chuc nang bat buoc phai co mot Ma ID duy nhat (Unique ID).
    #>
    $discovered = @()
    $manifestFiles = Get-ChildItem -Path $MODULES_DIR -Filter "module.json" -Recurse -ErrorAction SilentlyContinue

    foreach ($file in $manifestFiles) {
        try {
            $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            $mod = $raw | ConvertFrom-Json
            if ($mod.id -and $mod.name) {
                $discovered += [PSCustomObject]@{
                    Id          = $mod.id.Trim().ToUpper()
                    Name        = $mod.name.Trim()
                    Description = if ($mod.description) { $mod.description.Trim() } else { "" }
                    Category    = if ($mod.category) { $mod.category.Trim() } else { "Chung" }
                    LauncherBat = if ($mod.launcherBat) { $mod.launcherBat.Trim() } else { "" }
                    EntryPoint  = if ($mod.entryPoint) { $mod.entryPoint.Trim() } else { "" }
                    Version     = if ($mod.version) { $mod.version.Trim() } else { "1.0.0" }
                    Directory   = $file.DirectoryName
                }
            }
        } catch {
            Write-Warning "Bo qua tep module khong hop le: $($file.FullName)"
        }
    }

    return ($discovered | Sort-Object Id)
}

# ==============================================================================
# 3. DONG BO MA TRAN NHOM BAN QUYEN (DYNAMIC CATALOG & MATRIX AUTO-SYNC)
# ==============================================================================

function Sync-FeatureMatrix {
    <#
    .SYNOPSIS
        Dong bo ma tran cac nhom chuc nang voi danh muc tinh nang thuc te:
        - Neu chuc nang bi xoa khoi Core/Modules: Bo hoan toan khoi moi nhom.
        - Neu chuc nang moi xuat hien: Them vao TAT CA cac nhom voi trang thai mac dinh = 0.
        - Rieng F01_CLEANER mac dinh = 1 (Chuc nang cot loi).
        - Bao toan tuyet doi trang thai [0/1] da cau hinh truoc do cua cac chuc nang hien co.
        - Dam bao neu co N chuc nang thi MOI NHOM deu co day du dung N chuc nang do.
    #>
    $availableFeatures = Scan-AvailableFeatures
    $currentGroupsData = Read-JsonWithBom -Path $GROUPS_FILE

    if ($null -eq $currentGroupsData -or -not $currentGroupsData.groups) {
        $currentGroupsData = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                version     = "1.0.0"
                author      = "Mr. Tuan Beo (TuanBeoToolbox)"
                lastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            groups = @(
                [PSCustomObject]@{
                    groupId     = "GRP_DEFAULT"
                    groupName   = "Gói Mặc định (Tiêu chuẩn)"
                    description = "Gói chức năng cơ bản phục vụ dọn dẹp và tối ưu hóa hệ thống nhẹ"
                    features    = [ordered]@{}
                },
                [PSCustomObject]@{
                    groupId     = "GRP_ADVANCED"
                    groupName   = "Gói Chuyên sâu (Nâng cao)"
                    description = "Gói toàn diện bao gồm đầy đủ tiện ích dọn dẹp, mạng và cấu hình"
                    features    = [ordered]@{}
                }
            )
        }
    }

    $availableIds = @($availableFeatures | ForEach-Object { $_.Id })

    foreach ($grp in $currentGroupsData.groups) {
        $existingFeatures = [ordered]@{}
        if ($grp.features) {
            if ($grp.features -is [System.Management.Automation.PSCustomObject]) {
                foreach ($prop in $grp.features.PSObject.Properties) {
                    $existingFeatures[$prop.Name] = [int]$prop.Value
                }
            } elseif ($grp.features -is [System.Collections.IDictionary]) {
                foreach ($key in $grp.features.Keys) {
                    $existingFeatures[$key] = [int]$grp.features[$key]
                }
            }
        }

        # B1: XOA chuc nang khong con ton tai
        $keysToRemove = @()
        foreach ($fId in $existingFeatures.Keys) {
            if ($fId -notin $availableIds) {
                $keysToRemove += $fId
            }
        }
        foreach ($delKey in $keysToRemove) {
            $existingFeatures.Remove($delKey)
        }

        # B2: THEM chuc nang moi xuat hien (mac dinh = 0, F01 = 1)
        foreach ($feat in $availableFeatures) {
            if (-not $existingFeatures.Contains($feat.Id)) {
                if ($feat.Id -eq "F01_CLEANER") {
                    $existingFeatures[$feat.Id] = 1
                } else {
                    $existingFeatures[$feat.Id] = 0
                }
            }
        }

        # Sap xep theo ID
        $sortedFeatures = [ordered]@{}
        foreach ($feat in $availableFeatures) {
            $sortedFeatures[$feat.Id] = $existingFeatures[$feat.Id]
        }
        $grp.features = $sortedFeatures
    }

    $currentGroupsData.metadata.lastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Save-JsonWithBom -Path $GROUPS_FILE -Data $currentGroupsData | Out-Null

    return [PSCustomObject]@{
        Features = $availableFeatures
        Groups   = $currentGroupsData.groups
    }
}

# ==============================================================================
# 4. QUAN LY CONG TAC BAT/TAT TINH NANG THEO NHOM
# ==============================================================================

function Set-GroupFeatureState {
    param (
        [string]$GroupId,
        [string]$FeatureId,
        [int]$State
    )
    $matrix = Sync-FeatureMatrix
    $targetGroup = $matrix.Groups | Where-Object { $_.groupId -eq $GroupId }
    if (-not $targetGroup) {
        Write-Warning "Khong tim thay nhom: $GroupId"
        return $false
    }

    $featureIdUpper = $FeatureId.Trim().ToUpper()
    if ($targetGroup.features -is [System.Management.Automation.PSCustomObject]) {
        if ($targetGroup.features.PSObject.Properties[$featureIdUpper]) {
            $targetGroup.features.$featureIdUpper = [int]$State
        } else {
            $targetGroup.features | Add-Member -MemberType NoteProperty -Name $featureIdUpper -Value ([int]$State)
        }
    } else {
        $targetGroup.features[$featureIdUpper] = [int]$State
    }

    $groupsData = [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            version     = "1.0.0"
            author      = "Mr. Tuan Beo (TuanBeoToolbox)"
            lastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        groups   = $matrix.Groups
    }
    return (Save-JsonWithBom -Path $GROUPS_FILE -Data $groupsData)
}

# ==============================================================================
# 5. QUAN LY PHAN QUYEN RIENG THEO TAI KHOAN (ACCOUNT OVERRIDE)
# ==============================================================================

function Get-UserPermissionsStore {
    $store = Read-JsonWithBom -Path $USER_PERMS_FILE
    if ($null -eq $store -or -not $store.users) {
        $store = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                version     = "1.0.0"
                author      = "Mr. Tuan Beo (TuanBeoToolbox)"
                lastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            users = @()
        }
    }
    return $store
}

function Set-UserFeatureOverride {
    param (
        [string]$UserIdentifier,
        [string]$GroupId,
        [hashtable]$FeatureOverrides,
        [string]$FullName = "",
        [string]$Email = ""
    )
    $store = Get-UserPermissionsStore
    $userRecord = $store.users | Where-Object { 
        $_.identifier -eq $UserIdentifier -or $_.hwid -eq $UserIdentifier -or $_.email -eq $UserIdentifier 
    }

    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    if (-not $userRecord) {
        $userRecord = [PSCustomObject]@{
            identifier      = $UserIdentifier
            fullName        = $FullName
            email           = $Email
            baseGroupId     = $GroupId
            isCustomOverride= $true
            assignedAt      = $now
            lastUpdated     = $now
            features        = [ordered]@{}
        }
        $store.users += $userRecord
    } else {
        $userRecord.baseGroupId = $GroupId
        $userRecord.isCustomOverride = $true
        $userRecord.lastUpdated = $now
        if ($FullName) { $userRecord.fullName = $FullName }
        if ($Email) { $userRecord.email = $Email }
    }

    $featDict = [ordered]@{}
    if ($userRecord.features -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $userRecord.features.PSObject.Properties) {
            $featDict[$p.Name] = [int]$p.Value
        }
    }
    foreach ($k in $FeatureOverrides.Keys) {
        $featDict[$k.ToUpper()] = [int]$FeatureOverrides[$k]
    }
    $userRecord.features = $featDict

    $store.metadata.lastUpdated = $now
    Save-JsonWithBom -Path $USER_PERMS_FILE -Data $store | Out-Null
    return $userRecord
}

function Get-EffectiveUserPermissions {
    param (
        [string]$UserIdentifier,
        [string]$FallbackGroupId = "GRP_DEFAULT"
    )
    $matrix = Sync-FeatureMatrix
    $store = Get-UserPermissionsStore

    $userRecord = $store.users | Where-Object { 
        $_.identifier -eq $UserIdentifier -or $_.hwid -eq $UserIdentifier -or $_.email -eq $UserIdentifier 
    }

    $effectiveFeatures = [ordered]@{}
    $allFeatures = $matrix.Features

    if ($userRecord -and $userRecord.isCustomOverride) {
        $overrideDict = @{}
        if ($userRecord.features -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $userRecord.features.PSObject.Properties) {
                $overrideDict[$p.Name] = [int]$p.Value
            }
        } elseif ($userRecord.features -is [System.Collections.IDictionary]) {
            $overrideDict = $userRecord.features
        }

        foreach ($feat in $allFeatures) {
            if ($overrideDict.Contains($feat.Id)) {
                $effectiveFeatures[$feat.Id] = [int]$overrideDict[$feat.Id]
            } else {
                $effectiveFeatures[$feat.Id] = 0
            }
        }

        return [PSCustomObject]@{
            Mode       = "ACCOUNT_OVERRIDE"
            User       = $userRecord
            Features   = $effectiveFeatures
            DetailList = $allFeatures
        }
    } else {
        $targetGroupId = if ($userRecord -and $userRecord.baseGroupId) { $userRecord.baseGroupId } else { $FallbackGroupId }
        $group = $matrix.Groups | Where-Object { $_.groupId -eq $targetGroupId }
        if (-not $group) {
            $group = $matrix.Groups | Select-Object -First 1
        }

        $groupDict = @{}
        if ($group.features -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $group.features.PSObject.Properties) {
                $groupDict[$p.Name] = [int]$p.Value
            }
        } elseif ($group.features -is [System.Collections.IDictionary]) {
            $groupDict = $group.features
        }

        foreach ($feat in $allFeatures) {
            if ($groupDict.Contains($feat.Id)) {
                $effectiveFeatures[$feat.Id] = [int]$groupDict[$feat.Id]
            } else {
                $effectiveFeatures[$feat.Id] = 0
            }
        }

        return [PSCustomObject]@{
            Mode       = "GROUP_POLICY"
            Group      = $group
            Features   = $effectiveFeatures
            DetailList = $allFeatures
        }
    }
}

# ==============================================================================
# 6. HIEN THI MA TRAN TINH NANG DEP MAT TREN CONSOLE
# ==============================================================================

function Show-FeatureMatrixTable {
    param ()
    $matrix = Sync-FeatureMatrix
    $features = $matrix.Features
    $groups = $matrix.Groups

    Write-Host "`n=== BẢNG MA TRẬN TÍNH NĂNG & NHÓM BẢN QUYỀN (TB-TOOLBOX) ===" -ForegroundColor Cyan
    Write-Host ("Tổng số chức năng thực tế trong kho: {0}" -f $features.Count) -ForegroundColor Yellow
    Write-Host ("Tổng số gói nhóm đã cấu hình: {0}" -f $groups.Count) -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray

    $header = " {0,-18} | {1,-34}" -f "MÃ CHỨC NĂNG", "TÊN CHỨC NĂNG"
    foreach ($grp in $groups) {
        $header += " | {0,-14}" -f $grp.groupId
    }
    Write-Host $header -ForegroundColor Green
    Write-Host ("-" * [math]::Max(75, $header.Length)) -ForegroundColor DarkGray

    foreach ($feat in $features) {
        $row = " {0,-18} | {1,-34}" -f $feat.Id, $feat.Name
        foreach ($grp in $groups) {
            $val = 0
            if ($grp.features -is [System.Management.Automation.PSCustomObject]) {
                if ($grp.features.PSObject.Properties[$feat.Id]) {
                    $val = [int]$grp.features.$($feat.Id)
                }
            } elseif ($grp.features -is [System.Collections.IDictionary]) {
                if ($grp.features.Contains($feat.Id)) {
                    $val = [int]$grp.features[$feat.Id]
                }
            }
            $statusStr = if ($val -eq 1) { "[ 1 - BẬT ]" } else { "[ 0 - TẮT ]" }
            $row += " | {0,-14}" -f $statusStr
        }
        Write-Host $row
    }
    Write-Host "--------------------------------------------------------------------------------`n" -ForegroundColor DarkGray
}
