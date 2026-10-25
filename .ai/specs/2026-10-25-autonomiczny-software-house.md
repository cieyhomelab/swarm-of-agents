# Autonomiczny software house (swarm-of-agents)

## TLDR
System, który sam wymyśla pozytywne pomysły na aplikacje i sam je buduje. Jedyną interakcją człowieka jest ocena pomysłu: właściciel w aplikacji na telefon rozmawia z modelem, doprecyzowuje pomysł i go zatwierdza albo odrzuca. Po zatwierdzeniu rój agentów bez udziału człowieka tworzy repozytorium, specyfikację, architekturę i kod, równolegle buduje moduły, składa je w całość i wdraża aplikację na VPS pod prywatnym adresem. To następca sh-skills i sh-control.

## Problem i cel
Obecny software house (sh-skills, sh-control) wymaga człowieka na dwóch bramkach: zatwierdzenie specyfikacji i merge każdego PR, a pomysły i repozytoria dostarcza właściciel. To ogranicza tempo do czasu, jaki właściciel może poświęcić.

Cel: jedna interakcja właściciela na aplikację (ocena pomysłu), reszta w pełni autonomicznie, z zabezpieczeniami, które zastępują przegląd człowieka.

**Sukces:** rośnie odsetek zatwierdzonych pomysłów doprowadzonych do działającej aplikacji bez udziału człowieka (zatwierdzone → wdrożone bez interwencji właściciela).

## Użytkownicy i role

### Właściciel (jedyny człowiek)
- Dostaje powiadomienie o nowym pomyśle, ocenia go w rozmowie z modelem, zatwierdza albo odrzuca.
- Dostaje powiadomienia o gotowej aplikacji i o wstrzymanym projekcie.
- Korzysta z gotowych aplikacji pod prywatnym adresem.
- Nie zatwierdza specyfikacji, nie merguje PR, nie tworzy repozytoriów.

### Agenci (rój)
| Rola | Zadanie |
|------|---------|
| Generator pomysłów | Wymyśla pomysł, sprawdza go w sieci, odrzuca kategorie wykluczone, przygotowuje ocenę i rekomendację. |
| Analityk | Prowadzi rozmowę z właścicielem przy ocenie pomysłu i pisze specyfikację. |
| Architekt | Wybiera stos, dzieli aplikację na moduły z kontraktami, przygotowuje szkielet. |
| Kierownik | Zakłada zadania, przydziela moduły, pilnuje limitów i stanu projektu. |
| Inżynier (kilku równolegle) | Implementuje moduły według kontraktów. |
| Integrator | Składa moduły w całość i doprowadza do działania pełnej aplikacji. |
| Tester | Weryfikuje działanie według kryteriów akceptacji. |
| Reviewer | Recenzuje zmiany; działa na innym modelu niż inżynier. |
| Przegląd bezpieczeństwa | Osobny agent na innym modelu niż autor zmian. Sprawdza zmiany przed merge i aplikację przed wydaniem. |

Role od architekta do reviewera to obecne role sh-* rozwijane w tym repozytorium, bez bramek ludzkich.

## Scenariusze

### S1: Generowanie pomysłu
1. System nie ma aktywnego projektu (poprzednia aplikacja wdrożona, projekt wstrzymany albo pomysł odrzucony).
2. Generator wymyśla pomysł, który poprawia jakość życia, sytuację finansową lub zdrowie ludzi.
3. Sprawdza w sieci, czy problem jest realny i czy nie istnieje już dobre darmowe rozwiązanie.
4. Odrzuca pomysły z kategorii wykluczonych (patrz „Wymagania niefunkcjonalne → Bezpieczeństwo”) i generuje kolejny.
5. Przygotowuje kartę pomysłu: problem, dla kogo, co robi aplikacja, wynik sprawdzenia w sieci ze źródłami, ocenę według kryteriów i rekomendację.
6. Wysyła właścicielowi powiadomienie push.

