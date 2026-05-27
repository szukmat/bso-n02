# BSO N02 - System skanowania lokalnej sieci komputerowej

System automatycznego skanowania sieci lokalnej z wykrywaniem zagrożeń i raportowaniem email, działający bezpośrednio na routerze MikroTik (RouterOS v7) z wykorzystaniem mechanizmu kontenerów.

**Projekt akademicki:** Bezpieczeństwo Systemów i Oprogramowania, semestr 26L, Politechnika Warszawska
**Autorzy:** Mateusz Karaszewski (337036), David Gąsiorek (331168)
**Temat:** N02 - System skanowania lokalnej sieci komputerowej z wykrywaniem potencjalnych zagrożeń oraz raportowaniem email dla urządzeń sieciowych typu router

## Architektura

System działa w dwóch warstwach:

- **Warstwa sterująca (RouterOS)** - zarządzanie, harmonogram, integracja z routerem, wysyłka email
- **Warstwa wykonawcza (kontener Alpine Linux)** - skanowanie nmap, analiza wyników, generacja raportu

Komunikacja przez współdzielony nośnik danych (`sata1/bso/data/`) - kontener zapisuje raport, RouterOS go odczytuje i wysyła mailem.

Szczegóły architektury i komponentów - patrz `docs/BSO.pdf` (sprawozdanie projektowe).

## Wymagania

- MikroTik RouterOS v7.x (testowane na 7.22.1, architektura x86_64)
- Pakiet `container` zainstalowany i `device-mode container=yes` aktywowane
- Co najmniej 512 MB RAM, zewnętrzny dysk SATA/USB minimum 1 GB
- Dwie karty sieciowe: WAN (ether1) i LAN (ether2) do skanowania
- Połączenie z Internetem (pobranie obrazu z Docker Hub + SMTP)

## Instalacja - one-command (sekcja 9.3 PDF)

Z poziomu Winbox terminal lub SSH:

```
/tool fetch url="https://raw.githubusercontent.com/szukmat/bso-n02/main/routeros/install.rsc"
/import install.rsc
```

Skrypt sam:
1. Sprawdza wymagania (container, device-mode, storage)
2. Tworzy strukturę katalogów na storage
3. Konfiguruje sieć (bridge-lan, veth-bso)
4. Tworzy mounty i zmienne środowiskowe
5. Pobiera obraz `karaskar/bso-n02:latest` z Docker Hub
6. Dodaje skrypty i wpisy schedulera

Po instalacji wymagana ręczna konfiguracja SMTP (App Password Gmail):

```
/tool/e-mail/set server=smtp.gmail.com port=587 tls=starttls
/tool/e-mail/set user=<gmail> from=<gmail>
/tool/e-mail/set password=<16-znakowe-app-password>
```

## Profile skanowania (sekcja 4.2 PDF)

| Profil | Porty | Opcje nmap | Częstotliwość |
|--------|-------|------------|---------------|
| `fast` | 22, 23, 80, 443, 8291 | `-T3 --host-timeout 60s` | co 1h (auto) |
| `normal` | 21, 22, 23, 53, 80, 443, 445, 3389, 8291 | `-sV -T3` | co 6h (auto) |
| `full` | 1-1024 + admin ports | `-sV --script safe` | ręczny |

Test ręczny:
```
/system/script/run do-scan         # fast
/system/script/run do-scan-normal  # normal
/system/script/run do-scan-full    # full
/system/script/run send-report     # wyślij ostatni raport mailem
```

## Reguły detekcji zagrożeń (sekcja 7.3 PDF)

| Port/Sytuacja | Poziom ryzyka | Uzasadnienie |
|---------------|---------------|--------------|
| Port 23 (Telnet) | HIGH | Transmisja w czystym tekście |
| Port 21 (FTP) | MEDIUM | Brak szyfrowania |
| Port 3389 (RDP) | MEDIUM | Częsty cel brute-force |
| Port 445 (SMB) | MEDIUM | Historia podatności (EternalBlue) |
| Port 8291 (Winbox) | MEDIUM | Dostęp administracyjny |
| Nowy host w sieci | MEDIUM | Nieznane urządzenie |
| Nowy otwarty port | MEDIUM | Zmiana wymagająca uwagi |
| Port 22 (SSH) | LOW | Sprawdź uwierzytelnianie kluczem |
| Port 80 (HTTP bez HTTPS) | LOW | Dane przesyłane otwarcie |

