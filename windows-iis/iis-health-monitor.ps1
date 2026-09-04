<#
.SYNOPSIS
    Detects a stopped IIS App Pool, restarts it, verifies the site
    responds, and logs the remediation. Designed to run as a Scheduled
    Task every 1-2 minutes, or on-demand during an incident.

.DESCRIPTION
    This is the automated response to Incident INC-002 (IIS App Pool
    stopped) — see ../incidents/INC-002-iis-app-pool.md for the full
    incident writeup this script resolves.

.PARAMETER AppPoolName
    App Pool to monitor.

.PARAMETER SiteName
    Website to verify after restart.

.PARAMETER HealthCheckUrl
    Local URL to curl after restart to confirm the app actually responds
    (not just that the App Pool process exists).

.PARAMETER MaxRestartAttempts
    How many times to retry before giving up and alerting.

.EXAMPLE
    .\iis-health-monitor.ps1 -AppPoolName "PlatformAPIPool" -SiteName "PlatformAPI" `
        -HealthCheckUrl "http://localhost/health"
#>

param(
    [Parameter(Mandatory = $true)][string]$AppPoolName,
    [Parameter(Mandatory = $true)][string]$SiteName,
    [Parameter(Mandatory = $false)][string]$HealthCheckUrl = "http://localhost/health",
    [Parameter(Mandatory = $false)][int]$MaxRestartAttempts = 3,
    [Parameter(Mandatory = $false)][string]$EventLogSource = "PlatformAPIMonitor"
)

Import-Module WebAdministration -ErrorAction Stop

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Output "{`"timestamp`":`"$ts`",`"level`":`"$Level`",`"script`":`"iis-health-monitor`",`"message`":`"$Message`"}"
}

function Write-IncidentEvent {
    param([string]$Message, [string]$EntryType = "Warning")
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
        New-EventLog -LogName Application -Source $EventLogSource
    }
    Write-EventLog -LogName Application -Source $EventLogSource -EntryType $EntryType -EventId 9001 -Message $Message
}

try {
    $state = (Get-WebAppPoolState -Name $AppPoolName).Value
    Write-Log "Checked App Pool '$AppPoolName' -> state: $state"

    if ($state -eq "Started") {
        Write-Log "App Pool healthy, no action needed"
        exit 0
    }

    # ---- App Pool is stopped/unknown: this is the incident ----
    Write-Log "App Pool '$AppPoolName' is NOT running (state: $state). Beginning remediation." "ERROR"
    Write-IncidentEvent -Message "App Pool '$AppPoolName' detected stopped. Auto-remediation starting." -EntryType "Error"

    $attempt = 0
    $recovered = $false

    while ($attempt -lt $MaxRestartAttempts -and -not $recovered) {
        $attempt++
        Write-Log "Restart attempt $attempt of $MaxRestartAttempts"

        try {
            Start-WebAppPool -Name $AppPoolName -ErrorAction Stop
        }
        catch {
            Write-Log "Start-WebAppPool threw: $($_.Exception.Message)" "WARN"
        }

        Start-Sleep -Seconds 5
        $state = (Get-WebAppPoolState -Name $AppPoolName).Value

        if ($state -ne "Started") {
            Write-Log "App Pool still not started after attempt $attempt (state: $state)" "WARN"
            continue
        }

        # Process-level restart succeeded — now confirm the app actually
        # answers requests, not just that IIS thinks the pool is running.
        try {
            $response = Invoke-WebRequest -Uri $HealthCheckUrl -UseBasicParsing -TimeoutSec 10
            if ($response.StatusCode -eq 200) {
                $recovered = $true
                Write-Log "Health check passed after restart (HTTP $($response.StatusCode))"
            }
            else {
                Write-Log "Health check returned HTTP $($response.StatusCode), not yet healthy" "WARN"
            }
        }
        catch {
            Write-Log "Health check request failed: $($_.Exception.Message)" "WARN"
        }
    }

    if ($recovered) {
        $msg = "App Pool '$AppPoolName' auto-remediated successfully after $attempt attempt(s)."
        Write-Log $msg
        Write-IncidentEvent -Message $msg -EntryType "Information"
        exit 0
    }
    else {
        $msg = "App Pool '$AppPoolName' FAILED to recover after $MaxRestartAttempts attempts. Manual intervention required."
        Write-Log $msg "ERROR"
        Write-IncidentEvent -Message $msg -EntryType "Error"
        # Non-zero exit so a Scheduled Task failure / alerting pipeline
        # picks this up as a page-worthy event.
        exit 1
    }
}
catch {
    Write-Log "Monitor script itself failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
