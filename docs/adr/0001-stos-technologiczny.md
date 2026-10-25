# ADR 0001: Stos technologiczny

- Status: proponowany (PR architektury)
- Data: 2026-10-25
- Specyfikacja: `.ai/specs/2026-10-25-autonomiczny-software-house.md`

## Kontekst

System to nie klasyczna aplikacja z interfejsem, tylko rój agentów działający na istniejącej infrastrukturze właściciela. Wymagania właściciela ze specyfikacji:

- Claude Max jako jedyne źródło modeli;
- Cezar (Open Mercato) na VPS jako orkiestrator;
- cezar-pwa jako aplikacja na telefon;
- GitHub `cieyhomelab`;
- Docker na VPS;
- współistnienie z sh-skills bez nadpisywania czegokolwiek (prefiks `sw`).

Ustalenia z kodu Cezara (`open-mercato/cezar`, commit `f6b910f`):

- Workflowy w wersji 2 mają węzły:
  - `agent` (skill, model, werdykty `CEZ:VERDICT`),
  - `check` (dowolne polecenie bash, wyjście `pass`/`fail`, dostęp do sekretów),
  - `loop`, `if`, `fork`/`join`, `dispatch`,
  - `ask-user`, `gate.human`,
  - węzły git i GitHub.
- Automatyzacje działają per projekt:
  - rodzaje: `github` (odpytywanie), `schedule` (co 1–12 h) i `tracker`;
  - nie ma webhooków;
  - nazwy nie są unikalne, a aktualizacja odbywa się po `id`.
- Skille:
  - repozytorium projektu ma pierwszeństwo przed `~/.claude/skills`, a to przed repozytoriami skilli;
  - przy kolizji nazw wygrywa pierwsze znalezienie, bez ostrzeżenia.
- Zadania nieautonomiczne parkują w stanie `waiting`. Pytanie z opcjami (`CEZ:ASK`) pokazuje się jako karta z przyciskami.
- `POST /api/v1/projects/create` tworzy zawsze prywatne repozytorium na GitHubie z pustym commitem i od razu rejestruje je jako projekt Cezara.
- Limit planu modeli:
  - Cezar sam wykrywa limit i wznawia zadanie od przerwanego węzła (`autoResumeOnUsageLimit`, do 12 razy);
  - limit jest liczony per konto, więc nowe zadania na tym koncie są wstrzymywane.
- Równoległość: `resources.maxParallel` dla całego obszaru roboczego (domyślnie 2) i `maxParallel` per projekt (`PATCH /api/v1/projects/:id`).
- Cezar nie ma magazynu klucz-wartość dla agentów, uwierzytelnienia ani powiadomień push.

Ustalenia z kodu cezar-pwa (`cieyhomelab/cezar-pwa`, commit `6ae9908`):

- Ekran zadania (`RunScreen`) prowadzi rozmowę z zadaniem Cezara (`/messages`, `/continue`) i pokazuje karty pytań (`AskCard`) z przyciskami.
- Sidecar `cezar-push`:
  - sam wysyła powiadomienie `attention`, gdy zadanie przechodzi w `waiting`; powiadomienie otwiera ekran tego zadania;
  - przyjmuje od procesów na hoście bramki `spec|merge|blocked` (`POST 127.0.0.1:4330/m/push/gate`, nagłówek `X-Cezar-Push-Token`); takie powiadomienie otwiera adres na GitHubie.
- Reguła projektu: Cezara się nie modyfikuje; zmiany serwerowe trafiają do sidecara.

## Decyzja

### 1. Wykonanie: Cezar jako silnik, bez własnej usługi
Logika roju to skille Claude Code (`skills/sw-*/SKILL.md`), workflowy Cezara w wersji 2 (`workflows/sw-*.yml`) i krótkie skrypty powłoki (`bin/sw-*`). Nie ma własnego serwera, bazy ani kontenera produkcyjnego.

