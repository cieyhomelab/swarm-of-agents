# Autonomiczny software house (swarm-of-agents)

## TLDR
System, który sam wymyśla pozytywne pomysły na aplikacje i sam je buduje. Jedyną interakcją człowieka jest ocena pomysłu: właściciel w aplikacji na telefon rozmawia z modelem, doprecyzowuje pomysł i go zatwierdza albo odrzuca. Po zatwierdzeniu rój agentów bez udziału człowieka tworzy repozytorium, specyfikację, architekturę i kod, równolegle buduje moduły, składa je w całość i wdraża aplikację na VPS pod prywatnym adresem. To następca sh-skills i sh-control.

## Problem i cel
Obecny software house (sh-skills, sh-control) wymaga człowieka na dwóch bramkach: zatwierdzenie specyfikacji i merge każdego PR, a pomysły i repozytoria dostarcza właściciel. To ogranicza tempo do czasu, jaki właściciel może poświęcić.

Cel: jedna interakcja właściciela na aplikację (ocena pomysłu), reszta w pełni autonomicznie, z zabezpieczeniami, które zastępują przegląd człowieka.

**Sukces:** rośnie odsetek zatwierdzonych pomysłów doprowadzonych do wdrożenia bez interwencji właściciela (S13).

## Pojęcia
- **Cykl:** jedno uruchomienie przeglądu systemu. Interwał w konfiguracji, domyślnie co godzinę.
- **Aktywny projekt:** pomysł w stanie „w ocenie” albo „zatwierdzony” albo projekt w stanie innym niż „wdrożony” i „wstrzymany”. Naraz istnieje najwyżej jeden aktywny projekt.
- **Inny model:** inny model Claude niż ten, który przygotował ocenianą zmianę.
- **Ponowienie:** ponowne uruchomienie zadania po jego niepowodzeniu (błąd wykonania albo brak postępu, czyli brak commitu i zmiany stanu zadania przez 3 godziny).
- **Runda poprawek:** poprawka po uwagach recenzji, testu lub przeglądu. Liczona osobno od ponowień.
- **Wyczerpanie prób zadania:** przekroczenie liczby ponowień albo rund poprawek z konfiguracji.
- **Prywatny adres:** adres aplikacji, pod którym żądanie bez uwierzytelnienia właściciela kończy się odmową albo przekierowaniem do logowania.

## Użytkownicy i role

### Właściciel (jedyny człowiek)
- Dostaje powiadomienie o nowym pomyśle, ocenia go w rozmowie z modelem, zatwierdza albo odrzuca.
- Dostaje powiadomienia o gotowej aplikacji i o wstrzymanym projekcie.
- Korzysta z gotowych aplikacji pod prywatnym adresem.
- Od etapu 2 nie zatwierdza specyfikacji, nie merguje PR i nie tworzy repozytoriów.

### Agenci (rój)
| Rola | Zadanie |
|------|---------|
| Generator pomysłów | Wymyśla pomysł, sprawdza go w sieci, odrzuca nieudane próby, przygotowuje kartę pomysłu. |
| Analityk (wariant autonomiczny) | Prowadzi rozmowę oceny z właścicielem i pisze specyfikację bez dalszego dopytywania. |
| Architekt | Wybiera stos, dzieli aplikację na moduły z kontraktami, przygotowuje szkielet i CI. |
| Kierownik | Zakłada zadania, przydziela moduły, pilnuje limitów i stanu projektu. |
| Inżynier (kilku równolegle) | Implementuje moduły według kontraktów. |
| Integrator (nowa rola) | Składa moduły w całość i doprowadza do działania pełnej aplikacji. |
| Tester | Weryfikuje działanie według kryteriów akceptacji. |
| Reviewer | Recenzuje zmiany; inny model niż autor zmiany. |
| Przegląd bezpieczeństwa | Osobny agent; inny model niż autor zmiany. Sprawdza PR przed merge i aplikację przed wdrożeniem. |

Analityk, architekt, kierownik, inżynier, tester i reviewer to obecne role sh-* przeniesione do tego repozytorium jako skille z prefiksem `sw-` (np. `sw-analityk`), bez bramek ludzkich. Generator, integrator i przegląd bezpieczeństwa to nowe role, też z prefiksem `sw-`.

## Scenariusze

### S1: Generowanie pomysłu
1. W cyklu system nie ma aktywnego projektu.
2. Generator wymyśla pomysł, który poprawia jakość życia, sytuację finansową lub zdrowie ludzi.
3. Sprawdza w sieci, czy problem jest realny i czy istnieje już bezpłatne narzędzie realizujące główną funkcję pomysłu.
4. Odrzuca próbę nieudaną i próbuje ponownie, najwyżej 5 razy w cyklu. Nieudana próba to:
   - pomysł z kategorii wykluczonej (patrz „Bezpieczeństwo”),
   - istnieje bezpłatne narzędzie realizujące główną funkcję,
   - brak co najmniej jednego źródła potwierdzającego realność problemu,
   - duplikat pomysłu wcześniej odrzuconego (ten sam tytuł albo ten sam problem dla tej samej grupy ludzi).
5. Dla udanej próby przygotowuje kartę pomysłu z polami:
   - problem i dla kogo,
   - co robi aplikacja,
   - wynik sprawdzenia w sieci ze źródłami,
   - ocena 1–5 w trzech kryteriach: wpływ na jakość życia, finanse lub zdrowie; wykonalność w limicie czasu projektu; ryzyko,
   - rekomendacja: „rekomenduję” albo „nie rekomenduję”, z jednym zdaniem uzasadnienia.
6. Pomysł przechodzi w stan „w ocenie”, a właściciel dostaje powiadomienie push.

**Kryteria akceptacji**
- Zakładając brak aktywnego projektu i udaną próbę w cyklu, wtedy powstaje karta pomysłu ze wszystkimi polami z kroku 5, pomysł ma stan „w ocenie”, a właściciel dostaje powiadomienie push.
- Zakładając 5 nieudanych prób w cyklu, wtedy karta nie powstaje, powiadomienie nie jest wysyłane, a w dzienniku jest 5 wpisów z przyczyną odrzucenia każdej próby.
- Zakładając aktywny projekt, wtedy w cyklu nie powstaje nowy pomysł.
- Zakładając próbę z kategorii wykluczonej, wtedy nie trafia do właściciela, a dziennik zawiera przyczynę „kategoria wykluczona”.
- Zakładając próbę będącą duplikatem odrzuconego pomysłu, wtedy nie trafia do właściciela, a dziennik zawiera przyczynę „duplikat”.

### S2: Ocena i zatwierdzenie pomysłu
> Zmiana właściciela z 2026-10-27: ocena odbywa się etykietą na GitHubie, bez rozmowy z modelem. Rozmowa w cezar-pwa (`sw-ocena`) zostaje jako opcja uruchamiana ręcznie.

1. Właściciel dostaje powiadomienie z linkiem do issue pomysłu (etykiety `sw-pomysl`, `sw-w-ocenie`).
2. Czyta kartę na GitHubie i opcjonalnie dopisuje komentarze z uwagami.
3. Zmienia etykietę na `sw-zatwierdzony`.
4. W następnym cyklu system przechodzi do S4; uwagi z komentarzy są wejściem dla specyfikacji.

**Kryteria akceptacji**
- Zakładając nową kartę, wtedy właściciel dostaje powiadomienie z linkiem do issue, a żadne zadanie nie czeka na jego odpowiedź.
- Zakładając pomysł „w ocenie” bez etykiety decyzji, wtedy system nie podejmuje pracy nad nim ani nie generuje kolejnego pomysłu.
- Zakładając etykietę `sw-zatwierdzony` (także gdy `sw-w-ocenie` nadal jest na issue), wtedy w następnym cyklu powstaje repozytorium aplikacji, issue ma `sw-stan-specyfikacja`, a „approvedAt” jest ustawione.
- Zakładając zatwierdzenie (od etapu 2), wtedy aż do powiadomienia o wdrożeniu albo wstrzymaniu właściciel nie dostaje żadnej wiadomości wymagającej odpowiedzi.

### S3: Odrzucenie pomysłu
1. Właściciel ustawia etykietę `sw-odrzucony` i opcjonalnie dopisuje powód w komentarzu.
2. Pomysł przechodzi w stan „odrzucony”.
3. Generator tworzy kolejny pomysł w następnym cyklu (S1), z powodem odrzucenia jako wskazówką.

