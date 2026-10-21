#!/usr/bin/env bash
#
# check-blacklist.sh — check a mail server IP (or a domain's MX hosts) against
# the major DNS blacklists (Spamhaus, SpamCop, UCEPROTECT, Barracuda).
#
# Why: a listing silently tanks deliverability. Run this from cron weekly, or
# before/after you move a VPS, and you will know *before* your mail starts
# bouncing.
#
# Usage:
#   ./check-blacklist.sh --ip 203.0.113.25
#   ./check-blacklist.sh --domain example.com        # checks all MX hosts
#   ./check-blacklist.sh --ip 203.0.113.25 --json    # machine-readable
#
# Exit codes: 0 = clean, 1 = listed on at least one blacklist, 2 = usage/error.
#
# Dependencies: dig (bind-utils / dnsutils).

set -u

# ---------------------------------------------------------------------------
# Built-in DNSBL zones. Format: "zone|description"
# ---------------------------------------------------------------------------
BLACKLISTS=(
    "zen.spamhaus.org|Spamhaus Zen (SBL+XBL+PBL)"
    "bl.spamcop.net|SpamCop"
    "dnsbl-1.uceprotect.net|UCEPROTECT Level 1"
    "dnsbl-2.uceprotect.net|UCEPROTECT Level 2"
    "b.barracudacentral.org|Barracuda Central"
    "cbl.abuseat.org|Abuseat CBL"
    "dnsbl.sorbs.net|SORBS"
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
IP="" DOMAIN="" JSON=0 TIMEOUT=4

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --ip)     IP="$2";     shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --json)   JSON=1;      shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

if [ -z "$IP" ] && [ -z "$DOMAIN" ]; then
    echo "Error: give --ip or --domain." >&2; usage; exit 2
fi

command -v dig >/dev/null 2>&1 || { echo "Error: 'dig' not found." >&2; exit 2; }

# ---------------------------------------------------------------------------
# Reverse an IPv4 or IPv6 address for DNSBL lookup.
# ---------------------------------------------------------------------------
reverse_ip() {
    local ip="$1"
    if [[ "$ip" == *:* ]]; then
        # IPv6: expand, strip colons, reverse each nibble.
        local expanded
        expanded=$(python3 -c "import ipaddress,sys; print(ipaddress.ip_address(sys.argv[1]).exploded)" "$ip" 2>/dev/null) \
            || { echo "Error: invalid IPv6 address: $ip" >&2; return 1; }
        echo "$expanded" | tr -d ':' | rev | sed 's/./&./g'
    else
        # IPv4: reverse octets.
        local IFS=.
        read -r a b c d <<< "$ip"
        [[ "$a$b$c$d" =~ ^[0-9]+$ ]] || { echo "Error: invalid IPv4 address: $ip" >&2; return 1; }
        echo "$d.$c.$b.$a"
    fi
}

# ---------------------------------------------------------------------------
# Collect the IPs to check.
# ---------------------------------------------------------------------------
IPS=()
if [ -n "$DOMAIN" ]; then
    # Resolve MX hosts, then their A/AAAA records.
    mapfile -t MXHOSTS < <(dig +short +time="$TIMEOUT" MX "$DOMAIN" | awk '{print $2}')
    [ ${#MXHOSTS[@]} -eq 0 ] && { echo "Error: no MX records found for $DOMAIN" >&2; exit 2; }
    for mx in "${MXHOSTS[@]}"; do
        mapfile -t ADDRS < <(dig +short +time="$TIMEOUT" A "$mx"; dig +short +time="$TIMEOUT" AAAA "$mx")
        for addr in "${ADDRS[@]}"; do
            [ -n "$addr" ] && IPS+=("$addr")
        done
    done
    [ ${#IPS[@]} -eq 0 ] && { echo "Error: MX hosts for $DOMAIN did not resolve." >&2; exit 2; }
else
    IPS=("$IP")
fi

# ---------------------------------------------------------------------------
# Check one IP against every list.
# ---------------------------------------------------------------------------
check_ip() {
    local ip="$1"
    local rev
    rev=$(reverse_ip "$ip") || return 2
    local listed=() hits=0

    for entry in "${BLACKLISTS[@]}"; do
        local zone="${entry%%|*}"
        local desc="${entry#*|}"
        local answer
        answer=$(dig +short +time="$TIMEOUT" +tries=1 A "${rev}.${zone}" 2>/dev/null)
        if [ -n "$answer" ]; then
            listed+=("$zone ($desc)")
            hits=$((hits + 1))
        fi
    done

    if [ "$JSON" -eq 1 ]; then
        local items=""
        for l in "${listed[@]}"; do
            items="${items}${items:+,}\"${l//\"/\\\"}\""
        done
        printf '{"ip":"%s","listed":%s,"lists":[%s]}' "$ip" "$([ $hits -gt 0 ] && echo true || echo false)" "$items"
    else
        if [ $hits -eq 0 ]; then
            echo "OK      $ip — not listed anywhere"
        else
            echo "LISTED  $ip — found on:"
            for l in "${listed[@]}"; do echo "          - $l"; done
        fi
    fi
    # 0 = clean, 1 = listed, 2 = lookup error
    [ $hits -gt 0 ] && return 1 || return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
[ "$JSON" -eq 1 ] && printf '['
first=1
overall=0
for ip in "${IPS[@]}"; do
    [ "$JSON" -eq 1 ] && [ $first -eq 0 ] && printf ','
    first=0
    check_ip "$ip"
    rc=$?
    [ $rc -eq 1 ] && overall=1    # listed
    [ $rc -eq 2 ] && overall=2    # lookup error — distinct from "listed"
done
[ "$JSON" -eq 1 ] && printf ']\n'

[ "$JSON" -eq 0 ] && echo "---" && \
    { [ $overall -eq 0 ] && echo "All clear." || echo "ACTION NEEDED: delist via each blacklist's removal page."; }

exit $overall
