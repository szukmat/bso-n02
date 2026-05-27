#!/bin/bash
# ============================================================
# entrypoint.sh - Orkiestracja procesu w kontenerze
# ============================================================
# Wykonuje sekwencyjnie:
#   1. scan.sh    - skanowanie sieci
#   2. analyze.py - analiza wynikow i klasyfikacja ryzyka
#   3. report.sh  - generacja raportu tekstowego
# 
# Po zakonczeniu kontener wychodzi (exit 0/1).
# RouterOS po zatrzymaniu kontenera odczytuje data/state/latest_report.txt
# i wysyla mailem.
# ============================================================

set -e

DATA_DIR="${DATA_DIR:-/data}"

# Upewnij sie ze katalogi istnieja (na wypadek pierwszego uruchomienia)
mkdir -p "${DATA_DIR}/scans" "${DATA_DIR}/reports" "${DATA_DIR}/state"

echo "############################################################"
echo "# BSO N02 - System skanowania sieci"
echo "# Profil: ${SCAN_PROFILE}, Target: ${SCAN_TARGET}"
echo "# Start: $(date '+%Y-%m-%d %H:%M:%S')"
echo "############################################################"

# Krok 1: skanowanie
echo ""
echo ">>> KROK 1/3: Skanowanie sieci..."
/app/scan.sh "${SCAN_PROFILE}" "${SCAN_TARGET}"

# Krok 2: analiza
echo ""
echo ">>> KROK 2/3: Analiza wynikow..."
/app/analyze.py

# Krok 3: raport
echo ""
echo ">>> KROK 3/3: Generacja raportu..."
/app/report.sh

echo ""
echo "############################################################"
echo "# BSO N02 - Zakonczone pomyslnie"
echo "# Koniec: $(date '+%Y-%m-%d %H:%M:%S')"
echo "############################################################"