**Kryteria akceptacji**
- Zakładając odrzucenie z powodem, wtedy w następnym cyklu generator uruchamia się bez akcji właściciela, a powód jest przekazany generatorowi.
- Zakładając odrzucony pomysł, wtedy żadna późniejsza karta nie ma tego samego tytułu ani nie opisuje tego samego problemu dla tej samej grupy ludzi.

### S4: Repozytorium i specyfikacja aplikacji
1. System tworzy prywatne repozytorium na koncie `cieyhomelab` o nazwie z tytułu pomysłu w kebab-case. Gdy nazwa jest zajęta, dodaje przyrostek `-2`, `-3` itd. Repozytorium ma README na gałęzi bazowej.
2. Analityk pisze specyfikację aplikacji na podstawie podsumowania z S2. Luki rozstrzyga sam najprostszą, odwracalną opcją i zapisuje każdą w sekcji „Założenia”.
3. Niezależny przegląd (agent bez dostępu do rozumowania analityka) wydaje werdykt „zatwierdzona” albo „uwagi”; sprawdza też, czy każdy scenariusz ma kryteria, dla których da się napisać test E2E. Analityk poprawia uwagi, najwyżej 2 rundy poprawek.
4. PR ze specyfikacją jest mergowany automatycznie, gdy przegląd wydał werdykt „zatwierdzona”, a przegląd bezpieczeństwa przeszedł. Warunek CI nie dotyczy tego PR, bo CI powstaje w S5.
5. Projekt przechodzi w stan „architektura”.

**Kryteria akceptacji**
- Zakładając zatwierdzony pomysł, wtedy powstaje prywatne repozytorium z README na gałęzi bazowej.
- Zakładając zajętą nazwę repozytorium, wtedy powstaje repozytorium z pierwszym wolnym przyrostkiem.
- Zakładając PR ze specyfikacją, wtedy opis PR zawiera werdykt przeglądu i listę założeń, a specyfikacja nie zawiera danych osobowych właściciela.
- Zakładając werdykt „zatwierdzona” i pozytywny przegląd bezpieczeństwa, wtedy PR jest mergowany bez udziału właściciela.
- Zakładając werdykt „uwagi” po 2 rundach poprawek, wtedy projekt jest wstrzymywany (S11).

### S5: Architektura i moduły
1. Architekt wybiera stos (aplikacja uruchamia się w kontenerze na VPS z Dockerem) i dzieli aplikację na co najmniej jeden moduł.
2. Dla każdego modułu określa kontrakt z dwiema sekcjami: „udostępnia” i „wymaga”.
3. Dla każdego modułu zapisuje decyzję: część jednej aplikacji albo osobna usługa.
4. Przygotowuje szkielet i CI.
5. PR architektury przechodzi automatyczny merge (S8).

**Kryteria akceptacji**
- Zakładając zmergowaną specyfikację, wtedy powstaje PR architektury z listą modułów, kontraktem każdego modułu i decyzją „część aplikacji / osobna usługa”.
- Zakładając listę modułów, wtedy każdy scenariusz specyfikacji aplikacji jest przypisany do co najmniej jednego modułu.
- Zakładając PR architektury, wtedy repozytorium zawiera workflow CI, który uruchamia się na tym PR.

### S6: Równoległa implementacja modułów
1. Kierownik zakłada zadania dla modułów, których sekcja „wymaga” jest spełniona przez kontrakty (implementacja może opierać się na kontrakcie, a nie na gotowym module).
2. Do limitu równoległych agentów agenci pracują jednocześnie. Limit obejmuje wszystkie role pracujące naraz nad zadaniami projektu; konfigurowalny, start: 3.
3. Każdy moduł ma test dla każdej pozycji z sekcji „udostępnia”.

**Kryteria akceptacji**
- Zakładając limit 3 i 5 modułów gotowych do pracy, wtedy naraz pracuje najwyżej 3 agentów.
- Zakładając zmianę limitu w konfiguracji, wtedy nowy limit obowiązuje od następnego przydziału zadań.
- Zakładając PR modułu, wtedy zawiera test dla każdej pozycji z sekcji „udostępnia” jego kontraktu.

### S7: Integracja
1. Gdy wszystkie moduły mają stan „zmergowany”, kierownik zakłada zadanie integracji.
2. Integrator składa moduły w całość.
3. Tester uruchamia testy E2E pełnej aplikacji.

**Kryteria akceptacji**
- Zakładając wszystkie moduły „zmergowane”, wtedy powstaje zadanie integracji.
- Zakładając integrację, wtedy każdy scenariusz specyfikacji aplikacji ma co najmniej jeden test E2E, a wszystkie przechodzą, zanim projekt przejdzie w stan „przegląd”.

### S8: Automatyczny merge PR
PR (poza PR ze specyfikacją, S4) jest mergowany bez człowieka, gdy jednocześnie:
- reviewer na innym modelu zatwierdził zmianę,
- CI jest zielone (brak workflow CI oznacza niespełniony warunek),
- przegląd bezpieczeństwa na innym modelu przeszedł.

Każda strona może wymagać najwyżej 3 rund poprawek; potem zadanie ma wyczerpane próby (S11).

**Kryteria akceptacji**
- Zakładając spełnione trzy warunki, wtedy PR jest mergowany automatycznie.
- Zakładając niespełniony którykolwiek warunek, wtedy PR nie jest mergowany.
- Zakładając recenzję lub przegląd bezpieczeństwa wykonane przez ten sam model co autor, wtedy nie liczą się jako zatwierdzenie.
- Zakładając repozytorium bez workflow CI, wtedy PR nie jest mergowany.

### S9: Przegląd bezpieczeństwa przed wdrożeniem
Pełna aplikacja przechodzi przegląd z czterema punktami:
1. brak funkcji z kategorii wykluczonych,
2. brak sekretów w repozytorium,
3. każdy adres aplikacji wymaga uwierzytelnienia,
4. jedno konto właściciela: brak rejestracji innych osób i brak formularzy zbierających dane osób trzecich.

Znalezione problemy wracają do roju jako zadania poprawek (S8, S11).

**Kryteria akceptacji**
- Zakładając aplikację z funkcją z zestawu wzorcowego kategorii wykluczonych, wtedy wdrożenie nie następuje i powstaje zadanie poprawki.
- Zakładając sekret w repozytorium, wtedy wdrożenie nie następuje i powstaje zadanie poprawki.
- Zakładając adres aplikacji dostępny bez uwierzytelnienia, wtedy wdrożenie nie następuje.
- Zakładając funkcję rejestracji nowych kont, wtedy wdrożenie nie następuje.
- Zakładając pozytywny przegląd, wtedy w repozytorium jest raport z wynikiem każdego z czterech punktów.

### S10: Wdrożenie i powiadomienie o gotowości
1. Po zielonych testach E2E (S7) i pozytywnym przeglądzie (S9) aplikacja jest wdrażana na VPS pod prywatnym adresem.
2. Właściciel dostaje powiadomienie push z adresem i tytułem aplikacji.
3. Projekt przechodzi w stan „wdrożony”; generator rusza w następnym cyklu (S1).

**Kryteria akceptacji**
- Zakładając wdrożenie, wtedy żądanie bez uwierzytelnienia zwraca odmowę albo przekierowanie do logowania, a zalogowany właściciel widzi aplikację.
- Zakładając nieudane wdrożenie, wtedy aplikacja nie jest osiągalna bez uwierzytelnienia ani w trakcie, ani po awarii.
- Zakładając wdrożenie, wtedy właściciel dostaje powiadomienie z adresem.
- Zakładając wdrożenie, wtedy w następnym cyklu uruchamia się generator.

### S11: Wstrzymanie po utknięciu
1. Zadanie nie przechodzi (błąd, brak postępu, testy, CI, recenzja, przegląd).
2. System ponawia zadanie albo zleca rundę poprawek bez udziału właściciela.
3. Po wyczerpaniu prób projekt przechodzi w stan „wstrzymany”, a właściciel dostaje powiadomienie z przyczyną i ostatnim stanem.
4. Agenci nie podejmują dalszej pracy w tym projekcie; generator rusza w następnym cyklu (S1).

**Kryteria akceptacji**
- Zakładając nieudane zadanie, wtedy system ponawia je bez udziału właściciela.
- Zakładając zadanie bez commitu i zmiany stanu przez 3 godziny, wtedy liczy się jako nieudane.
- Zakładając wyczerpane próby, wtedy projekt ma stan „wstrzymany”, a powiadomienie zawiera przyczynę i ostatni stan.
- Zakładając wstrzymanie, wtedy właściciel nie dostaje pytań, agenci nie pracują w tym projekcie, a w następnym cyklu uruchamia się generator.
- Zakładając wstrzymanie przed utworzeniem repozytorium, wtedy powiadomienie zawiera przyczynę, a projekt nie ma repozytorium.

