#
# BSO N02 - install.rsc (v5 - interaktywny)
# System skanowania lokalnej sieci komputerowej
# Sekcja 9.3 PDF - "Instalacja przez SSH (one-command)"
#
# Wymagania wstepne (sekcja 2.1 PDF):
#  - RouterOS v7.x (testowane na 7.22.1)
#  - Pakiet "container" zainstalowany, device-mode container=yes
#  - Zewnetrzny nosnik danych jako sata1, sformatowany ext4
#  - Polaczenie z Internetem (registry-1.docker.io)
#  - Dwie karty sieciowe: ether1 (WAN), ether2 (LAN do skanowania)
#
# Uzycie:
#  /tool fetch url="https://raw.githubusercontent.com/szukmat/bso-n02/main/routeros/install.rsc"
#  /import install.rsc
#

:log info "[BSO-INSTALL] Start instalacji systemu BSO N02"
:put "============================================================"
:put "BSO N02 - System skanowania sieci lokalnej"
:put "Interaktywny instalator jednokomendowy"
:put "============================================================"
:put ""

# ===== DOMYSLNE WARTOSCI =====
:local cfgStorageMount "sata1"
:local cfgLanIp "192.168.56.1/24"
:local cfgVethIp "192.168.56.2/24"
:local cfgSmtpServer "smtp.gmail.com"
:local cfgSmtpPort 587
:local cfgDockerImage "karaskar/bso-n02:latest"
:local cfgIntervalFast "30m"
:local cfgIntervalNormal "3h"

# ===== INTERAKTYWNA KONFIGURACJA =====
:put "Konfiguracja interaktywna (Enter = wartosc domyslna):"
:put ""

# Email odbiorcy
:local cfgEmailTo [/terminal/ask prompt="Email odbiorcy raportow [projektbso26@gmail.com]:"]
:if ([:len $cfgEmailTo] = 0) do={ :set cfgEmailTo "projektbso26@gmail.com" }

# Email nadawcy (zwykle ten sam)
:local cfgEmailFrom [/terminal/ask prompt="Email nadawcy SMTP [taki sam jak odbiorcy]:"]
:if ([:len $cfgEmailFrom] = 0) do={ :set cfgEmailFrom $cfgEmailTo }

# App Password
:local cfgSmtpPass [/terminal/ask prompt="App Password Gmail (16 znakow, bez spacji):"]

# Zakres skanowania
:local cfgScanTarget [/terminal/ask prompt="Skanowana siec CIDR [192.168.56.0/24]:"]
:if ([:len $cfgScanTarget] = 0) do={ :set cfgScanTarget "192.168.56.0/24" }

:put ""
:put "Podsumowanie konfiguracji:"
:put "  Email odbiorcy:  $cfgEmailTo"
:put "  Email nadawcy:   $cfgEmailFrom"
:put "  Skanowana siec:  $cfgScanTarget"
:put "  App Password:    [ustawione: $[:len $cfgSmtpPass] znakow]"
:put ""
:delay 2s

# ===== 1. SPRAWDZENIE WYMAGAN =====
:put "[1/7] Sprawdzanie wymagan systemu..."

:if ([:len [/system/package/find name=container]] = 0) do={
    :log error "[BSO-INSTALL] Brak pakietu container"
    :put "BLAD: Pakiet container nie zainstalowany. Sciagnij z mikrotik.com, wgraj przez Files, reboot."
    :error "Brak pakietu container"
}

:local dmContainer [/system/device-mode/get container]
:if ($dmContainer != true) do={
    :log error "[BSO-INSTALL] device-mode container nie wlaczony"
    :put "BLAD: Wykonaj /system/device-mode/update container=yes i cold reboot (VirtualBox Reset)"
    :error "device-mode container=no"
}

:if ([:len [/disk/find mount-point=$cfgStorageMount]] = 0) do={
    :log error "[BSO-INSTALL] Brak storage $cfgStorageMount"
    :put "BLAD: Brak dysku $cfgStorageMount. Sprawdz /disk print, sformatuj jako ext4."
    :error "brak storage"
}

:local diskFs [/disk/get [find mount-point=$cfgStorageMount] fs]
:if ($diskFs != "ext4") do={
    :log error "[BSO-INSTALL] Storage nie ext4 (jest: $diskFs)"
    :put "BLAD: Dysk $cfgStorageMount musi byc ext4. Sformatuj: System -> Disks -> Format Drive -> ext4"
    :error "storage nie ext4"
}

