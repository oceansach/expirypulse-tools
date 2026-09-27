<#
.SYNOPSIS
    Scans internal hosts listed in a CSV and fills in their certificate
    expiry dates, ready to import into ExpiryPulse.

.DESCRIPTION
    ExpiryPulse cannot scan hosts that are not reachable from the public
    internet, which is most of what a corporate PKI signs - intranets, internal
    APIs, appliance management pages, anything behind a VPN. This script closes
    that gap by doing the scan from inside the network.

    You list the hosts. It reads each certificate, writes the expiry back into
    the same file, and leaves everything else alone. Import the result.

    The CSV is the durable thing here, not a throwaway export. Keep it, re-run
    this against it whenever you want fresh dates, and re-import - names stay
    the same, so ExpiryPulse updates the existing entries rather than creating
    new ones.

.PARAMETER Path
    The CSV to read and update. Must contain at minimum: name, internal_host.

.PARAMETER OutputPath
    Write to a different file instead of updating in place.

.PARAMETER TimeoutSeconds
    Per-host connection timeout. Default 5.

.EXAMPLE
    .\Scan-InternalCertificates.ps1 -Path .\internal-certs.csv

.EXAMPLE
    .\Scan-InternalCertificates.ps1 -Path .\hosts.csv -OutputPath .\ready.csv

.NOTES
    Author: ExpiryPulse
    Requires: PowerShell 5.1 or later. No modules, no admin rights.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [int]$TimeoutSeconds = 5
)

# -----------------------------------------------
# Execution policy courtesy check
# -----------------------------------------------
$executionPolicy = Get-ExecutionPolicy
if ($executionPolicy -in @('Restricted', 'AllSigned')) {
    Write-Host "Execution policy is $executionPolicy, which blocks this script." -ForegroundColor Yellow
    Write-Host "Allow it for this window only - nothing outside this session changes:" -ForegroundColor Yellow
    Write-Host "  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass" -ForegroundColor Cyan
    exit 1
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "No such file: $Path" -ForegroundColor Red
    Write-Host "Start from the template - see internal-certs-template.csv" -ForegroundColor Yellow
    exit 1
}

# -----------------------------------------------
# TLS inspection detection
# -----------------------------------------------
# Endpoint antivirus and corporate egress proxies terminate TLS, mint a
# certificate on the fly from a locally-trusted root, and hand you that - so
# the expiry you read is the proxy's, typically days away and meaningless.
# Common in exactly the regulated environments this is aimed at, and invisible
# unless you look at the issuer.
$InterceptionIssuers = @(
    'Avast', 'AVG', 'Kaspersky', 'Bitdefender', 'ESET', 'Sophos', 'McAfee',
    'Zscaler', 'Netskope', 'Blue Coat', 'Symantec Web', 'Forcepoint',
    'Fortinet', 'FortiGate', 'Palo Alto', 'Cisco Umbrella', 'Umbrella',
    'Charles Proxy', 'Fiddler', 'mitmproxy', 'Web/Mail Shield', 'SSL Inspection'
)

function Test-InterceptedIssuer {
    param([string]$Issuer)
    if (-not $Issuer) { return $false }
    foreach ($vendor in $InterceptionIssuers) {
        if ($Issuer -like "*$vendor*") { return $true }
    }
    return $false
}

function Get-CommonName {
    param([string]$DistinguishedName)
    if ($DistinguishedName -match 'CN=([^,]+)') { return $Matches[1].Trim() }
    return $DistinguishedName
}

# -----------------------------------------------
# Read one host's certificate
# -----------------------------------------------
function Read-HostCertificate {
    param([string]$HostSpec)

    $name = $HostSpec
    $port = 443
    if ($HostSpec -match '^(.*):(\d+)$') {
        $name = $Matches[1]
        $port = [int]$Matches[2]
    }

    $tcp = $null
    $ssl = $null
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $connect = $tcp.BeginConnect($name, $port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            throw "timed out after $TimeoutSeconds seconds"
        }
        $tcp.EndConnect($connect)

        # Validation is deliberately accepted. An internal CA is usually not in
        # this machine's trust store, and refusing those would reject exactly
        # the certificates this exists to track. The expiry is read off the
        # presented certificate either way.
        $ssl = [System.Net.Security.SslStream]::new(
            $tcp.GetStream(), $false, { param($s, $c, $ch, $e) $true }
        )
        $ssl.AuthenticateAsClient($name)

        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $ssl.RemoteCertificate
        )

        return [PSCustomObject]@{
            Success    = $true
            NotAfter   = $cert.NotAfter
            Issuer     = (Get-CommonName $cert.Issuer)
            Subject    = (Get-CommonName $cert.Subject)
            Thumbprint = $cert.Thumbprint
            Error      = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
    finally {
        if ($ssl) { $ssl.Dispose() }
        if ($tcp) { $tcp.Dispose() }
    }
}

# -----------------------------------------------
# Read the CSV
# -----------------------------------------------
$rows = @(Import-Csv -LiteralPath $Path)

if ($rows.Count -eq 0) {
    Write-Host "That file has no rows." -ForegroundColor Red
    exit 1
}