### S12: Limity czasu i zużycia
1. Każdy projekt ma limit czasu (domyślnie 7 × 24 godziny od zatwierdzenia pomysłu) i limit zużycia; obie wartości w konfiguracji.
2. Przed każdym przydziałem zadania system sprawdza oba limity projektu.
3. Po przekroczeniu limitu projektu projekt jest wstrzymywany jak w S11.
4. Gdy wyczerpie się limit planu modeli, praca jest zawieszana (stan projektu bez zmian, oznaczenie „czeka na limit planu”); system sprawdza dostępność w każdym cyklu i wznawia pracę automatycznie. Zawieszenie nie zużywa ponowień.
5. System nigdy nie włącza płatnego dodatkowego zużycia.

**Kryteria akceptacji**
- Zakładając projekt zatwierdzony 7 × 24 godziny temu i niewdrożony, wtedy projekt ma stan „wstrzymany”, a powiadomienie ma przyczynę „limit czasu”.
- Zakładając projekt zatwierdzony 6 dni i 23 godziny temu, wtedy projekt nie jest wstrzymywany z powodu czasu.
- Zakładając przekroczony limit zużycia projektu, wtedy projekt ma stan „wstrzymany”, a powiadomienie ma przyczynę „limit zużycia”.
- Zakładając wyczerpany limit planu, wtedy projekt ma oznaczenie „czeka na limit planu”, licznik ponowień się nie zmienia, a po odnowieniu limitu praca wznawia się bez akcji właściciela.
- Zakładając przydział zadania, wtedy przed nim system sprawdza, że płatne dodatkowe zużycie jest wyłączone; gdy jest włączone, zadanie nie startuje, a dziennik zawiera wpis.

### S13: Pomiar skuteczności
1. Projekt jest liczony jako „bez interwencji”, gdy osiągnął stan „wdrożony” bez wcześniejszego stanu „wstrzymany”.
2. Każde powiadomienie o wdrożeniu i wstrzymaniu zawiera bieżący odsetek: projekty „bez interwencji” / wszystkie zatwierdzone pomysły zakończone (wdrożone albo wstrzymane).

**Kryteria akceptacji**
- Zakładając 3 zakończone projekty, z czego 2 wdrożone bez wstrzymania, wtedy powiadomienie pokazuje 67%.

## Dane
- **Pomysł:** tytuł, problem, dla kogo, opis działania, wynik sprawdzenia w sieci ze źródłami, oceny 1–5 w trzech kryteriach, rekomendacja z uzasadnieniem, stan, powód odrzucenia [DANE OSOBOWE].
  - Stany: „w ocenie” → „zatwierdzony” albo „odrzucony”.
- **Rozmowa oceny:** wiadomości właściciela i modelu, podsumowanie ustaleń. [DANE OSOBOWE; przy pomysłach zdrowotnych lub finansowych także szczególnej kategorii]
- **Projekt:** pomysł, repozytorium, data zatwierdzenia, stan, oznaczenie „czeka na limit planu”, przyczyna wstrzymania, zużycie względem limitu, prywatny adres, „bez interwencji” (tak/nie).
  - Stany: „specyfikacja” → „architektura” → „implementacja” → „integracja” → „przegląd” → „wdrażanie” → „wdrożony”; z każdego stanu przed „wdrożony” możliwe przejście do „wstrzymany”.
- **Moduł:** projekt, nazwa, kontrakt („udostępnia”, „wymaga”), decyzja „część aplikacji / osobna usługa”, stan („do zrobienia”, „w pracy”, „zmergowany”).
- **Zadanie:** projekt, moduł (opcjonalnie), rola, stan, liczba ponowień, liczba rund poprawek, czas ostatniego postępu.
- **Raport z przeglądu bezpieczeństwa:** projekt, wynik każdego punktu S9, data.
- **Powiadomienie:** rodzaj (pomysł, wdrożenie, wstrzymanie, brak pomysłów), tytuł, link. Bez treści zdrowotnych ani finansowych.
- **Dziennik systemu:** odrzucone próby z przyczyną, ponowienia, wstrzymania, merge. Bez danych osobowych.
- **Konfiguracja:** interwał cyklu, limit równoległych agentów, limit czasu i zużycia projektu, liczba ponowień, liczba rund poprawek, liczba prób generowania, zestaw kategorii wykluczonych z przykładami.
- **Subskrypcja powiadomień:** urządzenie właściciela. [DANE OSOBOWE]
- **Dane w budowanych aplikacjach:** wyłącznie dane właściciela; mogą obejmować dane zdrowotne lub finansowe [DANE OSOBOWE, w tym szczególnej kategorii]. Dane uwierzytelnienia właściciela [DANE OSOBOWE].

## Integracje zewnętrzne
Wymagania właściciela (istniejąca infrastruktura):
- **Claude Max** jako jedyne źródło modeli (bez innych dostawców).
- **Cezar (Open Mercato)** na VPS jako orkiestrator agentów.
- **cezar-pwa** jako aplikacja na telefon. Powiadomienia push już działają; rozmowa oceny z przyciskami „Zatwierdź” i „Odrzuć” to nowa funkcja tej aplikacji.
- **GitHub, konto `cieyhomelab`:** repozytoria, PR, CI, zadania; agenci działają na koncie właściciela.
- **Wyszukiwanie w sieci** dla generatora pomysłów.
- **VPS właściciela z Dockerem** jako miejsce wdrożenia aplikacji; aplikacje uruchamiają się w kontenerach.
- **Inny model przy recenzji i przeglądzie bezpieczeństwa** (wymaganie właściciela przeniesione z sh-skills).

## Wymagania niefunkcjonalne

### Bezpieczeństwo
- **Kategorie wykluczone (pomysł i funkcje aplikacji):** wyliczanie lub sugerowanie dawek leków, diagnoza medyczna, porady inwestycyjne, obsługa prawdziwych pieniędzy (płatności, przelewy, handel). Także pomysły nielegalne, wprowadzające w błąd albo skierowane przeciw konkretnym osobom. Konfiguracja zawiera zestaw wzorcowy przykładów dozwolonych i wykluczonych, używany w testach.
- Każda aplikacja dostępna wyłącznie po uwierzytelnieniu właściciela; brak publicznego wydania.
- Sekrety poza repozytoriami.
- Przegląd bezpieczeństwa przed każdym merge (S4, S8) i przed wdrożeniem (S9).

### RODO
- Aplikacje przechowują wyłącznie dane właściciela i nie zbierają danych od innych osób.
- Specyfikacje, repozytoria i dziennik nie zawierają danych osobowych właściciela; podsumowanie rozmowy trafia do specyfikacji jako wymagania, bez danych osobowych.
- Agenci i testy używają danych syntetycznych, nigdy danych właściciela.
- Powiadomienia zawierają tylko tytuł i link.
- Dane zdrowotne i finansowe właściciela: dostęp tylko po uwierzytelnieniu, bez wysyłania do usług zewnętrznych poza niezbędnymi do działania.

### Skala, zasoby i niezawodność
- Jeden aktywny projekt naraz (od etapu 2).
- Równoległość ograniczona konfigurowalnym limitem agentów (start: 3), bo wszyscy agenci i czat właściciela dzielą limity jednego planu Claude Max, a zadania dzielą zasoby VPS.
- Stan systemu jest trwały: po restarcie orkiestratora praca wznawia się od ostatniego zapisanego stanu.

### Współistnienie z sh-skills
Wymaganie właściciela: skille, workflowy, automatyzacje i skrypty tego systemu działają na tym samym VPS i w tym samym Cezarze co sh-skills, nie nadpisując ich i nie przejmując ich projektów.

| Element | sh-skills (zostaje bez zmian) | swarm-of-agents |
|---------|-------------------------------|-----------------|
| Skille | `sh-*` (np. `sh-analityk`) | `sw-*` (katalog skilla i pole `name` w SKILL.md, np. `sw-analityk`) |
| Workflowy Cezara | `sh-delivery`, `sh-sweep` (plik i pole `name`) | `sw-*`, np. `sw-delivery`, `sw-sweep` |
| Automatyzacje Cezara | nazwy `sh: …` (np. „sh: realizacja”, „sh: przegląd co godzinę”) | nazwy `sw: …` |
| Skrypty | `~/sh-skills/bin/sh-notify`, `sh-sweep-gate` | `sw-*` w katalogu klonu `swarm-of-agents`, np. `sw-notify`, `sw-sweep-gate` |
| Katalog na VPS | `~/sh-skills` | osobny katalog klonu `swarm-of-agents` |
| Repozytorium sterujące przeglądem | `sh-control` | osobne (nie `sh-control`) |
| Etykiety własne systemu | `sh-architekt`, `sh-posprzatane` | `sw-*`, np. `sw-architekt`, `sw-posprzatane` |
| Rozpoznanie projektów przez przegląd | repozytoria z `.ai/cezar/workflows/sh-delivery.yml` | repozytoria z plikiem workflow `sw-*` |

