#!/bin/bash
# ============================================================
# report.sh - Modul raportowania (sekcja 4.4 + 8.1 PDF)
# ============================================================
# Generuje raport tekstowy z JSON-a stworzonego przez analyze.py
# Format zgodny z sekcja 8.1 PDF.
# Raport zapisywany do data/reports/<timestamp>.txt
# Aktualizuje data/state/latest_report.txt (RouterOS to wysyla mailem)
# ============================================================

set -e

DATA_DIR="${DATA_DIR:-/data}"
STATE_DIR="${DATA_DIR}/state"
REPORTS_DIR="${DATA_DIR}/reports"
ANALYSIS="${STATE_DIR}/last_analysis.json"

mkdir -p "${REPORTS_DIR}"

if [[ ! -f "${ANALYSIS}" ]]; then
    echo "BLAD: brak pliku analizy ${ANALYSIS}. Uruchom analyze.py najpierw." >&2
    exit 1
fi

TS=$(date +%Y%m%d_%H%M%S)
REPORT="${REPORTS_DIR}/report_${TS}.txt"
LATEST="${STATE_DIR}/latest_report.txt"

# Generowanie raportu przez Pythona (czystszy niz jq w bashu)
python3 << EOF > "${REPORT}"
import json
from datetime import datetime

with open("${ANALYSIS}") as f:
    a = json.load(f)

# ====== NAGLOWEK (sekcja 8.1 PDF) ======
print("=" * 60)
print("BSO - RAPORT SKANOWANIA SIECI LOKALNEJ")
print("=" * 60)
print(f"Data skanowania : {a['timestamp']}")
print(f"Sieć            : {a['target']}")
print(f"Profil          : {a['profile']}")
print(f"Wykryte hosty   : {a['summary']['hosts_total']}")
print()

# ====== ZMIANY WZGLEDEM POPRZEDNIEGO SKANU ======
diff = a['diff']
has_changes = bool(diff['new_hosts'] or diff['gone_hosts'] or diff['port_changes'])

print("-" * 60)
print("ZMIANY WZGLEDEM POPRZEDNIEGO SKANU")
print("-" * 60)
if not has_changes:
    print("Brak zmian.")
else:
    if diff['new_hosts']:
        print(f"[+] Nowe hosty ({len(diff['new_hosts'])}):")
        for h in diff['new_hosts']:
            print(f"      {h}")
    if diff['gone_hosts']:
        print(f"[-] Hosty niedostępne ({len(diff['gone_hosts'])}):")
        for h in diff['gone_hosts']:
            print(f"      {h}")
    for change in diff['port_changes']:
        if change['new_ports']:
            ports_str = ', '.join(str(p) for p in change['new_ports'])
            print(f"[+] {change['ip']}: nowe porty {ports_str}")
        if change['gone_ports']:
            ports_str = ', '.join(str(p) for p in change['gone_ports'])
            print(f"[-] {change['ip']}: zamkniete porty {ports_str}")
print()

# ====== WYKRYTE ZAGROZENIA ======
risks = a['risks']
counts = a['summary']['risks_by_level']
print("-" * 60)
print(f"WYKRYTE ZAGROZENIA (H:{counts['HIGH']} M:{counts['MEDIUM']} "
      f"L:{counts['LOW']} I:{counts['INFO']})")
print("-" * 60)

# Pokazujemy tylko HIGH/MEDIUM w skrocie, LOW/INFO dla peldnosci nizej
high_med = [r for r in risks if r['level'] in ('HIGH', 'MEDIUM')]
if high_med:
    for r in high_med:
        port_str = f":{r['port']}" if r['port'] else ""
        svc_str = f" ({r['service']})" if r.get('service') else ""
        print(f"[{r['level']:6}] {r['host']}{port_str}{svc_str}")
        print(f"         -> {r['reason']}")
else:
    print("Brak zagrozen poziomu HIGH/MEDIUM.")
print()

# ====== AKTYWNE HOSTY I USLUGI ======
print("-" * 60)
print("AKTYWNE HOSTY I USLUGI")
print("-" * 60)
for ip, info in sorted(a['hosts'].items()):
    hn = f" ({info['hostname']})" if info['hostname'] else ""
    print(f"{ip}{hn}")
    if not info['ports']:
        print("  brak otwartych portow")
        continue
    for p in info['ports']:
        ver = f" - {p['version']}" if p['version'] else ""
        print(f"  {p['port']:>5}/{p['protocol']} {p['service']}{ver}")
print()

# ====== STOPKA ======
print("=" * 60)
print("Raport wygenerowany automatycznie przez system BSO N02")
print("MikroTik RouterOS + Container (Alpine/nmap)")
print("=" * 60)
EOF

# Aktualizacja "latest_report.txt" - RouterOS bedzie to czytac
cp "${REPORT}" "${LATEST}"

echo "Raport zapisany: ${REPORT}"
echo "Latest:          ${LATEST}"
