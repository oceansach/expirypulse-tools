<#
.SYNOPSIS
    Exports Entra ID app registration secret and certificate expiry dates
    to a CSV file ready for import into ExpiryPulse.

.DESCRIPTION
    Connects to Microsoft Graph and retrieves all app registrations
    in your tenant. Extracts client secrets (password credentials)
    and certificates (key credentials) with their expiry dates,
    then exports them in ExpiryPulse's import format.
    Optionally exports a separate audit CSV for apps with no trackable
    credentials using the -IncludeAudit switch.

.REQUIREMENTS
    Microsoft.Graph PowerShell SDK
    Install-Module Microsoft.Graph -Scope CurrentUser

.PERMISSIONS
    Requires one of the following:
    - Application.Read.All (delegated or application)
    - Directory.Read.All (delegated or application)

.PARAMETER OutputPath
    Path for the ExpiryPulse import CSV file.
    Defaults to .\entra-app-credentials.csv

.PARAMETER AuditOutputPath
    Path for the audit CSV file (apps with no trackable credentials).
    Defaults to .\entra-app-audit.csv
    Only used when -IncludeAudit is specified.

.PARAMETER IncludeAudit
    Switch. When specified, also exports an audit CSV of app registrations
    with no trackable credentials.

.EXAMPLE
    .\Export-EntraAppCredentials.ps1
    .\Export-EntraAppCredentials.ps1 -IncludeAudit
    .\Export-EntraAppCredentials.ps1 -OutputPath "C:\exports\creds.csv" -IncludeAudit -AuditOutputPath "C:\exports\audit.csv"

.NOTES
    Author: ExpiryPulse
    Compatible with: Windows PowerShell 5.1+, PowerShell 7+
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$OutputPath = ".\entra-app-credentials.csv",

    [Parameter()]
    [string]$AuditOutputPath = ".\entra-app-audit.csv",

    [Parameter()]
    [switch]$IncludeAudit
)

# -----------------------------------------------
# Check execution policy
# -----------------------------------------------
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Host "Execution policy is Restricted. Please run PowerShell with:" -ForegroundColor Yellow
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\Export-EntraAppCredentials.ps1" -ForegroundColor Cyan
    exit 1
}

# -----------------------------------------------
# Check Microsoft.Graph module
# -----------------------------------------------
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Write-Host "Microsoft.Graph module not found." -ForegroundColor Yellow
    Write-Host "Installing - this may take a minute..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
    Write-Host "Installation complete." -ForegroundColor Green
}
else {
    Write-Host "Microsoft.Graph module found." -ForegroundColor Green
}

# -----------------------------------------------
# Connect to Microsoft Graph
# -----------------------------------------------
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

try {
    Connect-MgGraph -Scopes "Application.Read.All" -NoWelcome
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

# -----------------------------------------------
# Retrieve all app registrations
# -----------------------------------------------
Write-Host "Retrieving app registrations..." -ForegroundColor Cyan

try {
    $apps = Get-MgApplication -All -Property "Id,AppId,DisplayName,PasswordCredentials,KeyCredentials"
}
catch {
    Write-Error "Failed to retrieve app registrations: $_"
    Disconnect-MgGraph | Out-Null
    exit 1
}

Write-Host "Found $($apps.Count) app registrations." -ForegroundColor Green

# -----------------------------------------------
# Build export rows
# -----------------------------------------------
$rows      = [System.Collections.Generic.List[PSCustomObject]]::new()
$auditRows = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($app in $apps) {

    $hasTrackableCredential = $false

    # --- Client Secrets (PasswordCredentials) ---
    foreach ($secret in $app.PasswordCredentials) {

        if ($null -eq $secret.EndDateTime) { continue }

        $hasTrackableCredential = $true
        $expiry = $secret.EndDateTime.ToUniversalTime()
        $displayName = if ($secret.DisplayName) { $secret.DisplayName } else { "Unnamed Secret" }

        $rows.Add([PSCustomObject]@{
            name    = "$($app.DisplayName) - $displayName"
            service = "Entra ID"
            expiry  = $expiry.ToString("yyyy-MM-dd")
            notes   = "App ID: $($app.AppId) | Type: Client Secret"
        })
    }

    # --- Certificates (KeyCredentials) ---
    foreach ($cert in $app.KeyCredentials) {

        if ($null -eq $cert.EndDateTime) { continue }

        $hasTrackableCredential = $true
        $expiry = $cert.EndDateTime.ToUniversalTime()
        $displayName = if ($cert.DisplayName) { $cert.DisplayName } else { "Unnamed Certificate" }

        $rows.Add([PSCustomObject]@{
            name    = "$($app.DisplayName) - $displayName"
            service = "Entra ID"
            expiry  = $expiry.ToString("yyyy-MM-dd")
            notes   = "App ID: $($app.AppId) | Type: Certificate"
        })
    }

    # --- Audit: apps with no trackable credentials ---
    if ($IncludeAudit -and -not $hasTrackableCredential) {

        $hasSecrets = $app.PasswordCredentials.Count -gt 0
        $hasCerts   = $app.KeyCredentials.Count -gt 0

        $reason = if ($hasSecrets -or $hasCerts) {
            "Credentials present but no expiry date set (possibly federated)"
        }
        else {
            "No credentials configured"
        }

        $auditRows.Add([PSCustomObject]@{
            app_name = $app.DisplayName
            app_id   = $app.AppId
            reason   = $reason
        })
    }
}

# -----------------------------------------------
# Export credentials CSV (ExpiryPulse import)
# -----------------------------------------------
Write-Host ""
if ($rows.Count -eq 0) {
    Write-Host "No trackable credentials found." -ForegroundColor Yellow
}
else {
    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Export complete." -ForegroundColor Green
    Write-Host "  Credentials exported : $($rows.Count)" -ForegroundColor White
    Write-Host "  Output file          : $OutputPath" -ForegroundColor White
    Write-Host ""
    Write-Host "$OutputPath is ready to import into ExpiryPulse at https://expirypulse.dev" -ForegroundColor Cyan
}

# -----------------------------------------------
# Export audit CSV (optional)
# -----------------------------------------------
if ($IncludeAudit) {
    Write-Host ""
    if ($auditRows.Count -eq 0) {
        Write-Host "All app registrations have trackable credentials." -ForegroundColor Green
    }
    else {
        $auditRows | Export-Csv -Path $AuditOutputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Audit export complete." -ForegroundColor Yellow
        Write-Host "  Apps with no trackable credentials : $($auditRows.Count)" -ForegroundColor White
        Write-Host "  Audit file                         : $AuditOutputPath" -ForegroundColor White
    }
}

# -----------------------------------------------
# Disconnect
# -----------------------------------------------
Write-Host ""
Disconnect-MgGraph | Out-Null
