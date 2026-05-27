#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
============================================================
analyze.py - Modul analizy wynikow (sekcja 4.3 + 7 PDF)
============================================================
Funkcje:
  1. Parsuje XML z biezacego skanu (nmap -oX)
  2. Wczytuje poprzedni stan (state/previous_scan.json)
  3. Wykrywa: nowe hosty, znikniete hosty, nowe porty, zniknione porty
  4. Klasyfikuje ryzyko wg regul z sekcji 7.3 PDF
  5. Zapisuje wyniki do JSON (report.sh to konsumuje)
  6. Aktualizuje state na potrzeby kolejnego porownania
============================================================
"""

import sys
import os
import json
import xml.etree.ElementTree as ET
from datetime import datetime

# ---------- KONFIGURACJA REGUL DETEKCJI (sekcja 7.3 PDF) ----------
RISK_RULES = {
    # port: (poziom_ryzyka, uzasadnienie)
    23:   ("HIGH",   "Telnet - transmisja w czystym tekscie, brak szyfrowania"),
    21:   ("MEDIUM", "FTP - transmisja danych w czystym tekscie"),
    3389: ("MEDIUM", "RDP - czesty cel atakow brute-force"),
    445:  ("MEDIUM", "SMB - historia podatnosci (EternalBlue, itp.)"),
    8291: ("MEDIUM", "MikroTik Winbox - dostep administracyjny do routera"),
    22:   ("LOW",    "SSH - sprawdz uwierzytelnianie kluczem zamiast hasla"),
    80:   ("LOW",    "HTTP bez HTTPS - dane przesylane otwarcie"),
    53:   ("LOW",    "DNS - mozliwosc DNS amplification jesli otwarty"),
    443:  ("INFO",   "HTTPS - standardowo bezpieczny"),
}

NEW_HOST_RISK = ("MEDIUM", "Nowy nieznany host w sieci")
NEW_PORT_RISK = ("MEDIUM", "Nowy otwarty port na istniejacym hoscie")


# ---------- PARSOWANIE XML NMAP ----------
def parse_nmap_xml(xml_path):
    """Parsuje plik XML z nmap, zwraca slownik {host_ip: {ports: [...], hostname: str}}"""
    if not os.path.exists(xml_path):
        return {}

    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except ET.ParseError as e:
        print(f"BLAD parsowania XML: {e}", file=sys.stderr)
        return {}

    hosts = {}
    for host in root.findall("host"):
        # Adres IPv4
        addr_elem = host.find("address[@addrtype='ipv4']")
        if addr_elem is None:
            continue
        ip = addr_elem.get("addr")

        # Status hosta - bierzemy tylko "up"
        status = host.find("status")
        if status is None or status.get("state") != "up":
            continue

        # Hostname jesli wykryty
        hostname = ""
        hn_elem = host.find("hostnames/hostname")
        if hn_elem is not None:
            hostname = hn_elem.get("name", "")

        # Lista otwartych portow
        ports = []
        for p in host.findall("ports/port"):
            state = p.find("state")
            if state is None or state.get("state") != "open":
                continue
            port_num = int(p.get("portid"))
            protocol = p.get("protocol", "tcp")
            service_elem = p.find("service")
            service = service_elem.get("name", "?") if service_elem is not None else "?"
            version = ""
            if service_elem is not None:
                product = service_elem.get("product", "")
                ver = service_elem.get("version", "")
                version = f"{product} {ver}".strip()

            ports.append({
                "port": port_num,
                "protocol": protocol,
                "service": service,
                "version": version,
            })

        hosts[ip] = {
            "hostname": hostname,
            "ports": sorted(ports, key=lambda x: x["port"]),
        }

    return hosts


# ---------- PORWNANIE Z POPRZEDNIM SKANEM ----------
def compare_scans(current, previous):
    """Zwraca diff: nowe hosty, znikniete hosty, zmiany portow"""
    new_hosts = sorted(set(current.keys()) - set(previous.keys()))
    gone_hosts = sorted(set(previous.keys()) - set(current.keys()))

    port_changes = []  # lista zmian na poziomie portow
    for ip in sorted(set(current.keys()) & set(previous.keys())):
        cur_ports = {p["port"] for p in current[ip]["ports"]}
        prev_ports = {p["port"] for p in previous[ip]["ports"]}
        new_ports = sorted(cur_ports - prev_ports)
        gone_ports = sorted(prev_ports - cur_ports)
        if new_ports or gone_ports:
            port_changes.append({
                "ip": ip,
                "new_ports": new_ports,
                "gone_ports": gone_ports,
            })

    return {
        "new_hosts": new_hosts,
        "gone_hosts": gone_hosts,
        "port_changes": port_changes,
    }


# ---------- KLASYFIKACJA RYZYKA (sekcja 7.3 PDF) ----------
def classify_risks(current, diff):
    """Generuje liste detekcji zagrozen na podstawie regul"""
    risks = []

    # Reguly oparte o port (kazdy otwarty port wg slownika)
    for ip, info in current.items():
        for p in info["ports"]:
            port = p["port"]
            if port in RISK_RULES:
                level, reason = RISK_RULES[port]
                risks.append({
                    "level": level,
                    "host": ip,
                    "port": port,
                    "service": p["service"],
                    "reason": reason,
                })

    # Reguly oparte o zmiany w sieci
    for ip in diff["new_hosts"]:
        level, reason = NEW_HOST_RISK
        risks.append({
            "level": level,
            "host": ip,
            "port": None,
            "service": None,
            "reason": reason,
        })

    for change in diff["port_changes"]:
        for port in change["new_ports"]:
            level, reason = NEW_PORT_RISK
            risks.append({
                "level": level,
                "host": change["ip"],
                "port": port,
                "service": None,
                "reason": reason,
            })

    # Sortowanie: HIGH -> MEDIUM -> LOW -> INFO
    level_order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2, "INFO": 3}
    risks.sort(key=lambda r: (level_order.get(r["level"], 99), r["host"], r["port"] or 0))

    return risks


# ---------- GLOWNA FUNKCJA ----------
def main():
    data_dir = os.environ.get("DATA_DIR", "/data")
    state_dir = os.path.join(data_dir, "state")
    os.makedirs(state_dir, exist_ok=True)

    # Sciezka do ostatniego skanu (zapisana przez scan.sh)
    last_scan_pointer = os.path.join(state_dir, "last_scan_dir.txt")
    if not os.path.exists(last_scan_pointer):
        print("BLAD: brak wskaznika ostatniego skanu. Uruchom scan.sh najpierw.", file=sys.stderr)
        sys.exit(1)

    with open(last_scan_pointer) as f:
        scan_dir = f.read().strip()

    xml_path = os.path.join(scan_dir, "scan.xml")
    print(f"Analizuje: {xml_path}")

    # Parsowanie biezacego skanu
    current = parse_nmap_xml(xml_path)
    print(f"Wykryto hostow: {len(current)}")

    # Wczytanie poprzedniego stanu (jesli istnieje)
    prev_state_path = os.path.join(state_dir, "previous_scan.json")
    previous = {}
    if os.path.exists(prev_state_path):
        try:
            with open(prev_state_path) as f:
                previous = json.load(f)
        except (json.JSONDecodeError, IOError):
            print("UWAGA: nie udalo sie wczytac poprzedniego stanu - traktuje jako pierwszy skan")

    # Porownanie
    diff = compare_scans(current, previous)
    print(f"Nowe hosty: {len(diff['new_hosts'])}, Znikniete: {len(diff['gone_hosts'])}, "
          f"Zmian portow: {len(diff['port_changes'])}")

    # Klasyfikacja ryzyka
    risks = classify_risks(current, diff)
    counts = {"HIGH": 0, "MEDIUM": 0, "LOW": 0, "INFO": 0}
    for r in risks:
        counts[r["level"]] = counts.get(r["level"], 0) + 1
    print(f"Ryzyka: HIGH={counts['HIGH']} MEDIUM={counts['MEDIUM']} "
          f"LOW={counts['LOW']} INFO={counts['INFO']}")

    # Zapisanie wynikow analizy (report.sh to skonsumuje)
    analysis = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "scan_dir": scan_dir,
        "target": os.environ.get("SCAN_TARGET", "?"),
        "profile": os.environ.get("SCAN_PROFILE", "?"),
        "hosts": current,
        "diff": diff,
        "risks": risks,
        "summary": {
            "hosts_total": len(current),
            "risks_by_level": counts,
        },
    }

    analysis_path = os.path.join(state_dir, "last_analysis.json")
    with open(analysis_path, "w") as f:
        json.dump(analysis, f, indent=2, ensure_ascii=False)
    print(f"Analiza zapisana: {analysis_path}")

    # Aktualizacja "previous_scan.json" na nastepny przebieg
    with open(prev_state_path, "w") as f:
        json.dump(current, f, indent=2, ensure_ascii=False)
    print(f"Stan zaktualizowany: {prev_state_path}")


if __name__ == "__main__":
    main()
