# Internal Certificates

You have a number of certificates on internal hosts and no quick way to get them
tracked. List the hostnames, run this, import the result into ExpiryPulse.dev

ExpiryPulse scans public certificates automatically; give it a domain and it
reads the certificate and keeps the date current on its own. That stops at your
perimeter. Intranets, internal APIs, appliance management pages, anything
behind a VPN or signed by a private CA: none of it is reachable from the
outside, so none of it can be auto-tracked.

This script closes that gap. You list the hosts in the CSV (template), run the script on your machine. 
It reads each certificate from where it can actually see them, and writes the expiry
dates back into the same file ready to import.

**Only metadata is read.** Hostnames, expiry dates, issuers and thumbprints.
Private keys are never accessed, and the script never connects to ExpiryPulse
or anything else — it talks only to the hosts you list.

See the [repository README](../README.md) for the CSV format, the import
process, and setup that applies to every script here.

---

## Requirements

- Windows PowerShell 5.1 or later
- Network access to the hosts you want to scan
- No modules, no admin rights, no agent

Run it from a machine that can reach the hosts — a workstation on the VPN or a
management server is usually right. It does nothing else, so a locked-down
jump box is fine.

## Running it

**1. Start from the template.** Copy `internal-certs-template.csv` somewhere
you will keep it, and fill in two columns: `name` and `internal_host`.

```csv
name,internal_host,service,expiry,notes,tags
Intranet portal,intranet.corp.local,Internal PKI,,,INTERNAL
Exchange OWA,mail.corp.local,Internal PKI,,,INTERNAL;EMAIL
Firewall admin,fw01.corp.local:4443,Appliance,,,INTERNAL;APPLIANCE
```

`name` is what you will see in ExpiryPulse. Call it whatever makes sense to
whoever gets the reminder.

`internal_host` is what to connect to. Add `:port` for anything not on 443 —
appliance management pages usually are not.

**2. Run the script.**

```powershell
.\Scan-InternalCertificates.ps1 -Path .\internal-certs.csv
```

It updates the file in place. Use `-OutputPath` to write elsewhere, and
`-TimeoutSeconds` if your hosts are slow to answer (default 5).

```
  OK      intranet.corp.local - expires 2027-03-14
  OK      mail.corp.local - expires 2026-11-02
  FAILED  fw01.corp.local:4443 - No such host is known.

------------------------------------------------
  scanned      : 2
  unreachable  : 1   <-- expiry left blank
  written to   : .\internal-certs.csv
------------------------------------------------
```

