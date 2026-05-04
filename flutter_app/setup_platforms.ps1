# Adds Android/iOS/etc. folders to this Flutter app. Requires Flutter SDK on PATH.
# Run from repository root:  powershell -ExecutionPolicy Bypass -File flutter_app/setup_platforms.ps1
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "Install Flutter: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Red
    exit 1
}
Write-Host "Running flutter create . (adds missing platform projects)..." -ForegroundColor Cyan
flutter create . --project-name gloretto_mobile --org com.gloretto
Write-Host "Done. Next: flutter pub get && flutter run" -ForegroundColor Green
