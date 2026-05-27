# BSO N02 - System skanowania sieci lokalnej
# Obraz kontenera oparty o Alpine Linux (lekki, ~50MB)
# Zawiera nmap + NSE + Python3 do analizy XML
FROM alpine:3.20

# Instalacja narzedzi:
#  nmap         - skanowanie sieci (sekcja 6.2 PDF)
#  nmap-scripts - NSE scripts (sekcja 6.3 PDF)
#  python3      - parsowanie XML i analiza (sekcja 4.3 PDF)
#  bash         - skrypty (scan.sh, report.sh)
#  tzdata       - poprawne timestampy w raportach
RUN apk add --no-cache \
    nmap \
    nmap-scripts \
    python3 \
    bash \
    tzdata && \
    cp /usr/share/zoneinfo/Europe/Warsaw /etc/localtime && \
    echo "Europe/Warsaw" > /etc/timezone

# Katalog roboczy aplikacji
WORKDIR /app

# Kopiowanie skryptow systemu
# scan.sh    - moduł skanowania (sekcja 4.2 PDF)
# analyze.py - moduł analizy + detekcja zagrozen (sekcja 4.3 + 7 PDF)
# report.sh  - moduł raportowania (sekcja 4.4 PDF)
# entrypoint.sh - orchestracja: scan -> analyze -> report
COPY scripts/scan.sh /app/scan.sh
COPY scripts/analyze.py /app/analyze.py
COPY scripts/report.sh /app/report.sh
COPY scripts/entrypoint.sh /app/entrypoint.sh

# Uprawnienia wykonywania
RUN chmod +x /app/*.sh /app/*.py

# Domyslne zmienne srodowiskowe (nadpisywalne z RouterOS)
ENV SCAN_PROFILE=fast
ENV SCAN_TARGET=192.168.56.0/24
ENV DATA_DIR=/data

# Wolumeny montowane z hosta (sata1/bso/data)
VOLUME ["/data"]

# Entrypoint orkiestruje caly flow
ENTRYPOINT ["/app/entrypoint.sh"]