Zasady:
- Instalacja i konfiguracja elementów `sw-*` nie zmienia, nie wyłącza i nie usuwa elementów `sh-*`; aktualizacja „po nazwie” dotyczy tylko nazw z prefiksem `sw`.
- Przegląd `sw-*` obsługuje tylko projekty `sw-*`, a przegląd `sh-*` nadal tylko projekty `sh-*`. Projekt nie jest obsługiwany przez oba naraz.
- Wyjątek etapu 1: po zmergowaniu specyfikacji projekt jest przekazywany łańcuchowi `sh-*` (dostaje konfigurację `sh-*`) i od tej chwili obsługuje go tylko przegląd `sh-*`.
- Skille `sw-*` wywołują tylko skille `sw-*` i `om-*` z Open Mercato, poza przekazaniem z etapu 1.
- Etykiety ogólne (`spec`, `ready`, `blocked` itd.) mogą się powtarzać, bo każdy projekt należy do jednego systemu.

**Kryteria akceptacji**
- Zakładając zainstalowane skille, workflowy, automatyzacje i skrypty `sh-*`, gdy instaluję i konfiguruję `sw-*`, wtedy Cezar pokazuje obie grupy, a elementy `sh-*` mają niezmienioną treść, nazwy i stan (włączone albo wyłączone).
- Zakładając projekt w toku na łańcuchu `sh-*`, gdy uruchamia się przegląd `sw-*`, wtedy nie podejmuje on w tym projekcie żadnej akcji.
- Zakładając projekt `sw-*`, gdy uruchamia się przegląd `sh-*`, wtedy nie rozpoznaje go jako projektu zarządzanego.
- Zakładając repozytorium `swarm-of-agents`, wtedy żaden katalog skilla, pole `name`, nazwa workflow, nazwa automatyzacji, nazwa skryptu ani etykieta własna systemu nie zaczyna się od `sh-` albo `sh:`.

### Języki
- Komunikacja z właścicielem, karty pomysłów i specyfikacje po polsku.

## Przypadki brzegowe i błędy
- **Brak pomysłów przez dłuższy czas:** po 24 kolejnych cyklach bez udanej próby właściciel dostaje jedno powiadomienie „brak pomysłów”; generator próbuje dalej.
- **Właściciel nie odpowiada na pomysł:** pomysł zostaje „w ocenie”; nowy pomysł nie powstaje.
- **Powiadomienie niedostarczone albo cezar-pwa niedostępna:** pomysł zostaje „w ocenie”; karta jest widoczna po otwarciu aplikacji.
- **Wyczerpany limit planu podczas rozmowy oceny:** aplikacja pokazuje komunikat, że rozmowa będzie dostępna po odnowieniu limitu; pomysł zostaje „w ocenie”.
- **Brak uprawnień do utworzenia repozytorium lub push:** S11.
- **Brak dostępu do sieci przy sprawdzaniu pomysłu:** próba nieudana (brak źródła); ponowienie w następnym cyklu.
- **Awaria lub limit zapytań GitHuba:** zadanie nieudane, ponowienia, potem S11.
- **Konflikt modułów przy integracji:** runda poprawek; po wyczerpaniu S11.
- **Brak zasobów VPS na kolejne wdrożenie albo nieudane wdrożenie:** ponowienia, potem S11.
- **Wyczerpany limit planu:** S12.

## Poza zakresem
- Publiczne wydanie aplikacji, użytkownicy inni niż właściciel (także domownicy), zbieranie danych od innych osób.
- Komercjalizacja i płatności.
- Pomysły i funkcje z kategorii wykluczonych.
- Dowolny dostawca modeli inny niż Claude Max; płatne dodatkowe zużycie.
- Kilka aktywnych projektów jednocześnie.
- Obowiązkowa architektura mikroserwisów (forma modułów to decyzja architekta).
- Utrzymanie, rozwój i wznawianie aplikacji po wdrożeniu albo wstrzymaniu.
- Usuwanie i retencja rozmów oraz dziennika.

## Etapy dostarczenia
1. **Pomysł, ocena i specyfikacja:** generator, karta, powiadomienie, rozmowa oceny w cezar-pwa, zatwierdzenie i odrzucenie, repozytorium i specyfikacja z automatycznym merge. Projekt kończy się na zmergowanej specyfikacji i powiadomieniu „specyfikacja gotowa”; dalsza budowa idzie dotychczasowym łańcuchem sh-* z bramkami ludzkimi. Generator rusza w następnym cyklu po zmergowaniu specyfikacji. Scenariusze: S1, S2, S3, S4.
2. **Autonomiczne dostarczanie jednym modułem:** architektura z jednym modułem, szkielet i CI, automatyczny merge, testy E2E, przegląd bezpieczeństwa, wdrożenie, wstrzymania, limity i pomiar skuteczności. Od tego etapu obowiązuje jeden aktywny projekt aż do wdrożenia albo wstrzymania. Scenariusze: S5 (jeden moduł), S7 (testy E2E pełnej aplikacji), S8, S9, S10, S11, S12, S13.
3. **Praca równoległa modułami:** wiele modułów z kontraktami, równoległa implementacja do limitu agentów, integracja. Scenariusze: S5 (wiele modułów), S6, S7 (integracja).

## Założenia
- **Migracja:** `swarm-of-agents` przejmuje skille i workflowy z sh-skills oraz konfigurację z sh-control; skille dostają prefiks `sw-` i działają obok `sh-*`; stare repozytoria są archiwizowane po uruchomieniu etapu 2, bo do tego czasu etap 1 przekazuje budowę łańcuchowi sh-*. Analityk potrzebuje wariantu autonomicznego. Uzasadnienie: decyzja właściciela, jedno źródło prawdy; migracja to osobne zadanie, nie scenariusz systemu.
- **Etap 1 kończy się na specyfikacji:** generator rusza po zmergowaniu specyfikacji, bo w etapie 1 nie ma jeszcze stanów „wdrożony” i „wstrzymany”. Uzasadnienie: etap 1 działa samodzielnie; zasada jednego projektu obowiązuje od etapu 2.
- **Ponowienia i rundy:** 2 ponowienia na zadanie, 3 rundy poprawek na PR, 2 rundy poprawek specyfikacji; wartości w konfiguracji. Uzasadnienie: najprostsze i łatwe do zmiany.
- **Brak postępu = 3 godziny:** ten sam próg co dotychczasowy próg utknięcia PR w sh-kierownik.
- **Cykl co godzinę:** zgodnie z dotychczasowym rytmem przeglądu; wartość w konfiguracji.
- **5 prób generowania w cyklu i powiadomienie po 24 cyklach bez pomysłu:** ogranicza zużycie limitu i chroni przed bezterminową ciszą.
- **Limit 3 agentów i 7 dni na projekt:** wartości startowe zaakceptowane przez właściciela; do korekty po pierwszych projektach.
- **Limit zużycia projektu:** jednostkę i sposób pomiaru ustala architekt; wymaganie to mierzalność przed każdym przydziałem zadania.
- **Próg sukcesu:** bez wartości docelowej; system raportuje odsetek, bo najpierw trzeba poznać wartość bazową.
- **Repozytoria prywatne:** aplikacje są prywatnymi prototypami.

## Sekcje techniczne

Decyzja o stosie i jej uzasadnienie: `docs/adr/0001-stos-technologiczny.md`. Zasady pracy: `AGENTS.md`.

### Architektura

