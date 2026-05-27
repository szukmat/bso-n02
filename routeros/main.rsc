#
# BSO N02 - main.rsc (standalone reference)
#
# Sekcja 5.4.2 PDF - pseudokod algorytmu integracji z RouterOS
# 
# Ten plik jest referencyjny. W produkcji uzywamy dwoch oddzielnych
# skryptow (do-scan + send-report) zarzadzanych przez scheduler,
# co daje wieksza niezawodnosc (brak blokujacej petli :while w 
# tle - patrz Decyzje projektowe w README).
#

:log info "[BSO] Uruchamiam skan"
/container/start [find tag~"bso-n02"]
:log info "[BSO] Kontener wystartowal, czekam na zakonczenie..."

# Czekanie zewnetrzne realizuje scheduler (mail wysylany 2min pozniej)
# Skrypt 'send-report' robi wysylke i jest wywolywany osobnym wpisem.
