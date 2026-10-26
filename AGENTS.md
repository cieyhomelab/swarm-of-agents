# AGENTS.md — swarm-of-agents

Autonomiczny software house, następca sh-skills i sh-control. Specyfikacja: `.ai/specs/2026-10-25-autonomiczny-software-house.md`. Decyzja o stosie: `docs/adr/0001-stos-technologiczny.md`.

## Stos
- **Silnik:** Cezar (Open Mercato) na VPS: workflowy w wersji 2, automatyzacje, zadania. Własnego serwera ani bazy nie ma.
- **Logika:**
  - skille Claude Code `skills/sw-*/SKILL.md` (po polsku),
  - workflowy `workflows/sw-*.yml`,
  - skrypty Bash `bin/sw-*` (narzędzia: `jq`, `gh`, `curl`).
- **Stan:** etykiety i komentarze na GitHubie (repozytorium sterujące `sw-control`), konfiguracja w `config/sw.json`.
- **Testy:** `bats`, `shellcheck`, walidatory w Pythonie 3 (`tests/tools/`), E2E w Docker Compose z atrapami API.

## Struktura katalogów
| Katalog | Zawartość | Gdzie dodawać |
|---------|-----------|---------------|
| `skills/sw-<rola>/SKILL.md` | instrukcje ról roju; `name` = nazwa katalogu | nowa rola = nowy katalog `sw-*` |
| `workflows/sw-*.yml` | workflowy Cezara w wersji 2; nazwa pliku = `name` | nowy przebieg = nowy plik |
| `bin/sw-*` | skrypty wykonywane przez węzły `check` | logika deterministyczna, bez agenta |
| `bin/lib/common.sh` | wspólne funkcje (`sw_config`, `sw_die`, `SW_CEZAR_URL`) | funkcje używane przez co najmniej dwa skrypty |
| `config/` | `sw.json` (limity, modele), `kategorie-wykluczone.md`, opcjonalnie `automations/*.json`, `labels.json` | wartości, które właściciel może zmienić bez kodu |
| `scripts/` | pięć punktów wejścia testów i budowania oraz `install.sh` | – |
| `tests/unit`, `tests/integration`, `tests/e2e` | testy `bats` | test obok rodzaju, nie obok kodu |
| `tests/fakes/gh` | atrapa GitHub CLI kierująca `gh api` do atrapy API | nowe trasy dopisz w `tests/tools/mock_api.py` |
| `docs/adr/` | decyzje architektoniczne | kolejny numer |

## Komendy
Te same lokalnie, u agentów i w CI (`.ai/agentic.config.json`):

```bash
scripts/lint.sh                # shellcheck, walidacja workflowów, reguła nazw sw, poprawność JSON
scripts/test-unit.sh [plik]    # bats tests/unit
scripts/test-integration.sh [plik]  # bats tests/integration (system plików, HTTP do atrapy)
scripts/test-e2e.sh [plik]     # Docker Compose: atrapa API + kontener jak VPS
scripts/build.sh               # dist/swarm-of-agents.tar.gz i jego sprawdzenie
```

Zawężanie: przekaż ścieżki plików, np. `scripts/test-unit.sh tests/unit/sw_doctor.bats` albo `scripts/test-e2e.sh tests/e2e/sweep.bats` (ścieżka względem katalogu repozytorium).

Wymagane narzędzia lokalnie: `bash`, `bats`, `shellcheck`, `jq`, `python3` z PyYAML, `docker` z Compose. W świeżym worktree nic nie trzeba instalować przez npm ani pip.

### Kontrakt `scripts/test-e2e.sh`
- Projekt Compose `e2e-${E2E_RUN_ID}`; bez zmiennej losowy identyfikator.
- Nie publikuje portów na hoście. Testy działają w sieci Compose (`runner` → `mock:8080`).
- Zawsze sprząta (`down -v --remove-orphans` w `trap`), także przy błędzie i przerwaniu.
- Wczytuje `${SH_SECRETS_DIR:-$HOME/.sh-secrets}/swarm-of-agents.env`, jeśli istnieje. Nazwa zmiennej `SH_SECRETS_DIR` pochodzi z łańcucha, który buduje to repozytorium (sh-skills).
- Działa bez sekretów: Cezar, GitHub i sidecar push są atrapami (`tests/tools/mock_api.py`, `tests/fakes/gh`).
- Zmienne z pliku sekretów są wczytywane na hoście, a do kontenera trafiają tylko te wymienione w `compose.yml` (`environment`). Test, który potrzebuje sekretu, dopisuje go tam jako `NAZWA: ${NAZWA:-}`.
- Sprząta kontenery, sieci, wolumeny i obrazy projektu (`down -v --remove-orphans --rmi local`). Sygnał INT/TERM najpierw przerywa trwające polecenie Compose.
- `E2E_RUN_ID` musi pasować do `^[a-z0-9][a-z0-9_-]*$`.
- Obrazy bazowe pochodzą z `mirror.gcr.io` (odporność na limit Docker Hub).
- Na VPS bramka przeglądu sh-skills usuwa zasoby `e2e-*` starsze niż 6 godzin, także te z tego repozytorium. To nieszkodliwe, ale przebieg E2E nie może trwać tak długo.

