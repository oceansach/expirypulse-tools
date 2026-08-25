# Entra ID: App Registration Secrets and Certificates

Exports every app registration client secret and certificate in your tenant,
with its expiry date, to a CSV that imports straight into ExpiryPulse.

Entra ID does not warn you when app secrets are about to expire. There is no
banner in the portal, no email, and no single view of every credential across
every app registration sorted by expiry date. In a tenant with dozens of app
registrations, finding them by hand means clicking into each one.

**Only metadata is read.** Names and expiry dates. Secret values and key
material are never accessed or exported.

See the [repository README](../README.md) for the CSV format, the import
process, and setup that applies to every script here.

---

## Requirements

- PowerShell 5.1 or later (Windows PowerShell or PowerShell 7+)
- Microsoft.Graph PowerShell SDK

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Permissions

| Permission | Type |
|---|---|
| Application.Read.All | Delegated (interactive login) |

Read-only. The script never modifies anything in your tenant.

If you do not hold that permission, an administrator can grant it or run the
script themselves.

## Running it

```powershell
.\Export-EntraAppCredentials.ps1
```

A browser window opens for interactive sign-in. MFA is handled natively. No
service principal or app registration of your own is required.

> Blocked with `... is not digitally signed`? Run
> `Unblock-File .\Export-EntraAppCredentials.ps1` first. See
> [troubleshooting in the repository README](../README.md) for why, and for
> what to do if your execution policy is `AllSigned`.

**Optional parameters**

Export to a specific path:
```powershell
.\Export-EntraAppCredentials.ps1 -OutputPath "C:\exports\creds.csv"
```

Also export an audit file of app registrations with no trackable credentials,
useful for identifying orphaned or misconfigured apps:
```powershell
.\Export-EntraAppCredentials.ps1 -IncludeAudit
```

Combined:
```powershell
.\Export-EntraAppCredentials.ps1 -OutputPath "C:\exports\creds.csv" -IncludeAudit -AuditOutputPath "C:\exports\audit.csv"
```

The audit file has columns `app_name`, `app_id`, `reason`.

---

## Output

| Column | Example |
|---|---|
| name | MyApp - ClientSecret1 (a1b2c3d4) |
| service | Entra ID |
| expiry | 2026-12-31 |
| notes | App ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \| Type: Client Secret \| Key ID: a1b2c3d4-xxxx-xxxx-xxxx-xxxxxxxxxxxx |
| tags | ENTRA-ID;CLIENT-SECRET |

Certificates export identically, with `Type: Certificate` in the notes and
`ENTRA-ID;CERTIFICATE` in the tags.

Tags are supplied rather than left to ExpiryPulse's keyword matching, which
would tag an app certificate named `APICert` as `SSL` because the name contains
"cert". You can review and remove any of them in the import preview.

### Why each name ends in `(a1b2c3d4)`

Those eight characters are the start of the credential's **Key ID**, and they
are load-bearing rather than decorative.

A single app registration often holds several secrets and certificates, and
Entra happily lets them share a display name. ExpiryPulse de-duplicates a CSV
import on `name`, so without something unique per credential, two secrets from
the same app would collapse into one imported row and the second would be
silently dropped.

The Key ID is the only stable, guaranteed-unique identifier a credential has,
so it is always preserved. Names are capped at 100 characters to match
ExpiryPulse's limit; when the app and credential names are too long together,
the label is truncated with `...` and the suffix is appended afterwards, so the
distinguishing part never gets cut off.

---

## Re-running the export later

Entra never changes an existing credential's expiry. `endDateTime` is fixed
when the credential is created, and Microsoft Graph has no update operation for
it, only `addPassword` and `removePassword`. Rotating a secret therefore always
produces a **new credential with a new Key ID**, never a modified one.

That makes repeat imports predictable:

| In your tenant | Name produced | Result on import |
|---|---|---|
| Credential unchanged | identical to last export | Left as it is. The importer compares the two dates and finds nothing newer. |
| Credential rotated | new Key ID, so a new name | Imported as a new credential, alongside the old row. |
| Credential deleted | absent from the CSV | The existing ExpiryPulse row stays. |

On other platforms a repeat import can refresh an existing row's expiry in
place. That never happens here, and not because the importer treats Entra
specially: a changed Entra credential is always a *different* credential with a
different Key ID, so it never matches an existing name to begin with.

**This means rotation still leaves you with two rows.** The old one keeps
reporting an expiry for a secret nobody can renew, and it counts against your
plan's credential limit. Delete the superseded row after rotating. There is no
way for the importer to work this out for you today, because nothing in the CSV
says the new credential replaces the old one.

The deleted-credential row is worth the same attention. A credential removed in
Entra is **not** removed from ExpiryPulse, because a credential missing from a
CSV is indistinguishable from one you simply did not export this time.

---

## What to do with the output

**Open it in Excel.** Sort by expiry date, see what lapses in the next 30, 60,
or 90 days, and set your own reminders. Fine once, but it does not scale and it
is easy to forget to run again.

**Import it into ExpiryPulse.** Upload the CSV and get notifications before
anything expires, without maintaining a spreadsheet. The script output maps
exactly to ExpiryPulse's import format, so there is no reformatting. Free tier
available, no credit card required.

Steps are in the [repository README](../README.md).
