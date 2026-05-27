#!/bin/bash
# ============================================================
# scan.sh - Modul skanowania sieci (sekcja 4.2 i 6 PDF)
# ============================================================
# Trzy profile skanowania:
#   fast    - szybki monitoring cykliczny (5 portow, bez NSE)
#   normal  - bilans (9 portow z sekcji 6.1 PDF + -sV)
#   full    - pelen audyt (porty 1-1024 + NSE safe)
#
# Argumenty (lub zmienne srodowiskowe):
#   $1 / SCAN_PROFILE - fast | normal | full
#   $2 / SCAN_TARGET  - CIDR np. 192.168.56.0/24
# ============================================================

set -e

PROFILE="${1:-${SCAN_PROFILE:-fast}}"
TARGET="${2:-${SCAN_TARGET:-192.168.56.0/24}}"
DATA_DIR="${DATA_DIR:-/data}"

# Timestamp dla nazwy katalogu z wynikami
TS=$(date +%Y%m%d_%H%M%S)
OUT_DIR="${DATA_DIR}/scans/${TS}_${PROFILE}"
mkdir -p "${OUT_DIR}"

XML_OUT="${OUT_DIR}/scan.xml"
TXT_OUT="${OUT_DIR}/scan.txt"
LOG="${OUT_DIR}/scan.log"

echo "============================================" | tee -a "${LOG}"
echo "BSO Scan - profil: ${PROFILE}, target: ${TARGET}" | tee -a "${LOG}"
echo "Start: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "============================================" | tee -a "${LOG}"

# Profil decyduje o parametrach nmap (sekcja 4.2 PDF)
case "${PROFILE}" in
  fast)
    # Szybki przeglad - tylko najczestsze porty admin/web
    PORTS="22,23,80,443,8291"
    NMAP_OPTS="-T3 --max-retries 1 --host-timeout 60s"
    NSE_OPTS=""
    ;;
  normal)
    # Standardowy - porty z sekcji 6.1 PDF + detekcja wersji
    PORTS="21,22,23,53,80,443,445,3389,8291"
    NMAP_OPTS="-sV -T3 --max-retries 2 --host-timeout 120s"
    NSE_OPTS=""
    ;;
  full)
    # Pelen audyt - szeroki zakres + NSE safe
    PORTS="1-1024,3389,8291"
    NMAP_OPTS="-sV -T3 --max-retries 2 --host-timeout 300s"
    NSE_OPTS="--script safe"
    ;;
  *)
    echo "BLAD: nieznany profil '${PROFILE}'. Dozwolone: fast|normal|full" | tee -a "${LOG}"
    exit 1
    ;;
esac

echo "Porty: ${PORTS}" | tee -a "${LOG}"
echo "Opcje nmap: ${NMAP_OPTS} ${NSE_OPTS}" | tee -a "${LOG}"
echo "" | tee -a "${LOG}"

# Wykonanie skanu - XML do dalszej analizy, TXT do podgladu
# -Pn pomija ping discovery (czesc hostow filtruje ICMP)
#     w naszej sieci host-only ICMP dziala, ale lepiej miec to wlaczone
#     dla scenariuszy SOHO gdzie firewalle blokuja pingi
nmap ${NMAP_OPTS} ${NSE_OPTS} \
     -p "${PORTS}" \
     -oX "${XML_OUT}" \
     -oN "${TXT_OUT}" \
     "${TARGET}" 2>&1 | tee -a "${LOG}"

EXIT_CODE=${PIPESTATUS[0]}

echo "" | tee -a "${LOG}"
echo "Koniec: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "${LOG}"
echo "Exit code: ${EXIT_CODE}" | tee -a "${LOG}"
echo "Wyniki: ${OUT_DIR}" | tee -a "${LOG}"

# Zapisz sciezke ostatniego skanu - analyze.py to przeczyta
echo "${OUT_DIR}" > "${DATA_DIR}/state/last_scan_dir.txt"

exit ${EXIT_CODE}
