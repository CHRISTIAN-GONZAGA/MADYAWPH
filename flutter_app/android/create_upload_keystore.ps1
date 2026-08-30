# One-time Play upload keystore. Does not overwrite an existing keystore.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$keystore = Join-Path $here 'upload-keystore.jks'
$props = Join-Path $here 'key.properties'

if (Test-Path $keystore) {
    Write-Host "Keystore already exists: $keystore"
    exit 0
}

if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    Write-Error 'keytool not found. Install JDK 17 and add it to PATH.'
}

$bytes = New-Object byte[] 24
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$pass = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('/', 'A').Replace('+', 'B')

& keytool -genkeypair -v `
    -keystore $keystore `
    -storetype JKS `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -alias upload `
    -storepass $pass `
    -keypass $pass `
    -dname 'CN=MADYAW, OU=MADYAW, O=MADYAW PH, L=Philippines, ST=PH, C=PH'

@"
storePassword=$pass
keyPassword=$pass
keyAlias=upload
storeFile=../upload-keystore.jks
"@ | Set-Content -Path $props -Encoding ascii

Write-Host ""
Write-Host "Created $keystore and $props"
Write-Host "BACK THESE UP OFF THIS PC. Losing them means you cannot update MADYAW on Play."
Write-Host "Password is only in key.properties (gitignored)."