:put "  OK - pakiet container, device-mode, storage ext4"

# ===== 2. STRUKTURA KATALOGOW =====
:put "[2/7] Tworzenie struktury katalogow na $cfgStorageMount..."

:local dirs {"bso";"bso/data";"bso/data/scans";"bso/data/reports";"bso/data/state";"bso/container"}
:foreach d in=$dirs do={
    :local full ("$cfgStorageMount/$d")
    :if ([:len [/file/find name=$full]] = 0) do={
        /file/add type=directory name=$full
        :put "  Utworzono: $full"
    } else={
        :put "  Istnieje:  $full (pomijam)"
    }
}

# ===== 3. KONFIGURACJA KONTENERA =====
:put "[3/7] Konfiguracja kontenera..."
/container/config/set registry-url=https://registry-1.docker.io
/container/config/set tmpdir=($cfgStorageMount . "/bso/container/tmp")
/container/config/set memory-high=200M
:put "  OK - registry, tmpdir, memory-high=200M"

# ===== 4. SIEC LAN =====
:put "[4/7] Konfiguracja sieci LAN..."

:if ([:len [/interface/bridge/find name=bridge-lan]] = 0) do={
    /interface/bridge/add name=bridge-lan
    :put "  Utworzono bridge-lan"
}
:if ([:len [/interface/bridge/port/find interface=ether2]] = 0) do={
    /interface/bridge/port/add bridge=bridge-lan interface=ether2
    :put "  Podpieto ether2 do bridge-lan"
}
:if ([:len [/interface/veth/find name=veth-bso]] = 0) do={
    /interface/veth/add name=veth-bso address=$cfgVethIp gateway=[:pick $cfgLanIp 0 [:find $cfgLanIp "/"]]
    :put "  Utworzono veth-bso"
}
:if ([:len [/interface/bridge/port/find interface=veth-bso]] = 0) do={
    /interface/bridge/port/add bridge=bridge-lan interface=veth-bso
    :put "  Podpieto veth-bso do bridge-lan"
}
:if ([:len [/ip/address/find interface=bridge-lan]] = 0) do={
    /ip/address/add address=$cfgLanIp interface=bridge-lan
    :put "  Dodano IP $cfgLanIp na bridge-lan"
}

# ===== 5. MOUNTS I ENVS =====
:put "[5/7] Konfiguracja mountow i envs..."

:if ([:len [/container/mounts/find list=bso-data]] = 0) do={
    /container/mounts/add list=bso-data src=("/" . $cfgStorageMount . "/bso/data") dst=/data
    :put "  Mount bso-data: /$cfgStorageMount/bso/data -> /data"
}
:if ([:len [/container/envs/find list=bso-env key=SCAN_PROFILE]] = 0) do={
    /container/envs/add list=bso-env key=SCAN_PROFILE value=fast
}
:if ([:len [/container/envs/find list=bso-env key=SCAN_TARGET]] = 0) do={
    /container/envs/add list=bso-env key=SCAN_TARGET value=$cfgScanTarget
}
:if ([:len [/container/envs/find list=bso-env key=DATA_DIR]] = 0) do={
    /container/envs/add list=bso-env key=DATA_DIR value=/data
}
:put "  OK - envs (SCAN_PROFILE, SCAN_TARGET, DATA_DIR)"

# ===== 6. POBRANIE OBRAZU =====
:put "[6/7] Pobieranie obrazu $cfgDockerImage z Docker Hub..."

:do {
    :if ([:len [/container/find tag~"bso-n02"]] = 0) do={
        /container/add remote-image=$cfgDockerImage interface=veth-bso root-dir=($cfgStorageMount . "/bso/container/root") mountlists=bso-data envlist=bso-env logging=yes start-on-boot=no
        :put "  Obraz dodany - pobieranie i ekstrakcja trwa w tle (2-5 min)"
        :put "  Gdy zakonczy sie ekstrakcja, kontener bedzie gotowy (status: stopped)"
        :put "  Sprawdz: /container print"
    } else={
        :put "  Kontener juz istnieje, pomijam pobieranie"
    }
} on-error={
    :put "  INFO: pobieranie obrazu uruchomione w tle"
    :put "  Jesli kontener nie pojawi sie - uruchom /import install.rsc ponownie za 2 min"
}

