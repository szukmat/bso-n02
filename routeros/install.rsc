#
# BSO N02 - install.rsc
# Skrypt instalacyjny systemu skanowania sieci lokalnej
# Sekcja 9.3 PDF - "Instalacja przez SSH (one-command)"
#
# Wymagania wstepne:
#  - RouterOS v7.x (testowane na 7.22.1)
#  - Pakiet "container" zainstalowany i aktywowany (device-mode container=yes)
#  - Zewnetrzny nosnik danych zamontowany (sata1, USB, itp.)
#  - Polaczenie z Internetem (registry-1.docker.io osiagalny)
#  - Dwie karty sieciowe: ether1 (WAN), ether2 (LAN do skanowania)
#
# Uzycie z poziomu SSH lub Winbox terminal:
#  /tool fetch url="https://raw.githubusercontent.com/szukmat/bso-n02/main/routeros/install.rsc"
#  /import install.rsc
#

:log info "[BSO-INSTALL] Start instalacji systemu BSO N02"
:put "============================================================"
:put "BSO N02 - System skanowania sieci lokalnej"
:put "Automatyczna instalacja"
:put "============================================================"

# ---------- KONFIGURACJA ----------
:local cfgStorageMount "sata1"
:local cfgScanTarget "192.168.56.0/24"
:local cfgLanIp "192.168.56.1/24"
:local cfgVethIp "192.168.56.2/24"
:local cfgEmailTo "projektbso26@gmail.com"
:local cfgDockerImage "karaskar/bso-n02:latest"

:put ""
:put "Konfiguracja:"
:put "  Storage mount: $cfgStorageMount"
:put "  Skanowana siec: $cfgScanTarget"
:put "  IP routera w LAN: $cfgLanIp"
:put "  IP kontenera: $cfgVethIp"
:put "  Email odbiorcy: $cfgEmailTo"
:put "  Obraz Docker: $cfgDockerImage"
:put ""

# ---------- 1. SPRAWDZENIE WYMAGAN ----------
:put "[1/7] Sprawdzanie wymagan systemu..."

:if ([:len [/system/package/find name=container]] = 0) do={
    :log error "[BSO-INSTALL] Brak pakietu container"
    :error "Pakiet container nie jest zainstalowany. Sciagnij z mikrotik.com i wgraj przez Files."
}

:local dmContainer [/system/device-mode/get container]
:if ($dmContainer != true) do={
    :log error "[BSO-INSTALL] device-mode container nie jest wlaczony"
    :error "Wykonaj: /system/device-mode/update container=yes (wymaga cold reboot VM)"
}

:if ([:len [/disk/find mount-point=$cfgStorageMount]] = 0) do={
    :log error "[BSO-INSTALL] Brak nosnika danych $cfgStorageMount"
    :error "Zamontuj zewnetrzny dysk i sformatuj jako ext4."
}

:put "  OK - pakiet container, device-mode, storage"

# ---------- 2. STRUKTURA KATALOGOW ----------
:put "[2/7] Tworzenie struktury katalogow na $cfgStorageMount..."

:local dirs {"bso";"bso/data";"bso/data/scans";"bso/data/reports";"bso/data/state";"bso/container"}
:foreach d in=$dirs do={
    :local full ("$cfgStorageMount/$d")
    :if ([:len [/file/find name=$full]] = 0) do={
        /file/add type=directory name=$full
        :put "  Utworzono: $full"
    }
}

# ---------- 3. KONFIGURACJA KONTENERA ----------
:put "[3/7] Konfiguracja kontenera..."

/container/config/set registry-url=https://registry-1.docker.io
/container/config/set tmpdir=($cfgStorageMount . "/bso/container/tmp")
/container/config/set memory-high=200M
:put "  OK - registry, tmpdir, memory-high"

# ---------- 4. SIEC ----------
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

# ---------- 5. MOUNTS I ENVS ----------
:put "[5/7] Konfiguracja mountow i zmiennych srodowiskowych..."

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