**Kryteria akceptacji**
- Zakładając brak aktywnego projektu, gdy system jest uruchomiony, wtedy w ciągu jednego cyklu przeglądu powstaje karta pomysłu, a właściciel dostaje powiadomienie push.
- Zakładając aktywny projekt (w budowie lub czekający na ocenę), wtedy nowy pomysł nie powstaje.
- Zakładając pomysł z kategorii wykluczonej, wtedy nie trafia do właściciela, a w dzienniku systemu jest wpis z powodem odrzucenia.
- Zakładając kartę pomysłu, wtedy zawiera ona wszystkie pola z kroku 5, w tym co najmniej jedno źródło z sieci dla sprawdzenia realności problemu.

### S2: Ocena i zatwierdzenie pomysłu
1. Właściciel otwiera powiadomienie w aplikacji na telefon.
2. Widzi kartę pomysłu i rozmawia z modelem (analityk): zadaje pytania, doprecyzowuje zakres, odpowiada na pytania modelu.
3. Model podsumowuje ustalenia.
4. Właściciel zatwierdza pomysł.
5. System przechodzi do S4.

**Kryteria akceptacji**
- Zakładając kartę pomysłu, gdy właściciel otwiera powiadomienie, wtedy widzi kartę i pole rozmowy z modelem.
- Zakładając rozmowę, gdy właściciel zatwierdza pomysł, wtedy pomysł ma stan „zatwierdzony”, a ustalenia z rozmowy są zapisane jako wejście dla specyfikacji.
- Zakładając zatwierdzenie, wtedy system nie prosi właściciela o żadną dalszą decyzję aż do powiadomienia o gotowej lub wstrzymanej aplikacji.

### S3: Odrzucenie pomysłu
1. Właściciel w rozmowie odrzuca pomysł i opcjonalnie podaje powód.
2. Generator od razu tworzy kolejny pomysł (S1), biorąc pod uwagę powód odrzucenia.

**Kryteria akceptacji**
- Zakładając odrzucenie z powodem, wtedy kolejna karta pomysłu powstaje bez dodatkowej akcji właściciela, a powód jest przekazany generatorowi.
- Zakładając odrzucenie, wtedy odrzucony pomysł nie jest proponowany ponownie.

### S4: Repozytorium i specyfikacja bez bramki
1. System tworzy prywatne repozytorium na koncie `cieyhomelab`.
2. Analityk pisze specyfikację na podstawie ustaleń z S2.
3. Niezależny przegląd (agent ze świeżym kontekstem) sprawdza spójność i testowalność; analityk poprawia uwagi.
4. Specyfikacja jest mergowana automatycznie.

**Kryteria akceptacji**
- Zakładając zatwierdzony pomysł, wtedy powstaje prywatne repozytorium z commitem na gałęzi bazowej.
- Zakładając specyfikację, wtedy każdy scenariusz ma kryteria akceptacji, a PR zawiera wynik niezależnego przeglądu.
- Zakładając pozytywny przegląd specyfikacji, wtedy PR jest mergowany bez udziału właściciela.

### S5: Architektura i podział na moduły
1. Architekt wybiera stos i dzieli aplikację na moduły.
2. Dla każdego modułu określa kontrakt (co moduł udostępnia i czego potrzebuje od innych).
3. Decyduje, czy moduły są częściami jednej aplikacji, czy osobnymi usługami.
4. PR architektury przechodzi automatyczny merge (S8).

**Kryteria akceptacji**
- Zakładając zmergowaną specyfikację, wtedy powstaje PR architektury z listą modułów i kontraktem każdego modułu.
- Zakładając listę modułów, wtedy każdy scenariusz ze specyfikacji jest przypisany do co najmniej jednego modułu.

### S6: Równoległa implementacja modułów
1. Kierownik zakłada zadania dla modułów.
2. Do limitu równoległych agentów (konfigurowalny, start: 3) inżynierowie implementują moduły jednocześnie.
3. Każdy moduł jest testowany względem swojego kontraktu.