# ===== 7. SKRYPTY I SCHEDULER =====
:put "[7/7] Instalacja skryptow i schedulera..."

/system/script/remove [find name="do-scan"]
/system/script/remove [find name="do-scan-normal"]
/system/script/remove [find name="do-scan-full"]
/system/script/remove [find name="send-report"]
/system/scheduler/remove [find name~"^bso-"]

/system/script/add name=do-scan source="/container/envs/set [find list=bso-env key=SCAN_PROFILE] value=fast; :log info \"[BSO] Uruchamiam skan FAST\"; /container/start [find tag~\"bso-n02\"]; :log info \"[BSO] Kontener wystartowal\""

/system/script/add name=do-scan-normal source="/container/envs/set [find list=bso-env key=SCAN_PROFILE] value=normal; :log info \"[BSO] Uruchamiam skan NORMAL\"; /container/start [find tag~\"bso-n02\"]; :log info \"[BSO] Kontener wystartowal\""

/system/script/add name=do-scan-full source="/container/envs/set [find list=bso-env key=SCAN_PROFILE] value=full; :log info \"[BSO] Uruchamiam skan FULL\"; /container/start [find tag~\"bso-n02\"]; :log info \"[BSO] Kontener wystartowal\""

/system/script/add name=send-report source=":log info \"[BSO] Wysylam raport\"; /tool e-mail send to=\"$cfgEmailTo\" subject=\"[BSO N02] Raport skanowania sieci\" body=\"W zalaczniku raport skanowania sieci lokalnej.\" file=\"$cfgStorageMount/bso/data/state/latest_report.txt\"; :log info \"[BSO] Wyslano\""

:put "  Skrypty: do-scan, do-scan-normal, do-scan-full, send-report"

/system/scheduler/add name=bso-scan-fast on-event=do-scan interval=$cfgIntervalFast start-time=startup comment="BSO szybki skan"
/system/scheduler/add name=bso-mail-fast on-event=send-report interval=$cfgIntervalFast start-time=00:02:00 comment="BSO wysylka po fast"
/system/scheduler/add name=bso-scan-normal on-event=do-scan-normal interval=$cfgIntervalNormal start-time=00:30:00 comment="BSO standardowy skan"
/system/scheduler/add name=bso-mail-normal on-event=send-report interval=$cfgIntervalNormal start-time=00:34:00 comment="BSO wysylka po normal"
/system/scheduler/add name=bso-scan-full on-event=do-scan-full interval=12h start-time=03:00:00 comment="BSO pelen audyt 2x dziennie"
/system/scheduler/add name=bso-mail-full on-event=send-report interval=12h start-time=03:07:00 comment="BSO wysylka po full"

:put "  Scheduler: 6 wpisow (fast, normal, full + maile)"

# ===== KONFIGURACJA SMTP =====
:put ""
:put "Konfiguracja SMTP (Gmail)..."
/tool/e-mail/set server=$cfgSmtpServer port=$cfgSmtpPort tls=starttls
/tool/e-mail/set user=$cfgEmailFrom from=$cfgEmailFrom
:if ([:len $cfgSmtpPass] > 0) do={
    /tool/e-mail/set password=$cfgSmtpPass
    :put "  OK - SMTP w pelni skonfigurowany (server, port, tls, user, from, password)"
} else={
    :put "  OK - SMTP czesciowo (BRAK App Password!)"
    :put "  Ustaw recznie: /tool/e-mail/set password=<app-password>"
}

# ===== PODSUMOWANIE =====
:put ""
:put "============================================================"
:put "INSTALACJA ZAKONCZONA POMYSLNIE"
:put "============================================================"
:put ""
:put "TEST RECZNY:"
:put "  /system/script/run do-scan         # fast"
:put "  /system/script/run do-scan-normal  # normal"
:put "  /system/script/run do-scan-full    # full"
:put "  /container/print                   # czekaj az kontener bedzie STOPPED"
:put "  /system/script/run send-report     # wyslij ostatni gotowy raport"
:put ""
:put "STATUS:"
:put "  /container/print"
:put "  /system/scheduler/print"
:put "  /log/print where message~\"BSO\""
:put ""
:put "UWAGA: jesli kontener jeszcze sie pobiera, poczekaj 2 min"
:put "       przed pierwszym /system/script/run do-scan"
:put ""
:log info "[BSO-INSTALL] Instalacja zakonczona"
