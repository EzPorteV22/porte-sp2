# PorteSP - instalador
# Uso:  irm https://raw.githubusercontent.com/USUARIO/REPO/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # acelera mucho Invoke-WebRequest en PS 5.1

# ---- CONFIG (editar) ----------------------------------------------------
$ExeUrl   = 'https://github.com/EzPorteV22/porte-sp2/releases/latest/download/PorteSP.exe'
$Sha256   = '2b44870846aa01105f9ca3279570166fb5c84f7223ce944f17cb19fc6dd7f467'  # actualizar en cada version nueva
$AppName  = 'PorteSP'
$InstallDir = Join-Path $env:LOCALAPPDATA $AppName
$ExePath  = Join-Path $InstallDir "$AppName.exe"
# -------------------------------------------------------------------------

function Test-WebView2 {
    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )
    foreach ($k in $keys) {
        if (Test-Path $k) {
            $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).pv
            if ($v -and $v -ne '0.0.0.0') { return $true }
        }
    }
    return $false
}

Write-Host ''
Write-Host "  $AppName" -ForegroundColor White
Write-Host '  ------------------------------' -ForegroundColor DarkGray

# 1) WebView2 (la interfaz lo necesita)
if (-not (Test-WebView2)) {
    Write-Host '  Instalando Microsoft WebView2...' -ForegroundColor Yellow
    $wv = Join-Path $env:TEMP 'MicrosoftEdgeWebview2Setup.exe'
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $wv -UseBasicParsing
    Start-Process -FilePath $wv -ArgumentList '/silent','/install' -Wait
    Remove-Item $wv -Force -ErrorAction SilentlyContinue
}

# 2) Descargar el .exe
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
$tmp = Join-Path $env:TEMP "$AppName.download.exe"
Write-Host '  Descargando...' -ForegroundColor Cyan
if (Test-Path $tmp) { Remove-Item $tmp -Force }

function Get-FileRobust($url, $out) {
    # 1) curl.exe (viene con Windows 10/11, maneja bien los redirects de GitHub)
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $curl) {
        try {
            & $curl -L --fail --retry 3 --silent --show-error -o $out $url
            if ($LASTEXITCODE -eq 0 -and (Test-Path $out)) { return $true }
        } catch { }
    }
    # 2) BITS
    try {
        Start-BitsTransfer -Source $url -Destination $out -ErrorAction Stop
        if (Test-Path $out) { return $true }
    } catch { }
    # 3) Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
        if (Test-Path $out) { return $true }
    } catch { }
    return $false
}

if (-not (Get-FileRobust $ExeUrl $tmp)) {
    throw "No se pudo descargar $ExeUrl. Verifica que la release este publicada (no borrador) y que el archivo se llame PorteSP.exe."
}

# 3) Verificar integridad
$hash = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $Sha256.ToLower()) {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    throw "El archivo descargado no coincide con el hash esperado ($hash). Instalacion cancelada."
}

# 4) Instalar (cerrar la app si esta abierta)
Get-Process -Name $AppName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Move-Item -Path $tmp -Destination $ExePath -Force

# 5) Acceso directo en el escritorio
try {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk"
    $sh  = New-Object -ComObject WScript.Shell
    $sc  = $sh.CreateShortcut($lnk)
    $sc.TargetPath = $ExePath
    $sc.WorkingDirectory = $InstallDir
    $sc.IconLocation = "$ExePath,0"
    $sc.Save()
} catch { }

Write-Host '  Listo. Abriendo...' -ForegroundColor Green
Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir
