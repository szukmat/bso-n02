# QUICKSTART — uruchomienie z gotowej maszyny wirtualnej (OVA)

Ten przewodnik dotyczy osób, które otrzymały gotowy plik `bso-chr-demo.ova`.
Jeśli stawiasz system od zera na własnym routerze — patrz README.md.

Maszyna-demo ma już skonfigurowane: pakiet container, device-mode=yes,
dysk sata1 (ext4), DHCP na ether1. NIE ma zainstalowanej logiki BSO —
instalujesz ją jedną komendą (poniżej).

---

## Krok 1 — Import OVA do VirtualBox

1. Zainstaluj VirtualBox: https://www.virtualbox.org/
2. VirtualBox → Plik → **Importuj urządzenie** → wskaż `bso-chr-demo.ova`
3. Import (zostaw domyślne ustawienia)

## Krok 2 — Dostosuj karty sieciowe

Ustawienia VM → Sieć:

- **Karta 1 (ether1, WAN):** Mostkowana karta sieciowa → wybierz **swoją** kartę z Internetem (Wi-Fi lub Ethernet). To źródło Internetu — potrzebne do pobrania obrazu z Docker Hub i wysyłki maili.
- **Karta 2 (ether2, LAN):** Sieć izolowana hosta (Host-only) → zostaw lub wybierz swój Host-Only Adapter. To sieć którą system skanuje.

## Krok 3 — Uruchom VM i sprawdź Internet

Start VM. Login: `admin`, hasło: `bso2026` (lub ustalone).

W konsoli sprawdź czy jest Internet:

```
/ip/address/print
/ping 8.8.8.8 count=3
```

Jeśli ether1 nie dostał IP (inna sieć niż przy budowie), odśwież DHCP:

```
/ip/dhcp-client/disable 0
/ip/dhcp-client/enable 0
/ip/address/print
```

Zanotuj IP routera — pod nim połączysz się Winboxem (opcjonalnie).

## Krok 4 — Instalacja jedną komendą

W konsoli VM (lub Winbox terminal):

```
/tool fetch url="https://raw.githubusercontent.com/szukmat/bso-n02/main/routeros/install.rsc"
/import install.rsc
```

Instalator zapyta o:
- Email odbiorcy raportów (Enter = projektbso26@gmail.com)
- Email nadawcy (Enter = ten sam)
- **App Password Gmail** (16 znaków, bez spacji) — patrz niżej jak uzyskać
- Zakres sieci CIDR (Enter = 192.168.56.0/24)

Czekaj aż pojawi się `INSTALACJA ZAKONCZONA POMYSLNIE`.

**Jeśli krok [6/7] zgłosi że kontener pobiera się w tle** — poczekaj 2 minuty
i uruchom `/import install.rsc` jeszcze raz (skrypt jest idempotentny,
pominie to co już zrobione, dokończy resztę).

## Krok 5 — Test

```
/system/script/run do-scan
```

Poczekaj aż kontener skończy (sprawdź `/container/print` — status `stopped`):

```
/container/print
/system/script/run send-report
```

Sprawdź skrzynkę e-mail — powinien przyjść raport z załącznikiem.

---

## App Password Gmail (jak uzyskać)

1. https://myaccount.google.com → Security
2. Włącz weryfikację dwuetapową (2-Step Verification), jeśli wyłączona
3. App passwords → utwórz nowe (np. nazwa "BSO router")
4. Skopiuj 16-znakowy ciąg (Google pokazuje go ze spacjami — wpisuj BEZ spacji)

---

## Status i diagnostyka

```
/container/print                    # status kontenera
/system/scheduler/print             # harmonogram skanów
/system/script/print                # zainstalowane skrypty
/log/print where message~"BSO"      # logi systemu BSO
/log/print where topics~"e-mail"    # logi wysylki maili
```

## Harmonogram (domyślny)

- Skan **fast** — co 30 min, mail 2 min później
- Skan **normal** — co 3 h
- Skan **full** — 2× dziennie (03:00 i 15:00)

## Profile skanowania

- **fast** — 5 kluczowych portów, najszybszy, bez detekcji wersji
- **normal** — 9 portów + detekcja wersji usług (`-sV`)
- **full** — porty 1-1024 + skrypty NSE wykrywające podatności (najwolniejszy)

---

Pełna dokumentacja techniczna: README.md oraz docs/BSO.pdf
