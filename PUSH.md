# Instrukcja: wrzucenie projektu na GitHub

## Krok 1: Załóż repo na GitHubie (jeśli jeszcze nie masz)

1. https://github.com/new
2. **Repository name:** `bso-n02`
3. **Public** (ważne)
4. NIE dodawaj README/gitignore/license
5. Create

## Krok 2: Rozpakuj plik bso-n02-github.zip

Rozpakuj gdzieś łatwo dostępnie, np. `D:\Uzytkowe\STUDIA\SEM_4\BSO\PROJEKT\bso-n02-github\`

## Krok 3: Podmień USERNAME w plikach

W plikach `README.md` i `routeros/install.rsc` zamień `USERNAME` na swoją nazwę GitHub.

PowerShell:
```powershell
cd D:\Uzytkowe\STUDIA\SEM_4\BSO\PROJEKT\bso-n02-github
(Get-Content README.md) -replace 'USERNAME', 'twoja-nazwa' | Set-Content README.md
(Get-Content routeros\install.rsc) -replace 'USERNAME', 'twoja-nazwa' | Set-Content routeros\install.rsc
```

## Krok 4: Init git + push

**Wymaga:** zainstalowanego Git (https://git-scm.com/download/win jeśli nie masz).

W PowerShell:
```powershell
cd D:\Uzytkowe\STUDIA\SEM_4\BSO\PROJEKT\bso-n02-github

git init
git add .
git commit -m "Initial commit - BSO N02 system skanowania sieci"
git branch -M main
git remote add origin https://github.com/TWOJA-NAZWA/bso-n02.git
git push -u origin main
```

Git poprosi o autoryzację - albo:
- Wpisze username + Personal Access Token (NIE hasło, GitHub od 2021 nie akceptuje haseł)
- Albo (jeśli masz GitHub CLI / Git Credential Manager) otworzy przeglądarkę

Personal Access Token tworzysz na: https://github.com/settings/tokens → Generate new token (classic) → uprawnienia: `repo`

## Krok 5: Weryfikacja

Wejdź na `https://github.com/TWOJA-NAZWA/bso-n02` - powinieneś widzieć wszystkie pliki + README się wyświetla automatycznie.

## Krok 6: Test one-command install z routera

W Winboxie terminal:
```
/tool fetch url="https://raw.githubusercontent.com/TWOJA-NAZWA/bso-n02/main/routeros/install.rsc"
```

Powinieneś widzieć log pobierania (status: finished, size: ~6KB).

Plik pojawi się w Files. Możesz go potem zaimportować na czystym routerze (po reset config) komendą:
```
/import install.rsc
```

## Alternatywa bez gita - przez GitHub web upload

Jeśli nie chcesz instalować Gita:
1. https://github.com/TWOJA-NAZWA/bso-n02 → "uploading an existing file"
2. Przeciągnij wszystkie pliki/foldery z `bso-n02-github/` na stronę
3. Commit changes