## Format raportu (sekcja 8.1 PDF)

Raport tekstowy zawiera sekcje:
- Nagłówek (data, sieć, profil, liczba hostów)
- Zmiany względem poprzedniego skanu (nowe/zniknięte hosty, nowe/zamknięte porty)
- Wykryte zagrożenia (HIGH/MEDIUM z uzasadnieniami)
- Aktywne hosty i usługi

Raport zapisany jako `sata1/bso/data/state/latest_report.txt` i wysłany jako załącznik email.

## Struktura repozytorium

```
bso-n02/
├── container/
│   ├── Dockerfile              # Obraz Alpine + nmap + python (sekcja 9.1)
│   └── scripts/
│       ├── scan.sh             # Moduł skanowania (sekcja 4.2)
│       ├── analyze.py          # Moduł analizy + reguły ryzyka (sekcja 4.3 + 7)
│       ├── report.sh           # Moduł raportowania (sekcja 4.4 + 8.1)
│       └── entrypoint.sh       # Orkiestracja
├── routeros/
│   ├── install.rsc             # One-command installer (sekcja 9.3)
│   └── main.rsc                # Skrypt główny (referencja)
├── docs/
│   └── BSO.pdf                 # Sprawozdanie projektowe (etap I)
└── README.md
```

## Build obrazu lokalnie (opcjonalnie)

Domyślnie obraz pobierany jest z Docker Hub (`karaskar/bso-n02:latest`). Jeśli chcesz zbudować własną wersję:

```bash
cd container/
docker build -t szukmat/bso-n02:latest .
docker login
docker push szukmat/bso-n02:latest
```

Następnie zmień `cfgDockerImage` w `routeros/install.rsc` na własny tag.

## Decyzje projektowe

### Docker Hub remote-image zamiast lokalnego .tar
W trakcie implementacji zidentyfikowano niekompatybilność formatu `docker save` w Docker Engine 25.x+ (format OCI z attestation manifest) z parserem `/container/add file=` w RouterOS. Wybrano model `remote-image=`, w którym RouterOS pobiera obraz bezpośrednio z Docker Hub. Zgodne z sekcją 4.7.4 PDF ("obraz ... udostępniany z poziomu repozytorium projektu").

### Dwa skrypty zamiast jednego
Pierwotnie planowano monolityczny skrypt `main.rsc` z pętlą `:while` czekającą na zakończenie kontenera, ale obserwowano niestabilność (`:delay` w pętli nie działał konsekwentnie w RouterOS 7.22.1). Rozdzielono na `do-scan` (uruchomienie kontenera) i `send-report` (wysyłka mailem), wywoływane osobno przez scheduler z 2-minutowym opóźnieniem. Daje to lepszą obserwowalność i niezawodność.

### Network isolation
Kontener ma własne IP w sieci LAN (192.168.56.2) przez interfejs veth podpięty do mostu z ether2. Dzięki temu skanowanie odbywa się z perspektywy "klienta" w sieci użytkownika, a router pozostaje na 192.168.56.1.

## Wykryte ograniczenia (sekcja 10.3 PDF)

- Ograniczone zasoby CHR w VM (1 GB RAM, scheduler nmap-a wpływa na CPU)
- Brak surowych pakietów - skany TCP standardowe, bez SYN stealth
- Format raportu tylko tekstowy (nie HTML/PDF - możliwe rozszerzenie)
- Brak centralnego zarządzania wieloma urządzeniami (rozszerzenie operatorskie)

## Licencja

Projekt akademicki BSO 26L PW. Wykorzystywane narzędzia open-source:
- Alpine Linux (MIT)
- nmap (NPSL)
- Python 3 (PSF License)

## Bibliografia

Pełna bibliografia w sprawozdaniu projektowym `docs/BSO.pdf`.
