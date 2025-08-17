[CmdletBinding()]
param(
  [string]$SiteName       = "TestAppLocal",
  [string]$AppPoolName    = "TestAppPool",
  [string]$PhysicalPath   = "C:\inetpub\wwwroot\TestApp",
  [string]$EventLogSource = "TestApp",
  [switch]$RemoveAllVersions
)

function Use-WebAdmin {
  try { Import-Module WebAdministration -ErrorAction Stop; return $true } catch { return $false }
}
$haveWebAdmin = Use-WebAdmin
$appcmd = Join-Path $env:windir "System32\inetsrv\appcmd.exe"

Write-Host "== Teardown IIS Test App ==" -ForegroundColor Cyan

# Offline to release locks
try { if (Test-Path $PhysicalPath) { Set-Content (Join-Path $PhysicalPath "app_offline.htm") "<h2>Offline</h2>" -ErrorAction SilentlyContinue } } catch {}
Start-Sleep -Seconds 2

# Stop site + pool
try {
  if ($haveWebAdmin) {
    if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) { Stop-Website -Name $SiteName -ErrorAction SilentlyContinue }
    if (Get-Item "IIS:\AppPools\$AppPoolName" -ErrorAction SilentlyContinue) { Stop-WebAppPool -Name $AppPoolName -ErrorAction SilentlyContinue }
  } elseif (Test-Path $appcmd) {
    & $appcmd stop site /site.name:"$SiteName" | Out-Null
    & $appcmd stop apppool /apppool.name:"$AppPoolName" | Out-Null
  }
} catch {}

# Remove site
try {
  if ($haveWebAdmin) {
    if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) { Remove-Website -Name $SiteName -Confirm:$false }
  } elseif (Test-Path $appcmd) {
    & $appcmd delete site "$SiteName" | Out-Null
  }
} catch {}

# Remove app pool
try {
  if ($haveWebAdmin) {
    if (Get-Item "IIS:\AppPools\$AppPoolName" -ErrorAction SilentlyContinue) { Remove-WebAppPool -Name $AppPoolName -Confirm:$false }
  } elseif (Test-Path $appcmd) {
    & $appcmd delete apppool "$AppPoolName" | Out-Null
  }
} catch {}

# Delete files
try {
  if (Test-Path $PhysicalPath) {
    Remove-Item -Recurse -Force (Join-Path $PhysicalPath "logs") -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $PhysicalPath -ErrorAction SilentlyContinue
  }
  if ($RemoveAllVersions) {
    $parent = Split-Path $PhysicalPath -Parent
    $name   = Split-Path $PhysicalPath -Leaf
    Get-ChildItem -Path $parent -Filter "$name*" -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -ne $PhysicalPath } |
      ForEach-Object { try { Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue } catch {} }
  }
} catch {}

# Remove Event Log source
try {
  if ($EventLogSource -and [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
    [System.Diagnostics.EventLog]::DeleteEventSource($EventLogSource)
    Write-Host "Removed Event Log source '$EventLogSource'." -ForegroundColor Green
  }
} catch {
  Write-Host "Could not remove Event Log source '$EventLogSource': $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "Teardown complete." -ForegroundColor Green
