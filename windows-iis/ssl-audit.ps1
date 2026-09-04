<#
.SYNOPSIS
    Audits certificates in the local machine cert store bound to IIS
    sites, flags anything expiring soon, and logs WARNING/CRITICAL.

.DESCRIPTION
    Resolves Incident INC-003 (SSL certificate expiry) — see
    ../incidents/INC-003-ssl-expiry.md. Meant to run daily as a
    Scheduled Task.

.PARAMETER WarningDays
    Days-to-expiry threshold for a WARNING.

.PARAMETER CriticalDays
    Days-to-expiry threshold for CRITICAL.

.PARAMETER SiteName
    Optional. If given, only audits the certificate bound to this
    site's HTTPS binding rather than every cert in the store.

.EXAMPLE
    .\ssl-audit.ps1 -WarningDays 30 -CriticalDays 7
#>

param(
    [Parameter(Mandatory = $false)][int]$WarningDays = 30,
    [Parameter(Mandatory = $false)][int]$CriticalDays = 7,
    [Parameter(Mandatory = $false)][string]$SiteName,
    [Parameter(Mandatory = $false)][string]$EventLogSource = "PlatformAPIMonitor"
)

Import-Module WebAdministration -ErrorAction Stop

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Output "{`"timestamp`":`"$ts`",`"level`":`"$Level`",`"script`":`"ssl-audit`",`"message`":`"$Message`"}"
}

function Write-IncidentEvent {
    param([string]$Message, [string]$EntryType = "Warning")
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
        New-EventLog -LogName Application -Source $EventLogSource
    }
    Write-EventLog -LogName Application -Source $EventLogSource -EntryType $EntryType -EventId 9002 -Message $Message
}

try {
    if ($SiteName) {
        $binding = Get-WebBinding -Name $SiteName -Protocol "https" -ErrorAction Stop
        $thumbprints = @($binding.certificateHash)
        Write-Log "Auditing certificate bound to site '$SiteName'"
    }
    else {
        $thumbprints = (Get-ChildItem -Path Cert:\LocalMachine\My | Select-Object -ExpandProperty Thumbprint)
        Write-Log "Auditing all certificates in Cert:\LocalMachine\My ($($thumbprints.Count) found)"
    }

    $results = @()
    $hasCritical = $false
    $hasWarning = $false

    foreach ($thumb in $thumbprints) {
        $cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$thumb" -ErrorAction SilentlyContinue
        if (-not $cert) { continue }

        $remaining = ($cert.NotAfter - (Get-Date)).Days
        $status = "OK"

        if ($remaining -le $CriticalDays) {
            $status = "CRITICAL"
            $hasCritical = $true
        }
        elseif ($remaining -le $WarningDays) {
            $status = "WARNING"
            $hasWarning = $true
        }

        $result = [PSCustomObject]@{
            Subject       = $cert.Subject
            Thumbprint    = $cert.Thumbprint
            ExpiresOn     = $cert.NotAfter.ToString("yyyy-MM-dd")
            RemainingDays = $remaining
            Status        = $status
        }
        $results += $result

        $msg = "Certificate: $($cert.Subject) | Expires: $($cert.NotAfter.ToString('yyyy-MM-dd')) | Remaining: $remaining days | Status: $status"

        switch ($status) {
            "CRITICAL" { Write-Log $msg "ERROR" }
            "WARNING"  { Write-Log $msg "WARN" }
            default    { Write-Log $msg "INFO" }
        }
    }

    if ($hasCritical) {
        $criticalCerts = ($results | Where-Object { $_.Status -eq "CRITICAL" } | ForEach-Object { "$($_.Subject) ($($_.RemainingDays)d)" }) -join "; "
        Write-IncidentEvent -Message "CRITICAL: certificate(s) expiring within $CriticalDays days: $criticalCerts" -EntryType "Error"
    }
    elseif ($hasWarning) {
        $warningCerts = ($results | Where-Object { $_.Status -eq "WARNING" } | ForEach-Object { "$($_.Subject) ($($_.RemainingDays)d)" }) -join "; "
        Write-IncidentEvent -Message "WARNING: certificate(s) expiring within $WarningDays days: $warningCerts" -EntryType "Warning"
    }

    $results | Format-Table -AutoSize | Out-String | Write-Output

    if ($hasCritical) { exit 2 }
    if ($hasWarning) { exit 1 }
    exit 0
}
catch {
    Write-Log "SSL audit failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
