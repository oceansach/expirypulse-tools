# expirypulse-tools
PowerShell and Python scripts to export credentials and secrets from cloud platforms into ExpiryPulse — no manual entry required.

---

> **Free visibility into your Entra ID credential expiry — in minutes.**  
> Run the script, upload the CSV, and ExpiryPulse handles the rest.  
> [Get started free at expirypulse.dev](https://expirypulse.dev) — no credit card required.

## Why This Exists

Manually entering credentials into any tracking tool is slow, error-prone, and the kind of task that never actually gets done. These scripts do the work for you — connect to your platform, pull every credential and its expiry date, and export a CSV that imports directly into ExpiryPulse with no reformatting required.

---

## Available Scripts

| Platform | Script | Language | What It Exports |
|---|---|---|---|
| Microsoft Entra ID | `entra-id/Export-EntraAppCredentials.ps1` | PowerShell | Expiry metadata only — credential names and expiry dates| 

**Secret values, keys, and passwords are never accessed, read, or exported.**

More platforms coming soon — Azure Key Vault, AWS Secrets Manager, AWS ACM, and Windows Certificate Store.

---

## Getting Started

### Entra ID — App Registration Secrets & Certificates

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

**Optional parameters:**

Export to a specific path:
```powershell
.\Export-EntraAppCredentials.ps1 -OutputPath "C:\exports\creds.csv"
```

**Output:**

The script exports a CSV with the following columns, ready to import directly into ExpiryPulse:

| Column | Example |
|---|---|
| name | MyApp — ClientSecret1 |
| service | Entra ID |
| expiry | 2025-12-31 |
| notes | App ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \| Type: Client Secret |

**Import into ExpiryPulse:**
1. Log in to [expirypulse.dev](https://expirypulse.dev)
2. Click **Home -> Import CSV**
3. Upload the exported CSV
4. Done — your credentials are tracked and notifications are configured automatically

---

## Roadmap

- [ ] Azure Key Vault — secrets and certificates
- [ ] AWS Secrets Manager
- [ ] AWS Certificate Manager (ACM)
- [ ] Windows Certificate Store
- [ ] GitHub Actions secrets expiry
- [ ] Stripe API keys

---

## About ExpiryPulse

[ExpiryPulse](https://expirypulse.dev) is a credential expiry tracking and notification tool for IT teams and sysadmins. Track SSL certificates, API keys, client secrets, and any credential with an expiry date — manage them with your team, assign owner per credential and get notified via email/Slack/Teams before something breaks.

Free tier available. No enterprise contract required.

---

## License

The scripts in this repository are MIT licensed — free to use, modify, and distribute. See [LICENSE](./LICENSE) for details.

[ExpiryPulse](https://expirypulse.dev) is not covered by this license.
