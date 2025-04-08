# Rstudio-cheatset
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y software-properties-common
add-apt-repository -y ppa:c2d4u.team/c2d4u4.0+
echo "deb https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" > /etc/apt/sources.list.d/cran.list
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9
apt update && apt install -y r-cran-sass
wget https://download1.rstudio.org/electron/jammy/amd64/rstudio-2024.12.1-563-amd64.deb
sudo dpkg -i rstudio-2024.12.1-563-amd64.deb
sudo apt -f install
