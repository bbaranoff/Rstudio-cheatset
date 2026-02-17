#!/usr/bin/env bash
# =============================================================================
#  convert_to_office.sh
#  Conversion Rmd / .md / .qmd / .tex / .ipynb → .docx / .odt
#  Usage : bash convert_to_office.sh [OPTIONS] <fichier>
# =============================================================================
set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BLUE}▶${NC}  $*"; }
ok()      { echo -e "${GREEN}✔${NC}  $*"; }

# =============================================================================
# AIDE
# =============================================================================
usage() {
cat <<'EOF'
Usage: bash convert_to_office.sh [OPTIONS] <fichier_source>

FORMATS EN ENTRÉE :
  .Rmd .rmd       R Markdown  (officedown → Word natif)
  .qmd            Quarto Markdown
  .md .markdown   Markdown pur
  .tex .latex     LaTeX
  .ipynb          Jupyter Notebook

FORMATS EN SORTIE (défaut : docx) :
  -f docx         Microsoft Word  (.docx)
  -f odt          OpenDocument    (.odt)
  -f both         Les deux formats

OPTIONS :
  -o <dossier>    Dossier de sortie  (défaut : même dossier que la source)
  -t <fichier>    Template de référence .docx ou .odt
  -T <titre>      Titre du document  (injecté dans les métadonnées)
  -a <auteur>     Auteur             (injecté dans les métadonnées)
  -b              Ouvrir le résultat après conversion  (xdg-open)
  -k              Conserver les fichiers intermédiaires
  -v              Mode verbeux (pandoc --verbose)
  -n              Désactiver la numérotation des sections
  -h              Afficher cette aide

EXEMPLES :
  bash convert_to_office.sh rapport.Rmd
  bash convert_to_office.sh -f odt -o ./output/ these.tex
  bash convert_to_office.sh -f both -t mon_style.docx article.qmd
  bash convert_to_office.sh -f docx -T "Mon rapport" -a "Bastien" notes.md
  bash convert_to_office.sh -b -k presentation.Rmd
EOF
}

# =============================================================================
# ARGUMENTS
# =============================================================================
FORMAT="docx"
OUTPUT_DIR=""
TEMPLATE=""
DOC_TITLE=""
DOC_AUTHOR=""
OPEN_AFTER=false
KEEP=false
VERBOSE=false
NUM_SECTIONS=true
MATH_MODE="mathml"   # défaut

while getopts "f:o:t:T:a:m:bkvnh" opt; do
  case "$opt" in
    f) FORMAT="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    t) TEMPLATE="$OPTARG" ;;
    T) DOC_TITLE="$OPTARG" ;;
    a) DOC_AUTHOR="$OPTARG" ;;
    m) MATH_MODE="$OPTARG" ;;
    b) OPEN_AFTER=true ;;
    k) KEEP=true ;;
    v) VERBOSE=true ;;
    n) NUM_SECTIONS=false ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

