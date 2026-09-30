# Jakulo: Discovery

Ein kleines 3D-Erkundungsspiel in **Godot 4.7**. Der Spieler läuft in der
Third-Person-Ansicht über eine prozedural erzeugte Insel, die aus sieben
Landschaftstypen besteht. Kein Kampf, keine Aufgaben – nur Erkunden.

## Starten

Projekt in Godot öffnen und F5 drücken, oder von der Kommandozeile:

```bash
flatpak run --filesystem=home org.godotengine.Godot --path "$PWD"
```

## Steuerung

| Eingabe | Wirkung |
| --- | --- |
| W A S D | Laufen (relativ zur Kamera) |
| Shift | Rennen |
| Leertaste | Springen |
| Maus | Umsehen |
| Mausrad | Kamera heran-/wegzoomen |
| Esc | Maus freigeben |

## Die Welt

512 × 512 Meter, als Insel angelegt: das Land fällt zum Rand hin ins Meer ab,
unsichtbare Wände verhindern das Hinauslaufen. Die Landschaft ergibt sich aus
Höhe, Hangneigung und einem Feuchtigkeits-Rauschen:

| Landschaft | Bedingung |
| --- | --- |
| Meer | unter Meereshöhe |
| Strand | schmales Band über der Wasserlinie |
| Wüste | trocken und tief gelegen |
| Grasland | mittlere Feuchtigkeit |
| Wald | feucht |
| Gebirge | hoch **oder** steil |
| Schneegipfel | sehr hoch und nicht zu steil |

Alles wird beim Start aus einem Startwert (`noise_seed`) berechnet – dieselbe
Zahl ergibt immer dieselbe Insel. Es wird nichts gespeichert.

## Aufbau

```
scenes/main.tscn     Hauptszene: Umgebung, Sonne, Terrain, Bewuchs, Wasser, Spieler, HUD
scenes/player.tscn   Spielfigur mit Kameraarm
scripts/terrain.gd   erzeugt das Gelände und beantwortet height_at()/biome_at()
scripts/scatter.gd   verteilt Bäume, Büsche, Kakteen und Felsen je nach Landschaft
scripts/world.gd     Startplatz, Wasserfläche, Weltgrenzen
scripts/player.gd    Bewegung und Kamera
scripts/hud.gd       Anzeige von Landschaft und Position
tools/               Entwickler-Werkzeuge, nicht Teil des Spiels
```

`terrain.gd` speichert keine Höhendaten, sondern rechnet sie bei Bedarf aus dem
Rauschen. Dadurch kann jedes andere Skript jederzeit fragen, wie die Welt an
einer beliebigen Stelle aussieht, ohne das Mesh zu durchsuchen.

Der Bewuchs liegt in `MultiMeshInstance3D`-Knoten: ein Zeichenaufruf pro
Objekttyp statt einer pro Baum. Damit kosten ~3400 Objekte kaum Leistung.

## Einstellen

Die interessanten Regler sind im Inspektor am Knoten `Terrain` sichtbar:

* `noise_seed` – andere Zahl, andere Insel
* `world_size` – Kantenlänge der Welt
* `max_height` – Höhe der höchsten Gipfel
* `sea_level` – Wasserstand (verschiebt Strände und Seen)
* `rock_height` / `snow_height` – ab welcher Höhe Fels bzw. Schnee beginnt
* `detail_height` – Stärke der feinen Bodenunebenheiten

Am Knoten `Scatter`: `grid_step` (kleiner = dichterer Bewuchs) und
`scatter_seed`.

## Werkzeuge

Übersichtskarte der Insel rendern (`tools/biome_map.png`) und die
Biom-Verteilung in Prozent ausgeben:

```bash
flatpak run --filesystem=home org.godotengine.Godot --headless --path "$PWD" --script res://tools/biome_map.gd
```

Screenshots von festen Aussichtspunkten nach `tools/shots/` sowie eine
Bildratenmessung:

```bash
flatpak run --filesystem=home org.godotengine.Godot --path "$PWD" res://tools/shots.tscn
```

## Nächste Schritte

* Schwimmen statt Laufen unter Wasser
* Gras- und Blumenbüschel als weitere MultiMesh-Schicht
* Tag-/Nachtwechsel über eine animierte Sonne
* Fundstücke oder Aussichtspunkte, die das Erkunden belohnen
* Nachladen der Chunks rund um den Spieler, falls die Welt deutlich wachsen soll
