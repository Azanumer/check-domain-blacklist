# check-domain-blacklist

Check a mail server IP — or every MX host of a domain — against the major DNS blacklists (Spamhaus Zen, SpamCop, UCEPROTECT, Barracuda, Abuseat CBL, SORBS).

## Why

A DNSBL listing silently kills your deliverability: Gmail/Outlook start deferring or junking your mail and you only notice when clients complain. Run this weekly from cron, or right before/after a VPS move, and you'll know *before* mail starts bouncing.

## Usage

```bash
./check-blacklist.sh --ip 203.0.113.25
./check-blacklist.sh --domain example.com        # checks all MX hosts
./check-blacklist.sh --ip 203.0.113.25 --json    # machine-readable output
```

Exit codes: `0` = clean, `1` = listed on ≥1 blacklist, `2` = usage/DNS error — so it plugs straight into Nagios/cron alerts.

## Features

- IPv4 **and** IPv6 (proper nibble-reversed lookups)
- `--domain` mode resolves MX → A/AAAA and checks every mail host
- `--json` output for monitoring pipelines
- Short per-list timeouts so one dead DNSBL doesn't stall the run
- Only dependency is `dig` (`bind9-dnsutils` / `bind-utils`)

## Example

```
$ ./check-blacklist.sh --domain example.com
OK      203.0.113.10 — not listed anywhere
LISTED  203.0.113.11 — found on:
          - bl.spamcop.net (SpamCop)
          - dnsbl-1.uceprotect.net (UCEPROTECT Level 1)
---
ACTION NEEDED: delist via each blacklist's removal page.
```

## License

MIT — see [LICENSE](LICENSE).