[[ $# -eq 0 ]] && { usage; echo; error "Aucun fichier source fourni."; }
SRC="$1"

# ---- LaTeX sanitizer (OBLIGATOIRE avant pandoc) ----
FIX_LATEX="$(dirname "$0")/fix_latex_smart.py"

if [ ! -f "$FIX_LATEX" ]; then
    echo "❌ fix_latex_smart.py introuvable"
    exit 1
fi

TMP_MD="${SRC%.md}_fixed.md"

echo "[*] Nettoyage LaTeX → $TMP_MD"
python3 "$FIX_LATEX" "$SRC" "$TMP_MD"

SRC="$TMP_MD"
[[ ! -f "$SRC" ]] && error "Fichier introuvable : $SRC"


# =============================================================================
# CHEMINS
# =============================================================================
SRC_ABS=$(realpath "$SRC")
SRC_DIR=$(dirname "$SRC_ABS")
STEM=$(basename "$SRC_ABS")
STEM="${STEM%.*}"
EXT="${SRC_ABS##*.}"
EXT=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

OUTPUT_DIR="${OUTPUT_DIR:-$SRC_DIR}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")

# =============================================================================
# VÉRIFICATION DES OUTILS
# =============================================================================
step "Vérification des outils..."
MISSING=()
for cmd in R Rscript pandoc; do
  command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
[[ "$EXT" == "qmd" ]] && ! command -v quarto &>/dev/null && MISSING+=("quarto")
[[ ${#MISSING[@]} -gt 0 ]] && \
  error "Outils manquants : ${MISSING[*]}\n  → Lance d'abord : sudo bash install_rstudio.sh"

info "R    : $(R --version | head -1 | awk '{print $3}')"
info "Pandoc : $(pandoc --version | head -1 | awk '{print $2}')"
command -v quarto &>/dev/null && info "Quarto : $(quarto --version)"

# =============================================================================
# HELPERS PANDOC COMMUNS
# =============================================================================
pandoc_base_args() {
  local fmt="$1"
  local args=(
    "--standalone"
    "--wrap=none"
    "--toc"
    "--toc-depth=3"
    "--highlight-style=tango"
  )
  [[ "$NUM_SECTIONS" == true ]]          && args+=("--number-sections")
  [[ "$VERBOSE"      == true ]]          && args+=("--verbose")
  [[ -n "$TEMPLATE" && -f "$TEMPLATE" ]] && args+=("--reference-doc=$TEMPLATE")
  [[ -n "$DOC_TITLE"  ]] && args+=("--metadata=title:${DOC_TITLE}")
  [[ -n "$DOC_AUTHOR" ]] && args+=("--metadata=author:${DOC_AUTHOR}")
  if [[ "$fmt" == "odt" ]]; then
    if [[ "$MATH_MODE" == "webtex" ]]; then
      args+=("--webtex=https://latex.codecogs.com/png.latex?")
    else
      args+=("--mathml")
    fi
    args+=("--request-header=User-Agent:Mozilla/5.0")
  fi
  echo "${args[@]}"
}
# =============================================================================
# CONVERSION .Rmd
# =============================================================================
convert_rmd() {
  local fmt="$1"
  local out="${OUTPUT_DIR}/${STEM}.${fmt}"

  step "Rmd → $fmt  (officedown + rmarkdown)"

  Rscript --no-save --no-restore - <<'RSCRIPT'
suppressPackageStartupMessages({
  library(rmarkdown)
  library(knitr)
})

src    <- "$SRC_ABS"
outdir <- "$OUTPUT_DIR"
stem   <- "$STEM"
fmt    <- "$fmt"
keep   <- as.logical("$KEEP")
tpl    <- "$TEMPLATE"
title  <- "$DOC_TITLE"
author <- "$DOC_AUTHOR"
numSec <- as.logical("$NUM_SECTIONS")

has_pkg <- function(p) p %in% rownames(installed.packages())

# Injecter titre/auteur si non présents dans le YAML
inject_yaml <- function(path, title, author) {
  if (nchar(title) == 0 && nchar(author) == 0) return(path)
  lines <- readLines(path, warn = FALSE)
  yaml_start <- which(lines == "---")
  if (length(yaml_start) >= 2) {
    end <- yaml_start[2]
    has_title  <- any(grepl("^title:", lines[1:end]))
    has_author <- any(grepl("^author:", lines[1:end]))
    inject <- c()
    if (!has_title  && nchar(title)  > 0) inject <- c(inject, paste0('title: "', title, '"'))
    if (!has_author && nchar(author) > 0) inject <- c(inject, paste0('author: "', author, '"'))
    if (length(inject) > 0) {
      new_lines <- c(lines[1], inject, lines[2:length(lines)])
      tmp <- tempfile(fileext = ".Rmd")
      writeLines(new_lines, tmp)
      return(tmp)
    }
  }
  return(path)
}

src <- inject_yaml(src, title, author)
make_tpl <- function(t) if (nchar(t) > 0 && file.exists(t)) t else NULL

# Format officedown (docx seulement)
make_rdocx <- function() {
  if (!has_pkg("officedown")) return(NULL)
  tryCatch({
    officedown::rdocx_document(
      reference_docx    = make_tpl(tpl),
      toc               = TRUE,
      toc_depth         = 3,
      number_sections   = numSec,
      keep_md = keep
    )
  }, error = function(e) {
    message("[WARN] officedown indisponible : ", conditionMessage(e))
    NULL
  })
}

# Format word_document standard
make_word <- function() {
  word_document(
    reference_docx  = make_tpl(tpl),
    toc             = TRUE,
    toc_depth       = 3,
    number_sections = numSec,
    keep_md         = keep,
    highlight       = "tango",
    pandoc_args     = c("--wrap=none")
  )
}

# Format odt_document
make_odt <- function() {
  odt_document(
    reference_odt   = make_tpl(tpl),
    toc             = TRUE,
    number_sections = numSec,
    pandoc_args = c("--wrap=none", "--mathml")
  )
}
# Sélection du format
rmd_fmt <- if (fmt == "docx") {
  f <- make_rdocx()
  if (is.null(f)) make_word() else f
} else {
  make_odt()
}

out_file <- file.path(outdir, paste0(stem, ".", fmt))

# Rendu
result <- tryCatch({
  render(
    input         = src,
    output_format = rmd_fmt,
    output_file   = out_file,
    output_dir    = outdir,
    quiet         = FALSE,
    clean         = !keep
  )
  message("[R] OK : ", out_file)
  "OK"
}, error = function(e) {
  message("[R] render() échoué : ", conditionMessage(e))
  message("[R] Fallback knitr → pandoc ...")
  "FALLBACK"
})

# Fallback : knitr → .md puis pandoc
if (result == "FALLBACK") {
  md_tmp <- file.path(outdir, paste0(stem, "_tmp.md"))
  knitr::opts_knit\$set(base.dir = outdir)
  knitr::knit(src, output = md_tmp, quiet = FALSE)
  cat("FALLBACK_MD", md_tmp, "\n")
}
RSCRIPT

  # Fallback pandoc si demandé
  MD_TMP="${OUTPUT_DIR}/${STEM}_tmp.md"
  if [[ -f "$MD_TMP" ]]; then
    step "Fallback pandoc : $MD_TMP → $out"
    local base_args
    base_args=$(pandoc_base_args "$fmt")
    # shellcheck disable=SC2086
    	pandoc $base_args \
      --from "markdown+smart+yaml_metadata_block+implicit_figures+raw_html" \
      --to "$fmt" \
      -o "$out" \
      "$MD_TMP" 2>&1
    [[ "$KEEP" == false ]] && rm -f "$MD_TMP"
  fi

  [[ -f "$out" ]] && ok "Rmd → $out" || warn "Aucune sortie produite"
}

# =============================================================================
# CONVERSION .qmd — Quarto CLI natif
# =============================================================================
convert_qmd() {
  local fmt="$1"
  local out="${OUTPUT_DIR}/${STEM}.${fmt}"

  step "Quarto → $fmt"

  local qargs=("render" "$SRC_ABS" "--to" "$fmt" "--output" "$out")
  [[ -n "$TEMPLATE" && -f "$TEMPLATE" ]] && \
    qargs+=("-M" "reference-doc:${TEMPLATE}")
  [[ -n "$DOC_TITLE"  ]] && qargs+=("-M" "title:${DOC_TITLE}")
  [[ -n "$DOC_AUTHOR" ]] && qargs+=("-M" "author:${DOC_AUTHOR}")
  [[ "$NUM_SECTIONS" == true ]] && qargs+=("-M" "number-sections:true")
  [[ "$VERBOSE" == true ]] && qargs+=("--verbose")

  quarto "${qargs[@]}" 2>&1

  [[ -f "$out" ]] && ok "Quarto → $out" || warn "Quarto n'a pas produit de sortie."
}

# =============================================================================
# CONVERSION .md — pandoc avec extensions étendues
# =============================================================================
convert_md() {
  local fmt="$1"
  local out="${OUTPUT_DIR}/${STEM}.${fmt}"

  step "Markdown → $fmt  (pandoc)"

  local src_to_use="$SRC_ABS"
  if [[ -n "$DOC_TITLE" || -n "$DOC_AUTHOR" ]]; then
    local tmp_md
    tmp_md=$(mktemp /tmp/convert_XXXXXX.md)
    {
      echo "---"
      [[ -n "$DOC_TITLE"  ]] && echo "title: \"${DOC_TITLE}\""
      [[ -n "$DOC_AUTHOR" ]] && echo "author: \"${DOC_AUTHOR}\""
      echo "---"
      echo ""
      cat "$SRC_ABS"
    } > "$tmp_md"
    src_to_use="$tmp_md"
  fi

  local base_args
  base_args=$(pandoc_base_args "$fmt")


  #Juste avant l'appel pandoc dans convert_md()
  if [[ "$fmt" == "odt" ]] && command -v convert &>/dev/null; then
    # Télécharge et convertit les images GIF distantes en PNG dans le markdown
    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/pandoc_imgs_XXXXXX)
    sed -i -E "s|!\[([^]]*)\]\((https?://[^ )]+\.gif)\)|![\1]($(
      grep -oP 'https?://\S+\.gif' "$src_to_use" | while read url; do
        fname="$tmp_dir/$(basename "$url" .gif).png"
        curl -sL "$url" -o "$fname.gif" && convert "$fname.gif[0]" "$fname" 2>/dev/null
        echo "$fname"
      done
    ))|g" "$src_to_use" 2>/dev/null || true
  fi


  # shellcheck disable=SC2086
  pandoc $base_args \
    --from "markdown+smart+yaml_metadata_block+implicit_figures+raw_html+multiline_tables+grid_tables+pipe_tables+definition_lists+footnotes+citations" \
    --to "$fmt" \
    -o "$out" \
    "$src_to_use" 2>&1

  [[ -n "${tmp_md:-}" ]] && rm -f "$tmp_md"
  [[ -f "$out" ]] && ok "Markdown → $out" || warn "Pandoc n'a pas produit de sortie."
}

# =============================================================================
# CONVERSION .tex — pandoc from=latex
# =============================================================================
convert_tex() {
  local fmt="$1"
  local out="${OUTPUT_DIR}/${STEM}.${fmt}"

  step "LaTeX → $fmt  (pandoc)"

  local base_args
  base_args=$(pandoc_base_args "$fmt")

  # shellcheck disable=SC2086
  pandoc $base_args \
    --from "latex" \
    --to "$fmt" \
    -o "$out" \
    "$SRC_ABS" 2>&1

  [[ -f "$out" ]] && ok "LaTeX → $out" || warn "Pandoc n'a pas produit de sortie."
}

# =============================================================================
# CONVERSION .ipynb — Jupyter Notebook
# =============================================================================
convert_ipynb() {
  local fmt="$1"
  local out="${OUTPUT_DIR}/${STEM}.${fmt}"

  step "Jupyter Notebook → $fmt  (pandoc)"

  local base_args
  base_args=$(pandoc_base_args "$fmt")

  # shellcheck disable=SC2086
  pandoc $base_args \
    --from "ipynb" \
    --to "$fmt" \
    -o "$out" \
    "$SRC_ABS" 2>&1

  [[ -f "$out" ]] && ok "Notebook → $out" || warn "Pandoc n'a pas produit de sortie."
}

# =============================================================================
# POST-TRAITEMENT DOCX via officer (simple et résistant aux erreurs)
# =============================================================================
postprocess_docx() {
  local docx="$1"
  [[ ! -f "$docx" ]] && return
  [[ -n "$TEMPLATE" && -f "$TEMPLATE" ]] && return
  step "Post-traitement docx avec officer..."
  DOCX_PATH="$docx" Rscript --no-save --no-restore - 2>/dev/null <<'RSCRIPT'
docx <- Sys.getenv("DOCX_PATH")
repair_officer <- function() {
  pkgs_apt <- c(
    "r-cran-rlang", "r-cran-vctrs", "r-cran-cli", "r-cran-lifecycle",
    "r-cran-glue", "r-cran-pillar", "r-cran-tibble",
    "r-cran-officer", "r-cran-zip"
  )
  cmd <- paste("apt-get install --allow-downgrades -y", paste(pkgs_apt, collapse = " "))
  message("[officer] Conflit détecté, réparation automatique...")
  message("[officer] Commande : ", cmd)
  ret <- system(cmd)
  if (ret != 0) {
    message("[officer] Échec (pas root ?). Lance manuellement :")
    message("  sudo ", cmd)
    return(FALSE)
  }
  return(TRUE)
}
ok <- tryCatch({
  suppressPackageStartupMessages(library(officer))
  TRUE
}, error = function(e) {
  msg <- conditionMessage(e)
  if (grepl("namespace|version|requis|required", msg, ignore.case = TRUE)) {
    return(repair_officer())
  } else {
    message("[officer] ", msg)
    return(FALSE)
  }
})
if (!ok) quit(status = 0)
tryCatch({
  doc <- read_docx(docx)
  doc <- body_set_default_section(doc,
    prop_section(
      page_margins = page_mar(top = 2.5, bottom = 2.5, left = 2.5, right = 2.5, unit = "cm")
    )
  )
  print(doc, target = docx)
  message("[officer] Marges appliquées → ", docx)
}, error = function(e) {
  message("[officer] Erreur : ", conditionMessage(e))
})
RSCRIPT

  if [[ $? -ne 0 ]]; then
    warn "officer non disponible ou en conflit — docx conservé intact"
    warn "Fix : sudo apt-get install --allow-downgrades -y r-cran-rlang r-cran-vctrs r-cran-officer"
    return 0
  fi
}
# =============================================================================
# POST-TRAITEMENT ODT : fix rendu math LibreOffice
# =============================================================================
postprocess_odt() {
  local odt="$1"
  [[ ! -f "$odt" ]] && return
  step "Post-traitement ODT (fix math U+2223)..."
  python3 - "$odt" << 'PYEOF'
import sys, zipfile, shutil, re, tempfile, os

odt = sys.argv[1]
tmp = odt + '.tmp'

with zipfile.ZipFile(odt, 'r') as zin:
    files = {}
    for name in zin.namelist():
        data = zin.read(name)
        if 'Formula' in name and name.endswith('content.xml'):
            text = data.decode('utf-8')
            # | ASCII → ∣ littéral
            text = re.sub(r'<mo([^>]*)>\|</mo>', '<mo\\1>∣</mo>', text)
            # stretchy=false → true sur ∣
            text = re.sub(
                r'<mo stretchy="false"([^>]*)>∣</mo>',
                r'<mo stretchy="true"\1>∣</mo>',
                text
            )
            text = text.replace('<mi>−</mi>', '<mo>−</mo>')
            text = text.replace('<mi>-</mi>', '<mo>-</mo>')
            text = text.replace('<mi>+</mi>', '<mo>+</mo>')
            text = text.replace('<mi>∞</mi>', '<mo>∞</mo>')
            data = text.encode('utf-8')
        files[name] = data

with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as zout:
    for name, data in files.items():
        zout.writestr(name, data)

os.replace(tmp, odt)
print(f"[ODT] Math fix appliqué → {odt}")
PYEOF
}
# =============================================================================
# DISPATCHER
# =============================================================================
do_convert() {
  local fmt="$1"
  local out="${OUTPUT_DIR}/${STEM}.${fmt}"

  echo -e "\n${CYAN}════════════════════════════════════════${NC}"
  info "Source  : $SRC_ABS"
  info "Cible   : $out"
  info "Format  : $fmt"
  echo -e "${CYAN}════════════════════════════════════════${NC}"

  case "$EXT" in
    rmd|rmarkdown) convert_rmd  "$fmt" ;;
    qmd)           convert_qmd  "$fmt" ;;
    md|markdown)   convert_md   "$fmt" ;;
    tex|latex)     convert_tex  "$fmt" ;;
    ipynb)         convert_ipynb "$fmt" ;;
    *)             error "Extension non supportée : .$EXT\n  Accepté : .Rmd .qmd .md .tex .ipynb" ;;
  esac

  # Post-traitement Word uniquement
  [[ "$fmt" == "docx" && -f "$out" ]] && postprocess_docx "$out"
  [[ "$fmt" == "odt" && -f "$out" ]] && postprocess_odt "$out"
  if [[ -f "$out" ]]; then
    local size
    size=$(du -sh "$out" | cut -f1)
    echo ""
    ok "${GREEN}${fmt^^} généré${NC} → $out  ($size)"
    [[ "$OPEN_AFTER" == true ]] && { xdg-open "$out" 2>/dev/null & }
  else
    warn "Aucun fichier produit pour $out — voir les messages ci-dessus."
  fi
}

# =============================================================================
# EXECUTION
# =============================================================================
case "$FORMAT" in
  docx)      do_convert "docx" ;;
  odt)       do_convert "odt"  ;;
  both|all)  do_convert "docx"; do_convert "odt" ;;
  *)         error "Format invalide : '$FORMAT'  (valeurs : docx, odt, both)" ;;
esac

# Résumé final
echo ""
echo -e "${GREEN}═══════ Terminé ═══════${NC}"
echo "Dossier : $OUTPUT_DIR"
shopt -s nullglob
files=("$OUTPUT_DIR"/*.docx "$OUTPUT_DIR"/*.odt)
for f in "${files[@]}"; do
  echo -e "  ${GREEN}•${NC} $(basename "$f")  ($(du -sh "$f" | cut -f1))"
done
[[ ${#files[@]} -eq 0 ]] && warn "Aucun fichier .docx/.odt trouvé"