$columns = $rows[0].PSObject.Properties.Name
foreach ($required in @('name', 'internal_host')) {
    if ($columns -notcontains $required) {
        Write-Host "Missing required column: $required" -ForegroundColor Red
        Write-Host "Columns found: $($columns -join ', ')" -ForegroundColor Yellow
        exit 1
    }
}

# ssl_domain is refused outright - its presence, not just its contents.
#
# It is the column that tells ExpiryPulse a row is scan-tracked, and an
# internal host is by definition one it cannot reach. A populated one would
# mean the nightly job tries from the public internet and fails every night,
# and - worse - every future re-import of this file is REFUSED for that row,
# because the importer will not overwrite a scan-derived expiry with a CSV one.
# The round trip this script exists for would break on the second run,
# silently.
#
# An empty column is harmless today and one keystroke from all of that, and its
# presence means the wrong template was used. Cheaper to stop here than to let
# somebody discover the failure months later, when the file is long and the
# re-imports have quietly been doing nothing.
if ($columns -contains 'ssl_domain') {
    Write-Host ""
    Write-Host "This file has an ssl_domain column. Remove it." -ForegroundColor Red
    Write-Host ""
    Write-Host "Internal hosts belong in internal_host. ssl_domain marks a row as" -ForegroundColor Yellow
    Write-Host "scan-tracked, which means ExpiryPulse would try to reach the host from" -ForegroundColor Yellow
    Write-Host "the public internet - and would refuse every future update from this" -ForegroundColor Yellow
    Write-Host "file, so re-running this script would stop having any effect." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Start from internal-certs-template.csv, which has no such column." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "Scanning $($rows.Count) host(s) from $Path" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------
# Scan
# -----------------------------------------------
$scanned     = 0
$failed      = 0
$intercepted = 0
$skipped     = 0
$problems    = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($row in $rows) {
    $target = if ($row.internal_host) { $row.internal_host.Trim() } else { '' }

    if (-not $target) {
        $skipped++
        Write-Host "  (skipped) $($row.name) - no internal_host" -ForegroundColor DarkGray
        continue
    }

    $result = Read-HostCertificate -HostSpec $target

    if (-not $result.Success) {
        $failed++
        # Left blank on purpose. A stale date is worse than no date: it would
        # import as a real expiry and sit there looking watched. Blank means
        # the row blocks in the import preview, which is the correct outcome
        # for a host nobody could reach.
        $row.expiry = ''
        $problems.Add([PSCustomObject]@{ Host = $target; Reason = $result.Error })
        Write-Host "  FAILED  $target - $($result.Error)" -ForegroundColor Red
        continue
    }

    $scanned++
    $row.expiry = $result.NotAfter.ToUniversalTime().ToString('yyyy-MM-dd')

    if ($columns -contains 'notes') {
        $row.notes = "Issuer: $($result.Issuer) | Thumbprint: $($result.Thumbprint) | Scanned: $(Get-Date -Format 'yyyy-MM-dd')"
    }

    $isIntercepted = Test-InterceptedIssuer $result.Issuer
    if ($isIntercepted) {
        $intercepted++
        if ($columns -contains 'tags') {
            $existing = if ($row.tags) { $row.tags.Trim() } else { '' }
            if ($existing -notlike '*TLS-INSPECTED-VERIFY*') {
                $row.tags = if ($existing) { "$existing;TLS-INSPECTED-VERIFY" } else { 'TLS-INSPECTED-VERIFY' }
            }
        }
        $problems.Add([PSCustomObject]@{
            Host   = $target
            Reason = "TLS inspection detected (issuer: $($result.Issuer)) - this expiry is the proxy's, not the real certificate's"
        })
        Write-Host "  WARN    $target - intercepted by $($result.Issuer), expiry is NOT the real certificate's" -ForegroundColor Yellow
    }
    else {
        Write-Host "  OK      $target - expires $($row.expiry)" -ForegroundColor Green
    }
}

# -----------------------------------------------
# Write back
# -----------------------------------------------
$destination = if ($OutputPath) { $OutputPath } else { $Path }
$rows | Export-Csv -LiteralPath $destination -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "------------------------------------------------" -ForegroundColor Cyan
Write-Host "  scanned      : $scanned" -ForegroundColor Green
if ($intercepted -gt 0) {
    Write-Host "  intercepted  : $intercepted   <-- dates below are the proxy's" -ForegroundColor Yellow
}
if ($failed -gt 0) {
    Write-Host "  unreachable  : $failed   <-- expiry left blank" -ForegroundColor Red
}
if ($skipped -gt 0) {
    Write-Host "  no host set  : $skipped" -ForegroundColor DarkGray
}
Write-Host "  written to   : $destination" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Cyan

if ($problems.Count -gt 0) {
    Write-Host ""
    Write-Host "Needs attention:" -ForegroundColor Yellow
    foreach ($p in $problems) {
        Write-Host "  $($p.Host)" -ForegroundColor Yellow
        Write-Host "    $($p.Reason)" -ForegroundColor DarkYellow
    }
}

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "Rows with a blank expiry will be blocked in the import preview." -ForegroundColor Yellow
    Write-Host "Fix the host or remove the row before importing." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next: import $destination at https://expirypulse.dev/cred/import" -ForegroundColor Cyan
Write-Host "Keep this file - re-run this script against it for fresh dates." -ForegroundColor DarkGray
Write-Host ""