### 2. Język skryptów: Bash + `jq` + `gh` + `curl`
Ten sam zestaw co w sh-skills, z którym agenci już pracują. Skrypty narzędziowe testów (walidacja YAML, atrapy API) są w Pythonie 3 z biblioteką standardową i PyYAML; nie trafiają na VPS jako część systemu.

### 3. Stan systemu: GitHub jako maszyna stanów
Specyfikacja wymaga trwałego stanu. Cezar nie ma magazynu, a sh-skills już używa etykiet jako maszyny stanów. Dlatego:

- **Repozytorium sterujące `sw-control`** (osobne, nie `sh-control`):
  - jest projektem Cezara z automatyzacją `sw: przegląd co godzinę` i workflowami `sw-sweep`, `sw-ocena`;
  - każdy pomysł to issue z etykietą `sw-pomysl`, a stan pomysłu to etykieta (`sw-w-ocenie`, `sw-zatwierdzony`, `sw-odrzucony`, `sw-spec-gotowa`);
  - dziennik systemu to komentarze w jednym przypiętym issue z etykietą `sw-dziennik`;
  - licznik cykli bez pomysłu to plik w `CEZ_SHARED_CACHE_DIR` (pamięć podręczna checków per projekt), a gdy jej zabraknie — liczba wpisów „brak pomysłu” w dzienniku od ostatniej karty.
- **Projekt aplikacji** to prywatne repozytorium utworzone przez `POST /api/v1/projects/create`, powiązane z issue pomysłu (link w obu kierunkach). Jego stan to etykiety `sw-stan-*` na issue pomysłu.
- **Konfiguracja** w `config/sw.json` w tym repozytorium: limity, liczba ponowień i rund, liczba prób, limit agentów, modele ról. Zestaw wzorcowy kategorii wykluczonych jest w `config/kategorie-wykluczone.md`.

### 4. Rozmowa oceny: zwykłe zadanie Cezara w cezar-pwa
Ocena pomysłu to nieautonomiczne zadanie workflow `sw-ocena` w projekcie `sw-control`:

- agent `sw-analityk` (tryb ocena) prowadzi rozmowę;
- kończy ją pytaniem `CEZ:ASK` z opcjami „Zatwierdź” i „Odrzuć”;
- po odpowiedzi zapisuje decyzję etykietą na issue pomysłu;
- węzeł `check` sprawdza, że issue ma dokładnie jedną etykietę decyzji.

Powiadomienie push i ekran rozmowy dają istniejące mechanizmy cezar-pwa (`attention` → `RunScreen` → `AskCard`), bez zmian w cezar-pwa w etapie 1.

Decyzja żyje na GitHubie, a nie w pamięci zadania. Zadanie oceny jest więc jednorazowe: gdy zginie (restart Cezara, codzienna aktualizacja), przegląd uruchamia nowe dla tego samego issue.

### 5. Modele i niezależność ocen
- **Autor:** generator, analityk i inżynier działają na `opus`.
- **Recenzja i przegląd bezpieczeństwa:** `sonnet`, czyli inny model Claude niż autor, zgodnie z definicją „inny model”.
- **Proste kroki porządkowe:** `haiku`.

Mapowanie ról na modele jest w `config/sw.json`.

### 6. Równoległość
- Limit równoległych agentów projektu to `maxParallel` projektu w Cezarze, ustawiany z `config/sw.json` przy tworzeniu repozytorium.
- Limit całego VPS (`resources.maxParallel`) zostaje w gestii właściciela, bo dzieli go też sh-skills.

### 7. Instalacja na VPS
`scripts/install.sh` linkuje wyłącznie katalogi `skills/sw-*` do `~/.claude/skills`. Odmawia pracy przy katalogu bez prefiksu `sw-` i nie dotyka żadnego innego wpisu. Workflowy trafiają do `sw-control/.ai/cezar/workflows/` przez przyszły skill `sw-start`. Skrypty są wywoływane z katalogu klonu, np. `~/swarm-of-agents/bin`.

