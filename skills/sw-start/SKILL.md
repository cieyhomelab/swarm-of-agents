---
name: sw-start
description: Jednorazowa konfiguracja repozytorium sterującego sw-control dla roju agentów. Zakłada prywatne repozytorium, etykiety sw-*, kopię workflowu sw-sweep, issue sw-dziennik i godzinną automatyzację „sw: przegląd co godzinę”. Bezpieczne do ponownego uruchomienia. Model - chores.
---

# sw-start

Działasz autonomicznie, na modelu `chores`. Cała logika jest w skrypcie; ty go uruchamiasz i raportujesz wynik.

## Kroki

1. Uruchom `~/swarm-of-agents/bin/sw-start` (albo `bin/sw-start` w klonie repozytorium). Potrzebne są `gh` zalogowany na koncie właściciela i `CEZ_BIN` ustawione przez Cezara.
2. Ostatnia linia wyjścia to `STAN: OK` albo `STAN: BLAD <powód>`.
   - `STAN: OK`: zgłoś, co skrypt utworzył (linie `sw-start: …`). Przy ponownym uruchomieniu nic nie jest dublowane.
   - `STAN: BLAD`: nie próbuj obejść błędu. Podaj powód właścicielowi.
3. Uruchom `~/swarm-of-agents/bin/sw-doctor`. Po poprawnej konfiguracji zwraca `STAN: OK`.

## Granice

- Skrypt zmienia tylko elementy `sw-*` i automatyzacje o nazwach `sw: …`. Nie usuwa żadnej automatyzacji.
- Nie ruszasz elementów należących do innych łańcuchów agentów ani ich automatyzacji.
- Repozytorium sterujące musi być prywatne; skrypt kończy się błędem, gdy nie jest.
- Nie zapisuj sekretów ani danych osobowych w `sw-control`.
