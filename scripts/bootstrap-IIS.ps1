[CmdletBinding()]
param(
  # === Required ===
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,                                  # e.g., C:\dev\TestApp\TestApp.csproj

  # === IIS objects ===
  [string]$SiteName     = "TestAppLocal",
  [string]$AppPoolName  = "TestAppPool",
  [int]   $Port         = 8080,
  [string]$PublishPath  = "C:\inetpub\wwwroot\TestApp",  # site physical path

  # === Web.config tweaks (optional) ===
  [int]$StartupTimeLimitSeconds = 0,                     # set >0 to write startupTimeLimit (helps 500.37 tests)
  [switch]$EnableStdoutLogs,                             # turns on stdout logging to .\logs\stdout*

  # === Warmup ===
  [string]$WarmupUrl = "",                               # e.g., http://localhost:8080/

  # === Event Log source (optional; only if your app logs to EventLog) ===
  [string]$EventLogSource = ""                           # e.g., "TestApp"
)

function Use-WebAdmin {
  try { Import-Module WebAdministration -ErrorAction Stop; return $true } catch { return $false }
}

function Ensure-Dir($path) {
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}

function Grant-AppPoolPerms {
  param([string]$Path,[string]$Pool)
  $acct = "IIS AppPool\$Pool"
  Write-Host "Granting Modify to '$acct' on '$Path'..." -ForegroundColor Yellow
  & icacls $Path /grant "$acct:(OI)(CI)(M)" /T | Out-Null
}

function Publish-App {
  param([string]$Csproj,[string]$Out)
  Write-Host "Publishing $Csproj -> $Out ..." -ForegroundColor Yellow
  & dotnet publish $Csproj -c Release -o $Out | Write-Host
  if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }
}

function Take-AppOffline {
  param([string]$Root)
  Set-Content -Path (Join-Path $Root "app_offline.htm") -Value "<h2>Updating…</h2>" -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}
function Bring-AppOnline {
  param([string]$Root)
  Remove-Item (Join-Path $Root "app_offline.htm") -ErrorAction SilentlyContinue
}

function Ensure-SiteAndPool {
  param([string]$Site,[string]$Pool,[int]$Port,[string]$Path,[bool]$HaveWebAdmin)

  if ($HaveWebAdmin) {
    # App Pool
    if (Get-Item "IIS:\AppPools\$Pool" -ErrorAction SilentlyContinue) {
      Write-Host "App Pool '$Pool' exists." -ForegroundColor DarkGray
    } else {
      New-WebAppPool -Name $Pool | Out-Null
    }
    Set-ItemProperty "IIS:\AppPools\$Pool" -Name managedRuntimeVersion -Value ""    # No Managed Code
    Set-ItemProperty "IIS:\AppPools\$Pool" -Name startMode -Value "AlwaysRunning"

    # Website
    $existing = Get-Website -Name $Site -ErrorAction SilentlyContinue
    if ($existing) {
      Write-Host "Site '$Site' exists -> updating physicalPath/bindings/appPool" -ForegroundColor DarkGray
      if ($existing.physicalPath -ne $Path) {
        Set-ItemProperty "IIS:\Sites\$Site" -Name physicalPath -Value $Path
      }
      if ($existing.Bindings.Collection.bindingInformation -notmatch ":$Port:") {
        # reset binding to http/*:$Port
        Remove-WebBinding -Name $Site -Protocol "http" -Port $existing.Bindings.Collection.bindingInformation.Split(':')[1] -ErrorAction SilentlyContinue
        New-WebBinding -Name $Site -Protocol "http" -Port $Port -IPAddress "*" -HostHeader ""
      }
      Set-ItemProperty "IIS:\Sites\$Site" -Name applicationPool -Value $Pool
    } else {
      New-Website -Name $Site -Port $Port -PhysicalPath $Path -ApplicationPool $Pool -Force | Out-Null
    }
  } else {
    $appcmd = Join-Path $env:windir "System32\inetsrv\appcmd.exe"
    if (-not (Test-Path $appcmd)) { throw "Neither WebAdministration module nor appcmd.exe available." }

    # App Pool
    & $appcmd list apppool "$Pool" | Out-Null
    if ($LASTEXITCODE -ne 0) { & $appcmd add apppool /name:$Pool | Out-Null }
    & $appcmd set apppool "$Pool" /managedRuntimeVersion:"" | Out-Null

    # Website
    & $appcmd list site "$Site" | Out-Null
    if ($LASTEXITCODE -ne 0) {
      & $appcmd add site /name:$Site /bindings:"http/*:$Port:" /physicalPath:"$Path" | Out-Null
    } else {
      & $appcmd set site "$Site" /+bindings.[protocol='http',bindingInformation='*:$Port:'] | Out-Null
      & $appcmd set site "$Site" /applicationDefaults.applicationPool:"$Pool" | Out-Null
      & $appcmd set site "$Site" /physicalPath:"$Path" | Out-Null
    }
  }
}