## Budowa aplikacji (etap 2, `workflows/sw-build.yml`)
- Po architekturze `sw-inzynier` implementuje jedyny moduł, a `sw-tester` ocenia E2E pełnej aplikacji. Stan projektu przestawia `bin/sw-stan` (`architektura` → `implementacja` → `integracja` → `przeglad`), po jednym kroku naprzód.
- Konwencja pokrycia, którą sprawdza `bin/sw-pokrycie-check`:
  - `modul`: kontrakt `docs/kontrakty/<modul>.md` ma sekcję `## Pokrycie` z linią `- <pozycja „Udostępnia”> => <plik testu>` dla każdej pozycji, a plik istnieje i nie jest pusty;
  - `e2e`: każdy scenariusz specyfikacji (`### S<n>`) występuje jako identyfikator w jakimś pliku `tests/e2e/`, a w `tests/e2e/` nie ma konstrukcji pomijających test (`skip` jako polecenie bats, `test.skip(`, `xit(`, `@pytest.mark.skip` itp.; samo słowo w nazwie czy asercji nie liczy się).
- Moduły (S5): po merge'u architektury `bin/sw-moduly zaloz` zakłada w repozytorium aplikacji issue „Moduł: <modul>” z etykietami `sw-modul` i `sw-modul-do-zrobienia` (treść = kontrakt; ponowny przebieg nie dubluje issues). `bin/sw-architektura-check` przy dwóch i więcej kontraktach sprawdza dodatkowo `## Wymaga` (`brak` albo `- <modul>: <pozycja>` istniejąca w „Udostępnia” innego modułu, bez cykli) i `## Testy kontraktu` (istniejące, niepuste pliki).
- Poprawka po nieudanych testach E2E trafia do nowego PR modułu (recenzja, CI, bezpieczeństwo, `sw-merge kod`); rundy poprawek każdej pętli to `fixRoundsPerPr`.
- Przegląd bezpieczeństwa pełnej aplikacji (S9): po `sw-stan-przeglad` `sw-bezpieczenstwo` (tryb `aplikacja`) zapisuje wynik czterech punktów w `.ai/sw-run/przeglad.json`, a `bin/sw-przeglad` rozstrzyga (werdykt i wszystkie punkty `pass`; sekrety dodatkowo skanuje sam). Wynik pozytywny daje `docs/security/<data>-raport.md`, który przechodzi PR modułu (recenzja, CI, bezpieczeństwo, `sw-merge kod`); dopiero zmergowany raport otwiera wdrożenie (sekcja „Wdrożenie”). Wynik negatywny to runda poprawek inżyniera (`rounds-app`, `fixRoundsPerPr`) z nowym PR, ponownymi testami E2E i ponownym przeglądem; wyczerpane rundy wstrzymują projekt.
- Uwaga: gałąź zadania `sw-build` po merge'u architektury dostaje kolejne commity i drugi PR (to samo `git.draft-pr`); działanie na prawdziwym Cezarze trzeba potwierdzić według „Sprawdzenie na VPS”.

## Przydział modułów (etap 3, krok 2, S6)
- `bin/sw-kierownik` (skill `sw-kierownik`, model `chores`) zarządza stanem modułów, którym jest etykieta issue „Moduł: <modul>”: `sw-modul-do-zrobienia` → `sw-modul-w-pracy` → `sw-modul-zmergowany`.
  - `przydziel` czyta `maxParallelAgents` z `config/sw.json` przy każdym wywołaniu, ustawia go jako `maxParallel` projektu w Cezarze (`CEZ_PROJECT_ID`) i przenosi na `w-pracy` najwyżej tyle modułów, ile zostawia wolnych miejsc limit (niższy numer issue pierwszy); każdy moduł wypisuje jako `URUCHOM: <modul>`.
  - Moduł jest gotowy, gdy każdy moduł z jego `## Wymaga` ma kontrakt (issue), bo implementacja opiera się na kontrakcie, a nie na gotowym module.
  - `zmergowany <modul>` przenosi `w-pracy` na `zmergowany` i zamyka issue; `stan` liczy moduły w trzech stanach.