### 8. Testy
- **Lint:** `shellcheck` dla skryptów, walidator workflowów (wersja 2, prefiks `sw-`, typy węzłów i porty jak w Cezarze, krawędzie wskazujące istniejące węzły), test spójności skilli i nazw (prefiks `sw`, brak odwołań do `sh-` poza wyjątkiem etapu 1).
- **Testy jednostkowe i integracyjne:** `bats`. Zewnętrzne usługi są zastąpione atrapą `gh` na `PATH` i atrapą API Cezara/GitHuba w Pythonie.
- **E2E:** Docker Compose z atrapą API (Cezar + GitHub + sidecar push) i kontenerem testującym, który uruchamia prawdziwe skrypty `bin/` w środowisku jak na VPS.

  Zachowanie agentów (Claude) nie jest testowane w CI, bo wymaga planu Max. Skille sprawdza test spójności, a zachowanie — przebieg na VPS opisany w `AGENTS.md`.

## Rozważone alternatywy

- **Własna usługa (np. Node.js + SQLite) jako orkiestrator stanu z API dla PWA.** Odrzucona: dubluje Cezara, wymaga uwierzytelnienia, wdrożenia i utrzymania. Reguła cezar-pwa i tak kieruje logikę serwerową do sidecara albo do Cezara.
- **Stan w plikach repozytorium (commit na każdą zmianę stanu).** Odrzucona: szum w historii i konflikty przy równoległych węzłach. Etykiety są atomowe i widoczne w GitHubie.
- **Rozmowa oceny jako nowa funkcja sidecara cezar-pwa (własny czat z API modelu).** Odrzucona: wymagałaby klucza API (sprzeczne z „tylko Claude Max”) i dużej zmiany w innym repozytorium. Zadanie Cezara daje to samo bez zmian.
- **Węzeł `ask-user` zamiast `CEZ:ASK` w agencie.** Odrzucona: odpowiedź węzła `ask-user` jest trzymana w pamięci procesu Cezara i ginie przy restarcie, a rozmowa przed decyzją i tak wymaga agenta.
- **Rozpoznawanie przeglądu po webhooku.** Niedostępne: Cezar nie ma wyzwalacza webhook. Zostaje automatyzacja co godzinę, zgodnie z definicją cyklu.
- **Narzędzia testowe w Node (vitest).** Odrzucona: drugi ekosystem tylko dla testów skryptów powłoki. `bats` jest standardem dla Bash.

## Konsekwencje

- Etap 1 nie wymaga zmian w Cezarze ani w cezar-pwa.
- Etap 2 wymaga zmiany w cezar-pwa: nowe rodzaje powiadomień bramki (`wdrożony`, `wstrzymany`, `brak pomysłów`) w sidecarze i aplikacji, zgodnie z jej regułami zgodności wstecznej.
  - Do tego czasu „brak pomysłów” idzie bramką `blocked` z linkiem do issue dziennika.
  - „Specyfikacja gotowa” idzie bramką `spec` z linkiem do PR.
- **Ograniczenie S12, pkt 5 i 6 (dodatkowe płatne zużycie).** Cezar ani Claude Code nie udostępniają programowo stanu ustawienia „usage credits” planu. Weryfikowalna część to brak klucza API w środowisku Cezara: bez niego nie ma rozliczenia według stawek API. To sprawdza `bin/sw-doctor` przed każdym przydziałem. Wyłączenie „usage credits” w ustawieniach konta pozostaje obowiązkiem właściciela, opisanym w `AGENTS.md`.
- Jednostką limitu zużycia projektu jest suma `costUsd` z zadań projektu w Cezarze (ekwiwalent kosztu liczony przez Cezara także na planie Max). Domyślny limit jest w `config/sw.json`.
- **Codzienna aktualizacja Cezara restartuje serwer.** Zadania są zaprojektowane jako jednorazowe i odtwarzalne z etykiet: przegląd wykrywa issue bez żywego zadania i uruchamia je ponownie, co spełnia wymaganie trwałości stanu.
- **Automatyzacje nie mają unikalnych nazw.** `sw-start` musi aktualizować automatyzację „po nazwie” przez `list` i dopasowanie nazwy `sw: …`, nigdy nie dotykając nazw `sh: …`.
