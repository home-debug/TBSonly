# TBS Drivers - Notatki projektu

## Cel
Kompilacja sterowników TBS dla kernela dystrybucji (bez rekompilacji kernela),
z możliwością dostosowania do nowszych kerneli przez dopisywanie patchy.

## Założenia
- Kernel z dystrybucji - nie rekompilujemy
- Kompilujemy TYLKO sterowniki TBS jako moduły zewnętrzne (obj-m)
- Nic nie usuwamy ze źródeł TBS - skrypt naprawia problemy dynamicznie
- Nie używamy DKMS - każdy nowy kernel wymaga ręcznej weryfikacji i poprawek
- Jeden aktywny kernel - nie wracamy do starszych
- Skrypt główny modyfikujemy minimalnie (zmiany API buildsystemu)
- Patche źródeł kernela idą wyłącznie do kernel-patches.sh

## Sprzęt
- **Karta 1:** Klon TBS (SAA7160 / Technotrend)
  - Sterownik: `saa716x_tbs-dvb.ko` + `saa716x_core.ko`
  - Frontends: `cx24117.ko` + `tas2101.ko`
- **Karta 2:** TBS 6902 (TBSECP3)
  - Sterownik: `tbsecp3.ko`
  - Frontends: `gx1133.ko` + `tas2101.ko`

## System
- OS: Debian 14
- Kernel: 6.19.13+deb14-amd64
- Źródła TBS: `/usr/src/tbs-drivers` (git, branch: latest)
- Skrypty: `/usr/src/`

## Struktura plików
```
/usr/src/
  install_tbsdtv-smart.sh   # skrypt główny v13
  kernel-patches.sh          # patche API kernela
  install_tbsdtv-smart.log   # log ostatniego uruchomienia
  tbs-build-tmp/             # tymczasowy katalog budowania (usuwany po kompilacji)
```

---

## Problemy naprawione w skrypcie głównym

### Kernel 6.12 (v12 → działało)
#### 1. Redefinicja avl6882_attach
- **Przyczyna:** `CONFIG_DVB_AVL6882` nie istnieje w konfiguracji kernela dystrybucji
- **Rozwiązanie:** Automatyczne wykrywanie brakujących `CONFIG_DVB_*` i dodanie `-DCONFIG_DVB_XXX=1` do flag

#### 2. missing binary operator before token (gx1133)
- **Przyczyna:** Brak `#include <linux/version.h>` w niektórych plikach TBS
- **Rozwiązanie:** Dodanie `-include linux/version.h` do flag

---

## Problemy naprawione w kernel-patches.sh

### Kernel 6.19
#### 1. from_timer / del_timer (dvb-core/dmxdev.c)
- **Rozwiązanie:** `from_timer` → `timer_container_of`, `del_timer` → `timer_delete`

#### 2. dvb_vb2_fill_buffer brakujący argument (dvb-core/dmxdev.c)
- **Rozwiązanie:** Dodanie `NULL` jako ostatni argument (flush callback)

#### 3. IS_REACHABLE avl6882 (dvb-frontends/avl6882.h)
- **Rozwiązanie:** Zamiana bloku `#if IS_REACHABLE(...)` na bezwarunkowy `extern`

#### 4. gpio_chip.set void → int (dvb-frontends/cxd2820r_core.c)
- **Przyczyna:** Kernel 6.19 zmienił sygnaturę callbacka `gpio_chip.set` z `void` na `int`
- **Rozwiązanie:** Zmiana sygnatury funkcji + `return;` → `return 0;`

---

## Zmiany w skrypcie głównym (install_tbsdtv-smart.sh)

### v13 względem v12 (kernel 6.19)

#### 1. EXTRA_CFLAGS → KCFLAGS
- **Przyczyna:** Kernel 6.19 usunął obsługę `EXTRA_CFLAGS` z `scripts/Makefile.build`
- **Gdzie:** Linia wywołania `make` w pętli kompilacji
- **Zmiana:** `EXTRA_CFLAGS="$EXTRA_CFLAGS"` → `KCFLAGS="$EXTRA_CFLAGS"`

#### 2. Makefile dla pci/saa716x
- **Przyczyna:** Oryginalny Makefile używa `obj-$(CONFIG_SAA716X_CORE)` etc. — nie ustawione
- **Rozwiązanie:** Skrypt tworzy minimalny Makefile z `obj-m` (analogicznie jak dvb-frontends)
- **Przywracanie:** cleanup/trap przywraca oryginał z `.orig`

#### 3. Makefile dla pci/tbsecp3
- **Przyczyna:** j.w. — `obj-$(CONFIG_DVB_TBSECP3)` nie ustawione
- **Rozwiązanie:** Skrypt tworzy minimalny Makefile z `obj-m`
- **Przywracanie:** cleanup/trap przywraca oryginał z `.orig`

#### 4. Sprawdzanie .orig rozszerzone
- Sprawdzane pliki: dvb_frontend.h, frontend.h, dvb-frontends/Makefile,
  saa716x/Makefile, tbsecp3/Makefile (5 plików zamiast 3)

---

## Wyniki kompilacji

### Kernel 6.12 (v12)
- **Wynik:** KOMPILACJA OK
- **Moduły:** 131 .ko
- **Wszystkie TARGET_DIRS:** OK

### Kernel 6.19 (v13)
- **Wynik:** INSTALACJA OK
- **Moduły zainstalowane:** 25 .ko do `/lib/modules/6.19.13+deb14-amd64/updates/tbs/`
- **dvb-core:** OK
- **dvb-frontends:** OK (25 frontendów)
- **pci/saa716x:** skompilowane — do weryfikacji po restarcie
- **pci/tbsecp3:** skompilowane — do weryfikacji po restarcie
- **pci/tbsci:** OK
- **pci/tbsmod:** OK

---

## Co dalej / TODO

- [ ] Uruchomić skrypt v13 i zweryfikować czy `saa716x_core.ko`, `saa716x_tbs-dvb.ko`, `tbsecp3.ko` są generowane
- [ ] Po restarcie sprawdzić dmesg i lsmod
- [ ] Jeśli pojawią się nowe błędy — dopisać patche do kernel-patches.sh w bloku `6.19`

## Weryfikacja po restarcie
```bash
lsmod | grep -E "saa716x|tbsecp3|cx24117|tas2101|gx1133"
dmesg | grep -E "TBS|saa716|tbsecp3" | head -30
ls /dev/dvb/
```

## Instalacja modułów
- Katalog docelowy: `/lib/modules/<kver>/updates/tbs/`
- Katalog `updates/` ma wyższy priorytet niż `kernel/` — nasze moduły zastąpią standardowe
- Po instalacji skrypt automatycznie uruchamia `depmod -a`
- Po restarcie system ładuje nowe moduły automatycznie

## Jak dopisać nowy patch (przyszłe kernele)
1. Uruchom skrypt — zbierz błędy z loga
2. Otwórz `kernel-patches.sh`
3. Dopisz nowy blok `if ker_ge X Y; then ... fi`
4. Użyj `apply_sed_if_match` dla prostych zamian lub `apply_python_patch` dla złożonych
5. Marker = unikalny fragment STAREGO kodu — patch jest idempotentny
6. Uruchom skrypt ponownie
