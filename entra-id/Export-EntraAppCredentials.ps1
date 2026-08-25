<#
.SYNOPSIS
    Exports Entra ID app registration secret and certificate expiry dates
    to a CSV file ready for import into ExpiryPulse.

.DESCRIPTION
    Connects to Microsoft Graph and retrieves all app registrations
    in your tenant. Extracts client secrets (password credentials)
    and certificates (key credentials) with their expiry dates,
    then exports them in ExpiryPulse's import format.

    Each row carries a tags column so ExpiryPulse does not have to
    guess tags from the name. Without it, an app certificate named
    "APICert" matches ExpiryPulse's "cert" keyword and is tagged SSL,
    which it is not.
    Optionally exports a separate audit CSV for apps with no trackable
    credentials using the -IncludeAudit switch.

.REQUIREMENTS
    Two submodules of the Microsoft.Graph PowerShell SDK, not the whole thing:
    Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications -Scope CurrentUser

    The full Microsoft.Graph meta-module pulls in around forty packages and
    takes several minutes. This script calls three cmdlets, all covered by
    those two. If you already have the full SDK, nothing further is needed.

.PERMISSIONS
    Application.Read.All, delegated, granted at interactive sign-in.
    Read-only: the script only calls Get-MgApplication and never writes.

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
# A courtesy check rather than a real gate. Under either of these policies the
# host usually refuses to load the file before this line ever runs, so the user
# sees PowerShell's own error instead. It costs nothing to catch the
# configurations where execution does reach here and say something useful.
$executionPolicy = Get-ExecutionPolicy
if ($executionPolicy -in @('Restricted', 'AllSigned')) {
    Write-Host "Execution policy is $executionPolicy, which blocks this script." -ForegroundColor Yellow
    Write-Host "Allow it for this window only - nothing outside this session changes:" -ForegroundColor Yellow
    Write-Host "  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass" -ForegroundColor Cyan
    Write-Host "  .\Export-EntraAppCredentials.ps1" -ForegroundColor Cyan
    if ($executionPolicy -eq 'AllSigned') {
        Write-Host ""
        Write-Host "Under AllSigned, Unblock-File is not enough on its own - an unsigned" -ForegroundColor Yellow
        Write-Host "script needs a publisher signature no matter where it came from." -ForegroundColor Yellow
    }
    exit 1
}

# -----------------------------------------------
# Check Microsoft.Graph module
# -----------------------------------------------
# Only the two submodules this script actually uses. The check already looked
# for Microsoft.Graph.Applications while the install pulled the full
# Microsoft.Graph meta-module, which is roughly forty packages and several
# minutes for the sake of one cmdlet. Anyone who already has the full SDK
# satisfies the check and installs nothing.
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Write-Host "Microsoft.Graph.Applications module not found." -ForegroundColor Yellow
    Write-Host "Installing Microsoft.Graph.Authentication and Microsoft.Graph.Applications..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications -Scope CurrentUser -Force -AllowClobber
    Write-Host "Installation complete." -ForegroundColor Green
}
else {
    Write-Host "Microsoft.Graph.Applications module found." -ForegroundColor Green
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

# ExpiryPulse caps credential 'name' at 100 chars AND dedups the CSV import on
# name so each name must be BOTH <=100 chars and unique per credential. We keep
# the app + credential label readable but always preserve an 8-char KeyId suffix
# (the only guaranteed-unique, stable per-credential identifier), so multiple
# secrets/certs on one app never collapse into a single imported row.
function Format-CredentialName {
    param([string]$AppName, [string]$CredLabel, [string]$KeyId)
    $suffix = " ($($KeyId.Substring(0,8)))"          # unique per cred, never trimmed
    $label  = "$AppName - $CredLabel"
    $budget = 100 - $suffix.Length
    if ($label.Length -gt $budget) {
        $label = $label.Substring(0, $budget - 3) + "..."
    }
    return "$label$suffix"
}

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
            name    = Format-CredentialName -AppName $app.DisplayName -CredLabel $displayName -KeyId $secret.KeyId
            service = "Entra ID"
            expiry  = $expiry.ToString("yyyy-MM-dd")
            notes   = "App ID: $($app.AppId) | Type: Client Secret | Key ID: $($secret.KeyId)"
            tags    = "ENTRA-ID;CLIENT-SECRET"
        })
    }

    # --- Certificates (KeyCredentials) ---
    foreach ($cert in $app.KeyCredentials) {

        if ($null -eq $cert.EndDateTime) { continue }

        $hasTrackableCredential = $true
        $expiry = $cert.EndDateTime.ToUniversalTime()
        $displayName = if ($cert.DisplayName) { $cert.DisplayName } else { "Unnamed Certificate" }

        $rows.Add([PSCustomObject]@{
            name    = Format-CredentialName -AppName $app.DisplayName -CredLabel $displayName -KeyId $cert.KeyId
            service = "Entra ID"
            expiry  = $expiry.ToString("yyyy-MM-dd")
            notes   = "App ID: $($app.AppId) | Type: Certificate | Key ID: $($cert.KeyId)"
            tags    = "ENTRA-ID;CERTIFICATE"
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