function Update-WebConfig {
  param([string]$Root,[int]$StartupTimeLimitSeconds,[switch]$EnableStdoutLogs)
  $cfgPath = Join-Path $Root "web.config"
  if (-not (Test-Path $cfgPath)) { Write-Host "web.config not found at $cfgPath (skipping tweaks)" -ForegroundColor Yellow; return }

  [xml]$xml = Get-Content $cfgPath
  $asp = $xml.configuration.'system.webServer'.aspNetCore
  if (-not $asp) {
    Write-Host "aspNetCore section missing (skipping tweaks)" -ForegroundColor Yellow
  } else {
    if ($StartupTimeLimitSeconds -gt 0) {
      $asp.SetAttribute("startupTimeLimit", [string]$StartupTimeLimitSeconds) | Out-Null
    }
    if ($EnableStdoutLogs) {
      $asp.SetAttribute("stdoutLogEnabled", "true") | Out-Null
      $asp.SetAttribute("stdoutLogFile", ".\logs\stdout") | Out-Null
      Ensure-Dir (Join-Path $Root "logs")
    }
    $xml.Save($cfgPath)
  }
}

function Warmup-Url($url) {
  if ([string]::IsNullOrWhiteSpace($url)) { return }
  try {
    Write-Host "Warming up $url ..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15 | Out-Null
    Write-Host "Warmup OK." -ForegroundColor Green
  } catch {
    Write-Host "Warmup failed: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

function Ensure-EventLogSource($source) {
  if ([string]::IsNullOrWhiteSpace($source)) { return }
  try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
      [System.Diagnostics.EventLog]::CreateEventSource($source, "Application")
      Write-Host "Created Event Log source '$source'." -ForegroundColor Green
    }
  } catch {
    Write-Host "Could not create Event Log source '$source': $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# ================== Main ==================
Write-Host "== Bootstrap IIS Test App ==" -ForegroundColor Cyan
$haveWebAdmin = Use-WebAdmin
Ensure-Dir $PublishPath

# Take offline if re-deploying into same folder
Take-AppOffline -Root $PublishPath

# Publish
Publish-App -Csproj $ProjectPath -Out $PublishPath

# Create/Update IIS objects
Ensure-SiteAndPool -Site $SiteName -Pool $AppPoolName -Port $Port -Path $PublishPath -HaveWebAdmin $haveWebAdmin

# Permissions for the app pool identity
Grant-AppPoolPerms -Path $PublishPath -Pool $AppPoolName

# Web.config tweaks (optional)
Update-WebConfig -Root $PublishPath -StartupTimeLimitSeconds $StartupTimeLimitSeconds -EnableStdoutLogs:$EnableStdoutLogs

# Bring online + recycle
Bring-AppOnline -Root $PublishPath
if ($haveWebAdmin) {
  Restart-WebAppPool -Name $AppPoolName
} else {
  & (Join-Path $env:windir "System32\inetsrv\appcmd.exe") recycle apppool /apppool.name:"$AppPoolName" | Out-Null
}

# Warmup & EventLog source
if (-not $WarmupUrl) { $WarmupUrl = "http://localhost:$Port/" }
Warmup-Url $WarmupUrl
Ensure-EventLogSource -source $EventLogSource

Write-Host "`nDone. Site: http://localhost:$Port/  Pool: $AppPoolName  Path: $PublishPath" -ForegroundColor Green
Write-Host "To test 500.37: temporarily add a startup delay in Program.cs and set -StartupTimeLimitSeconds small (e.g., 5)." -ForegroundColor DarkGray