#### Komponenty
| Komponent | Gdzie | Rola |
|-----------|-------|------|
| Cezar | VPS, `127.0.0.1:4321` | Silnik: zadania, workflowy w wersji 2, automatyzacje, wznawianie po limicie planu, rejestracja projektów. Nie jest modyfikowany. |
| cezar-pwa + sidecar `cezar-push` | VPS (`/m/`, `127.0.0.1:4330`) | Rozmowa oceny (`RunScreen`, `AskCard`) i powiadomienia push. Etap 1 bez zmian; etap 2 dodaje nowe rodzaje bramek (zmiana w repozytorium cezar-pwa). |
| `swarm-of-agents` (to repozytorium) | klon w `~/swarm-of-agents` | Kod roju: `skills/sw-*`, `workflows/sw-*.yml`, `bin/sw-*`, `config/`. Skille linkowane do `~/.claude/skills` przez `scripts/install.sh`. |
| `sw-control` | **prywatne** repozytorium GitHub + projekt Cezara | Repozytorium sterujące: issues pomysłów i dziennik (stan), automatyzacja `sw: przegląd co godzinę`, kopie workflowów `sw-sweep` i `sw-ocena` w `.ai/cezar/workflows/`. `sw-doctor` blokuje pracę, gdy repozytorium nie jest prywatne. |
| Projekt aplikacji | prywatne repozytorium GitHub + projekt Cezara | Utworzony przez `POST /api/v1/projects/create`. Zawiera specyfikację aplikacji, kod i kopie workflowów `sw-*` potrzebnych do budowy. |
| GitHub `cieyhomelab` | – | Trwały stan (etykiety, komentarze, issues, PR), CI aplikacji. Agenci działają na koncie właściciela. |

Granice:
- **Skrypty `bin/sw-*` (węzły `check`):** cała logika deterministyczna, czyli decyzje bramki, zmiany stanu (także etykieta decyzji pomysłu), merge, tworzenie repozytoriów i powiadomienia.
- **Agenci (węzły `agent`, zawsze `runner: claude`, jawny `model`, ograniczone `allowedTools` i `bashAllowlist`):** wyłącznie treść, czyli pomysły, rozmowa, specyfikacje, kod, recenzje i werdykty `CEZ:VERDICT`.
- **Zapisy agentów na GitHubie:** tylko komentarze opisane w modelu danych oraz commity i PR w repozytorium aplikacji.
- **Werdykty:** trafiają do skryptów jako wyjścia węzłów (`{{nodes.<id>.verdict}}`), nigdy z treści komentarzy.

#### Skille (`skills/sw-*`)
| Skill | Model (`config/sw.json`) | Etap | Zadanie |
|-------|--------------------------|------|---------|
| `sw-start` | `chores` | 1 | Jednorazowa konfiguracja `sw-control`: utworzenie jako prywatne (jeśli brak), etykiety `sw-*`, workflowy, automatyzacja „sw: przegląd co godzinę” (aktualizacja po nazwie przez `list`, tylko nazwy `sw: …`; `delete` niedozwolone w `bashAllowlist`), issue dziennika, przewinięcie lokalnej kopii `sw-control` w Cezarze (`git pull --ff-only`; Cezar czyta workflowy z niej, nie z GitHuba). |
| `sw-generator` | `generator` | 1 | S1: pomysł, sprawdzenie w sieci, odrzucanie duplikatów i kategorii wykluczonych, karta pomysłu w issue. |
| `sw-analityk` | `analyst` | 1 | Tryb `ocena` (S2/S3: rozmowa, podsumowanie, karta decyzji) i tryb `spec` (S4: specyfikacja aplikacji bez dopytywania, luki w „Założeniach”). |
| `sw-recenzent` | `reviewer` | 1 | Niezależny przegląd specyfikacji (S4) i recenzja PR (S8); werdykty `zatwierdzona`/`uwagi` oraz `approve`/`changes`. |
| `sw-bezpieczenstwo` | `security` | 1 | Przegląd bezpieczeństwa PR (S4, S8) i aplikacji (S9): kategorie wykluczone według `config/kategorie-wykluczone.md`, brak danych osobowych (także w komentarzu `sw:ustalenia`), sekrety, uwierzytelnienie; werdykty `pass`/`fail`. |
| `sw-architekt` | `architect` | 2 | S5: stos, moduły z kontraktami, szkielet i CI aplikacji z check-runami `requiredChecks`. |
| `sw-kierownik` | `chores` | 2 | Zadania modułów, przydział do limitu, wykrywanie utknięcia (S6, S11). |
| `sw-inzynier` | `engineer` | 2 | Implementacja modułu według kontraktu (S6). |
| `sw-tester` | `reviewer` | 2 | Testy E2E pełnej aplikacji (S7). |
| `sw-integrator` | `integrator` | 3 | Składanie modułów (S7). |

#### Skrypty (`bin/sw-*`)
| Skrypt | Etap | Zadanie |
|--------|------|---------|
| `sw-doctor` | szkielet | Zdrowie środowiska: narzędzia, `gh`, Cezar (`/api/v1/health`), prywatne `sw-control`, brak zmiennych rozliczanych poza planem Max; ostrzeżenie o `resources.maxParallel`. |
| `sw-gate` | szkielet → 1 | Decyzja cyklu: `URUCHOM: NIC`, `GENERATOR`, `OCENA <issue>`, `SPEC <issue>`, później `PROJEKT <issue>`. Zwraca `NIC`, gdy w `sw-control` trwa inne zadanie `sw-sweep`. |
| `sw-log` | 1 | Wpis w issue dziennika (bez danych osobowych). |
| `sw-start-ocena` | 1 | Tworzy nieautonomiczne zadanie `sw-ocena` dla issue pomysłu. |
| `sw-ocena-wynik` | 1 | Czyta historię zadania oceny z Cezara, ustawia etykietę decyzji na podstawie wiadomości właściciela, sprawdza komentarze agenta. |
| `sw-create-repo` | 1 | Repozytorium aplikacji przez Cezara (z adopcją repozytorium utworzonego w przerwanym przebiegu), zasiew plików, `maxParallel`. |
| `sw-pr-body` | 1 | Dopisuje do opisu PR werdykty przeglądów i listę założeń (S4). |
| `sw-merge` | 1 | Merge PR po spełnieniu warunków (S4/S8): werdykty z argumentów, modele z rekordów zadań, SHA, nazwane check-runy. |
| `sw-notify` | 1 | Powiadomienie przez bramkę `cezar-push` (tylko tytuł i link). |
| `sw-handover-sh` | 1 | Wyjątek etapu 1: przekazanie projektu łańcuchowi sh-*. Jedyny plik, któremu `check-names.sh` pozwala odwoływać się do `sh-*`. |
| `sw-limits` | 2 | Limit czasu i zużycia projektu, wyczerpanie wznowień Cezara (S12). |
| `sw-pause` | 2 | Wstrzymanie projektu z przyczyną (S11, S12). |
| `sw-deploy` | 2 | Wdrożenie aplikacji na VPS i sprawdzenie dostępu (S10). |

#### Przepływy
1. **Cykl (S1).**
   - Automatyzacja `sw: przegląd co godzinę` (`schedule`, `hours: 1`, autonomiczna) uruchamia `sw-sweep` w `sw-control`.
   - Węzeł `check` `sw-gate` czyta stan z GitHuba i Cezara i drukuje jedną decyzję. Gałęzie `if` (`contains`) wybierają dalszy krok.
   - **Bez powiadomień o porażce.** `sw-sweep` i pozostałe zadania autonomiczne kończą się statusem `success` także przy porażce. Sidecar powiadamia o każdym zadaniu, które wchodzi w `failed`, a specyfikacja nie przewiduje takich wiadomości. Ponowienia i rundy poprawek to pętle `loop` w jednym zadaniu, a nie kolejne nieudane zadania.
   - **Porażki środowiska:** linia `STAN: BLAD` trafia do dziennika. Po `noIdeaNotifyAfterCycles` kolejnych takich cyklach przychodzi jedno powiadomienie `blocked`.
   - **Przy `URUCHOM: GENERATOR`:**
     - `sw-gate` zapisuje w worktree zadania plik `.ai/sw-run/generator.json`: tytuły i problemy odrzuconych pomysłów oraz zredagowane wskazówki z odrzuceń;
     - węzeł `agent` `sw-generator` w pętli `loop` (`max` = `ideaAttemptsPerCycle`) kończy werdyktem `karta` albo `nieudana`; przy `nieudana` skrypt `sw-log` zapisuje przyczynę;
     - po karcie `sw-start-ocena` tworzy zadanie oceny;
     - po wyczerpaniu prób licznik cykli bez pomysłu rośnie. Po `noIdeaNotifyAfterCycles` przychodzi jedno powiadomienie.
