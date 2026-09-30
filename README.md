# Jakulo: Discovery

Ein kleines 3D-Erkundungsspiel in **Godot 4.7**. Der Spieler läuft in der
Third-Person-Ansicht über eine prozedural erzeugte Insel mit Klimazonen,
Flüssen, Gebirgen und vierzehn Landschaftstypen. Kein Kampf, keine Aufgaben – nur Erkunden.

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
| M | Karte ein-/ausblenden |
| Esc | Maus freigeben |

## Die Welt

1536 × 1536 Meter, als Insel angelegt: das Land fällt zum Rand hin ins Meer ab,
unsichtbare Wände verhindern das Hinauslaufen. Das Relief entsteht aus
verwirbeltem Rauschen (Domain Warping) mit Bergkämmen, sanften Hügeln und
Flusstälern, die sich im Flachland bis unter den Meeresspiegel eingraben und
dort Wasser führen.

Die Landschaft ergibt sich aus einem einfachen Klimamodell: **Temperatur**
(Norden kalt, Süden warm, mit der Höhe kälter) und **Feuchtigkeit** wählen das
Biom, Hangneigung und Wassernähe legen Fels, Strand und Sumpf darüber. Die
Bodenfarben gehen weich ineinander über.

| | trocken | | | nass |
| --- | --- | --- | --- | --- |
| **heiß** | Wüste | Savanne | Grasland | Regenwald |
| **gemäßigt** | Steppe | Grasland | Blumenwiese | Laubwald |
| **kühl** | Steppe | | | Nadelwald |
| **kalt** | Tundra | | | |

Dazu: **Meer**, **Strand** (in kalten Gegenden Kies), **Sumpf** (feucht und
knapp über dem Wasser), **Gebirge** (steile Hänge) und **Schneegipfel**.

Jedes Biom hat eigenen Bewuchs – Laub- und Nadelbäume, Urwaldriesen, Palmen,
Akazien, abgestorbene Bäume, Büsche, Farne, Kakteen, Baumstämme, Felsen und
Findlinge – sowie eigenes Gras: kurz und grün auf der Wiese mit bunten Blumen,
hoch und gelb in der Savanne, Schilf im Sumpf, niedrig und bräunlich in der
Tundra. Das Gras wiegt sich im Wind.

Alles wird beim Start aus einem Startwert (`noise_seed`) berechnet – dieselbe
Zahl ergibt immer dieselbe Insel. Es wird nichts gespeichert.

## Aufbau

```
scenes/main.tscn        Hauptszene: Umgebung, Sonne, Terrain, Bewuchs, Gras, Wasser, Spieler, HUD
scenes/player.tscn      Spielfigur mit Kameraarm
scripts/terrain.gd      Relief, Klima, Biome; erzeugt Gelände und beantwortet height_at()/biome_at()
scripts/scatter.gd      verteilt Bäume, Büsche, Kakteen und Felsen je nach Landschaft
scripts/grass.gd        Gras, Schilf und Blumen in Zellen rund um die Kamera
scripts/world.gd        Ablauf beim Start, Wasserfläche, Weltgrenzen
scripts/player.gd       Bewegung und Kamera
scripts/hud.gd          Anzeige, Ladehinweis und Karte
shaders/terrain.gdshader  Bodenstruktur über den Biomfarben
shaders/water.gdshader    Wellen, Tiefenfarbe, Uferschaum
shaders/grass.gdshader    Wind und weiches Ausblenden des Grases
tools/                  Entwickler-Werkzeuge, nicht Teil des Spiels
```

`terrain.gd` rechnet die Höhe beim Start einmal auf einem 2-m-Gitter aus
(auf mehreren Kernen) und hält es im Speicher. Danach beantwortet es jede
Frage nach Höhe, Landschaft oder Bodenfarbe direkt aus diesem Gitter – exakt
passend zum sichtbaren Mesh. Die Kollision des Geländes besteht aus
Höhenfeldern (`HeightMapShape3D`), günstiger als Dreiecksnetze.

Der Bewuchs liegt in `MultiMeshInstance3D`-Knoten, aufgeteilt in Regionen von
128 m: ein Zeichenaufruf pro Objekttyp und Region, Regionen außerhalb des
Blickfelds oder jenseits ihrer Sichtweite werden nicht gezeichnet. Die
Kollisionskörper der Bäume und Felsen gehen direkt an den `PhysicsServer3D`.

Gras gibt es nur in der Nähe der Kamera. Es wird in 16-m-Zellen erzeugt, beim
Laufen nachgeladen (höchstens zwei Zellen pro Bild) und hinten wieder
entfernt; der Shader lässt es zum Rand hin schrumpfen, sodass keine Kante
sichtbar ist.

## Einstellen

Die interessanten Regler sind im Inspektor am Knoten `Terrain` sichtbar:

* `noise_seed` – andere Zahl, andere Insel
* `world_size` – Kantenlänge der Welt
* `max_height` – Höhe der höchsten Gipfel
* `sea_level` – Wasserstand (verschiebt Strände, Flüsse und Seen)
* `detail_height` – Stärke der feinen Bodenunebenheiten
* `warp_strength` – wie stark Küsten und Kämme verwirbelt sind
* `river_width` – Breite der Flusstäler
* `north_south_gradient`, `lapse_rate`, `snow_temperature` – Klima: wie viel
  kälter der Norden bzw. die Höhe ist und wo Schnee liegt

Am Knoten `Scatter`: `grid_step` (kleiner = dichterer Bewuchs) und
`scatter_seed`. Am Knoten `Grass`: `density`, `radius` (wie weit Gras reicht)
und `cells_per_frame`.

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
* Tag-/Nachtwechsel über eine animierte Sonne
* Fundstücke oder Aussichtspunkte, die das Erkunden belohnen
* Detailstufen (LOD) für weit entfernte Gelände-Chunks, falls die Welt noch
  deutlich wachsen soll
* Wind auch in den Baumkronen