- `workflows/sw-build.yml` woła `przydziel` węzłem `kierownik` przed inżynierem, a `zmergowany` węzłem `kierownik-merged` po merge'u PR modułu. Zadania modułów dla wielu inżynierów naraz zakłada agent `sw-kierownik` z linii `URUCHOM`; podpięcie ich do `sw-build` (węzły `dispatch`) to osobny krok etapu 3; integracja to sekcja „Integracja modułów”.
- Testy: `tests/integration/sw_kierownik.bats`, `tests/e2e/kierownik.bats` i testy `S6` w `tests/e2e/build.bats`.

## Integracja modułów (etap 3, krok 3, S7)
- Po `sw-kierownik zmergowany` projekt przechodzi w `sw-stan-integracja` (`bin/sw-stan`), a `bin/sw-integracja gotowe` tworzy zadanie integracji tylko wtedy, gdy wszystkie issues modułów mają `sw-modul-zmergowany` (żaden nie czeka ani nie jest w pracy; co najmniej jeden istnieje).
- `sw-integrator` (model `integrator`) składa moduły w aplikację: werdykt `zlozona` wysyła zmiany nowym PR (recenzja, CI, bezpieczeństwo, `sw-merge kod`), `bez-zmian` prowadzi prosto dalej. Pierwsze złożenie dzieje się najwyżej raz (`once-integ`).
- `bin/sw-integracja spojnosc` sprawdza deterministycznie brak znaczników konfliktu scalania i to, że każde `- <modul>: <pozycja>` z `## Wymaga` jest w `## Udostępnia` wskazanego modułu. Konflikt (uwagi w `.ai/sw-run/uwagi.md`) to runda poprawek integratora (`rounds-integ`, `fixRoundsPerPr`, poprawka nowym PR); wyczerpane rundy wstrzymują projekt (`pause-rounds-integ`). Dopiero spójna aplikacja przechodzi do testów E2E i testera (S7), potem jak w etapie 2.
- Testy: `tests/integration/sw_integracja.bats`, testy `S7` integracji w `tests/e2e/build.bats` i `tests/unit/sw_build.bats`. Włączenie wielu modułów (`multiModule`) wymaga jeszcze podpięcia równoległych zadań modułów do `sw-build`.

## Wdrożenie (etap 2, krok 5b)
- Po zmergowanym raporcie z przeglądu `workflows/sw-build.yml` przestawia projekt na `sw-stan-wdrazanie` (`bin/sw-stan`) i uruchamia `bin/sw-deploy`; potem `bin/sw-wdrozony` ustawia `sw-stan-wdrozony`, zapisuje adres w metadanych pomysłu (`deployUrl`), zamyka issue pomysłu (generator rusza w następnym cyklu) i wysyła `sw-notify deployed` (tytuł z adresem, link do issue pomysłu).
- `sw-deploy` buduje obraz z `Dockerfile` repozytorium (port z `EXPOSE`, domyślnie 8080) i uruchamia kontener na sieci Docker `--internal`, bez publikowanych portów. Jedynym wejściem jest proxy nginx z logowaniem (basic auth), opublikowane na `deploy.bindAddress`. Proxy startuje jako ostatnie, a wdrożenie jest przyjęte dopiero po teście odmowy: żądanie bez logowania i z błędnym hasłem dostaje 401/403, zalogowany właściciel widzi aplikację.
- Każda porażka po rozpoczęciu wdrożenia usuwa kontenery i sieć, więc nieudane wdrożenie nie zostawia nic osiągalnego. Workflow ponawia je `retriesPerTask` razy (`rounds-deploy`), potem wstrzymuje projekt.
- Login właściciela to plik `~/.sw-deploy/owner-login` (`login:haslo`, `chmod 600`, poza repozytorium; zmienna `SW_DEPLOY_LOGIN_FILE`). Stan proxy (konfiguracja, hash hasła, port) jest w `~/.sw-deploy/<aplikacja>/`. Brak pliku to `STAN: BLAD` wdrożenia, nie sekret w repozytorium.
- Zastępstwo do czasu nowych rodzajów w cezar-pwa: `deployed` idzie bramką jako rodzaj `spec`, a adres jest w tytule (adres w polu `url` bramka odrzuca). Odsetek „bez interwencji” (S13) dopisuje `sw-notify` do tytułu powiadomień `deployed` i `paused` (` · 67% bez interwencji`): zamknięte issues `sw-pomysl` z `sw-stan-wdrozony` i `sw-bez-interwencji` / wszystkie z `sw-stan-wdrozony` albo `sw-stan-wstrzymany`; `sw-wdrozony` dodaje `sw-bez-interwencji`, a `sw-pause` wysyła rodzaj `paused` (bramka jako `blocked`). Bez zakończonych projektów albo gdy GitHub nie odpowiada, tytuł zostaje bez odsetka. Od etapu 2 jeden aktywny projekt aż do wdrożenia albo wstrzymania pilnuje `sw-gate` (stany od `sw-w-ocenie` do `sw-stan-wdrazanie`).
- Testy: `tests/integration/sw_deploy.bats`, `sw_wdrozony.bats` i `tests/e2e/build.bats` używają atrapy `tests/fakes/docker` z prawdziwym nasłuchem (`tests/tools/fake_deploy_proxy.py`); prawdziwy Docker sprawdza się na VPS.