2. **Ocena (S2, S3).**
   - `sw-start-ocena` wywołuje `POST /api/v1/p/{sw-control}/runs` z `workflow: sw-ocena`, `autonomous: false`, a zadaniem jest numer issue.
   - Agent `sw-analityk` (tryb `ocena`):
     - pokazuje kartę i ustawia tytuł zadania (`CEZ:TITLE=Pomysł: …`);
     - rozmawia z właścicielem;
     - pokazuje podsumowanie i kończy turę pytaniem `CEZ:ASK` z opcjami „Zatwierdź” i „Odrzuć”.

     Zadanie w stanie `waiting` uruchamia powiadomienie `attention` sidecara, które otwiera `RunScreen`.
   - Po odpowiedzi agent zapisuje komentarz `sw:ustalenia` (wymagania bez danych osobowych) albo `sw:odrzucenie` (zredagowana wskazówka bez danych osobowych) i kończy `CEZ:DONE`.
   - Węzeł `check` `sw-ocena-wynik`:
     - czyta historię zadania (`GET …/runs/{id}/history`) i szuka ostatniej wiadomości użytkownika w formacie „Decyzja: Zatwierdź” albo „Decyzja: Odrzuć”;
     - dopiero na tej podstawie ustawia etykietę;
     - gdy brak decyzji albo komentarza, zostawia `sw-w-ocenie` i zapisuje wpis w dzienniku.

     Agent nie ustawia etykiet, a treść z sieci w rozmowie nie może zatwierdzić pomysłu.
   - **Zaginione zadanie** (np. po restarcie Cezara) wykrywa `sw-gate`: issue ma etykietę `sw-w-ocenie`, a zadanie z metadanych nie jest w stanie `waiting`, `running` ani `queued`. Bramka zwraca wtedy `URUCHOM: OCENA <issue>`.
3. **Specyfikacja (S4).**
   - `sw-gate` widzi `sw-zatwierdzony` bez repozytorium i zwraca `URUCHOM: SPEC <issue>`.
   - `sw-create-repo` tworzy repozytorium i projekt, a potem uruchamia w nowym projekcie autonomiczne zadanie `sw-spec`. Kroki `sw-spec`:
     1. agent `sw-analityk` (tryb `spec`), `git.commit`, `git.push`, `github.draft-pr`;
     2. `loop` (`max` = `specFixRounds`) z agentem `sw-recenzent` (werdykty `zatwierdzona`/`uwagi`) i poprawką analityka;
     3. agent `sw-bezpieczenstwo` (`pass`/`fail`);
     4. `check` `sw-pr-body`;
     5. `check` `sw-merge spec` z werdyktami i identyfikatorami zadań z wyjść węzłów;
     6. `check` `sw-notify spec`;
     7. `check` `sw-handover-sh` (etap 1) albo przejście do `sw-build` (etap 2).
4. **Przekazanie łańcuchowi sh-* (wyjątek etapu 1).**
   - `sw-handover-sh` uruchamia w projekcie aplikacji zadanie ze skillem `sh-start`, który dodaje konfigurację sh-*.
   - Od tej chwili projekt obsługuje wyłącznie przegląd sh-*: jest rozpoznawany po `sh-delivery.yml`, a `sw-gate` pomija repozytoria z tym plikiem.
   - Issue pomysłu dostaje `sw-spec-gotowa` i jest zamykane.
5. **Budowa (etap 2, 3).**
   - Workflow `sw-build` w projekcie aplikacji:
     1. architekt i jego PR przez `sw-merge kod`;
     2. kierownik zakłada zadania modułów;
     3. moduły przez `dispatch`/`fork` (najwyżej `maxParallel` projektu): `sw-inzynier`, potem `sw-recenzent` + CI (`github.wait-ci`) + `sw-bezpieczenstwo`, potem `sw-merge kod`;
     4. integracja i `sw-tester`;
     5. `sw-bezpieczenstwo` (S9), `sw-deploy`, `sw-notify`.
   - Każdy krok zaczyna się od `check` `sw-limits`. Po wyczerpaniu prób albo limitu `sw-pause` wstrzymuje projekt.

### Model danych

Nie ma bazy. Stan to obiekty GitHuba; zmieniają go wyłącznie skrypty. Każda zmiana etykiet to jedno `PATCH /repos/{o}/{r}/issues/{n}` z pełną listą `labels` po świeżym odczycie.

#### Pomysł — issue w `sw-control`
- **Etykiety stałe:** `sw-pomysl`.
- **Etykieta stanu pomysłu** (dokładnie jedna): `sw-w-ocenie` → `sw-zatwierdzony` | `sw-odrzucony`.
- **Treść issue:** karta pomysłu w stałych sekcjach Markdown:
  - `## Problem i dla kogo`, `## Co robi aplikacja`, `## Sprawdzenie w sieci` (lista źródeł);
  - `## Ocena` (trzy kryteria 1–5);
  - `## Rekomendacja` („rekomenduję” albo „nie rekomenduję” + zdanie).
- **Metadane:** na końcu treści blok `<!-- sw:meta {...} -->` z JSON:
  - `approvedAt` (ISO, ustawia `sw-ocena-wynik`),
  - `evalRunId`,
  - `repo` (`owner/name`) i `projectId` (Cezar),
  - `pauseReason`, `usageUsd`.

  Metadane zmienia tylko skrypt przez `PATCH /repos/{o}/{r}/issues/{n}`, zawsze po świeżym odczycie.
- **Komentarze:**
  - `<!-- sw:ustalenia -->`: podsumowanie oceny jako wymagania, bez danych osobowych. Sprawdzane przez `sw-bezpieczenstwo` w `sw-spec`, zanim analityk z niego skorzysta.
  - `<!-- sw:odrzucenie -->`: zredagowana wskazówka dla generatora (np. „za podobne do istniejących budżetów domowych”), bez danych osobowych.
- **Treść rozmowy oceny i dosłowny powód odrzucenia:** zostają wyłącznie w historii zadania Cezara na VPS. [DANE OSOBOWE] Nie są kopiowane na GitHuba.
- **Zamknięcie:** po odrzuceniu (stan `sw-odrzucony`), po przekazaniu w etapie 1 (`sw-spec-gotowa`), po wdrożeniu albo wstrzymaniu.

#### Projekt — etykiety na issue pomysłu
Jedna etykieta stanu projektu:
- `sw-stan-specyfikacja` → `sw-stan-architektura` → `sw-stan-implementacja` → `sw-stan-integracja` → `sw-stan-przeglad` → `sw-stan-wdrazanie` → `sw-stan-wdrozony`;
- z każdego stanu przed `sw-stan-wdrozony` możliwe przejście do `sw-stan-wstrzymany`.

Etykiety dodatkowe:
- `sw-czeka-na-limit` — zawieszenie po wyczerpaniu limitu planu;
- `sw-bez-interwencji` — dodawana przy wdrożeniu, jeśli nigdy nie było `sw-stan-wstrzymany`.

W etapie 1 projekt kończy się na `sw-stan-specyfikacja` i `sw-spec-gotowa` albo na `sw-stan-wstrzymany`. Repozytorium aplikacji ma temat GitHuba `sw-projekt` i w README link do issue pomysłu.

#### Aktywny projekt
Aktywnym projektem jest otwarte issue `sw-pomysl` w jednym z tych stanów:
- `sw-w-ocenie` albo `sw-zatwierdzony`;
- dowolna etykieta `sw-stan-*` poza `sw-stan-wdrozony` i `sw-stan-wstrzymany`.

`sw-gate` oblicza to przy każdym cyklu.

**Wzajemne wykluczenie cykli:** `sw-gate` zwraca `URUCHOM: NIC`, gdy w projekcie `sw-control` istnieje inne zadanie workflow `sw-sweep` w stanie `queued` albo `running` (`GET /api/v1/p/{id}/runs`, z pominięciem własnego `CEZ_RUN_ID`).

#### Moduł i zadanie (etap 2, 3)
- **Moduł:** plik kontraktu `docs/kontrakty/<modul>.md` w repozytorium aplikacji (sekcje `## Udostępnia`, `## Wymaga`, `## Forma`: „część aplikacji” albo „osobna usługa”) oraz issue z etykietą `sw-modul` i stanem `sw-modul-do-zrobienia` | `sw-modul-w-pracy` | `sw-modul-zmergowany`.
- **Zadanie:** zadanie Cezara. Liczniki ponowień i rund to wyjścia węzłów `loop` (`iteration`). Czas ostatniego postępu to ostatni commit na gałęzi albo zmiana stanu zadania.

