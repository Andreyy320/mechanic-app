# deploy.ps1: версия +1, сборка, загрузка на сервер, публикация обновления
# Запуск:  .\deploy.ps1 "что нового"
param([string]$Notes = "")

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$Server = "root@194.156.66.100"
$Remote = "/var/www/app"
$ApkUrl = "http://194.156.66.100:5001/download/app.apk"
$Utf8   = New-Object System.Text.UTF8Encoding($false)

# 1. читаем версию из pubspec.yaml и увеличиваем
$pubPath = Join-Path $PSScriptRoot "pubspec.yaml"
$old = [System.IO.File]::ReadAllText($pubPath)
$m = [regex]::Match($old, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)')
if (-not $m.Success) { throw "Version line not found in pubspec.yaml" }

$build = [int]$m.Groups[4].Value + 1
$newVersion = "{0}.{1}.{2}+{3}" -f $m.Groups[1].Value, $m.Groups[2].Value, ([int]$m.Groups[3].Value + 1), $build
$new = ([regex]'(?m)^version:[^\r\n]*').Replace($old, "version: $newVersion", 1)
Write-Host "New version: $newVersion"
[System.IO.File]::WriteAllText($pubPath, $new, $Utf8)

# 2. сборка (если упала, возвращаем старую версию)
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    [System.IO.File]::WriteAllText($pubPath, $old, $Utf8)
    throw "Build failed. pubspec.yaml restored."
}

# 3. загрузка APK
scp build\app\outputs\flutter-apk\app-release.apk "${Server}:$Remote/app.apk"
if ($LASTEXITCODE -ne 0) { throw "APK upload failed" }

# 4. публикация: меняем version.json на сервере (только после загрузки APK)
$json = @{ version = $build; url = $ApkUrl; notes = $Notes } | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText("$PSScriptRoot\deploy-version.tmp", $json, $Utf8)
scp deploy-version.tmp "${Server}:$Remote/version.json"
$code = $LASTEXITCODE
Remove-Item deploy-version.tmp -ErrorAction SilentlyContinue
if ($code -ne 0) { throw "version.json upload failed" }

Write-Host "DONE. Version $newVersion published. Phones will see the update on next app start."