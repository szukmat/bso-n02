#
# BSO N02 - install.rsc (v2)
# Skrypt instalacyjny systemu skanowania sieci lokalnej
# Sekcja 9.3 PDF - "Instalacja przez SSH (one-command)"
#
# Konfiguracja domyslna (zmien sekcje KONFIGURACJA ponizej jesli chcesz inna):
#  - email: projektbso26@gmail.com
#  - sieć skanowana: 192.168.56.0/24
#  - skan szybki: co 1h
#  - skan standardowy: co 6h
#  - skan pelny: codziennie o 03:00
#
# Po instalacji wymagane recznie tylko App Password Gmail (sekcja 9.3 PDF
# uzasadnia - poswiadczenia nie powinny byc w repozytorium publicznym)
#
# Wymagania wstepne (sekcja 2.1 PDF):
#  - RouterOS v7.x (testowane na 7.22.1)
#  - Pakiet "container" zainstalowany i aktywowany (device-mode container=yes)
#  - Zewnetrzny nosnik danych zamontowany jako sata1, sformatowany ext4
#  - Polaczenie z Internetem (registry-1.docker.io osiagalny)
#  - Dwie karty sieciowe: ether1 (WAN), ether2 (LAN do skanowania)
#
# Uzycie:
#  /tool fetch url="https://raw.githubusercontent.com/szukmat/bso-n02/main/routeros/install.rsc"
#  /import install.rsc
#

:log info "[BSO-INSTALL] Start instalacji systemu BSO N02"
:put "============================================================"
:put "BSO N02 - System skanowania sieci lokalnej"
:put "Automatyczna instalacja jednokomendowa"
:put "============================================================"
:put ""

# ===== DOMYSLNA KONFIGURACJA =====
:local cfgStorageMount "sata1"
:local cfgScanTarget "192.168.56.0/24"
:local cfgLanIp "192.168.56.1/24"
:local cfgVethIp "192.168.56.2/24"
:local cfgEmailTo "projektbso26@gmail.com"
:local cfgSmtpServer "smtp.gmail.com"
:local cfgSmtpPort 587
:local cfgDockerImage "karaskar/bso-n02:latest"
:local cfgIntervalFast "1h"
:local cfgIntervalNormal "6h"

:put "Domyslna konfiguracja:"
:put "  Email odbiorcy:  $cfgEmailTo"
:put "  Skanowana siec:  $cfgScanTarget"
:put "  Interwal fast:   $cfgIntervalFast"
:put "  Interwal normal: $cfgIntervalNormal"
:put ""
:put "UWAGA: Po instalacji nalezy ustawic App Password Gmail recznie:"
:put "  /tool/e-mail/set password=<16-znakowe-app-password>"
:put ""
:put "Aby zmienic powyzsze parametry, przerwij (Ctrl+C) i edytuj install.rsc"
:put "Kontynuuje za 5 sekund..."
:delay 5s
:put ""

# ===== 1. SPRAWDZENIE WYMAGAN =====
:put "[1/7] Sprawdzanie wymagan systemu..."

# Pakiet container
:if ([:len [/system/package/find name=container]] = 0) do={
    :log error "[BSO-INSTALL] Brak pakietu container"
    :put ""
    :put "BLAD: Pakiet container nie jest zainstalowany!"
    :put "Sciagnij z mikrotik.com (Extra packages 7.22.1):"
    :put "  https://mikrotik.com/download"
    :put "Wgraj container-7.22.1.npk przez Files i zrestartuj router."
    :error "Brak pakietu container"
}

# Device-mode
:local dmContainer [/system/device-mode/get container]
:if ($dmContainer != true) do={
    :log error "[BSO-INSTALL] device-mode container nie wlaczony"
    :put ""
    :put "BLAD: Tryb obsługi kontenerów nie jest wlaczony!"
    :put "Wykonaj:"
    :put "  /system/device-mode/update container=yes"
    :put "Nastepnie cold reboot (Maszyna -> Reset w VirtualBox)"
    :error "device-mode container=no"
}

# Storage zamontowany
:if ([:len [/disk/find mount-point=$cfgStorageMount]] = 0) do={
    :log error "[BSO-INSTALL] Brak storage $cfgStorageMount"
    :put ""
    :put "BLAD: Nie znaleziono dysku $cfgStorageMount!"
    :put "Sprawdz: /disk print"
    :put "Jesli widoczny ale nie sformatowany - sformatuj jako ext4:"
    :put "  System -> Disks -> Format Drive -> ext4"
    :error "brak storage"
}

