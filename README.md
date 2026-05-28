# BSO N02 — System skanowania lokalnej sieci komputerowej

Automatyczny system skanowania sieci lokalnej z wykrywaniem zagrożeń i raportowaniem e-mail, działający bezpośrednio na routerze MikroTik (RouterOS v7) z wykorzystaniem mechanizmu kontenerów.

**Projekt akademicki** — Bezpieczeństwo Systemów i Oprogramowania, semestr 26L, Politechnika Warszawska
**Autorzy:** Mateusz Karaszewski (337036), David Gąsiorek (331168)
**Temat:** N02 — System skanowania lokalnej sieci komputerowej z wykrywaniem potencjalnych zagrożeń oraz raportowaniem e-mail dla urządzeń sieciowych typu router

---

## Spis treści
- [Architektura](#architektura)
- [Wymagania](#wymagania)
- [Szybki start](#szybki-start)
- [Przygotowanie routera (pre-requisites)](#przygotowanie-routera-pre-requisites)
- [Instalacja one-command](#instalacja-one-command)
- [Profile skanowania](#profile-skanowania)
- [Reguły detekcji zagrożeń](#reguły-detekcji-zagrożeń)
- [Format raportu](#format-raportu)
- [Struktura repozytorium](#struktura-repozytorium)
- [Build obrazu lokalnie](#build-obrazu-lokalnie)
- [Decyzje projektowe](#decyzje-projektowe)
- [Ograniczenia](#ograniczenia)

---

## Architektura

System działa w dwóch warstwach:

- **Warstwa sterująca (RouterOS)** — zarządzanie, harmonogram (scheduler), integracja z routerem, wysyłka e-mail przez `/tool e-mail`
- **Warstwa wykonawcza (kontener Alpine Linux)** — skanowanie nmap, analiza wyników, generacja raportu

Komunikacja odbywa się przez współdzielony nośnik danych (`sata1/bso/data/`): kontener zapisuje raport, RouterOS go odczytuje i wysyła mailem.

```
        Internet (SMTP, Docker Hub)
              |
          [ether1 WAN]
              |
   +----------+------------------------+
   |     MikroTik RouterOS             |
   |  /tool e-mail  /system scheduler  |
   |  /system script  /container       |
   +----------+------------------------+
          |              |
     [ether2 LAN]   [veth-bso]
          |              |
          +-- bridge-lan (192.168.56.0/24) --+
                         |
                  [kontener Alpine]
                   nmap + skrypty
                   (skanuje siec klienta)
```

Szczegóły architektury i komponentów — patrz `docs/BSO.pdf` (sprawozdanie projektowe, etap I).

---

## Wymagania

- MikroTik RouterOS **v7.x** (testowane na 7.22.1, architektura x86_64 / CHR)
- Pakiet **container** zainstalowany, `device-mode container=yes` aktywowane
- Minimum 512 MB RAM, zewnętrzny dysk SATA/USB ≥ 1 GB sformatowany ext4
- Dwie karty sieciowe: **ether1** (WAN, Internet) i **ether2** (LAN do skanowania)
- Połączenie z Internetem (pobranie obrazu z Docker Hub + SMTP)
- Konto Gmail z wygenerowanym **App Password** (do wysyłki raportów)

---

## Szybki start

```
# 1. Pobierz instalator z GitHub
/tool fetch url="https://raw.githubusercontent.com/szukmat/bso-n02/main/routeros/install.rsc"

# 2. Uruchom (skrypt zapyta o email, App Password, zakres sieci)
/import install.rsc

# 3. Test
/system/script/run do-scan
# czekaj 30s
/system/script/run send-report
```

Jeśli używasz dołączonej **gotowej maszyny wirtualnej** (`bso-chr-golden.ova`), pre-requisites są już skonfigurowane — przejdź od razu do kroku 1. Wystarczy dostosować kartę sieciową WAN do własnej sieci.

---

## Przygotowanie routera (pre-requisites)

Te kroki wykonuje się **raz**, przed instalacją. W scenariuszu operatorskim router jest dostarczany klientowi już przygotowany (sekcja 2.1.2 PDF — aktywacja kontenerów wymaga fizycznej obecności urządzenia).

### 1. Pakiet container

Pobierz `container-7.22.1.npk` z [mikrotik.com/download](https://mikrotik.com/download) (Extra packages, zgodna wersja i architektura). Wgraj przez Winbox → Files (drag & drop), następnie:

```
/system/reboot
```

Po reboocie sprawdź: `/system/package/print` — powinien być `container`.

### 2. Tryb obsługi kontenerów

```
/system/device-mode/update container=yes
```

RouterOS poprosi o cold reboot (twardy restart — w VirtualBox: Maszyna → Reset). Po reboocie:

```
/system/device-mode/print
```

Sprawdź `container: yes`.

### 3. Dysk storage (ext4)

W Winbox → System → Disks → wybierz zewnętrzny dysk → **Format Drive** → File System: **ext4**. Mount point powinien być `sata1`. Sprawdź:

```
/disk/print
```

### 4. Internet na ether1

```
/ip/dhcp-client/add interface=ether1 disabled=no
/ping 8.8.8.8 count=3
```

---

## Instalacja one-command

```
/tool fetch url="https://raw.githubusercontent.com/szukmat/bso-n02/main/routeros/install.rsc"
/import install.rsc
```

Instalator interaktywnie zapyta o:
- **Email odbiorcy** raportów (Enter = domyślny)
- **Email nadawcy** SMTP (Enter = ten sam co odbiorcy)
- **App Password** Gmail (16 znaków bez spacji)
- **Zakres sieci** CIDR do skanowania (Enter = 192.168.56.0/24)

Następnie automatycznie wykonuje 7 kroków: weryfikacja wymagań → struktura katalogów → konfiguracja kontenera → sieć LAN → mounty i envs → pobranie obrazu z Docker Hub → skrypty i scheduler. Na końcu konfiguruje SMTP.

**Uwaga:** pobranie obrazu z Docker Hub (krok 6) trwa 2–5 min i odbywa się w tle. Jeśli skrypt zgłosi problem na tym etapie, poczekaj 2 min i uruchom `/import install.rsc` ponownie — skrypt jest **idempotentny** (pomija już skonfigurowane elementy).

### App Password Gmail

1. [myaccount.google.com](https://myaccount.google.com) → Security
2. Włącz 2-Step Verification (jeśli wyłączone)
3. App passwords → utwórz nowe → skopiuj 16-znakowy ciąg
4. Wpisz w instalatorze (bez spacji)

---

## Profile skanowania

System obsługuje trzy profile o różnym poziomie szczegółowości (sekcja 4.2 PDF):

| Profil | Porty | Opcje nmap | Domyślny harmonogram |
|--------|-------|------------|----------------------|
| `fast` | 22, 23, 80, 443, 8291 | `-T3 --host-timeout 60s` | co 30 min (auto) |
| `normal` | 21, 22, 23, 53, 80, 443, 445, 3389, 8291 | `-sV -T3` | co 3 h (auto) |
| `full` | 1–1024 + porty administracyjne | `-sV --script safe` | 2× dziennie (auto) |

**Czym się różnią:**
- `fast` — sprawdza tylko czy najważniejsze porty są otwarte. Lekki, do częstego monitoringu.
- `normal` — dodaje detekcję wersji usług (`-sV`): nie tylko "port otwarty", ale jaka usługa i w jakiej wersji.
- `full` — najszerszy zakres portów + skrypty NSE kategorii `safe` wykrywające potencjalne podatności. Najwolniejszy, najbardziej obciąża router — stąd uruchamiany rzadziej.

Test ręczny:
```
/system/script/run do-scan         # fast
/system/script/run do-scan-normal  # normal
/system/script/run do-scan-full    # full
/system/script/run send-report     # wyślij ostatni raport mailem
```

---

## Reguły detekcji zagrożeń

Detekcja heurystyczna oparta o reguły (sekcja 7.3 PDF):

| Port / sytuacja | Poziom ryzyka | Uzasadnienie |
|-----------------|---------------|--------------|
| Port 23 (Telnet) | **HIGH** | Transmisja w czystym tekście, brak szyfrowania |
| Port 21 (FTP) | MEDIUM | Brak szyfrowania danych |
| Port 3389 (RDP) | MEDIUM | Częsty cel ataków brute-force |
| Port 445 (SMB) | MEDIUM | Historia podatności (EternalBlue) |
| Port 8291 (Winbox) | MEDIUM | Dostęp administracyjny do routera |
| Nowy host w sieci | MEDIUM | Nieznane urządzenie |
| Nowy otwarty port | MEDIUM | Zmiana konfiguracji wymagająca uwagi |
| Port 22 (SSH) | LOW | Zalecane uwierzytelnianie kluczem |
| Port 80 (HTTP bez HTTPS) | LOW | Dane przesyłane otwarcie |

System **nie wykonuje aktywnej eksploitacji** — identyfikuje jedynie symptomy zwiększonego ryzyka (zgodnie z założeniem nieinwazyjności, NFR8 PDF).

---

## Format raportu

Raport tekstowy (sekcja 8.1 PDF) zawiera sekcje:
- **Nagłówek** — data, sieć, profil, liczba hostów
- **Zmiany względem poprzedniego skanu** — nowe/zniknięte hosty, nowe/zamknięte porty
- **Wykryte zagrożenia** — poziomy HIGH/MEDIUM z uzasadnieniami
- **Aktywne hosty i usługi** — pełna lista

Raport zapisywany jako `sata1/bso/data/state/latest_report.txt` i wysyłany jako załącznik e-mail.

---

## Struktura repozytorium

```
bso-n02/
├── container/
│   ├── Dockerfile              # Obraz Alpine + nmap + python (sekcja 9.1)
│   └── scripts/
│       ├── scan.sh             # Moduł skanowania (sekcja 4.2)
│       ├── analyze.py          # Moduł analizy + reguły ryzyka (sekcja 4.3 + 7)
│       ├── report.sh           # Moduł raportowania (sekcja 4.4 + 8.1)
│       └── entrypoint.sh       # Orkiestracja scan -> analyze -> report
├── routeros/
│   ├── install.rsc             # Interaktywny instalator one-command (sekcja 9.3)
│   ├── do-scan.rsc             # Skrypt uruchamiajacy kontener (referencja)
│   ├── send-report.rsc         # Skrypt wysylki raportu (referencja)
│   └── main.rsc                # Skrypt glowny (referencja)
├── docs/
│   └── BSO.pdf                 # Sprawozdanie projektowe (etap I)
├── PUSH.md                     # Instrukcja wgrania na GitHub
└── README.md
```

---

## Build obrazu lokalnie

Domyślnie obraz pobierany jest z Docker Hub (`karaskar/bso-n02:latest`). Aby zbudować własną wersję:

```bash
cd container/
docker build -t TWOJ_USER/bso-n02:latest .
docker login
docker push TWOJ_USER/bso-n02:latest
```

Następnie zmień `cfgDockerImage` w `routeros/install.rsc` na własny tag.

---

## Decyzje projektowe

### Docker Hub remote-image zamiast lokalnego .tar
W trakcie implementacji zidentyfikowano niekompatybilność formatu `docker save` w Docker Engine 25.x+ (format OCI z attestation manifest) z parserem `/container/add file=` w RouterOS. Wybrano model `remote-image=`, w którym RouterOS pobiera obraz bezpośrednio z Docker Hub. Zgodne z sekcją 4.7.4 PDF ("obraz ... udostępniany z poziomu repozytorium projektu").

### Rozdzielenie skryptów (do-scan + send-report)
Pierwotnie planowano monolityczny skrypt z pętlą `:while` czekającą na zakończenie kontenera, ale obserwowano niestabilność `:delay` w pętli (RouterOS 7.22.1). Rozdzielono na `do-scan` (uruchomienie kontenera) i `send-report` (wysyłka), wywoływane osobno przez scheduler z 2-minutowym opóźnieniem. Daje lepszą obserwowalność i niezawodność.

### Izolacja sieciowa kontenera
Kontener ma własne IP (192.168.56.2) w sieci LAN przez interfejs veth podpięty do mostu z ether2. Skanowanie odbywa się z perspektywy "klienta" w sieci użytkownika. Kontener NIE ma dostępu do WAN — podnosi to bezpieczeństwo (minimalizacja powierzchni ataku, sekcja 2.1.3 PDF).

### Konfiguracja interaktywna zamiast hardcoded
Instalator używa `/terminal/ask` do zebrania email, App Password i zakresu sieci podczas importu. App Password NIE jest przechowywane w repozytorium publicznym (sekcja 2.0.2 NFR7 PDF — poświadczenia nie powinny być jawne w kodzie).

---

## Ograniczenia

(sekcja 10.3 PDF)
- Ograniczone zasoby CHR w środowisku VM (RAM, scheduler nmap-a wpływa na CPU)
- Brak surowych pakietów — skany TCP standardowe, bez SYN stealth
- Format raportu tylko tekstowy (HTML/PDF jako możliwe rozszerzenie)
- Brak centralnego zarządzania wieloma urządzeniami (rozszerzenie operatorskie)

---

## Licencja i narzędzia open-source

Projekt akademicki BSO 26L PW. Wykorzystane narzędzia:
- Alpine Linux (MIT)
- nmap + NSE (Nmap Public Source License)
- Python 3 (PSF License)

Pełna bibliografia w sprawozdaniu `docs/BSO.pdf`.