#Requires -Version 5.1
<#
.SYNOPSIS
    Umao VDownloader 一键 Release 构建脚本
.DESCRIPTION
    构建 Windows (MSIX/EXE) 和 Android (APK) 的 Release 版本，
    并将产物复制到项目根目录的 release/ 目录。
.EXAMPLE
    .\build_release.ps1              # 同时构建 Windows + Android
    .\build_release.ps1 -Windows     # 仅构建 Windows
    .\build_release.ps1 -Android     # 仅构建 Android
#>
param(
    [switch]$Windows,
    [switch]$Android
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── 参数默认值：两个都不传则全部构建 ───────────────────────────────
if (-not $Windows -and -not $Android) {
    $Windows = $true
    $Android = $true
}

# ── 路径常量 ────────────────────────────────────────────────────────
$ProjectRoot = $PSScriptRoot
$ReleaseDir = Join-Path $ProjectRoot 'release'

# ── 从 pubspec.yaml 读取版本号 ──────────────────────────────────────
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$VersionLine = Get-Content $PubspecPath | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
if ($VersionLine -match '^version:\s*(.+?)\s*$') {
    $Version = $Matches[1] -replace '\+.*', ''   # 去掉 +build 部分
}
else {
    $Version = '0.0.0'
}
Write-Host "版本号: $Version" -ForegroundColor Cyan

# ── 通用函数 ────────────────────────────────────────────────────────
function Invoke-Step([string]$Name, [scriptblock]$Block) {
    Write-Host "`n── $Name ──" -ForegroundColor Yellow
    & $Block
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Error "$Name 失败，退出码 $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

function Copy-Artifact([string]$Src, [string]$DestName) {
    if (-not (Test-Path $Src)) {
        Write-Warning "产物不存在，跳过复制: $Src"
        return
    }
    $Dest = Join-Path $ReleaseDir $DestName
    Copy-Item -Force $Src $Dest
    Write-Host "已复制: $DestName" -ForegroundColor Green
}

# ── 准备 release/ 目录 ──────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null

# ── 切换到项目根目录 ────────────────────────────────────────────────
Push-Location $ProjectRoot
try {

    # ── flutter pub get ─────────────────────────────────────────────
    Invoke-Step 'flutter pub get' {
        flutter pub get
    }

    # ════════════════════════════════════════════════════════════════
    #  Windows Release（生成 \build\windows\x64\runner\Release\*.exe）
    # ════════════════════════════════════════════════════════════════
    if ($Windows) {
        Invoke-Step '构建 Windows Release' {
            flutter build windows --release
        }

        $WinExeSrc = Join-Path $ProjectRoot 'build\windows\x64\runner\Release\UmaoVDown.exe'
        Copy-Artifact $WinExeSrc "UmaoVDown_v${Version}.exe"

        # 如果有 MSIX 产物也一并复制
        $WinMsixSrc = Join-Path $ProjectRoot 'build\windows\x64\runner\Release\UmaoVDown.msix'
        if (Test-Path $WinMsixSrc) {
            Copy-Artifact $WinMsixSrc "UmaoVDown_v${Version}.msix"
        }

        # 打包 installer 目录为 zip（包含所有运行时依赖）
        $WinReleaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
        $WinZipDest = Join-Path $ReleaseDir "UmaoVDown_v${Version}.zip"
        if (Test-Path $WinReleaseDir) {
            Write-Host '正在打包 Windows 运行目录为 ZIP…' -ForegroundColor DarkCyan
            Compress-Archive -Force -Path "$WinReleaseDir\*" -DestinationPath $WinZipDest
            Write-Host "已生成: UmaoVDown_v${Version}.zip" -ForegroundColor Green
        }
    }

    # ════════════════════════════════════════════════════════════════
    #  Android Release APK（生成 build/app/outputs/flutter-apk/*.apk）
    # ════════════════════════════════════════════════════════════════
    if ($Android) {
        Invoke-Step '构建 Android Release APK' {
            flutter build apk --release --split-per-abi
        }

        $ApkDir = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk'
        $Apks = @(
            @{ Src = 'app-arm64-v8a-release.apk'; Dest = "UmaoVDown_arm64_v${Version}.apk" }
            @{ Src = 'app-armeabi-v7a-release.apk'; Dest = "UmaoVDown_armv7_v${Version}.apk" }
            @{ Src = 'app-x86_64-release.apk'; Dest = "UmaoVDown_x86_64_v${Version}.apk" }
            @{ Src = 'app-release.apk'; Dest = "UmaoVDown_universal_v${Version}.apk" }
        )
        foreach ($entry in $Apks) {
            $src = Join-Path $ApkDir $entry.Src
            if (Test-Path $src) {
                Copy-Artifact $src $entry.Dest
            }
        }
    }

    # ── 完成汇总 ────────────────────────────────────────────────────
    Write-Host "`n✅ 构建完成！产物目录: $ReleaseDir" -ForegroundColor Green
    Get-ChildItem $ReleaseDir | Format-Table Name, @{L = '大小'; E = { "{0:N0} KB" -f ($_.Length / 1KB) } } -AutoSize

}
finally {
    Pop-Location
}
