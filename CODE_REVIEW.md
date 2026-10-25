# CODE_REVIEW.md — swarm-of-agents

Reguły recenzji specyficzne dla tego repozytorium. Blokuj tylko poważne problemy; drobiazgi zgłaszaj jako uwagi.

## Blokujące
- **Kolizja z sh-skills:** tworzy, zmienia lub usuwa coś o nazwie `sh-*` albo `sh: …` (skill, workflow, automatyzacja, skrypt, etykieta, katalog `~/sh-skills`), poza opisanym wyjątkiem etapu 1.
- **Merge bez warunków:** scala PR bez kompletu warunków ze specyfikacji (S4: przegląd + bezpieczeństwo; S8: reviewer na innym modelu + zielone CI + bezpieczeństwo).
- **Jedna interakcja:** wysyła właścicielowi pytanie po zatwierdzeniu pomysłu (łamie zasadę jednej interakcji).
- **Dane osobowe** właściciela trafiają do repozytorium, dziennika, logów albo treści powiadomienia.
- **Sekret albo `ANTHROPIC_API_KEY`** w kodzie, konfiguracji albo testach; wywołanie API modeli poza Cezarem.
- **Zmiana zabezpieczeń bez osobnego werdyktu bezpieczeństwa:** zmiany w `.github/workflows/**`, `scripts/test-*.sh`, `tests/**` (usunięcie lub osłabienie testu) albo w warunkach `sw-merge`.
- **Decyzja albo werdykt zapisywane przez agenta:** etykietę decyzji pomysłu ustawia `sw-ocena-wynik` na podstawie historii zadania w Cezarze; werdykty trafiają do `sw-merge` jako argumenty z węzłów workflow, nie z komentarzy.
- **Merge bez powiązania z SHA:** werdykt i merge muszą dotyczyć tego samego SHA głowy PR, a CI to nazwane check-runy z `requiredChecks`.
- **Węzeł `agent` bez `runner: claude`, jawnego `model`, `allowedTools` albo `bashAllowlist`.**
- **Zmiana stanu bez warunku:** zmienia stan na GitHubie bez wcześniejszego odczytu i warunku, więc powtórzony przegląd zrobi coś dwa razy.
- **Workflow niezgodny z Cezarem w wersji 2:** nieznany typ węzła, port albo krawędź (powinien to złapać `scripts/lint.sh`).
- **Brak testu** dla zmiany zachowania albo testu E2E dla scenariusza, test wołający prawdziwą usługę zewnętrzną.

## Bash
- `shellcheck` bez ostrzeżeń. Wyłączenie reguły tylko z komentarzem `# shellcheck disable=…` i uzasadnieniem.
- Zmienne w cudzysłowach, ścieżki z `"$SW_ROOT"`. Pliki tymczasowe tylko przez `mktemp`, sprzątane w `trap`.
- `gh` z jawnym `--repo` / pełną ścieżką `repos/{owner}/{repo}` przy każdej zmianie.
- Każde wywołanie sieci ma limit czasu (`curl --max-time`).
- Wyjście dla węzłów Cezara w ustalonym formacie (`STAN:`, `URUCHOM:`), bez dodatkowych linii, które mogłyby spełnić warunek `contains`.

## Workflowy i skille
- Nazwa pliku workflow = pole `name`; skill: katalog = `name`.
- Węzeł `agent` ma `runner: claude`, jawny `model` z `config/sw.json`, ograniczone `allowedTools`/`bashAllowlist`, a werdykty są zadeklarowane i obsłużone krawędziami.
- Etykiety zmienia się jednym `PATCH /repos/{o}/{r}/issues/{n}` z pełną listą `labels` po świeżym odczycie, nie parą usuń/dodaj.
- Skill opisuje raport końcowy w ustalonym formacie i to, co wolno mu zmieniać. Nie zawiera poleceń, które mogłyby nadpisać `sh-*`.
- Pętle mają węzeł `loop` z `max` równym wartości z konfiguracji (rundy poprawek, ponowienia).
