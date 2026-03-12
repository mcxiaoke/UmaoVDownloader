#Requires -Version 5.1
<#
.SYNOPSIS
    Umao VDownloader 一键 Release 构建脚本
.DESCRIPTION
    构建 Windows (MSIX/EXE) 和 Android (APK) 的 Release 版本，
    并将产物复制到项目根目录的 release/ 目录。
.EXAMPLE
    .\build_release.ps1              # 同时构建 Windows + Android + CLI
    .\build_release.ps1 -Windows     # 仅构建 Windows
    .\build_release.ps1 -Android     # 仅构建 Android
    .\build_release.ps1 -CLI         # 仅编译 umao_vd CLI 工具 (Windows x64)
#>
param(
    [switch]$Windows,
    [switch]$Android,
    [switch]$CLI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── 参数默认值：三个都不传则全部构建 ───────────────────────────────
if (-not $Windows -and -not $Android -and -not $CLI) {
    $Windows = $true
    $Android = $true
    $CLI = $true
}

# ── 路径常量 ────────────────────────────────────────────────────────
$ProjectRoot = $PSScriptRoot
$ReleaseDir = Join-Path $ProjectRoot 'release'

# ── 从 pubspec.yaml 读取版本号并自动递增 patch ──────────────────────
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$VersionLine = Get-Content $PubspecPath | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
if ($VersionLine -match '^(version:\s*)(\d+)\.(\d+)\.(\d+)(\+\d+)?\s*$') {
    $Major = [int]$Matches[2]
    $Minor = [int]$Matches[3]
    $Patch = [int]$Matches[4] + 1          # patch 加 1
    $BuildNum = if ($Matches[5]) { '+' + ([int]($Matches[5] -replace '\+', '') + 1) } else { '+1' }
    $Version = "$Major.$Minor.$Patch"
    # 回写 pubspec.yaml
    $PubspecContent = Get-Content $PubspecPath -Encoding UTF8
    $PubspecContent = $PubspecContent -replace '^version:\s*.+', "$($Matches[1])${Version}${BuildNum}"
    $PubspecContent | Set-Content $PubspecPath -Encoding UTF8
    Write-Host "版本号: $Version  (已自动递增 patch)" -ForegroundColor Cyan
}
else {
    $Version = '0.0.0'
    Write-Warning "无法解析 pubspec.yaml 版本号，使用默认值 0.0.0"
}

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

        # 如果有 MSIX 产物也一并复制
        $WinMsixSrc = Join-Path $ProjectRoot 'build\windows\x64\runner\Release\UmaoVDown.msix'
        if (Test-Path $WinMsixSrc) {
            Copy-Artifact $WinMsixSrc "UmaoVDown_x64_v${Version}.msix"
        }

        # 打包 installer 目录为 7z（包含所有运行时依赖）
        $WinReleaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
        $Win7zDest = Join-Path $ReleaseDir "UmaoVDown_x64_v${Version}.7z"
        if (Test-Path $WinReleaseDir) {
            if (Get-Command '7z' -ErrorAction SilentlyContinue) {
                Write-Host '正在打包 Windows 运行目录为 7z…' -ForegroundColor DarkCyan
                & 7z a -mx=9 $Win7zDest "$WinReleaseDir\*" | Out-Null
                Write-Host "已生成: UmaoVDown_x64_v${Version}.7z" -ForegroundColor Green
            }
            else {
                Write-Warning '未找到 7z，跳过打包（请安装 7-Zip 并确保 7z.exe 在 PATH 中）'
            }
        }
    }

    # ════════════════════════════════════════════════════════════════
    #  CLI 工具 umao_vd（dart compile exe，仅支持当前主机平台）
    #  Linux 版需在 Linux / WSL 上执行：
    #    dart compile exe cli/umao_vd.dart -o release/umao_vd_linux_x64_vX.X.X
    # ════════════════════════════════════════════════════════════════
    if ($CLI) {
        $CliExeOut = Join-Path $ProjectRoot "build\umao_vd_x64.exe"
        Invoke-Step '编译 umao_vd CLI (dart compile exe)' {
            dart compile exe cli/umao_vd.dart -o $CliExeOut
        }

        $CliDestName = "umao_vd_x64_v${Version}.exe"
        Copy-Artifact $CliExeOut $CliDestName

        # 打包为 7z（需要 7z.exe 在 PATH 中）
        $Cli7zDest = Join-Path $ReleaseDir "umao_vd_x64_v${Version}.7z"
        if (Get-Command '7z' -ErrorAction SilentlyContinue) {
            Write-Host '正在打包 CLI 为 7z…' -ForegroundColor DarkCyan
            & 7z a -mx=9 $Cli7zDest (Join-Path $ReleaseDir $CliDestName) | Out-Null
            Write-Host "已生成: umao_vd_x64_v${Version}.7z" -ForegroundColor Green
        }
        else {
            Write-Warning '未找到 7z，跳过 7z 打包（请安装 7-Zip 并确保 7z.exe 在 PATH 中）'
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
