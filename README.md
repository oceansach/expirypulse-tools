# expirypulse-tools

PowerShell and Python scripts to export credentials and secrets from cloud platforms into ExpiryPulse, with no manual entry required.

---

> **Full visibility into your Entra ID credential expiry, in minutes.**
> Run the script, upload the CSV, and ExpiryPulse handles the rest.
> [Get started free at expirypulse.dev](https://expirypulse.dev). No credit card required.

## Why This Exists

Manually entering credentials into any tracking tool is slow, error-prone, and the kind of task that never actually gets done. These scripts do the work for you: connect to your platform, pull every credential and its expiry date, and export a CSV that imports directly into ExpiryPulse with no reformatting required.

---

## Available Scripts

| Platform | Script | Language | What It Exports |
|---|---|---|---|
| Microsoft Entra ID | `entra-id/Export-EntraAppCredentials.ps1` | PowerShell | Expiry metadata only: credential names and expiry dates |

**Secret values, keys, and passwords are never accessed, read, or exported.**

More platforms coming soon: Azure Key Vault, AWS Secrets Manager, AWS ACM, and Windows Certificate Store.

---

## Getting Started

### Entra ID: App Registration Secrets & Certificates

**Requirements**
- PowerShell 5.1 or later (Windows PowerShell or PowerShell 7+)
- Microsoft.Graph PowerShell SDK

**Install the Microsoft.Graph module if you don't have it:**
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

**Permissions**

These scripts use read-only permissions and never modify anything in your tenant or cloud environment.

| Script | Permission Required | Type |
|---|---|---|
| Export-EntraAppCredentials.ps1 | Application.Read.All | Delegated (interactive login) |

**Run the script:**
```powershell
.\Export-EntraAppCredentials.ps1
```

This will open a browser window for interactive login. MFA is supported natively. Sign in with an account that has at least **Application.Read.All** permissions.

> **Getting `... is not digitally signed`?**
>
> Windows blocks downloaded scripts by default. The file arrives tagged with the
> Mark of the Web, and under the common `RemoteSigned` execution policy that tag
> means it needs a publisher signature to run. Nothing is wrong with the script.
> Windows simply cannot tell where it came from.
>
> Clear the download tag, which is the narrowest fix and only affects this file:
> ```powershell
> Unblock-File .\Export-EntraAppCredentials.ps1
> ```
>
> If your policy is `AllSigned`, unblocking is not enough. Allow unsigned
> scripts for the current window only. This affects nothing outside the
> PowerShell session you are in and disappears when you close it:
> ```powershell
> Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
> ```
>
> Check what you are actually running under with `Get-ExecutionPolicy -List`.
> Please don't set `Bypass` machine-wide to run a one-off export. Read the
> script first if you'd rather verify it than trust it. It is about 200 lines
> and does nothing but read and write a CSV.

**Optional parameters:**

Export to a specific path:
```powershell
.\Export-EntraAppCredentials.ps1 -OutputPath "C:\exports\creds.csv"
```

Include an audit file of app registrations with no trackable credentials:
```powershell
.\Export-EntraAppCredentials.ps1 -IncludeAudit
```

> When `-IncludeAudit` is specified, a second file `entra-app-audit.csv` is exported listing app registrations with no trackable credentials, useful for identifying orphaned or misconfigured apps.

Combined:
```powershell
.\Export-EntraAppCredentials.ps1 -OutputPath "C:\exports\creds.csv" -IncludeAudit -AuditOutputPath "C:\exports\audit.csv"
```

**Output:**

The script exports a CSV with the following columns, ready to import directly into ExpiryPulse:

| Column | Example |
|---|---|
| name | MyApp - ClientSecret1 (a1b2c3d4) |
| service | Entra ID |
| expiry | 2026-12-31 |
| notes | App ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \| Type: Client Secret \| Key ID: a1b2c3d4-xxxx-xxxx-xxxx-xxxxxxxxxxxx |

Certificates export identically, with `Type: Certificate` in the notes.

#### Why each name ends in `(a1b2c3d4)`

Those eight characters are the start of the credential's **Key ID**, and they are load-bearing rather than decorative.

A single app registration often holds several secrets and certificates, and Entra happily lets them share a display name. ExpiryPulse de-duplicates a CSV import on `name`, so without something unique per credential, two secrets from the same app would collapse into one imported row and the second would be silently dropped.

The Key ID is the only stable, guaranteed-unique identifier a credential has, so it is always preserved. Names are capped at 100 characters to match ExpiryPulse's limit; when the app and credential names are too long together, the **label is truncated with `...` and the suffix is appended afterwards**, so the distinguishing part never gets cut off.

**Import into ExpiryPulse:**
1. Log in to [expirypulse.dev](https://expirypulse.dev)
2. Click **Home -> Import CSV**
3. Upload the exported CSV
4. Done. Your credentials are tracked and notifications are configured automatically

When `-IncludeAudit` is used, a second file is exported with columns: `app_name`, `app_id`, `reason`.

#### Re-running the export later

Entra never changes an existing credential's expiry. `endDateTime` is fixed when the credential is created, and Microsoft Graph has no update operation for it, only `addPassword` and `removePassword`. Rotating a secret therefore always produces a **new credential with a new Key ID**, never a modified one.

That makes repeat imports predictable:

| In your tenant | Name produced | Result on import |
|---|---|---|
| Credential unchanged | identical to last export | Skipped as a duplicate. Correct: its expiry cannot have changed. |
| Credential rotated | new Key ID, so a new name | Imported as a new credential. |
| Credential deleted | absent from the CSV | The existing ExpiryPulse row stays. |

The last row is the one to watch. A credential removed in Entra is **not** removed from ExpiryPulse, because a credential missing from a CSV is indistinguishable from one you simply did not export this time. After rotating, delete the superseded row in ExpiryPulse so it stops reporting an expiry for a credential that no longer exists.

---

## Roadmap

- [ ] Azure Key Vault: secrets and certificates
- [ ] AWS Secrets Manager
- [ ] AWS Certificate Manager (ACM)
- [ ] Windows Certificate Store
- [ ] GitHub Actions secrets expiry
- [ ] Stripe API keys

---

## About ExpiryPulse

[ExpiryPulse](https://expirypulse.dev) is a credential expiry tracking and notification tool for IT teams and sysadmins. Track SSL certificates, API keys, client secrets, and any credential with an expiry date. Manage them with your team, assign owner per credential and get notified via email/Slack/Teams before something breaks.

Free tier available. No enterprise contract required.

---

## License

The scripts in this repository are MIT licensed, free to use, modify, and distribute. See [LICENSE](./LICENSE) for details.

[ExpiryPulse](https://expirypulse.dev) is not covered by this license.
