# ============================================================
# send-report.rsc - Wysylka raportu mailem
# ============================================================
# Sekcja 4.4 + 8.2 PDF
#
# Odczytuje raport z sata1/bso/data/state/latest_report.txt
# (utworzony przez kontener po skanowaniu) i wysyla go
# jako zalacznik mailem przez /tool e-mail.
#
# SMTP musi byc skonfigurowany wczesniej w /tool e-mail
# (server, port, tls, user, from, password).
# ============================================================

:log info "[BSO] Wysylam raport"
/tool e-mail send to="projektbso26@gmail.com" \
    subject="[BSO N02] Raport skanowania sieci" \
    body="W zalaczniku raport skanowania sieci lokalnej." \
    file="sata1/bso/data/state/latest_report.txt"
:log info "[BSO] Wyslano"
