<#
.SYNOPSIS
    Exports Entra ID app registration secret and certificate expiry dates
    to a CSV file ready for import into ExpiryPulse.

.DESCRIPTION
    Connects to Microsoft Graph and retrieves all app registrations
    in your tenant. Extracts client secrets (password credentials)
    and certificates (key credentials) with their expiry dates,
    then exports them in ExpiryPulse's import format.

.REQUIREMENTS
    Microsoft.Graph PowerShell SDK
    Install-Module Microsoft.Graph -Scope CurrentUser

.PERMISSIONS
    Requires one of the following:
    - Application.Read.All (delegated or application)
    - Directory.Read.All (delegated or application)

.PARAMETER OutputPath
    Path for the exported CSV file.
    Defaults to .\entra-app-credentials.csv

.EXAMPLE
    .\Export-EntraAppCredentials.ps1
    .\Export-EntraAppCredentials.ps1 -OutputPath "C:\exports\creds.csv"

.NOTES
    Author: ExpiryPulse
    Compatible with: Windows PowerShell 5.1+, PowerShell 7+
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$OutputPath = ".\entra-app-credentials.csv"
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
$rows = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($app in $apps) {

    # --- Client Secrets (PasswordCredentials) ---
    foreach ($secret in $app.PasswordCredentials) {

        if ($null -eq $secret.EndDateTime) { continue }

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

        $expiry = $cert.EndDateTime.ToUniversalTime()
        $displayName = if ($cert.DisplayName) { $cert.DisplayName } else { "Unnamed Certificate" }

        $rows.Add([PSCustomObject]@{
            name    = "$($app.DisplayName) - $displayName"
            service = "Entra ID"
            expiry  = $expiry.ToString("yyyy-MM-dd")
            notes   = "App ID: $($app.AppId) | Type: Certificate"
        })
    }
}

# -----------------------------------------------
# Export to CSV
# -----------------------------------------------
if ($rows.Count -eq 0) {
    Write-Host "No credentials found." -ForegroundColor Yellow
}
else {
    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host "Export complete." -ForegroundColor Green
    Write-Host "  Credentials exported : $($rows.Count)" -ForegroundColor White
    Write-Host "  Output file          : $OutputPath" -ForegroundColor White
    Write-Host ""
    Write-Host "Ready to import into ExpiryPulse at https://expirypulse.dev" -ForegroundColor Cyan
}

# -----------------------------------------------
# Disconnect
# -----------------------------------------------
Disconnect-MgGraph | Out-Null
