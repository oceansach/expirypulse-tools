# expirypulse-tools

PowerShell and Python scripts to export credentials and secrets from cloud platforms into ExpiryPulse, with no manual entry required.

---

> **Full visibility into your credential expiry, in minutes.**
> Run the script, upload the CSV, and ExpiryPulse handles the rest.
> [Get started free at expirypulse.dev](https://expirypulse.dev). No credit card required.

## Why This Exists

Manually entering credentials into any tracking tool is slow, error-prone, and the kind of task that never actually gets done. These scripts do the work for you: connect to your platform, pull every credential and its expiry date, and export a CSV that imports directly into ExpiryPulse with no reformatting required.

---

## Available Scripts

| Platform | Script | Language | Docs |
|---|---|---|---|
| Microsoft Entra ID | `entra-id/Export-EntraAppCredentials.ps1` | PowerShell | [entra-id/](./entra-id/) |

Each script has its own README covering the permissions it needs, how to run
it, what its output looks like, and how repeat exports behave. Start there.

**Secret values, keys, and passwords are never accessed, read, or exported.**
Every script reads metadata only: names and expiry dates.

More platforms are on the [roadmap](#roadmap) below.

---

## Before You Start

All PowerShell scripts here need PowerShell 5.1 or later (Windows PowerShell or
PowerShell 7+). Per-script module requirements are in each script's README.

### Getting `... is not digitally signed`?

Windows blocks downloaded scripts by default. The file arrives tagged with the
Mark of the Web, and under the common `RemoteSigned` execution policy that tag
means it needs a publisher signature to run. Nothing is wrong with the script.
Windows simply cannot tell where it came from.

Clear the download tag, which is the narrowest fix and only affects that file:

```powershell
Unblock-File .\TheScript.ps1
```

If your policy is `AllSigned`, unblocking is not enough. Allow unsigned scripts
for the current window only. This affects nothing outside the PowerShell session
you are in and disappears when you close it:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Check what you are actually running under with `Get-ExecutionPolicy -List`.
Please don't set `Bypass` machine-wide to run a one-off export. Read the script
first if you'd rather verify it than trust it. Each is a couple of hundred lines
and does nothing but read metadata and write a CSV.

---

## The CSV Format

Every script emits the same five columns, which are exactly what ExpiryPulse's
importer expects:

| Column | Required | Notes |
|---|---|---|
| name | yes | Maximum 100 characters. Must be unique per credential. |
| service | no | Free text, e.g. `Entra ID`. Used for grouping. |
| expiry | yes | `yyyy-MM-dd`. Dates in the past are accepted and tracked. |
| notes | no | Free text. Scripts put platform identifiers here. |
| tags | no | Semicolon separated, e.g. `ENTRA-ID;CERTIFICATE`. |

### About the tags column

Leave it out, or leave a cell blank, and ExpiryPulse generates tags by matching
keywords in the name and service. That guessing is wrong often enough to matter:
an Entra app certificate named `APICert` matches the `cert` keyword and gets
tagged `SSL`, which it is not. The scripts here supply tags explicitly because
they know what they exported.

Tags are stored uppercase, use letters, numbers and hyphens, and are capped at
20 characters and 10 per credential. Anything outside that is dropped rather
than mangled, so a tag with an accent in it disappears instead of arriving
truncated. You can review and remove any of them in the import preview before
committing.

### Why names look the way they do

**The importer matches on `name`.** When a row's name already exists in your
workspace, the importer compares dates rather than blindly skipping: if the CSV
carries a later expiry, and that date is in the future, the tracked expiry is
updated in place. Otherwise the row is left alone.

It refuses to update in these cases, all of them reported in the preview before
you commit:

| Situation | Why |
|---|---|
| Same date | Nothing to do. |
| Earlier date than the one tracked | A stale export must never roll a live date backwards. Flagged for review rather than hidden, because a certificate reissued early on a shorter policy also lands here, and that means the tracked date is optimistic. |
| Later, but already in the past | Stale collector output. Writing it would re-fire an expiry alert you have already seen. |
| The tracked credential is an SSL scan | Its expiry is maintained from the live certificate. A hand-supplied date would override it and would not correct itself. |
| Two credentials share the name | The importer will not guess which one you meant. Merge them first. |

Only the expiry is written. Name, service, notes and tags belong to whoever
edited the credential after the first import, and a re-export never overwrites
them.

That rule shapes how every script here builds names, and it is why the schemes
differ between platforms.

Where a platform lets several distinct credentials share a display name, the
script must add something unique, or one of them silently disappears on import.
Where a platform reuses a name across rotations, the script deliberately adds no
suffix: the name is then the stable identity, and each export refreshes the same
row rather than creating a new one every time. That is the whole point of
matching on name, and it is why a rotation on such a platform costs you nothing
to keep current.

Each script's README explains the choice it makes and what a repeat export does.
It is worth reading once before your second export.

---

## Importing into ExpiryPulse

1. Log in to [expirypulse.dev](https://expirypulse.dev)
2. Click **Home -> Import CSV**
3. Upload the exported CSV
4. Done. Your credentials are tracked and notifications are configured automatically

---

## Roadmap

- [ ] Windows Certificate Store: machine and user stores, locally or across a fleet
- [ ] AWS Certificate Manager (ACM)
- [ ] GitHub fine-grained personal access tokens
- [ ] ... more in the pipeline

---

## About ExpiryPulse

[ExpiryPulse](https://expirypulse.dev) is a credential expiry tracking and notification tool for IT teams and sysadmins. Track SSL certificates, API keys, client secrets, and any credential with an expiry date. Manage them with your team, assign owner per credential and get notified via email/Slack/Teams before something breaks.

Free tier available. No enterprise contract required.

---

## License

The scripts in this repository are MIT licensed, free to use, modify, and distribute. See [LICENSE](./LICENSE) for details.

[ExpiryPulse](https://expirypulse.dev) is not covered by this license.
