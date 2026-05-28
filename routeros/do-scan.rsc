# ============================================================
# do-scan.rsc - FAST scan
# ============================================================

/container/envs/set [find list=bso-env key=SCAN_PROFILE] value=fast
:log info "[BSO] Uruchamiam skan FAST"
/container/start [find tag~"bso-n02"]
:log info "[BSO] Kontener wystartowal"