# ---------- 6. POBRANIE OBRAZU Z DOCKER HUB ----------
:put "[6/7] Pobieranie obrazu $cfgDockerImage z Docker Hub..."
:put "      To moze potrwac 2-5 minut..."

:if ([:len [/container/find tag~"bso-n02"]] = 0) do={
    /container/add remote-image=$cfgDockerImage interface=veth-bso root-dir=($cfgStorageMount . "/bso/container/root") mountlists=bso-data envlists=bso-env logging=yes start-on-boot=no

    :local waited 0
    :local ready false
    :while (($waited < 60) and (!$ready)) do={
        :delay 5s
        :set waited ($waited + 1)
        :if ([:len [/container/find tag~"bso-n02"]] > 0) do={
            :local st [/container/get [find tag~"bso-n02"] status]
            :if ($st = "stopped") do={ :set ready true }
        }
    }

    :if ($ready) do={
        :put "  OK - obraz pobrany i rozpakowany"
    } else={
        :put "  UWAGA - kontener moze jeszcze sie rozpakowywac, sprawdz /container print"
    }
} else={
    :put "  Kontener juz istnieje, pomijam pobieranie"
}

# ---------- 7. SKRYPTY I SCHEDULER ----------
:put "[7/7] Instalacja skryptow i schedulera..."

/system/script/remove [find name~"^(do-scan|do-scan-normal|do-scan-full|send-report)\$"]
/system/scheduler/remove [find name~"^bso-"]

/system/script/add name=do-scan source=":log info \"[BSO] Uruchamiam skan\"; /container/start [find tag~\"bso-n02\"]; :log info \"[BSO] Kontener wystartowal\""

/system/script/add name=do-scan-normal source="/container/envs/set [find list=bso-env key=SCAN_PROFILE] value=normal; /system/script/run do-scan"

/system/script/add name=do-scan-full source="/container/envs/set [find list=bso-env key=SCAN_PROFILE] value=full; /system/script/run do-scan"

/system/script/add name=send-report source=":log info \"[BSO] Wysylam raport\"; /tool e-mail send to=\"$cfgEmailTo\" subject=\"[BSO N02] Raport skanowania sieci\" body=\"W zalaczniku raport skanowania sieci lokalnej.\" file=\"$cfgStorageMount/bso/data/state/latest_report.txt\"; :log info \"[BSO] Wyslano\""

:put "  Skrypty: do-scan, do-scan-normal, do-scan-full, send-report"

/system/scheduler/add name=bso-scan-fast on-event=do-scan interval=1h start-time=startup comment="BSO szybki skan co 1h"
/system/scheduler/add name=bso-mail-fast on-event=send-report interval=1h start-time=00:02:00 comment="BSO wysylka raportu 2min po skanie fast"
/system/scheduler/add name=bso-scan-normal on-event=do-scan-normal interval=6h start-time=00:30:00 comment="BSO standardowy skan co 6h"
/system/scheduler/add name=bso-mail-normal on-event=send-report interval=6h start-time=00:32:00 comment="BSO wysylka po normal"
/system/scheduler/add name=bso-scan-full on-event=do-scan-full interval=0 disabled=yes comment="BSO pelen audyt (recznie)"

:put "  Scheduler: 5 wpisow"

# ---------- KONIEC ----------
:put ""
:put "============================================================"
:put "INSTALACJA ZAKONCZONA POMYSLNIE"
:put "============================================================"
:put ""
:put "WYMAGA RECZNEJ KONFIGURACJI (SMTP):"
:put "  /tool/e-mail/set server=smtp.gmail.com port=587 tls=starttls"
:put "  /tool/e-mail/set user=<gmail> from=<gmail>"
:put "  /tool/e-mail/set password=<app-password>"
:put ""
:put "Test recznie:"
:put "  /system/script/run do-scan       (czekaj 30s)"
:put "  /system/script/run send-report   (sprawdz email)"
:put ""
:log info "[BSO-INSTALL] Instalacja zakonczona pomyslnie"
