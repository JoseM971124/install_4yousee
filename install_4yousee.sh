#!/bin/bash

UBUNTU_VERSION=$(lsb_release -rs)
ARCHITECTURE=$(uname -m)
IGNORE_VALIDATION=false
[[ $1 == '--force' ]] && IGNORE_VALIDATION=true

if [[ "$IGNORE_VALIDATION" == false && "$UBUNTU_VERSION" != "16.04" && "$UBUNTU_VERSION" != "18.04" && "$UBUNTU_VERSION" != "20.04" ]]; then
  echo "Ops! A versão do Ubuntu ($UBUNTU_VERSION) não é suportada. Por favor, use a versão 16.04, 18.04 ou 20.04."
  echo "Você pode ignorar a verificação da versão e da arquitetura usando o parâmetro --force: ./installRobot.sh --force"
  exit 1
fi

if [[ "$ARCHITECTURE" == "armv7l" || "$ARCHITECTURE" == "aarch64" || "$ARCHITECTURE" == "arm64" ]]; then
  echo "Ops! A arquitetura do sistema ($ARCHITECTURE) não é suportada (ARM). Este script não pode ser executado em dispositivos ARM."
  exit 1
fi

---
### Instalação de Dependências Essenciais
---

# Instala o 'curl' se ele não estiver presente
if ! command -v curl &>/dev/null; then
  echo "curl não encontrado. Instalando..."
  sudo apt update && sudo apt install -y curl
fi

# Instala o 'python2.7' se ele não estiver presente
if ! command -v python2.7 &>/dev/null; then
    echo "Python 2.7 não encontrado. Instalando..."
    sudo apt update && sudo apt install -y python2.7
fi

# Cria links simbólicos para 'python' e 'python2'
if ! command -v python2 &>/dev/null; then
    echo "Criando link simbólico para 'python2'..."
    sudo ln -s /usr/bin/python2.7 /usr/bin/python2
fi
if ! command -v python &>/dev/null; then
    echo "Criando link simbólico para 'python'..."
    sudo ln -s /usr/bin/python2.7 /usr/bin/python
fi

# Instala o 'pip' para Python 2.7
if ! python2.7 -m pip --version &>/dev/null; then
    echo "Instalando pip para Python 2.7..."
    wget -q https://bootstrap.pypa.io/pip/2.7/get-pip.py -O /tmp/get-pip.py --no-check-certificate || {
        echo "Erro: Falha ao baixar get-pip.py"
        exit 1
    }
    sudo python2.7 /tmp/get-pip.py && echo "Pip instalado com sucesso!" || {
        echo "Erro: Falha ao instalar o pip."
        exit 1
    }
else
    echo "O pip já está instalado."
fi

# Adiciona o diretório local de pacotes ao PATH
echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Instala dependências GTK2 e Pygobject
echo "Instalando dependências do PyGTK e Pygobject..."
sudo apt-get update -y
sudo apt-get install -y pkg-config python-dev libgirepository1.0-dev python-cairo-dev python-gi-dev libffi-dev build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libcairo2-dev

# Instala PyGTK2
# Estes pacotes DEB são necessários para o GTK2
wget -c http://archive.ubuntu.com/ubuntu/pool/universe/p/pygtk/python-gtk2_2.24.0-5.1ubuntu2_amd64.deb
wget -c http://archive.ubuntu.com/ubuntu/pool/universe/p/pygtk/python-gtk2-dev_2.24.0-5.1ubuntu2_all.deb
sudo apt-get install -y ./python-gtk2-dev_2.24.0-5.1ubuntu2_all.deb ./python-gtk2_2.24.0-5.1ubuntu2_amd64.deb
sudo pip install pygobject

# Instala dependências do setuptools e wheel
sudo pip install setuptools wheel

---
### Instalação do 4yousee Player Linux
---

# URL e nome do arquivo
URL="http://files.4yousee.com.br/players/new/robot"
ZIP="4youseeRobot.zip"