#### Pozostałe obiekty
- **Raport z przeglądu bezpieczeństwa:** `docs/security/<data>-raport.md` w repozytorium aplikacji, z wynikiem czterech punktów S9.
- **Dziennik:** issue `sw-dziennik` w `sw-control`, jeden komentarz na zdarzenie (`odrzucona próba: <przyczyna>`, `ponowienie`, `wstrzymanie`, `merge`, `brak pomysłu`, `STAN: BLAD …`). Bez danych osobowych.
- **Licznik cykli bez pomysłu:** liczba kolejnych komentarzy „brak pomysłu” w dzienniku od ostatniej karty, liczona przez `sw-gate`. Odporna na restart; nie ma osobnego magazynu.
- **Konfiguracja:** `config/sw.json` (pola w `AGENTS.md`). Nowe pola zawsze z wartością domyślną w skryptach.
- **Powiadomienie:** nie jest przechowywane przez rój. Deduplikację robi sidecar (10 minut na bramkę i numer).
- **Subskrypcja powiadomień:** w sidecarze (`~/.cezar-push/subscriptions.json`), bez zmian.
- **Dane w aplikacjach:** decyduje architekt każdej aplikacji. Wymagania: tylko dane właściciela, dostęp po uwierzytelnieniu, dane syntetyczne w testach.

### Kontrakty API

#### Wyjście skryptów dla węzłów Cezara
Każdy skrypt wywoływany przez węzeł `check` drukuje na stdout tylko linie w formacie:

```
STAN: OK | STAN: BLAD <przyczyny oddzielone "; ">
URUCHOM: NIC | GENERATOR | OCENA <nr> | SPEC <nr> | PROJEKT <nr>      (tylko sw-gate)
WYNIK: <słowo>                                                         (pozostałe skrypty)
```

Ostrzeżenia idą na stderr (`UWAGA: …`). Kod 0 oznacza `pass`, a 1 `fail`. Workflow rozgałęzia się warunkiem `{kind: output, ref: <węzeł>.output, op: contains, value: "URUCHOM: GENERATOR"}`.

| Skrypt | Wejście | Wyjście | Zmienia |
|--------|---------|---------|---------|
| `sw-gate` | – (`CEZ_RUN_ID` z Cezara) | `STAN`, jedna linia `URUCHOM`; przy `GENERATOR` plik `.ai/sw-run/generator.json` w worktree | nic na GitHubie |
| `sw-start-ocena <nr>` | issue `sw-w-ocenie` | `WYNIK: ZADANIE <runId>` | `evalRunId` w metadanych |
| `sw-ocena-wynik <nr>` | issue + historia zadania `evalRunId` | `WYNIK: ZATWIERDZONY` / `ODRZUCONY` / `BRAK_DECYZJI` | etykiety, `approvedAt`, zamknięcie przy odrzuceniu |
| `sw-create-repo <nr>` | issue `sw-zatwierdzony` bez `repo` | `WYNIK: REPO <owner/name> <projectId>` | repozytorium, projekt Cezara, `repo`/`projectId`, `sw-stan-specyfikacja` |
| `sw-pr-body <repo> <pr> <plik-zalozen>` | werdykty z argumentów `--werdykt` | `WYNIK: ZAPISANO` | opis PR |
| `sw-merge <repo> <pr> <tryb> --sha <sha> --werdykt <rola>=<wynik>@<runId>…` | `tryb` = `spec` albo `kod` | `WYNIK: ZMERGOWANY` / `WARUNKI_NIESPELNIONE <które>` | merge PR |
| `sw-notify <rodzaj> <repo> <nr> <tytuł> <url>` | rodzaj: `spec`, `blocked` (etap 1); `deployed`, `paused`, `no-ideas` (etap 2) | `WYNIK: WYSLANO` / `WYNIK: POMINIETO` | nic w stanie roju |
| `sw-log <tekst>` | tekst bez danych osobowych | `WYNIK: ZAPISANO` | komentarz w dzienniku |
| `sw-handover-sh <nr>` | projekt `sw-stan-specyfikacja` ze zmergowaną specyfikacją | `WYNIK: PRZEKAZANY <runId>` | `sw-spec-gotowa`, zamknięcie issue |

**Warunki `sw-merge`:**
- Werdykty przychodzą wyłącznie jako argumenty z wyjść węzłów workflow: `{{nodes.<id>.verdict}}` oraz identyfikator zadania węzła. Skrypt nie czyta werdyktów z komentarzy.
- Model każdego oceniającego i autora skrypt odczytuje z rekordu zadania w Cezarze (`GET /api/v1/p/{id}/runs/{runId}`, pole tożsamości modelu), nie z konfiguracji. Recenzent i bezpieczeństwo muszą mieć inny model niż autor.
- `--sha` to SHA głowy PR, który ocenili recenzent i bezpieczeństwo. Skrypt sprawdza, że głowa PR nadal ma ten SHA, i przekazuje go do `PUT …/pulls/{n}/merge` (`sha`).
- **`tryb spec`:** `zatwierdzona` od przeglądu i `pass` od bezpieczeństwa.
- **`tryb kod`:** `approve` od recenzenta, `pass` od bezpieczeństwa oraz zielone check-runy o nazwach z `requiredChecks` dla tego SHA (`GET …/commits/{sha}/check-runs`). Brak któregoś z nazwanych check-runów oznacza niespełniony warunek.

#### Używane API Cezara (loopback, bez uwierzytelnienia)
- `GET /api/v1/health` → `{version, projects, …}` (`sw-doctor`; odpowiedź bez pola `version` oznacza brak Cezara). `GET /api/v1/workspace/config` → `resources.maxParallel` (ostrzeżenie w `sw-doctor`).
- `POST /api/v1/p/{projectId}/runs` `{task, workflow, autonomous, model?}` → `{id}` (`sw-start-ocena`, `sw-create-repo`, `sw-handover-sh`).
- `GET /api/v1/p/{projectId}/runs` i `…/runs/{id}` → `status` ∈ `queued|running|waiting|review|done|failed|cancelled`, model, `costUsd`, `autoResumeAt`/liczba wznowień:
  - wykrywanie zaginionych zadań;
  - wzajemne wykluczenie cykli;
  - suma kosztów (`sw-limits`);
  - wyczerpane wznowienia po limicie planu (`sw-limits`).
- `GET /api/v1/p/{projectId}/runs/{id}/history` → wiadomości zadania (`sw-ocena-wynik`).
- `POST /api/v1/projects/create` `{name, github: {owner}}` → projekt z prywatnym repozytorium i pustym commitem.
  - Odpowiedź 409 `folder_exists` oznacza zajętą nazwę lokalną. Odpowiedź 500 `github_create` oznacza błąd `gh` (np. zajętą nazwę na GitHubie). Cezar nie usuwa repozytorium utworzonego przed błędem.
  - Dlatego `sw-create-repo` przed utworzeniem sprawdza `GET /repos/{o}/{nazwa}`. Repozytorium z tematem `sw-projekt` i linkiem do tego samego issue jest **adoptowane** (`POST /api/v1/projects/checkout {url}`). Każde inne istniejące repozytorium oznacza kolejny przyrostek `-2`, `-3`.
- `PATCH /api/v1/projects/{id}` `{maxParallel}` — limit agentów projektu z `config/sw.json`.
- `node "$CEZ_BIN" automation list|create|update|enable` — tylko w `sw-start`, tylko automatyzacje o nazwach `sw: …`; `delete` i zmiany automatyzacji `sh: …` są poza `bashAllowlist`.

#### Używane API GitHuba (`gh api`, REST)
- Issues: `GET /repos/{o}/sw-control/issues?labels=sw-pomysl&state=all`, `POST …/issues`, `PATCH …/issues/{n}` (treść, etykiety jako pełna lista), `POST …/issues/{n}/comments`.
- PR: `GET …/pulls/{n}` (SHA głowy), `PATCH …/pulls/{n}` (opis), `PUT …/pulls/{n}/merge` (z `sha`), `GET …/commits/{sha}/check-runs`.
- Repozytoria: `GET /repos/{o}/{r}` (widoczność `sw-control`, adopcja), `GET /repos/{o}/{r}/contents/.ai/cezar/workflows/sh-delivery.yml` (rozpoznanie projektów sh-*), `PUT /repos/{o}/{r}/topics`.

#### Bramka powiadomień `cezar-push`
- `POST http://127.0.0.1:4330/m/push/gate`, nagłówek `X-Cezar-Push-Token: <~/.cezar-push/gate-token>`, bez nagłówków `Origin` i `X-Forwarded-For`.
- Ciało: `{gate: "spec"|"merge"|"blocked", repo, number, title (≤100), url: "https://github.com/…"}`. Odpowiedzi: 202, 400, 401.
- Etap 2 dodaje do sidecara i aplikacji rodzaje `deployed`, `paused`, `no-ideas` (zmiana w cezar-pwa, addytywna według jej reguł zgodności). Do tego czasu:
  - „brak pomysłów” idzie jako `blocked` z linkiem do issue dziennika;
  - „specyfikacja gotowa” idzie jako `spec` z linkiem do PR.