**Kryteria akceptacji**
- Zakładając limit 3, wtedy naraz pracuje najwyżej 3 agentów implementujących.
- Zakładając zmianę limitu w konfiguracji, wtedy nowy limit obowiązuje od następnego przydziału zadań.
- Zakładając moduł, wtedy jego PR zawiera testy kontraktu.

### S7: Integracja
1. Gdy wszystkie moduły są zmergowane, integrator składa je w całość.
2. Tester sprawdza pełną aplikację według kryteriów akceptacji specyfikacji.

**Kryteria akceptacji**
- Zakładając zmergowane wszystkie moduły, wtedy powstaje zadanie integracji.
- Zakładając integrację, wtedy testy E2E wszystkich scenariuszy specyfikacji przechodzą przed wydaniem.

### S8: Automatyczny merge PR
PR jest mergowany bez człowieka, gdy jednocześnie:
- reviewer na innym modelu niż autor zatwierdził zmianę,
- CI jest zielone,
- przegląd bezpieczeństwa (osobny agent na innym modelu niż autor) przeszedł.

**Kryteria akceptacji**
- Zakładając spełnione trzy warunki, wtedy PR jest mergowany automatycznie.
- Zakładając niespełniony którykolwiek warunek, wtedy PR nie jest mergowany.
- Zakładając recenzję lub przegląd bezpieczeństwa wykonane przez ten sam model co autor, wtedy nie liczą się jako zatwierdzenie.

### S9: Przegląd bezpieczeństwa przed wydaniem
1. Przed wdrożeniem pełna aplikacja przechodzi przegląd bezpieczeństwa.
2. Przegląd sprawdza: brak funkcji z kategorii wykluczonych, brak sekretów w repozytorium, dostęp tylko po uwierzytelnieniu, przechowywanie wyłącznie danych właściciela.
3. Znalezione problemy wracają do roju do poprawy.

**Kryteria akceptacji**
- Zakładając aplikację z funkcją z kategorii wykluczonej, wtedy wdrożenie nie następuje.
- Zakładając pozytywny przegląd, wtedy w repozytorium jest raport z przeglądu z listą sprawdzonych punktów.

### S10: Wdrożenie i powiadomienie o gotowości
1. Aplikacja jest wdrażana na VPS pod prywatnym adresem.
2. Właściciel dostaje powiadomienie push z adresem i krótkim opisem.
3. Projekt ma stan „wdrożony”; system wraca do S1.

**Kryteria akceptacji**
- Zakładając pozytywny przegląd bezpieczeństwa, wtedy aplikacja jest dostępna pod prywatnym adresem i wymaga uwierzytelnienia.
- Zakładając wdrożenie, wtedy właściciel dostaje powiadomienie z adresem.
- Zakładając wdrożenie, wtedy powstaje nowy pomysł (S1).

### S11: Utknięcie projektu
1. Zadanie nie przechodzi (testy, CI, recenzja, przegląd bezpieczeństwa albo brak postępu).
2. System ponawia automatycznie.
3. Po wyczerpaniu ponowień projekt jest wstrzymywany, a właściciel dostaje powiadomienie z przyczyną.
4. System generuje nowy pomysł (S1). Wstrzymany projekt zostaje w repozytorium bez dalszej pracy.

**Kryteria akceptacji**
- Zakładając nieudane zadanie, wtedy system ponawia je bez udziału właściciela.
- Zakładając wyczerpane ponowienia, wtedy projekt ma stan „wstrzymany”, a powiadomienie zawiera przyczynę i ostatni etap.
- Zakładając wstrzymanie, wtedy system nie zadaje właścicielowi pytań i tworzy nowy pomysł (S1) bez akcji właściciela.
- Zakładając wstrzymany projekt, wtedy agenci nie podejmują w nim dalszej pracy.

