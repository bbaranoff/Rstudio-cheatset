#!/usr/bin/env bash
# =============================================================================
#  install_rstudio.sh
#  Installation R + RStudio Desktop + paquets CRAN
#
#  Ubuntu / Linux Mint  →  r2u (24 000 paquets CRAN pré-compilés via apt)
#  Debian               →  r-cran-* Debian officiel + install.packages() pour
#                          les paquets absents des dépôts
#
#  Compatible :
#    Ubuntu  20.04 (focal) / 22.04 (jammy) / 24.04 (noble)
#    Mint    20.x / 21.x / 22.x
#    Debian  11 (bullseye) / 12 (bookworm)
# =============================================================================
set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}══ $* ══${NC}"; }

[[ $EUID -ne 0 ]] && error "Lance le script en root : sudo bash $0"

# =============================================================================
# DETECTION DE LA DISTRIBUTION
# =============================================================================
section "Détection de la distribution"

DISTRO_ID=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
DISTRO_LIKE=$(grep ^ID_LIKE= /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
DISTRO_CODENAME=$(lsb_release -cs 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d '"')
DISTRO_DESC=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')

info "Distribution : $DISTRO_DESC"
info "ID : $DISTRO_ID | Codename : $DISTRO_CODENAME"

# Famille : ubuntu ou debian
case "$DISTRO_ID" in
  ubuntu) FAMILY="ubuntu"; UBUNTU_CODENAME="$DISTRO_CODENAME" ;;
  linuxmint|mint)
    FAMILY="ubuntu"
    # Récupérer le codename Ubuntu parent (inscrit dans os-release sur Mint)
    UBUNTU_CODENAME=$(grep UBUNTU_CODENAME /etc/os-release 2>/dev/null \
      | cut -d= -f2 | tr -d '"' || true)
    # Fallback manuel si absent
    if [[ -z "$UBUNTU_CODENAME" ]]; then
      case "$DISTRO_CODENAME" in
        wilma|virginia)        UBUNTU_CODENAME="noble" ;;
        vera|victoria|vanessa) UBUNTU_CODENAME="jammy" ;;
        uma|una|ulyssa|ulyana) UBUNTU_CODENAME="focal" ;;
        *) UBUNTU_CODENAME="jammy" ;;
      esac
    fi
    ;;
  debian)
    FAMILY="debian"
    DEBIAN_CODENAME="$DISTRO_CODENAME"
    ;;
  *)
    # Dernier recours : regarder ID_LIKE
    if echo "$DISTRO_LIKE" | grep -q "ubuntu"; then
      FAMILY="ubuntu"
      UBUNTU_CODENAME=$(grep UBUNTU_CODENAME /etc/os-release 2>/dev/null \
        | cut -d= -f2 | tr -d '"' || echo "jammy")
    elif echo "$DISTRO_LIKE" | grep -q "debian"; then
      FAMILY="debian"
      DEBIAN_CODENAME="$DISTRO_CODENAME"
    else
      error "Distribution non supportée : $DISTRO_ID. Script prévu pour Ubuntu/Mint/Debian."
    fi
    ;;
esac

info "Famille détectée : $FAMILY"
if [[ "$FAMILY" == "ubuntu" ]]; then
  info "Codename Ubuntu : $UBUNTU_CODENAME  →  r2u sera utilisé pour les paquets R"
else
  info "Codename Debian : $DEBIAN_CODENAME  →  r-cran-* Debian + install.packages() pour le reste"
fi

# =============================================================================
# CLEAN r-cran Ubuntu/Debian (éviter mélange APT ↔ CRAN)
# =============================================================================
section "Nettoyage des anciens r-cran-* (optionnel mais recommandé)"

read -rp "Supprimer tous les r-cran-* existants et /usr/lib/R/site-library ? [Y/n] " CLEAN_RCRAN
CLEAN_RCRAN=${CLEAN_RCRAN:-Y}