#### Karta decyzji (`CEZ:ASK`)
Ostatnia linia tury agenta oceny:

```
CEZ:ASK {"questions":[{"header":"Decyzja","question":"Co robimy z tym pomysłem?","options":[{"label":"Zatwierdź"},{"label":"Odrzuć"}]}]}
```

`AskCard` odsyła odpowiedź jako wiadomość użytkownika „Decyzja: Zatwierdź” albo „Decyzja: Odrzuć”. `sw-ocena-wynik` uznaje tylko wiadomość użytkownika, nie asystenta, dokładnie w tym formacie.

### Integracje
| Integracja | Dostawca | Tryb atrapy | Sekrety |
|------------|----------|-------------|---------|
| Orkiestracja, zadania, projekty | Cezar na VPS | `tests/tools/mock_api.py` (`/api/v1/health`, `/api/v1/workspace/config`, kolejne trasy `/api/v1/...` dodawane wraz z krokami) | brak (loopback) |
| GitHub | `gh` na koncie właściciela | `tests/fakes/gh` → atrapa `/github/...` | token `gh` na VPS (już skonfigurowany) |
| Powiadomienia | sidecar `cezar-push` | trasa `/m/push/gate` w atrapie (dodawana w etapie 1) | `~/.cezar-push/gate-token` na VPS (już istnieje) |
| Wyszukiwanie w sieci | narzędzie wyszukiwania agenta Claude Code w węźle `agent` | nie dotyczy (zachowanie agentów nie jest testowane w CI) | brak |
| Modele | Claude Max przez Cezara | nie dotyczy | brak; zmienne kluczy API, bram i chmur zabronione (`sw-doctor`) |

### Plan implementacji

Każdy krok kończy się działającym systemem i testami: unit i integracja dla skryptów, E2E w Compose z atrapą dla przepływu. W E2E węzły `agent` zastępuje skrypt testowy zwracający ustalony werdykt.

#### Etap 1: pomysł, ocena i specyfikacja (S1–S4)
Zależności: brak (tylko szkielet z tego PR).

1. **`sw-start` i repozytorium sterujące:**
   - utworzenie prywatnego `sw-control`, jeśli go nie ma,
   - etykiety `config/labels.json`,
   - automatyzacja `config/automations/sw-przeglad.json`,
   - kopiowanie `sw-sweep` do `sw-control`,
   - issue dziennika.

   Test: atrapa API Cezara (`automation list/create/update`) potwierdza, że automatyzacje `sh: …` nie są ruszane.
2. **`sw-gate`: aktywny projekt i decyzje.**
   - Decyzje `NIC` / `GENERATOR` / `OCENA` z wykrywaniem zaginionego zadania.
   - Wzajemne wykluczenie cykli i pomijanie projektów sh-*.
   - Licznik cykli bez pomysłu i liczba kolejnych `STAN: BLAD` z jednym powiadomieniem.

   Testy tablicowe na stanach z atrapy GitHuba i Cezara.
3. **`sw-generator` + gałąź `GENERATOR` w `sw-sweep`.**
   - Plik `.ai/sw-run/generator.json` (odrzucone pomysły i wskazówki), na tej podstawie odrzucanie duplikatów.
   - `loop` 5 prób z werdyktami `karta`/`nieudana`.
   - `sw-log` w dzienniku.
   - Po 24 cyklach bez pomysłu `sw-notify blocked` z linkiem do dziennika.

   E2E: 5 nieudanych prób daje 5 wpisów w dzienniku i brak powiadomienia. Duplikat odrzuconego pomysłu nie trafia do właściciela.
4. **`sw-ocena`:**
   - `sw-start-ocena`;
   - skill `sw-analityk` (tryb `ocena`) bez prawa do zmiany etykiet;
   - `sw-ocena-wynik` z odczytem historii zadania;
   - przejścia `sw-w-ocenie` → `sw-zatwierdzony` | `sw-odrzucony`.

   E2E: wiadomość użytkownika „Decyzja: Odrzuć” zamyka issue i w następnym cyklu bramka zwraca `GENERATOR`. Ta sama treść od asystenta nie zmienia stanu.
5. **`sw-create-repo`:** nazwa w kebab-case z przyrostkiem przy konflikcie, adopcja repozytorium z przerwanego przebiegu, zasiew README (link do issue) i workflowu `sw-spec`, `maxParallel`, temat `sw-projekt`.
6. **`sw-spec`:**
   - tryb `spec` analityka;
   - `sw-recenzent` (pętla 2 rund);
   - `sw-bezpieczenstwo` (także komentarz `sw:ustalenia`);
   - `sw-pr-body` (werdykt i założenia w opisie PR);
   - `sw-merge spec` (SHA, modele z rekordów zadań);
   - `sw-notify spec`.

   E2E: werdykt `uwagi` po 2 rundach ustawia `sw-stan-wstrzymany` z przyczyną w metadanych, zamyka issue, wysyła `sw-notify blocked`, a w następnym cyklu bramka zwraca `GENERATOR` (S4, ostatnie kryterium). Push po werdykcie (inny SHA) blokuje merge.
7. **`sw-handover-sh`:** zadanie `sh-start` w projekcie aplikacji, `sw-spec-gotowa`, zamknięcie issue, pomijanie projektu przez `sw-gate`.
8. **Sprawdzenie na VPS:** instalacja obok sh-skills i jeden pełny przebieg od pomysłu do przekazania.

   Kryterium: w PR kroku jest raport z linkami do issue pomysłu, repozytorium aplikacji i zmergowanego PR specyfikacji oraz potwierdzenie, że lista skilli i automatyzacji `sh-*` w Cezarze jest niezmieniona.

#### Etap 2: autonomiczne dostarczanie jednym modułem (S5 jeden moduł, S7 testy E2E, S8–S13)
Zależności: etap 1, kroki 1–6 (pętla pomysłów, repozytorium i specyfikacja). Krok 7 etapu 1 zostaje zastąpiony przejściem do `sw-build`.

1. **`sw-limits` i `sw-pause`** (S11, S12):
   - limit czasu (`approvedAt` + `projectTimeLimitHours`) i suma `costUsd`;
   - `sw-czeka-na-limit` przy limicie planu (wznowienie zostawione Cezarowi);
   - po wyczerpaniu 12 automatycznych wznowień Cezara nowe zadanie od przerwanego kroku, bez zużywania ponowień;
   - brak zmiennych rozliczanych poza planem;
   - ponowienia i 3 godziny bez postępu.
2. **Zmiana w cezar-pwa (osobne repozytorium):** rodzaje bramki `deployed`, `paused`, `no-ideas` w sidecarze i aplikacji. Zgłoszenie z zakresu przygotowuje ten krok; do jego wdrożenia działa zastępstwo z etapu 1.
3. **`sw-architekt` (jeden moduł) i `sw-merge kod`** (S5, S8): reviewer na innym modelu, nazwane check-runy, bezpieczeństwo, powiązanie z SHA.
4. **`sw-build` dla jednego modułu:** `sw-inzynier`, `sw-recenzent`, `sw-tester` (S7: E2E wszystkich scenariuszy aplikacji).
5. **`sw-bezpieczenstwo` dla aplikacji i `sw-deploy`** (S9, S10): cztery punkty, kontener na VPS, dostęp tylko po uwierzytelnieniu, test odmowy bez logowania.
6. **S13 i powiadomienia:** odsetek „bez interwencji” w treści powiadomień `deployed`/`paused`, jeden aktywny projekt aż do wdrożenia albo wstrzymania.

#### Etap 3: praca równoległa modułami (S5 wiele modułów, S6, S7 integracja)
Zależności: etap 2 (`sw-build`, `sw-merge kod`, `sw-limits`).

1. **`sw-architekt` dla wielu modułów:** kontrakty `docs/kontrakty/*.md`, decyzja „część aplikacji / osobna usługa”, testy kontraktów.
2. **`sw-kierownik`:** zadania modułów, których „wymaga” spełniają kontrakty; przydział przez `fork`/`dispatch` do `maxParallel` projektu; zmiana limitu działa od następnego przydziału.
3. **`sw-integrator`:** zadanie integracji po zmergowaniu wszystkich modułów, rundy poprawek przy konfliktach, potem S7 i dalej jak w etapie 2.
