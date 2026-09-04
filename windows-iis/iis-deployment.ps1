<#
.SYNOPSIS
    Deploys/updates the Platform API website on IIS: creates the App Pool,
    Website, HTTPS binding, and points it at a deployment folder.

.DESCRIPTION
    Idempotent — safe to re-run. Used both for initial setup and for
    each deployment (copies new content, recycles the App Pool).

.PARAMETER SiteName
    IIS website name.

.PARAMETER AppPoolName
    IIS Application Pool name.

.PARAMETER SourcePath
    Path to the build output to deploy (e.g. a CI artifact drop location).

.PARAMETER PhysicalPath
    Path IIS will serve from.

.PARAMETER CertThumbprint
    Thumbprint of the SSL certificate to bind for HTTPS (443).

.EXAMPLE
    .\iis-deployment.ps1 -SiteName "PlatformAPI" -AppPoolName "PlatformAPIPool" `
        -SourcePath "C:\Deploy\platform-api\v1.2.0" `
        -PhysicalPath "C:\inetpub\wwwroot\platform-api" `
        -CertThumbprint "AB12CD34EF56..."
#>

param(
    [Parameter(Mandatory = $true)][string]$SiteName,
    [Parameter(Mandatory = $true)][string]$AppPoolName,
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$PhysicalPath,
    [Parameter(Mandatory = $false)][string]$CertThumbprint,
    [Parameter(Mandatory = $false)][int]$HttpsPort = 443
)

Import-Module WebAdministration -ErrorAction Stop

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Output "{`"timestamp`":`"$ts`",`"level`":`"$Level`",`"script`":`"iis-deployment`",`"message`":`"$Message`"}"
}

try {
    # ---- 1. App Pool: create if missing, otherwise reuse ----
    if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
        Write-Log "Creating App Pool: $AppPoolName"
        New-WebAppPool -Name $AppPoolName | Out-Null
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "managedRuntimeVersion" -Value ""
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "startMode" -Value "AlwaysRunning"
        # Auto-recovery: don't let a crashed pool stay stopped silently
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "failure.rapidFailProtection" -Value $true
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "failure.rapidFailProtectionInterval" -Value "00:05:00"
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name "failure.rapidFailProtectionMaxCrashes" -Value 5
    }
    else {
        Write-Log "App Pool $AppPoolName already exists, reusing"
    }

    # ---- 2. Physical path: ensure it exists ----
    if (-not (Test-Path $PhysicalPath)) {
        Write-Log "Creating physical path: $PhysicalPath"
        New-Item -ItemType Directory -Path $PhysicalPath -Force | Out-Null
    }

    # ---- 3. Deploy content ----
    # Recycle before file copy to release file locks, avoiding a
    # partially-updated app serving traffic mid-copy.
    if (Test-Path "IIS:\AppPools\$AppPoolName") {
        Write-Log "Stopping App Pool before deployment: $AppPoolName"
        Stop-WebAppPool -Name $AppPoolName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }

    Write-Log "Copying content from $SourcePath to $PhysicalPath"
    Copy-Item -Path "$SourcePath\*" -Destination $PhysicalPath -Recurse -Force

    # ---- 4. Website: create if missing ----
    if (-not (Test-Path "IIS:\Sites\$SiteName")) {
        Write-Log "Creating Website: $SiteName"
        New-Website -Name $SiteName -PhysicalPath $PhysicalPath -ApplicationPool $AppPoolName -Port 80 | Out-Null
    }
    else {
        Write-Log "Website $SiteName already exists, updating bindings/pool"
        Set-ItemProperty "IIS:\Sites\$SiteName" -Name "applicationPool" -Value $AppPoolName
        Set-ItemProperty "IIS:\Sites\$SiteName" -Name "physicalPath" -Value $PhysicalPath
    }

    # ---- 5. HTTPS binding ----
    if ($CertThumbprint) {
        $existingBinding = Get-WebBinding -Name $SiteName -Protocol "https" -ErrorAction SilentlyContinue
        if (-not $existingBinding) {
            Write-Log "Adding HTTPS binding on port $HttpsPort"
            New-WebBinding -Name $SiteName -Protocol "https" -Port $HttpsPort -SslFlags 1
        }
        Write-Log "Binding SSL certificate $CertThumbprint"
        $binding = Get-WebBinding -Name $SiteName -Protocol "https"
        $binding.AddSslCertificate($CertThumbprint, "my")
    }
    else {
        Write-Log "No CertThumbprint provided, skipping HTTPS binding" "WARN"
    }

    # ---- 6. Start everything back up ----
    Write-Log "Starting App Pool: $AppPoolName"
    Start-WebAppPool -Name $AppPoolName

    Write-Log "Starting Website: $SiteName"
    Start-Website -Name $SiteName

    # ---- 7. Verify ----
    Start-Sleep -Seconds 2
    $poolState = (Get-WebAppPoolState -Name $AppPoolName).Value
    if ($poolState -ne "Started") {
        throw "App Pool $AppPoolName did not reach Started state (current: $poolState)"
    }

    Write-Log "Deployment successful. Site: $SiteName, Pool: $AppPoolName, State: $poolState"
    exit 0
}
catch {
    Write-Log "Deployment failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