if [[ "$CLEAN_RCRAN" =~ ^[Yy]$ ]]; then
  warn "Purge des paquets r-cran-* système…"
  apt-get purge -y 'r-cran-*' || true
  apt-get autoremove -y --purge || true

  if [[ -d /usr/lib/R/site-library ]]; then
    warn "Nettoyage /usr/lib/R/site-library/*"
    rm -rf /usr/lib/R/site-library/* || true
  fi

  info "Nettoyage r-cran terminé."
else
  warn "Nettoyage r-cran ignoré (risque de conflits de versions)."
fi

# =============================================================================
# 1. DEPENDANCES SYSTEME COMMUNES
# =============================================================================
section "1. Dépendances système"
apt-get update -qq
apt-get install -y --no-install-recommends \
  wget curl ca-certificates gnupg2 lsb-release apt-transport-https \
  software-properties-common dirmngr \
  libcurl4-openssl-dev libssl-dev libxml2-dev libfontconfig1-dev \
  libharfbuzz-dev libfribidi-dev libfreetype6-dev libpng-dev \
  libtiff5-dev libjpeg-dev libgit2-dev zlib1g-dev \
  gfortran g++ make cmake git python3-pip

# =============================================================================
# 2. LATEX
# =============================================================================
section "2. LaTeX (xelatex / lualatex / pdflatex)"
apt-get install -y --no-install-recommends \
  texlive-xetex texlive-luatex texlive-latex-extra \
  texlive-fonts-recommended texlive-fonts-extra \
  texlive-lang-french texlive-science \
  lmodern fonts-lmodern latexmk

# =============================================================================
# 3. PANDOC (GitHub — plus récent que apt)
# =============================================================================
section "3. Pandoc"
PANDOC_VERSION="3.2.1"
PANDOC_DEB="pandoc-${PANDOC_VERSION}-1-amd64.deb"
wget -q "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/${PANDOC_DEB}" \
  -O /tmp/"$PANDOC_DEB"
dpkg -i /tmp/"$PANDOC_DEB"
rm /tmp/"$PANDOC_DEB"
info "$(pandoc --version | head -1) installé."

# =============================================================================
# 4. QUARTO CLI
# =============================================================================
section "4. Quarto CLI"
QUARTO_VERSION="1.5.57"
QUARTO_DEB="quarto-${QUARTO_VERSION}-linux-amd64.deb"
wget -q "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/${QUARTO_DEB}" \
  -O /tmp/"$QUARTO_DEB"
dpkg -i /tmp/"$QUARTO_DEB"
rm /tmp/"$QUARTO_DEB"
info "Quarto $(quarto --version) installé."

# =============================================================================
# 5. NODE.JS + MERMAID CLI
# =============================================================================
section "5. Node.js LTS + Mermaid CLI"
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs
npm install -g @mermaid-js/mermaid-cli
info "Node $(node --version) | mmdc installé."

# =============================================================================
# 6. R
#    Ubuntu/Mint  → dépôt CRAN officiel (cran40)
#    Debian       → dépôt CRAN Debian
# =============================================================================
section "6. R"

if [[ "$FAMILY" == "ubuntu" ]]; then
  # ── Dépôt CRAN Ubuntu (Michael Rutter) ─────────────────────────────────────
  wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
    | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc > /dev/null
  add-apt-repository -y \
    "deb https://cloud.r-project.org/bin/linux/ubuntu ${UBUNTU_CODENAME}-cran40/"

else
  # ── Dépôt CRAN Debian ───────────────────────────────────────────────────────
  wget -qO- https://cloud.r-project.org/bin/linux/debian/marutter_pubkey.asc \
    | tee -a /etc/apt/trusted.gpg.d/cran_debian_key.asc > /dev/null
  echo "deb [arch=amd64] https://cloud.r-project.org/bin/linux/debian ${DEBIAN_CODENAME}-cran40/" \
    > /etc/apt/sources.list.d/cran-debian.list
fi

apt-get update -qq
apt-get install -y --no-install-recommends r-base r-base-dev r-recommended
info "R $(R --version | head -1 | awk '{print $3}') installé."

# =============================================================================
# 7. RSTUDIO DESKTOP
#    Build jammy (libssl3) — fonctionne sur Ubuntu 22.04/24.04, Mint 21/22,
#    et Debian 11/12 (tous ont libssl3)
# =============================================================================
section "7. RStudio Desktop"
RSTUDIO_DEB="rstudio-2026.01.0-392-amd64.deb"
wget -q "https://download1.rstudio.org/electron/jammy/amd64/${RSTUDIO_DEB}" \
  -O /tmp/"$RSTUDIO_DEB"
apt-get install -y /tmp/"$RSTUDIO_DEB"
rm /tmp/"$RSTUDIO_DEB"
info "RStudio installé."

# =============================================================================
# 8. PAQUETS R — stratégie selon la famille
# =============================================================================

# ── Branche Ubuntu / Mint : r2u ───────────────────────────────────────────────
if [[ "$FAMILY" == "ubuntu" ]]; then

  section "8a. r2u — CRAN as Ubuntu Binaries"
  info "Configuration de r2u pour $UBUNTU_CODENAME..."

  # r2u supporte focal / jammy / noble
  case "$UBUNTU_CODENAME" in
    focal|jammy|noble) R2U_CODENAME="$UBUNTU_CODENAME" ;;
    *) R2U_CODENAME="jammy" ;;
  esac

  wget -q "https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc" \
    -O /etc/apt/trusted.gpg.d/r2u.asc

  echo "deb [arch=amd64] https://r2u.stat.illinois.edu/ubuntu ${R2U_CODENAME} main" \
    > /etc/apt/sources.list.d/cranapt.list

  # Priorité r2u > dépôts Ubuntu génériques pour r-cran-*
  cat > /etc/apt/preferences.d/99r2u <<'PREF'
Package: r-*
Pin: release o=CRAN2deb4ubuntu
Pin-Priority: 700
PREF

  apt-get update -qq
  info "r2u configuré. Installation de tous les paquets R via apt..."

  apt-get install -y --no-install-recommends \
    \
    r-cran-rmarkdown       \
    r-cran-knitr           \
    r-cran-quarto          \
    r-cran-bookdown        \
    r-cran-blogdown        \
    r-cran-distill         \
    r-cran-flexdashboard   \
    r-cran-xaringan        \
    r-cran-pagedown        \
    \
    r-cran-tinytex         \
    r-cran-pdftools        \
    r-cran-qpdf            \
    r-cran-rticles         \
    \
    r-cran-officer         \
    r-cran-officedown      \
    r-cran-flextable       \
    r-cran-openxlsx        \
    r-cran-readxl          \
    r-cran-writexl         \
    \
    r-cran-kableextra      \
    r-cran-gt              \
    r-cran-gtextras        \
    r-cran-huxtable        \
    r-cran-dt              \
    r-cran-reactable       \
    r-cran-formattable     \
    r-cran-tinytable       \
    \
    r-cran-ggplot2         \
    r-cran-ggthemes        \
    r-cran-ggrepel         \
    r-cran-ggforce         \
    r-cran-ggtext          \
    r-cran-ggsignif        \
    r-cran-ggpubr          \
    r-cran-ggridges        \
    r-cran-ggalluvial      \
    r-cran-patchwork       \
    r-cran-cowplot         \
    r-cran-scales          \
    r-cran-paletteer       \
    r-cran-viridis         \
    r-cran-rcolorbrewer    \
    \
    r-cran-plotly          \
    r-cran-highcharter     \
    r-cran-echarts4r       \
    r-cran-dygraphs        \
    r-cran-diagrammer      \
    r-cran-networkd3       \
    r-cran-visnetwork      \
    r-cran-htmlwidgets     \
    r-cran-leaflet         \
    r-cran-tmap            \
    r-cran-sf              \
    r-cran-mapview         \
    \
    r-cran-shiny           \
    r-cran-shinydashboard  \
    r-cran-shinydashboardplus \
    r-cran-bslib           \
    r-cran-bsicons         \
    r-cran-shinywidgets    \
    r-cran-shinyjs         \
    \
    r-cran-tidyverse       \
    r-cran-dplyr           \
    r-cran-tidyr           \
    r-cran-readr           \
    r-cran-purrr           \
    r-cran-stringr         \
    r-cran-forcats         \
    r-cran-lubridate       \
    r-cran-tibble          \
    \
    r-cran-data.table      \
    r-cran-dtplyr          \
    r-cran-arrow           \
    r-cran-duckdb          \
    r-cran-dbplyr          \
    r-cran-janitor         \
    r-cran-skimr           \
    r-cran-naniar          \
    r-cran-mice            \
    r-cran-tidylog         \
    r-cran-collapse        \
    \
    r-cran-jsonlite        \
    r-cran-xml2            \
    r-cran-rvest           \
    r-cran-httr2           \
    r-cran-curl            \
    r-cran-haven           \
    r-cran-foreign         \
    \
    r-cran-tidymodels      \
    r-cran-caret           \
    r-cran-lme4            \
    r-cran-nlme            \
    r-cran-survival        \
    r-cran-corrplot        \
    r-cran-factominer      \
    r-cran-factoextra      \
    r-cran-psych           \
    r-cran-hmisc           \
    r-cran-rstatix         \
    r-cran-effectsize      \
    r-cran-parameters      \
    r-cran-performance     \
    r-cran-see             \
    r-cran-bayestestr      \
    r-cran-emmeans         \
    \
    r-cran-igraph          \
    r-cran-ggraph          \
    r-cran-tidygraph       \
    \
    r-cran-tidytext        \
    r-cran-quanteda        \
    r-cran-glue            \
    \
    r-cran-devtools        \
    r-cran-remotes         \
    r-cran-usethis         \
    r-cran-pak             \
    r-cran-renv            \
    r-cran-here            \
    r-cran-fs              \
    r-cran-cli             \
    r-cran-crayon          \
    r-cran-styler          \
    r-cran-lintr           \
    r-cran-testthat        \
    r-cran-roxygen2        \
    r-cran-rcpp            \
    r-cran-future          \
    r-cran-furrr           \
    r-cran-progressr       \
    r-cran-memoise         \
    r-cran-reticulate      \
    r-cran-rlang           \
    r-cran-vctrs           \
    r-cran-lifecycle       \
    r-cran-zip

  info "Tous les paquets R installés via apt + r2u."

# ── Branche Debian ────────────────────────────────────────────────────────────
else

  section "8b. Paquets Debian officiels + install.packages() pour le reste"
  
  # Liste conservatrice des paquets disponibles dans Debian
  APT_PKGS=(
    r-cran-rmarkdown r-cran-knitr r-cran-bookdown r-cran-flexdashboard
    r-cran-tinytex r-cran-pdftools
    r-cran-officer r-cran-openxlsx r-cran-readxl r-cran-writexl
    r-cran-kableextra r-cran-dt r-cran-huxtable
    r-cran-ggplot2 r-cran-ggthemes r-cran-ggrepel r-cran-ggforce
    r-cran-ggpubr r-cran-ggridges r-cran-patchwork r-cran-cowplot
    r-cran-scales r-cran-viridis r-cran-rcolorbrewer
    r-cran-plotly r-cran-htmlwidgets r-cran-leaflet r-cran-dygraphs
    r-cran-networkd3 r-cran-visnetwork
    r-cran-shiny r-cran-shinydashboard r-cran-bslib r-cran-shinyjs
    r-cran-tidyverse r-cran-dplyr r-cran-tidyr r-cran-readr
    r-cran-purrr r-cran-stringr r-cran-forcats r-cran-lubridate r-cran-tibble
    r-cran-data.table r-cran-dtplyr r-cran-janitor r-cran-skimr
    r-cran-naniar r-cran-mice
    r-cran-jsonlite r-cran-xml2 r-cran-rvest r-cran-curl
    r-cran-haven r-cran-foreign
    r-cran-lme4 r-cran-nlme r-cran-survival r-cran-caret
    r-cran-corrplot r-cran-factominer r-cran-factoextra
    r-cran-psych r-cran-hmisc r-cran-emmeans r-cran-effectsize
    r-cran-sf r-cran-tmap r-cran-igraph r-cran-diagrammer
    r-cran-tidytext r-cran-glue
    r-cran-devtools r-cran-remotes r-cran-usethis r-cran-renv
    r-cran-here r-cran-fs r-cran-cli r-cran-crayon
    r-cran-styler r-cran-lintr r-cran-testthat r-cran-roxygen2
    r-cran-rcpp r-cran-future r-cran-memoise r-cran-reticulate
    r-cran-rlang r-cran-vctrs r-cran-lifecycle
  )

  info "Installation des paquets r-cran-* disponibles dans Debian..."
  MISSING_DEB=()
  for pkg in "${APT_PKGS[@]}"; do
    if apt-cache show "$pkg" &>/dev/null 2>&1; then
      apt-get install -y --no-install-recommends "$pkg" || \
        warn "$pkg : erreur à l'installation, on continue."
    else
      CRAN_NAME=$(echo "$pkg" | sed 's/^r-cran-//')
      MISSING_DEB+=("$CRAN_NAME")
    fi
  done

  # Paquets sans .deb Debian → install.packages()
  CRAN_FALLBACK=(
    "quarto" "blogdown" "distill" "xaringan" "pagedown"
    "officedown" "flextable" "rticles" "qpdf"
    "gt" "gtExtras" "reactable" "formattable" "tinytable"
    "ggtext" "ggsignif" "ggalluvial" "paletteer"
    "highcharter" "echarts4r" "mapview"
    "shinydashboardPlus" "bsicons" "shinyWidgets"
    "arrow" "duckdb" "dbplyr" "tidylog" "collapse"
    "httr2" "tidymodels" "rstatix" "parameters" "performance"
    "see" "bayestestR" "ggraph" "tidygraph"
    "quanteda" "pak" "furrr" "progressr"
  )

  ALL_CRAN=("${CRAN_FALLBACK[@]}" "${MISSING_DEB[@]}")
  ALL_CRAN=($(printf '%s\n' "${ALL_CRAN[@]}" | sort -u))

  if [[ ${#ALL_CRAN[@]} -gt 0 ]]; then
    info "Installation via install.packages() : ${#ALL_CRAN[@]} paquets..."
    R_PKGS=$(printf '"%s",' "${ALL_CRAN[@]}" | sed 's/,$//')
    R --no-save --no-restore <<RSCRIPT
options(repos = c(CRAN = "https://cloud.r-project.org"))
pkgs <- c($R_PKGS)
n <- max(1L, parallel::detectCores() - 1L)
message("Installation de ", length(pkgs), " paquets sur ", n, " coeurs...")
install.packages(pkgs, Ncpus = n, dependencies = TRUE, quiet = FALSE)
RSCRIPT
  fi

fi

# =============================================================================
# 9. VERIFICATION FINALE
# =============================================================================
section "9. Vérification"

echo ""
info "── Outils système ──"
for cmd in R Rscript pandoc quarto xelatex lualatex pdflatex mmdc node npm; do
  if command -v "$cmd" &>/dev/null; then
    VER=$("$cmd" --version 2>&1 | head -1 || true)
    echo -e "  ${GREEN}OK${NC}  $cmd  →  $VER"
  else
    echo -e "  ${RED}KO${NC}  $cmd  →  NON TROUVÉ"
  fi
done

echo ""
info "── Paquets R clés ──"
R --no-save --no-restore -e "
pkgs <- c('rmarkdown','knitr','ggplot2','tidyverse','shiny',
          'officer','flextable','plotly','DiagrammeR','sf',
          'tinytex','devtools','renv','quarto')
inst <- rownames(installed.packages())
for (p in pkgs) {
  status <- if (p %in% inst) 'OK' else 'MANQUANT'
  cat(sprintf('  %-22s %s\n', p, status))
}"

echo ""
info "Installation terminée !"
echo -e "  Lance RStudio via : ${CYAN}rstudio &${NC}"
echo -e "  ou depuis le menu Applications de ton bureau."