# Storage sformatowany jako ext4
:local diskFs [/disk/get [find mount-point=$cfgStorageMount] fs]
:if ($diskFs != "ext4") do={
    :log error "[BSO-INSTALL] Storage $cfgStorageMount nie jest ext4 (jest: $diskFs)"
    :put ""
    :put "BLAD: Dysk $cfgStorageMount musi byc sformatowany jako ext4!"
    :put "Aktualnie: $diskFs"
    :put "Sformatuj recznie: System -> Disks -> Format Drive -> File System: ext4"
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

# ===== 6. POBRANIE OBRAZU Z DOCKER HUB =====
:put "[6/7] Pobieranie obrazu $cfgDockerImage z Docker Hub..."
:put "      To moze potrwac 2-5 minut, prosze czekac..."

:if ([:len [/container/find tag~"bso-n02"]] = 0) do={
    /container/add remote-image=$cfgDockerImage interface=veth-bso root-dir=($cfgStorageMount . "/bso/container/root") mountlists=bso-data envlists=bso-env logging=yes start-on-boot=no
    
    # Czekamy az kontener pojawi sie w bazie (najpierw enumeracja)
    :local appeared false
    :local tries 0
    :while ((!$appeared) and ($tries < 12)) do={
        :delay 5s
        :set tries ($tries + 1)
        :if ([:len [/container/find tag~"bso-n02"]] > 0) do={
            :set appeared true
        }
    }
    
    :if (!$appeared) do={
        :put "  UWAGA - kontener nie pojawil sie w bazie po 60s"
        :put "  Sprawdz: /container print  oraz  /log print where topics~\"container\""
    } else={
        # Czekamy na ukonczenie ekstrakcji (status stopped)
        :local extracted false
        :local tries2 0
        :while ((!$extracted) and ($tries2 < 60)) do={
            :delay 5s
            :set tries2 ($tries2 + 1)
            :local conts [/container/find tag~"bso-n02"]
            :if ([:len $conts] > 0) do={
                :local st [/container/get [:pick $conts 0] status]
                :if ($st = "stopped") do={ :set extracted true }
            }
        }
        
        :if ($extracted) do={
            :put "  OK - obraz pobrany i rozpakowany (status: stopped)"
        } else={
            :put "  UWAGA - obraz nadal sie rozpakowuje, sprawdz: /container print"
            :put "         Kontynuuje konfiguracje, sprawdz status pozniej."
        }
    }
} else={
    :put "  Kontener juz istnieje, pomijam pobieranie"
}

# ===== 7. SKRYPTY I SCHEDULER =====
:put "[7/7] Instalacja skryptow i schedulera..."

# Wyczysc stare wpisy (idempotentnosc)
/system/script/remove [find name="do-scan"]
/system/script/remove [find name="do-scan-normal"]
/system/script/remove [find name="do-scan-full"]
/system/script/remove [find name="send-report"]
/system/scheduler/remove [find name~"^bso-"]

# Skrypt: do-scan (uruchamia kontener)
/system/script/add name=do-scan source=":log info \"[BSO] Uruchamiam skan\"; /container/start [find tag~\"bso-n02\"]; :log info \"[BSO] Kontener wystartowal\""

# Skrypt: do-scan-normal (zmienia profil na normal i woluje do-scan)
/system/script/add name=do-scan-normal source="/container/envs/set [find list=bso-env key=SCAN_PROFILE] value=normal; /system/script/run do-scan"

# Skrypt: do-scan-full (zmienia profil na full i woluje do-scan)
/system/script/add name=do-scan-full source="/container/envs/set [find list=bso-env key=SCAN_PROFILE] value=full; /system/script/run do-scan"

# Skrypt: send-report (wysylka raportu mailem)
/system/script/add name=send-report source=":log info \"[BSO] Wysylam raport\"; /tool e-mail send to=\"$cfgEmailTo\" subject=\"[BSO N02] Raport skanowania sieci\" body=\"W zalaczniku raport skanowania sieci lokalnej.\" file=\"$cfgStorageMount/bso/data/state/latest_report.txt\"; :log info \"[BSO] Wyslano\""

:put "  Skrypty: do-scan, do-scan-normal, do-scan-full, send-report"

# Scheduler - 3 aktywne profile
/system/scheduler/add name=bso-scan-fast on-event=do-scan interval=$cfgIntervalFast start-time=startup comment="BSO szybki skan"
/system/scheduler/add name=bso-mail-fast on-event=send-report interval=$cfgIntervalFast start-time=00:02:00 comment="BSO wysylka po fast (2min po skanie)"
/system/scheduler/add name=bso-scan-normal on-event=do-scan-normal interval=$cfgIntervalNormal start-time=00:30:00 comment="BSO standardowy skan"
/system/scheduler/add name=bso-mail-normal on-event=send-report interval=$cfgIntervalNormal start-time=00:32:00 comment="BSO wysylka po normal"
/system/scheduler/add name=bso-scan-full on-event=do-scan-full interval=24h start-time=03:00:00 comment="BSO pelen audyt codziennie 3:00"
/system/scheduler/add name=bso-mail-full on-event=send-report interval=24h start-time=03:05:00 comment="BSO wysylka po full"

:put "  Scheduler: 6 wpisow (fast, normal, full + maile)"

# ===== KONFIGURACJA SMTP =====
:put ""
:put "Konfiguracja SMTP (Gmail)..."
/tool/e-mail/set server=$cfgSmtpServer port=$cfgSmtpPort tls=starttls
/tool/e-mail/set user=$cfgEmailTo from=$cfgEmailTo
:put "  OK - server, port, tls, from, user"
:put ""
:put "  UWAGA: Musisz recznie ustawic App Password Gmail:"
:put "    /tool/e-mail/set password=<twoje-16-znakowe-app-password>"

# ===== PODSUMOWANIE =====
:put ""
:put "============================================================"
:put "INSTALACJA ZAKONCZONA POMYSLNIE"
:put "============================================================"
:put ""
:put "WYMAGANE DZIALANIE PO INSTALACJI:"
:put ""
:put "1. Ustaw App Password SMTP (Gmail -> Security -> App Passwords):"
:put "   /tool/e-mail/set password=<16-znakowe-app-password>"
:put ""
:put "2. (Opcjonalnie) Zmien email odbiorcy jesli nie projektbso26@gmail.com:"
:put "   /tool/e-mail/set to=<inny-email>"
:put ""
:put "TEST RECZNY:"
:put "  /system/script/run do-scan       # uruchom skan (czekaj 30s)"
:put "  /system/script/run send-report   # wyslij raport mailem"
:put ""
:put "STATUS:"
:put "  /container/print                 # status kontenera"
:put "  /system/scheduler/print          # harmonogram"
:put "  /log/print where message~\"BSO\"   # logi BSO"
:put ""
:log info "[BSO-INSTALL] Instalacja zakonczona pomyslnie"