## Konfiguracja `config/sw.json`
| Pole | Domyślnie | Znaczenie (specyfikacja) |
|------|-----------|--------------------------|
| `stage` | 1 | przełącznik etapu po zmergowanej specyfikacji (`bin/sw-build-start`): 1 przekazuje projekt łańcuchowi sh-* (`sw-handover-sh`), 2 uruchamia workflow `sw-build` i ustawia `sw-stan-architektura`; brak pola = 1 |
| `multiModule` | false | tryb architekta (S5, etap 3): `false` = jeden moduł, `true` = co najmniej dwa moduły z `Wymaga` i `Testy kontraktu`; brak pola = `false`. Włącz dopiero po kroku integracji etapu 3: kierownik już przydziela moduły do limitu (sekcja „Przydział modułów”), ale `sw-build` implementuje wciąż jeden moduł |
| `cycleHours` | 1 | interwał cyklu; automatyzacja „sw: przegląd co godzinę” |
| `maxParallelAgents` | 3 | limit równoległych agentów projektu → `maxParallel` projektu w Cezarze (S6) |
| `projectTimeLimitHours` | 168 | limit czasu projektu od zatwierdzenia pomysłu (S12) |
| `projectUsageLimitUsd` | 150 | limit zużycia projektu jako suma `costUsd` z Cezara (S12) |
| `retriesPerTask` | 2 | ponowienia zadania (S11) |
| `fixRoundsPerPr` | 3 | rundy poprawek na PR (S8) |
| `specFixRounds` | 2 | rundy poprawek specyfikacji (S4) |
| `ideaAttemptsPerCycle` | 5 | próby generowania w cyklu (S1) |
| `noIdeaNotifyAfterCycles` | 24 | po tylu cyklach bez pomysłu jedno powiadomienie |
| `stalledAfterHours` | 3 | brak postępu = zadanie nieudane (S11) |
| `cezarAutoResumes` | 12 | automatyczne wznowienia Cezara po limicie planu; po ich wyczerpaniu `sw-limits` zakłada nowe zadanie od przerwanego kroku, bez zużywania ponowień (S12) |
| `deploy.*` | `bindAddress` 127.0.0.1, porty 18100–18199, `memory` 512m, `readySeconds` 60, `proxyImage` nginx | wdrożenie (S10): prywatny adres (konkretny IPv4, nigdy 0.0.0.0, np. adres sieci prywatnej VPS), zakres portów, limit pamięci kontenera, czas oczekiwania na aplikację, obraz proxy z logowaniem |
| `githubOwner`, `controlRepo` | `cieyhomelab`, `cieyhomelab/sw-control` | konto i repozytorium sterujące (musi być prywatne) |
| `requiredChecks` | `["checks", "e2e"]` | nazwy check-runów wymaganych do merge (S8); ustawia architekt aplikacji w jej repozytorium |
| `models.*` | `opus` / `sonnet` / `haiku` | model każdej roli; recenzja i bezpieczeństwo inne niż autor |

## Konwencje
- **Nazwy:** wszystko, co ten system instaluje na VPS, ma prefiks `sw`:
  - skille, workflowy i skrypty: `sw-…`;
  - automatyzacje Cezara: `sw: …`;
  - etykiety własne: `sw-…`.

  Nigdy nie twórz, nie zmieniaj ani nie usuwaj elementów `sh-*` / `sh: …`, bo należą do działającego sh-skills. Pilnuje tego `tests/tools/check-names.sh`. Wyjątek: przekazanie projektu łańcuchowi sh-* w etapie 1, opisane w sekcjach technicznych specyfikacji.
