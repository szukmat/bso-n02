# ============================================================
# do-scan.rsc - Uruchomienie skanowania
# ============================================================
# Sekcja 5.4.2 PDF
#
# Skrypt minimalistyczny - tylko startuje kontener.
# Faktyczna logika (scan -> analyze -> report) jest w kontenerze.
# Po zakonczeniu kontener sam sie zatrzymuje.
#
# Wysylka mailem odbywa sie przez osobny skrypt 'send-report'
# uruchamiany 2 minuty po do-scan (scheduler).
# Rozdzielenie wynika z ograniczen RouterOS Script
# (problemy z polling-iem statusu kontenera w :while).
# ============================================================

:log info "[BSO] Uruchamiam skan"
/container/start [find tag~"bso-n02"]
:log info "[BSO] Kontener wystartowal"
