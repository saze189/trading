# Konten und Supabase einrichten

Die Website kann ohne Konto lokal genutzt werden. Für Anmeldung, Rollenverwaltung und geräteübergreifende Depots brauchst du ein eigenes Supabase-Projekt. Die Anmeldung verwendet Benutzername und Passwort; eine Sicherungs-E-Mail kann nach dem Anmelden freiwillig hinterlegt werden. Es werden nur virtuelle Trades ausgeführt.

## Supabase verbinden

1. Erstelle ein Projekt unter [supabase.com](https://supabase.com/).
2. Öffne den SQL Editor und führe den vollständigen Inhalt von `supabase-setup.sql` aus. Das SQL ergänzt bei bestehenden Profilen automatisch Benutzernamen aus dem bisherigen E-Mail-Präfix. Wenn du Supabase bereits eingerichtet hast, führe die aktualisierte Datei erneut vollständig aus, damit Spielerübersicht, Überweisungen, IP-Anzeige, Developer-Konsole und Multiplayer-Welt eingerichtet werden. Die persönliche Depot-Reset-Funktion wird dabei entfernt.
3. Hole die zwei Verbindungswerte für deine Website:
   1. Öffne dein Projekt im Supabase-Dashboard. Prüfe oben links, dass der Projektname stimmt.
   2. Klicke links unten auf das **Zahnrad (Project Settings / Projekteinstellungen)**.
   3. Öffne dort **API Keys**. Je nach Dashboard-Version findest du die Projektadresse auch über **Connect** im oberen Bereich der Projektübersicht oder der Schaltfläche **Data API** in den Projekteinstellungen.
   4. Kopiere die **Project URL** (Projekt-URL). Sie sieht ungefähr so aus: `https://abcdefghijklmnopqrst.supabase.co`. Verwende die vollständige Adresse mit `https://`, aber ohne zusätzliche Pfade wie `/rest/v1`.
   5. Auf derselben Seite kopierst du den öffentlichen **anon**-Key (Legacy/JWT). Wenn das Dashboard stattdessen nach **Publishable key** und **Secret key** unterscheidet, verwende den **Publishable key** (`sb_publishable_...`), nicht den Secret key. Der öffentliche Schlüssel ist ausdrücklich für Browser-Apps vorgesehen.
4. Öffne im Projektordner die Datei `supabase-config.js` und ersetze die beiden leeren Zeichenketten. Beispiel (nur Beispieldaten, nicht übernehmen):

   ```js
   window.PAPERTRADE_SUPABASE_CONFIG = {
     url: "https://abcdefghijklmnopqrst.supabase.co",
     anonKey: "eyJhbGciOi...oder_sb_publishable_..."
   };
   ```

   Lass die Anführungszeichen stehen und lösche keine Kommas oder Klammern. Speichere die Datei und lade die Website neu. Danach sollte die Meldung „Supabase noch nicht eingerichtet“ verschwinden. Der öffentliche anon-/publishable-Key darf im Frontend stehen. Kopiere **niemals** den `service_role`- oder `sb_secret_...`-Key in diese Datei; diese Schlüssel gewähren weitreichenden Serverzugriff.
5. In **Authentication → Providers → Email** deaktiviere **Confirm email**, da neue Konten eine interne, nicht empfangbare Auth-E-Mail erhalten. Setze unter **Authentication → URL Configuration** die Site URL auf die App-Seite, z. B. `http://127.0.0.1:5500/`, und erlaube diese URL unter Redirect URLs. Ergänze später auch die URL deiner veröffentlichten Website. Deaktiviere **Secure email change**, damit das Hinzufügen einer Sicherungs-E-Mail nur eine Bestätigung an die neue Adresse erfordert.
6. Installiere die [Supabase CLI](https://supabase.com/docs/guides/cli) und öffne ein Terminal im Ordner `C:\Users\samue\Desktop\idk\papertrade`. Deploye von dort aus die Edge Function:

   ```powershell
   supabase login
   supabase link --project-ref DEIN-PROJEKT-REF
   supabase functions deploy username-sign-in
   ```

   Supabase stellt der Function URL, anon-Key und service-role-Key serverseitig bereit. Der Service-Role-Key wird von der Function benötigt und darf nicht in `supabase-config.js` oder im Browser landen. Wenn die Function schon deployed ist, deploye sie nach dieser Änderung erneut.
7. Öffne den Ordner `papertrade` über einen lokalen Webserver, zum Beispiel VS Code Live Server. Die Startseite ist jetzt `index.html` und öffnet sich unter `http://localhost:5500/`. Authentifizierung funktioniert nicht über `file://`.
8. Erstelle ein Konto mit einem Benutzernamen aus 3–24 Buchstaben (a–z), Zahlen oder Unterstrichen und einem Passwort mit mindestens 8 Zeichen. Füge danach im angemeldeten Konto optional eine Sicherungs-E-Mail hinzu und bestätige den Link. Über **Passwort vergessen?** kann anschließend ein Passwort-Reset angefordert werden.

Bei bestehenden Konten wird ein Benutzername aus dem bisherigen E-Mail-Präfix und einem eindeutigen Suffix erzeugt. Der genaue Benutzername steht in `profiles.username` im Supabase SQL Editor.

## Erstes Developer-Konto

Die erste Developer-Rolle wird einmalig im Supabase SQL Editor gesetzt. Ersetze den Beispiel-Benutzernamen durch deinen:

```sql
update public.profiles
set role = 'developer'
where lower(username) = lower('dein_benutzername')
returning user_id, username, role;
```

Das Ergebnis muss eine Zeile mit der Rolle `developer` enthalten. Melde dich auf der Website ab und wieder an, damit die neue Rolle geladen wird.

## Rollen und Datenschutz

- **Nutzer** können ihr eigenes virtuelles Depot handeln. Das Depot lässt sich über die Website nicht zurücksetzen.
- **Nur lesen** können das eigene Depot ansehen, aber nicht handeln oder überweisen.
- **Admins und Developer** sehen Benutzernamen, optionale Sicherungs-E-Mail-Adressen, Rollen und die zuletzt erfasste IP-Adresse. Admins können keine Developer-Rolle vergeben; Passwörter sind nicht sichtbar.
- **Developer** können zusätzlich virtuelle Depots und die letzten 100 Trades einsehen sowie fremde Depots schließen oder wieder öffnen. Beim Schließen werden Positionen entfernt; beim Wiederöffnen startet das Depot mit 10.000 €.
- **Angemeldete Nutzer** sehen die gemeinsame Spielerliste mit Benutzernamen, virtuellem Barguthaben und gehaltenen Aktien/ETFs. Sie können verfügbares virtuelles Bargeld an andere aktive Spieler überweisen; das eigene Guthaben wird dabei belastet. Die Liste aktualisiert sich automatisch ungefähr alle 30 Sekunden.
- **Developer** können außerdem in ihrem eigenen Browser einen einzelnen Simulationskurs für einen Tick ändern. Das wirkt nicht global auf andere Spieler; der nächste Kursabruf überschreibt den Wert, und Live-Kurse werden nicht verändert. Die Simulation kann über die Website nicht zurückgesetzt werden.
- **Developer** können die Ingame-Konsole im geöffneten Spieler/Konto-Panel über die Schaltfläche öffnen oder mit **F9 gedrückt halten + F10**. Die Konsole akzeptiert:
  - `/hilfe` zeigt die Befehlsübersicht.
  - `/aktion runter 10%` senkt alle angezeigten Live- und Simulationskurse global um 10 %. Weitere Absenkungen beziehen sich auf den dann aktuellen Kursfaktor.
  - `/aktion reset` setzt den globalen Kursfaktor auf 100 % zurück.
  - `/nachricht <Text>` veröffentlicht eine Nachricht für alle verbundenen Spieler; `/nachricht reset` entfernt sie.
  - `/geld set <Benutzer> <Betrag>` setzt das virtuelle Guthaben und `/geld add <Benutzer> <Betrag>` erhöht es, z. B. `/geld add sam 250.50`. Beträge werden mit Dezimalpunkt oder Dezimalkomma eingegeben.
  - `/rolle <Benutzer> <user|read_only|admin|developer>` ändert eine Kontorolle unter denselben Schutzregeln wie die Kontenverwaltung.
  - `/depot close <Benutzer>` schließt ein fremdes Depot und entfernt seine Positionen; `/depot open <Benutzer>` öffnet es wieder mit 10.000 €.
  - `/konto <Benutzer>` zeigt Rolle, virtuelles Guthaben, Positionen und – falls erfasst – die letzte IP-Adresse.
  - `/block spawn` erzeugt einen zufälligen Geldblock; `/block spawn 30000000` erzeugt gezielt einen seltenen 30-Mio.-Block. Es können höchstens fünf Blöcke gleichzeitig in der Welt sein.
- Globale Kursänderungen und Servernachrichten werden in Supabase gespeichert und von verbundenen Browsern regelmäßig abgerufen. Die Kursänderung bleibt bestehen, bis ein Developer `/aktion reset` ausführt. Die lokale Ein-Tick-Kurssteuerung im Developer-Panel bleibt davon getrennt.
- **Angemeldete Spieler** können die gemeinsame Geld-Welt mit WASD/Pfeiltasten oder den Touch-Steuerungen erkunden. Spielerpositionen, Blöcke und Chat werden ungefähr einmal pro Sekunde synchronisiert; nicht erreichbare Spieler verschwinden nach kurzer Zeit. Gäste ohne Konto können nicht mitspielen oder chatten.
- Blöcke erscheinen automatisch, bis zu fünf gleichzeitig, mit zufälligem Abstand von 1–30 Minuten. Die Abbauzeit eines Blocks ist ebenfalls zufällig 1–30 Minuten. Während des Abbaus bleibt der Spieler stehen. Jeder weitere aktive Mitspieler beschleunigt den Fortschritt; nach Abschluss wird der Blockbetrag gleichmäßig unter allen Spielern aufgeteilt, die mitgearbeitet haben. Die virtuellen Belohnungsstufen sind 5.000 €, 25.000 €, 100.000 €, 1 Mio. €, 5 Mio. € und extrem selten 30 Mio. €. Diese Belohnungen werden dem virtuellen Barguthaben gutgeschrieben.
- Der Welt-Chat ist für angemeldete Spieler global sichtbar, auf 240 Zeichen und höchstens eine Nachricht pro Sekunde begrenzt. Nachrichten bleiben bis zu einem Tag gespeichert. Der Sprachumschalter im Seitenmenü bietet Englisch (Standard), Deutsch, Französisch, Spanisch und Türkisch; die Auswahl bleibt lokal im Browser gespeichert.

Rollen-, Handels-, Überweisungs- und Verwaltungsaktionen werden serverseitig durch geschützte Datenbankfunktionen geprüft. Die Tabellen verwenden Row Level Security; diese Aktionen laufen ausschließlich über die RPC-Funktionen aus dem SQL-Setup. Spielerübersicht und virtuelle Depotdaten sind für angemeldete Konten sichtbar; Sicherungs-E-Mail-Adressen und Passwörter werden dabei nicht angezeigt. Die Anmeldung per Benutzername wird serverseitig durch die `username-sign-in` Edge Function auf die interne Supabase-Auth-Adresse aufgelöst. Neue Konten müssen ebenfalls über diese Funktion erstellt werden.

Beim Erstellen eines Kontos und bei erfolgreicher Anmeldung speichert die Edge Function die vom Hosting weitergereichte IP-Adresse als zuletzt bekannte IP. Admins und Developer sehen diese Adresse und den Zeitpunkt der Erfassung in der Kontenliste. Es wird nur die jeweils letzte Adresse gespeichert; sie dient der manuellen Erkennung möglicher Mehrfachkonten. Es gibt keine automatische Sperre. Eine IP-Adresse identifiziert nicht sicher eine einzelne Person: mehrere Menschen können dieselbe Internetverbindung nutzen, und VPNs oder wechselnde Anschlüsse können die Adresse ändern. Teile diese Daten nicht öffentlich.

Informiere Nutzer in deiner Datenschutzerklärung darüber, dass IP-Adressen zu diesem Zweck verarbeitet werden, und prüfe die für dich geltenden Datenschutzpflichten.

## Marktdaten

Die App versucht Yahoo Finance direkt im Browser ungefähr alle 20 Sekunden abzurufen. Daten können verzögert sein oder der Anbieter kann Browseranfragen ablehnen. Live-Kurse ändern sich, sobald der Datenanbieter neue Werte liefert; simulierte Kurse bewegen sich im Vordergrund ungefähr jede Sekunde. Sobald ein Kursabruf fehlschlägt, wechselt die Anzeige sofort zu simulierten Kursen und Candlesticks; Live-Abfragen laufen im Hintergrund weiter. Simulierte Werte sind in der Statusanzeige und im Diagramm als **Simulation** gekennzeichnet und sind keine Live-Marktdaten.