- **Skrypty:**
  - `set -uo pipefail` (albo `-euo`, gdy każdy błąd ma przerwać);
  - pierwsza linia komentarza mówi, co skrypt robi;
  - wyjście dla węzłów Cezara to linie `STAN: …` i `URUCHOM: …`, które workflow sprawdza warunkiem `contains`;
  - błędy idą na stderr; kod wyjścia 0 oznacza sukces.
- **Logowanie:** `sw_log` (UTC, stderr). Nigdy nie loguj tokenów ani treści rozmów.
- **Dziennik i powiadomienia:** `sw-log` i `sw-notify` przepuszczają tekst przez `sw_scrub` (maska adresów e-mail i tokenów). `sw-gate` zapisuje w dzienniku tylko `STAN: BLAD`, `STAN: OK` i znaczniki `powiadomienie: …` (deduplikacja).
- **Obsługa błędów:** skrypt wykrywający problem kończy się kodem 1 i opisuje przyczynę w linii `STAN: BLAD …`. Nie maskuj błędów `|| true`, chyba że błąd jest oczekiwany i opisany komentarzem.
- **Stan:**
  - zapisujesz go tylko na GitHubie (etykiety, komentarze, issue) przez `gh`;
  - każda zmiana stanu ma najpierw odczyt i warunek, bo przegląd może się powtórzyć;
  - zadania Cezara traktuj jako jednorazowe.
- **Migracje:** nie ma bazy. Zmiana etykiet stanu albo formatu `config/sw.json` wymaga notatki w PR i zgodności wstecz: nowe pola mają wartości domyślne.
- **Modele:** z `config/sw.json` (`models.*`). Każdy węzeł `agent` ma `runner: claude` i jawny `model` (sprawdza walidator). Recenzja i przegląd bezpieczeństwa zawsze na innym modelu niż autor; faktyczny model sprawdza się w rekordzie zadania Cezara, nie w konfiguracji.
- **Uprawnienia agentów:** węzły `agent` mają `allowedTools` i `bashAllowlist` ograniczone do tego, czego rola potrzebuje. Zmiany stanu, merge i automatyzacje robią skrypty, nie agenci.
- **Język:** logika w Bashu z `jq`. Gdy logika skryptu przerasta prostą obróbkę JSON (maszyna stanów, warunki merge), dopuszczalny jest moduł w Pythonie 3 z biblioteką standardową w `bin/lib/*.py`, wołany ze skryptu `bin/sw-*` i testowany przez `bats` (ADR 0001).

## Testy
- Każda zmiana w zachowaniu ma test.
- Każdy scenariusz ze specyfikacji ma test E2E w `tests/e2e/`.
- Zewnętrzne usługi tylko przez atrapy; testy nie wołają prawdziwego GitHuba, Cezara ani modeli.
- Zachowanie agentów (treść skilli) nie jest testowane w CI. Strukturę skilli sprawdza `check-names.sh`, a przebieg na VPS sprawdzasz według sekcji „Sprawdzenie na VPS”.

## Sekrety
- W repozytorium nie ma sekretów. Lista zmiennych jest w `.env.example`.
- Na VPS: token `gh` należy do konta właściciela, a token bramki push leży w `~/.cezar-push/gate-token`.
- `ANTHROPIC_API_KEY` jest zabroniony (tylko plan Claude Max); sprawdza to `bin/sw-doctor`.
- Właściciel musi mieć wyłączone płatne dodatkowe zużycie („usage credits”) w ustawieniach konta Claude. Tego nie da się sprawdzić programowo (ADR 0001).

## Sprawdzenie na VPS
1. `git -C ~/swarm-of-agents pull`, potem `~/swarm-of-agents/scripts/install.sh`. Wpisy `sh-*` w `~/.claude/skills` muszą zostać bez zmian.
2. `~/swarm-of-agents/bin/sw-doctor` → `STAN: OK`.
3. Workflow `sw-sweep` w projekcie `sw-control` uruchomiony ręcznie kończy się sukcesem.

## Czego nie robić
- Nie modyfikuj Cezara ani cezar-pwa w tym repozytorium. Potrzebne zmiany w cezar-pwa opisz jako zgłoszenie w jego repozytorium.
- Nie dodawaj własnego serwera, bazy, kolejki ani crona. Harmonogram to automatyzacja Cezara.
- Nie wywołuj API modeli bezpośrednio. Agenci działają tylko jako węzły `agent` Cezara.
- Nie zapisuj danych osobowych właściciela w repozytoriach, dzienniku ani powiadomieniach (tylko tytuł i link).
- Nie używaj `--no-verify`, force-push ani merge bez warunków ze specyfikacji (S4, S8).