**3. Import it** at [expirypulse.dev](https://expirypulse.dev) → Import CSV.

**4. Keep the file.** This is the part people miss. The CSV is not a throwaway
export — it is your host list. Re-run the script against it whenever you want
fresh dates, and re-import.

## What it writes

For every host it reaches:

| Column | Filled with |
|---|---|
| `expiry` | The certificate's `notAfter`, as `YYYY-MM-DD` in UTC |
| `notes` | Issuer, thumbprint, and the date it was scanned |
| `tags` | `TLS-INSPECTED-VERIFY` appended if interception was detected |

`name`, `internal_host` and `service` are yours. The script never touches them.

## Re-running it later

Run it again whenever you like — monthly is a reasonable habit. On import,
ExpiryPulse matches each row to the credential it created before, so you get
updates rather than duplicates.

Rows are matched **by `name`**. That is the only thing tying a row to the
credential it created, so:

> **Change anything you like except `name`.** Renaming a row makes the next
> import create a second credential instead of updating the first.

Three outcomes when you re-import:

- **The certificate was renewed** — the new date is later, and the credential
  is updated. This is the case you are re-running for.
- **Nothing changed** — the date is the same, the row is skipped as already up
  to date, and nothing happens. Re-running costs you nothing.
- **The new date is earlier than what is tracked** — the import refuses it and
  flags the row for review, showing both dates. This is deliberate: a stale
  CSV should not be able to drag a date backwards. But it does happen for a
  real reason — a certificate reissued early onto a shorter policy — and when
  it does, you will need to correct that credential by hand. It is the one
  case this does not fix itself.

Note that `notes` and `tags` are only written on the **first** import.
Afterwards they belong to whoever edited them in the app, so the issuer and
scan date shown there will not refresh. The CSV always has the current values.

## When the expiry may not be the real one

Endpoint antivirus and corporate egress proxies terminate TLS. They intercept
the connection, mint a certificate on the fly from a locally trusted root, and
hand you that instead — so the expiry you read is whatever the proxy put in its
own certificate, not what is installed on the host.

How wrong that is depends on the vendor. Some mint a short-lived certificate of
their own, and the date is days away and meaningless. Others copy the original
validity window verbatim, and the date is correct — Avast does this, so it looks
right and there is nothing in the read that tells you either way. The issuer and
thumbprint are always the proxy's, whichever it is, so the `notes` this writes
for an intercepted host describe the proxy's certificate rather than yours.

This is common in exactly the regulated environments this script is aimed at,
and invisible if you only look at the date.

Which is also why the issuer check is a heuristic and not a real one. **This
script accepts any certificate without validating it**, deliberately: an
internal CA is usually not in the trust store of the machine you run from, and
refusing untrusted chains would reject exactly the certificates this exists to
read. So it cannot distinguish a legitimate private CA from an interception by
validating. Matching the issuer against known inspection vendors is the only
signal left, and a vendor not on that list will pass without comment.

The script checks the issuer of every certificate it reads against known
inspection vendors — Zscaler, Netskope, Avast, Sophos, Fortinet, Palo Alto and
others — and when it matches:

```
  WARN    intranet.corp.local - intercepted by Zscaler Root CA,
          expiry may not be the real certificate's
```

The row is tagged `TLS-INSPECTED-VERIFY` so it is obvious in ExpiryPulse too.
The date still imports, because a date you know to be unconfirmed is more useful
than no date — but treat it that way, and check the real expiry against the host
or your CA before relying on it.

If you see this on every host, run the script from somewhere that is not behind
the inspecting proxy. Endpoint antivirus is the usual culprit rather than a
network proxy: it hooks the local socket, so it intercepts internal hosts and
even localhost, while an egress proxy is normally not in the path for traffic
that never leaves your network. A management server or jump box without a web
shield installed is the reliable place to run this from.

## Hosts it could not reach

Unreachable hosts get a **blank** expiry, not a stale one, and are listed at
the end of the run. A blank expiry is blocked in the import preview, which is
the correct outcome — better a row you have to deal with than a date that looks
watched and is not.

Usual causes: a typo in the hostname, a host that only listens on a different
port, no route from the machine you are running on, or a service that is not
actually serving TLS.

## Why there is no ssl_domain column

The general import template has one; this one deliberately does not, and the
script refuses to run on a file that has it.

`ssl_domain` tells ExpiryPulse the row is auto-scanned, and it scans from the
public internet. For an internal host that fails every night — and, more
importantly, a row marked that way **refuses every future update from a CSV**.
Re-running this script would quietly stop having any effect, and nothing would
tell you.

So internal hosts go in `internal_host`, which ExpiryPulse ignores entirely.
Keeping the host in the file is what lets you re-run the scan; keeping it out
of `ssl_domain` is what lets the re-import work.

---

## Before you rely on it

MIT licensed, no warranty — see [LICENSE](../LICENSE). More practically: this
reports what each host presented at the moment it connected, which is not
always the certificate you think you are looking at. Spot-check a few dates
against the hosts or your CA before treating the whole file as monitored, and
treat anything tagged `TLS-INSPECTED-VERIFY` as unconfirmed until you have.

It changes nothing on the hosts it touches. One TLS connection per host you
listed, the certificate read, the connection closed. No ports are scanned, no
hosts are discovered, and nothing is written anywhere except your CSV.
