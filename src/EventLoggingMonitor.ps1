[CmdletBinding()]
param(
  [string]$ProviderName = "",               # "" to print everything first, then set e.g. "IIS AspNetCore Module V2"
  [string]$Pattern = "500\.37",             # Regex to detect
  [int]$IntervalMs = 1000,

  # IIS recycle target (use this on IIS)
  [string]$AppPoolName = "",                # e.g., "MySitePool"
  [string]$WarmupUrl = "",                  # e.g., "http://localhost/healthz"
  [int]$RestartCooldownSeconds = 5,

  # Alternative restart modes (use only if not using AppPoolName)
  [string]$ServiceName = "",
  [string]$RestartCommand = ""
)

function Invoke-IISRecycle {
  param([string]$Pool)
  if (-not $Pool) { return $false }
  try {
    if (Get-Module -ListAvailable -Name WebAdministration) {
      Import-Module WebAdministration -ErrorAction Stop
      Write-Host "Recycling IIS App Pool '$Pool'..." -ForegroundColor Yellow
      Restart-WebAppPool -Name $Pool
    } else {
      $appcmd = Join-Path $env:windir "System32\inetsrv\appcmd.exe"
      Write-Host "Recycling via appcmd '$Pool'..." -ForegroundColor Yellow
      & $appcmd recycle apppool /apppool.name:"$Pool" | Out-Null
    }
    Write-Host "App Pool '$Pool' recycled." -ForegroundColor Green
    return $true
  } catch {
    Write-Host "IIS recycle failed: $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }
}

function Do-Restart {
  Start-Sleep -Seconds $RestartCooldownSeconds
  if ($AppPoolName) {
    $ok = Invoke-IISRecycle -Pool $AppPoolName
    if ($ok -and $WarmupUrl) {
      try {
        Write-Host "Warming up $WarmupUrl ..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $WarmupUrl -UseBasicParsing -TimeoutSec 15 | Out-Null
        Write-Host "Warmup OK." -ForegroundColor Green
      } catch {
        Write-Host "Warmup failed: $($_.Exception.Message)" -ForegroundColor Yellow
      }
    }
    return
  }
  if ($ServiceName)     { Restart-Service -Name $ServiceName -Force; Write-Host "Service restarted." -ForegroundColor Green; return }
  if ($RestartCommand)  { Start-Process powershell -ArgumentList "-NoProfile","-Command",$RestartCommand | Out-Null; Write-Host "Restart command issued." -ForegroundColor Green; return }
  Write-Host "No restart mode configured; skipping." -ForegroundColor Yellow
}

$logName = "Application"
Write-Host "Listening on '$logName' | Provider='$ProviderName' | Pattern='$Pattern' | Poll=${IntervalMs}ms" -ForegroundColor Cyan

# Start at tail so we only see NEW events
$last = Get-WinEvent -LogName $logName -MaxEvents 1 -ErrorAction SilentlyContinue
$lastId = if ($last) { $last.RecordId } else { 0 }

while ($true) {
  try {
    $xpath = if ([string]::IsNullOrWhiteSpace($ProviderName)) {
      "*[System[EventRecordID>$lastId]]"
    } else {
      "*[System[Provider[@Name='$ProviderName'] and EventRecordID>$lastId]]"
    }
    $events = Get-WinEvent -LogName $logName -FilterXPath $xpath -ErrorAction SilentlyContinue
    foreach ($e in $events) {
      $msg  = try { $e.FormatDescription() } catch { $e.ToXml() }
      $prov = $e.ProviderName
      $ts   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
      Write-Host "[$ts] [$prov] $msg"

      if ($msg -match $Pattern) {
        Write-Host "[$ts] [MATCH] '$Pattern' -> recycle in $RestartCooldownSeconds s..." -ForegroundColor Red
        Do-Restart
      }
      if ($e.RecordId -gt $lastId) { $lastId = $e.RecordId }
    }
  } catch {
    Write-Host "[WARN] Poll error: $($_.Exception.Message)" -ForegroundColor Yellow
  }
  Start-Sleep -Milliseconds $IntervalMs
}
