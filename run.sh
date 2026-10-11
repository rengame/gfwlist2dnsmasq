#!/bin/sh
# Generate first, validate, then apply with rollback. No network/firewall reload.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mode=${1:---apply}
log() { printf '%s\n' "$*"; logger -t gfwlist-update "$*"; }
restore() {
    b=$1
    test -f "$b/ready" || { log 'Invalid rollback backup'; return 1; }
    for spec in "generated:$script_dir/gfwlist.conf" "persistent:/etc/dnsmasq.d/gfwlist.conf" "runtime:/tmp/dnsmasq.d/gfwlist.conf"; do
        name=${spec%%:*}; target=${spec#*:}
        if [ -f "$b/$name.absent" ]; then
            rm -f "$target"
        else
            cp -p "$b/$name.conf" "$target.rollback"
            mv -f "$target.rollback" "$target"
        fi
    done
    /etc/init.d/dnsmasq restart || return 1
    touch "$b/confirmed"
    log "Restored DNS files from $b"
}
case "$mode" in
    --rollback)
        b=${2:-}
        case "$b" in /root/gfwlist-apply-backup.*) restore "$b";; *) log 'Invalid backup path'; exit 1;; esac
        exit 0;;
    --check|--apply) ;;
    *) printf 'Usage: %s [--check|--apply|--rollback BACKUP]\n' "$0"; exit 2;;
esac
for cmd in sed base64 mktemp curl dnsmasq nft nslookup; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "Missing dependency: $cmd; no files changed."
        [ "$cmd" != base64 ] || log 'Install with: apk add coreutils-base64'
        exit 3
    fi
done
lock=/tmp/gfwlist2dnsmasq-update.lock
mkdir "$lock" 2>/dev/null || { log 'Another update is running; refusing concurrent update'; exit 1; }
work=$(mktemp -d /tmp/gfwlist-safe.XXXXXX) || { rmdir "$lock"; exit 1; }
backup=
changed=0
cleanup() {
    rc=$?
    trap - EXIT HUP INT TERM
    if [ "$changed" = 1 ]; then
        log 'Apply failed; restoring previous DNS configuration'
        restore "$backup" || log "Automatic restore failed; manually run: $script_dir/run.sh --rollback $backup"
        rc=1
    fi
    rm -rf "$work"
    rmdir "$lock"
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
cd "$script_dir"
test -f exclude.domain && test -f extra.domain
# Never let the generator overwrite the last-known-good output.
if ! ./gfwlist2dnsmasq.sh -d 1.1.1.1 -p 53 -s gfwlist -o "$work/candidate.conf" \
    --exclude-domain-file exclude.domain --extra-domain-file extra.domain; then
    log 'Generation failed; production files and dnsmasq unchanged'; exit 1
fi
test -s "$work/candidate.conf"
count=$(grep -c '^server=' "$work/candidate.conf" || true)
sets=$(grep -c '^nftset=' "$work/candidate.conf" || true)
test "$count" -ge 100 && test "$count" -eq "$sets" || { log 'Empty/incomplete rules; refusing apply'; exit 1; }
if [ -f /etc/dnsmasq.d/gfwlist.conf ]; then
    previous=$(grep -c '^server=' /etc/dnsmasq.d/gfwlist.conf || true)
    test "$count" -ge "$((previous / 2))" || { log 'Rule count dropped by over 50%; manual review required'; exit 1; }
fi
dnsmasq --test --conf-file="$work/candidate.conf"
nft list set inet fw4 gfwlist >/dev/null
log "Validated $count domain rules"
if [ "$mode" = --check ]; then
    log 'Check only: production files and DNS service unchanged'; exit 0
fi
# Ignore generated timestamp when comparing semantic content.
tail -n +4 "$work/candidate.conf" > "$work/new-body"
same=1
for target in "$script_dir/gfwlist.conf" /etc/dnsmasq.d/gfwlist.conf /tmp/dnsmasq.d/gfwlist.conf; do
    if [ -f "$target" ]; then
        tail -n +4 "$target" > "$work/old-body"
        cmp -s "$work/new-body" "$work/old-body" || same=0
    else same=0; fi
done
[ "$same" = 0 ] || { log 'Rules unchanged; DNS service not restarted'; exit 0; }
backup=$(mktemp -d /root/gfwlist-apply-backup.XXXXXX)
chmod 700 "$backup"
for spec in "generated:$script_dir/gfwlist.conf" "persistent:/etc/dnsmasq.d/gfwlist.conf" "runtime:/tmp/dnsmasq.d/gfwlist.conf"; do
    name=${spec%%:*}; target=${spec#*:}
    if [ -f "$target" ]; then cp -p "$target" "$backup/$name.conf"; else touch "$backup/$name.absent"; fi
done
touch "$backup/ready"
log "Recovery: $script_dir/run.sh --rollback $backup"
nohup sh -c 'sleep 180; test -f "$1/confirmed" || "$2" --rollback "$1"' sh "$backup" "$script_dir/run.sh" > "$backup/timer.log" 2>&1 < /dev/null &
changed=1
for target in "$script_dir/gfwlist.conf" /etc/dnsmasq.d/gfwlist.conf /tmp/dnsmasq.d/gfwlist.conf; do
    cp "$work/candidate.conf" "$target.new"
    chmod 644 "$target.new"
    mv -f "$target.new" "$target"
done
# Check the complete existing instance configs as well as the generated include.
found=0
for config in /var/etc/dnsmasq.conf.*; do
    [ -f "$config" ] || continue
    dnsmasq --test --conf-file="$config"
    found=1
done
test "$found" = 1
# conf-dir options are not reliably re-read with SIGHUP; restart DNS only.
/etc/init.d/dnsmasq restart
healthy=0
for attempt in 1 2 3 4 5; do
    if nslookup esxi.pukeng.com 127.0.0.1 > "$work/dns-check" 2>&1 && grep -q '10\.200\.0\.10' "$work/dns-check"; then healthy=1; break; fi
    sleep 1
done
test "$healthy" = 1 || { log 'DNS health check failed'; exit 1; }
touch "$backup/confirmed"
changed=0
log "Applied $count domain rules; DNS healthy; backup: $backup"