# Cria e entra na pasta do player
if ! mkdir -p $HOME/.4yousee; then
    echo "Error creating folder .4yousee"
    exit
fi
cd $HOME/.4yousee

# Baixa e processa o arquivo de versão do Robot
if ! curl -L -O "$URL/robotVersion.xml"; then
    echo "Can't download file $URL/robotVersion.xml"
    exit
fi
FILES=$(cat robotVersion.xml)
if [[ $FILES =~ \<version\>(.+)\<\/version\> ]]; then
    ROBOT_VERSION=${BASH_REMATCH[1]};
    echo "Versão do Robot: $ROBOT_VERSION";
fi

# Baixa e descompacta o Robot
if ! curl -L -O "$URL/v$ROBOT_VERSION/$ZIP"; then
    echo "Can't download file $URL/v$ROBOT_VERSION/$ZIP"
    exit
fi
if ! unzip -o $ZIP; then
    echo "Can't unzip $ZIP"
    exit
fi
rm $ZIP

# Cria pastas necessárias para o player
mkdir -p player player/update update

cd $HOME/.4yousee/player/update
if ! curl -L -O "$URL/playerFiles/version.xml"; then
    echo "Can't download file $URL/playerFiles/version.xml"
    exit
fi
FILES=$(cat version.xml)
if [[ $FILES =~ \<version\>(.+)\<\/version\> ]]; then
    PLAYER_VERSION=${BASH_REMATCH[1]};
    echo "Versão do Player: $PLAYER_VERSION";
fi

# Baixa os arquivos do Player de acordo com a arquitetura
architecture=$(uname -m)
if [ "$architecture" == "i686" ]; then
    file="4YouSeeChromeApp-linux-ia32"
else
    file="4YouSeeChromeApp-linux-x64"
fi
if ! wget --continue "$URL/playerFiles/v$PLAYER_VERSION/$file.zip"; then
    echo "Can't download file $URL/playerFiles/v$PLAYER_VERSION/$file.zip"
    exit
fi

# Descompacta e move os arquivos do Player
echo "Iniciando extração dos arquivos..."
if ! unzip -qod "$HOME/.4yousee/player/" "$HOME/.4yousee/player/update/$file"; then
    echo "Can't unzip $HOME/.4yousee/player/update/$file"
    exit
fi
mv "$HOME/.4yousee/player/$file" "$HOME/.4yousee/player/4YouSeeChromeApp"
cp "$HOME/.4yousee/player/update/version.xml" "$HOME/.4yousee/player/version.xml"
echo "Extração de arquivos finalizada."

cd $HOME/.4yousee
chmod -R 777 *

if ! python 4youseeRobot setup; then
    echo "Falha na instalação do Robot"
else
    # Configura o serviço de acordo com o sistema de inicialização (systemd ou upstart)
    initStat=$(sudo stat --format %N /proc/1/exe)
    system=""
    if test "${initStat#*systemd}" != "$initStat"; then
        system="systemd"
    elif test "${initStat#*"/sbin/init"}" != "$initStat"; then
        initVersion=$(/sbin/init --version)
        if test "$initVersion#*upstart" != "$initVersion"; then
            system="upstart"
        else
            system="other"
        fi
    else
        system="other"
    fi

    case "$system" in
        systemd )
            echo "Detectado systemd. Configurando serviço..."
            sudo cp 4youseeRobot.service /etc/systemd/user/
            systemctl --user daemon-reload
            systemctl --user enable 4youseeRobot
            systemctl --user stop 4youseeRobot
            systemctl --user start 4youseeRobot
            ;;
        upstart )
            echo "Detectado upstart. Configurando serviço..."
            cp 4youseeRobot.conf $HOME"/.config/upstart"
            service 4youseeRobot start
            initctl --session stop 4youseeRobot
            initctl --session start 4youseeRobot
            ;;
        * )
            echo "Não foi detectado nem upstart nem systemd. Por favor, adicione o serviço manualmente."
    esac

    echo "4youseeRobot instalado com sucesso!"
fi