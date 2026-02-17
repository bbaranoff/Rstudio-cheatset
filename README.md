# Markdown → Office avec normalisation LaTeX (Pandoc-safe)

Pipeline utilitaire pour convertir des documents Markdown contenant des équations LaTeX imparfaites
(ChatGPT-style, fragments cassés, `$$` inline, traits `-----`, indices orphelins, etc.)
vers ODT / DOCX **sans faire planter Pandoc ni LibreOffice**.

Le repo fournit :

- `fix_latex_smart.py` — préprocesseur LaTeX → Pandoc
- `convert_to_office.sh` — orchestrateur Markdown → Office
- `install_rstudio.sh` — installateur des dépendances système

Objectif : transformer du Markdown “sale” en MathML propre exploitable par LibreOffice.

---

# ⚡ Quick install

Sur Ubuntu / Mint / Debian :

```bash
chmod +x install_rstudio.sh
./install_rstudio.sh
````

Ce script installe :

* python3
* pandoc
* libreoffice
* dépendances CRAN (si présentes dans ton environnement)

---

# ⚡ Quick usage

```bash
chmod +x convert_to_office.sh
./convert_to_office.sh rapport.md
```
or
```bash
./convert_to_office.sh -f odt rapport.md
```
Plus d'options avec
```bash
./convert_to_office.sh --help
```

Résultat :


```
rapport_fixed.md
rapport_fixed.docx
```


Tu ne dois **jamais** appeler Pandoc directement.
Passe toujours par `convert_to_office.sh`.

---

# Principe

Chaîne complète :

```
rapport.md
  ↓
fix_latex_smart.py   (sanitisation LaTeX)
  ↓
rapport_fixed.md
  ↓
pandoc / libreoffice
  ↓
ODT / DOCX
```

Le préprocesseur est **obligatoire**.

Sans lui :

* `$$` collés cassent Pandoc
* `_{} ^{}` provoquent des erreurs de parsing
* `-----` et `====` deviennent du faux MathML
* parenthèses inline deviennent du texte brut
* LibreOffice affiche des horreurs type `SS ^_{}`

---

# Fonctionnalités

## fix_latex_smart.py

* Normalise `$$ ... $$` → vrais blocs display
* Supprime traits Markdown (`-----`, `====`, etc.) dans les maths
* Élimine `_` / `^` orphelins
* Supprime `_{} ^{}`
* Corrige `|x|` → `\mid x \mid`
* Nettoie virgules parasites dans intégrales
* Corrige `;\sim;`, `;\circ;`
* Convertit `(expr)` → `$expr$` si LaTeX détecté
* Supprime images distantes
* Préserve blocs code
* Produit automatiquement un fichier `_fixed.md`

Cible : LaTeX minimal compatible Pandoc + LibreOffice MathML.

---

## convert_to_office.sh

* appelle automatiquement `fix_latex_smart.py`
* remplace la source par `_fixed.md`
* lance ensuite Pandoc / LibreOffice

Il devient l’orchestrateur unique.

---

# Usage avancé

Utiliser uniquement le sanitizer :

```bash
python3 fix_latex_smart.py rapport.md
```

ou :

```bash
python3 fix_latex_smart.py rapport.md propre.md
```

---

# Philosophie

Ce repo n’essaie pas de “faire du vrai LaTeX”.

Il fait :

→ du LaTeX robuste pour Pandoc
→ du MathML stable pour LibreOffice
→ tolérance maximale aux sorties LLM

C’est un *sanitizer*, pas un compilateur TeX.

---

# Notes

* Pandoc n’accepte qu’un sous-ensemble strict de LaTeX.
* LibreOffice est encore plus strict.
* ChatGPT produit du LaTeX partiel.

Ce pipeline sert à réconcilier les trois.

---

# Licence

AGPL-3