### S12: Limity czasu i zużycia
1. Każdy projekt ma limit czasu (domyślnie 7 dni kalendarzowych od zatwierdzenia pomysłu) i limit zużycia; obie wartości w konfiguracji.
2. Rój nie włącza płatnego dodatkowego zużycia.
3. Po przekroczeniu limitu projektu projekt jest wstrzymywany z powiadomieniem, a system generuje nowy pomysł (jak w S11).

**Kryteria akceptacji**
- Zakładając projekt zatwierdzony 7 dni temu i niewdrożony, wtedy projekt ma stan „wstrzymany”, właściciel dostaje powiadomienie z przyczyną „limit czasu”, a powstaje nowy pomysł.
- Zakładając przekroczony limit zużycia projektu, wtedy projekt ma stan „wstrzymany”, a właściciel dostaje powiadomienie z przyczyną „limit zużycia”.
- Zakładając wyczerpany limit okna zużycia planu, wtedy praca jest wstrzymywana i wznawiana automatycznie po odnowieniu limitu, bez ponowień, które zużywają limit.
- Zakładając dowolny stan, wtedy system nie włącza dodatkowego płatnego zużycia.

## Dane
- **Pomysł:** tytuł, problem, dla kogo, opis działania, wynik sprawdzenia w sieci ze źródłami, ocena, rekomendacja, stan (nowy, w ocenie, zatwierdzony, odrzucony), powód odrzucenia.
- **Rozmowa oceny:** wiadomości właściciela i modelu, podsumowanie ustaleń. [DANE OSOBOWE] (treść wypowiedzi właściciela)
- **Projekt:** pomysł, repozytorium, stan (specyfikacja, architektura, implementacja, integracja, przegląd, wdrożony, wstrzymany), etap, przyczyna wstrzymania, zużycie względem limitu, prywatny adres.
- **Moduł:** projekt, nazwa, kontrakt, stan, przypisany agent.
- **Dziennik systemu:** odrzucone pomysły z powodem, ponowienia, wstrzymania, merge.
- **Konfiguracja:** limit równoległych agentów, limity projektu, liczba ponowień, kategorie wykluczone.
- **Dane w budowanych aplikacjach:** wyłącznie dane właściciela; mogą obejmować dane zdrowotne lub finansowe właściciela [DANE OSOBOWE, w tym szczególnej kategorii].

## Integracje zewnętrzne
Wymagania właściciela (istniejąca infrastruktura):
- **Claude Max** jako jedyne źródło modeli (bez Codex i innych dostawców).
- **Cezar (Open Mercato)** na VPS jako orkiestrator agentów.
- **cezar-pwa** jako aplikacja na telefon: powiadomienia push i rozmowa oceny pomysłu.
- **GitHub, konto `cieyhomelab`:** repozytoria, PR, CI, zadania; agenci działają na koncie właściciela.
- **Wyszukiwanie w sieci** dla generatora pomysłów.
- **VPS właściciela z Dockerem** jako miejsce wdrożenia aplikacji.

## Wymagania niefunkcjonalne

### Bezpieczeństwo
- **Kategorie wykluczone (pomysł i funkcje aplikacji):** wyliczanie lub sugerowanie dawek leków, diagnoza medyczna, porady inwestycyjne, obsługa prawdziwych pieniędzy (płatności, przelewy, handel). Także pomysły nielegalne, wprowadzające w błąd lub skierowane przeciw konkretnym osobom.
- Każda aplikacja dostępna wyłącznie po uwierzytelnieniu właściciela, pod prywatnym adresem; brak publicznego wydania.
- Brak sekretów w repozytoriach; sekrety tylko na VPS.
- Przegląd bezpieczeństwa przed każdym merge (S8) i przed wydaniem (S9).

### RODO
- Aplikacje przechowują wyłącznie dane właściciela i nie zbierają danych od innych osób.
- Dane zdrowotne i finansowe właściciela są danymi wrażliwymi: dostęp tylko po uwierzytelnieniu, bez wysyłania do usług zewnętrznych poza niezbędnymi do działania.

### Skala i zasoby
- Jeden projekt naraz.
- Równoległość ograniczona konfigurowalnym limitem agentów (start: 3), ze względu na wspólne limity planu Claude Max (okno 5-godzinne, limit tygodniowy, pula dzielona z czatem właściciela) i zasoby VPS.

### Języki
- Komunikacja z właścicielem, karty pomysłów i specyfikacje po polsku.

## Przypadki brzegowe i błędy
- **Brak pomysłu spełniającego kryteria:** po 5 nieudanych próbach w jednym cyklu generator przerywa cykl i próbuje w następnym, bez powiadomienia.
- **Właściciel nie odpowiada na pomysł:** pomysł czeka w stanie „w ocenie”; nowy pomysł nie powstaje.
- **Brak uprawnień do utworzenia repozytorium lub push:** projekt wstrzymany z powiadomieniem i przyczyną (S11).
- **Brak dostępu do sieci przy sprawdzaniu pomysłu:** pomysł nie trafia do właściciela bez sprawdzenia; ponowienie w następnym cyklu.
- **Konflikt modułów przy integracji:** wraca jako zadanie do roju; po wyczerpaniu ponowień S11.
- **Niedostępny VPS lub wdrożenie nieudane:** ponowienia, potem S11.
- **Wyczerpany limit planu:** S12.

## Poza zakresem
- Publiczne wydanie aplikacji, użytkownicy inni niż właściciel, zbieranie danych od innych osób.
- Komercjalizacja i płatności.
- Pomysły i funkcje z kategorii wykluczonych.
- Dowolny dostawca modeli inny niż Claude Max; płatne dodatkowe zużycie.
- Kilka projektów jednocześnie.
- Obowiązkowa architektura mikroserwisów (forma modułów to decyzja architekta dla każdej aplikacji).
- Utrzymanie i rozwój aplikacji po wdrożeniu.

## Etapy dostarczenia
1. **Pomysł i ocena:** generator pomysłów, karta pomysłu, powiadomienie, rozmowa oceny w cezar-pwa, zatwierdzenie i odrzucenie, specyfikacja z niezależnym przeglądem i automatycznym merge. Dalsza budowa na dotychczasowym łańcuchu ról. Scenariusze: S1, S2, S3, S4.
2. **Autonomiczne dostarczanie:** samodzielne tworzenie repozytorium, automatyczny merge, przegląd bezpieczeństwa, wdrożenie na VPS, powiadomienia o gotowości i wstrzymaniu, limity. Scenariusze: S8, S9, S10, S11, S12.
3. **Praca równoległa modułami:** podział na moduły z kontraktami, równoległa implementacja do limitu agentów, integracja. Scenariusze: S5, S6, S7.

## Założenia
- **Migracja:** `swarm-of-agents` przejmuje skille i workflowy z sh-skills i konfigurację z sh-control; stare repozytoria są archiwizowane po uruchomieniu etapu 1. Uzasadnienie: decyzja właściciela (R4.5), jedno źródło prawdy.
- **Ponowienia:** domyślnie 2 automatyczne ponowienia na zadanie, wartość w konfiguracji. Uzasadnienie: najprostsze i łatwe do zmiany.
- **Próg sukcesu:** nie ustalono wartości docelowej; system raportuje odsetek. Uzasadnienie: najpierw trzeba poznać wartość bazową.
- **Repozytoria prywatne:** każda nowa aplikacja w prywatnym repozytorium. Uzasadnienie: aplikacje są prywatnymi prototypami.

- **Próby generowania:** najwyżej 5 prób znalezienia pomysłu spełniającego kryteria w jednym cyklu, wartość w konfiguracji. Uzasadnienie: ogranicza zużycie limitu na nieudane próby.

## Sekcje techniczne
> Uzupełnia architekt po zatwierdzeniu specyfikacji: architektura, model danych, kontrakty API, plan implementacji.
