#!/bin/bash

MENU_LINK="https://raw.githubusercontent.com/linuxiarznaetacie/multi-scripts/refs/heads/main/msk-qwert-server.sh"

if [ "$EUID" -ne 0 ]; then
  echo "Ten skrypt wymaga uprawnień roota. Próba restartu z sudo..."
  exec sudo "$0" "$@"
fi

  echo "Wpisz swoja nazwe uzytkownika dla VNC (domyslnie: vncuser):"
  read VNC_USER
  VNC_USER=${VNC_USER:-vncuser}

  if ! id -u "$VNC_USER" &>/dev/null; then
    echo "Uzytkownik $VNC_USER nie istnieje. Stworzmy go!"
    useradd -m -s /bin/bash "$VNC_USER"
    echo "Stworz haslo dla uzytkownika $VNC_USER:"
    passwd "$VNC_USER"
  fi

  echo "Wpisz haslo dla VNC (minimum 6 znakow):"
  read -s VNC_PASSWORD
  echo ""  

  if systemctl is-active --quiet novnc; then
    echo "noVNC jest juz zainstalowane."
    NOVNC_PORT=$(systemctl show -p ExecStart --value novnc | awk -F'--listen ' '{print $2}' | awk '{print $1}')
    echo "Uzyto obecnego portu NoVNC: $NOVNC_PORT"
  else
    echo "Wpisz port NoVNC (domyslnie 6080):"
    read NOVNC_PORT
    NOVNC_PORT=${NOVNC_PORT:-6080}
  fi

  echo "Wpisz swoj numer ekranu VNC (domyslnie :1):"
  read VNC_DISPLAY
  VNC_DISPLAY=${VNC_DISPLAY:-:1}
  VNC_PORT=$((5900 + ${VNC_DISPLAY#:}))

  PUBLIC_IP=$(curl -s4 https://ifconfig.me)

  apt update && apt upgrade -y
  apt install -y tigervnc-standalone-server tigervnc-common git xfce4 xfce4-goodies dbus-x11 xfce4-terminal
  echo "Setting up VNC password..."
  su - "$VNC_USER" -c "mkdir -p ~/.vnc"
  echo "$VNC_PASSWORD" | su - "$VNC_USER" -c "vncpasswd -f > ~/.vnc/passwd"
  su - "$VNC_USER" -c "chmod 600 ~/.vnc/passwd"
  su - "$VNC_USER" -c "cat << EOF > ~/.vnc/xstartup
#!/bin/bash
[ -f "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"
export XKL_XMODMAP_DISABLE=1
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
startxfce4
EOF"
  su - "$VNC_USER" -c "chmod +x ~/.vnc/xstartup"

  echo "Initializing and enabling VNC server..."
  su - "$VNC_USER" -c "vncserver $VNC_DISPLAY"
  su - "$VNC_USER" -c "vncserver -kill $VNC_DISPLAY"
  
  echo "Creating TigerVNC systemd service..."
  cat << EOF > /etc/systemd/system/tigervncserver@.service
[Unit]
Description=TigerVNC Server
After=syslog.target network.target

[Service]
Type=forking
User=$VNC_USER
Group=$VNC_USER
WorkingDirectory=/home/$VNC_USER


PIDFile=/home/$VNC_USER/.vnc/%H%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :1 > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -depth 24 -geometry 1280x800 :1
ExecStop=/usr/bin/vncserver -kill :1

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable tigervncserver@$VNC_DISPLAY
  systemctl start tigervncserver@$VNC_DISPLAY

  if ! systemctl is-active --quiet novnc; then
    su - "$VNC_USER" -c "cd ~ && git clone https://github.com/novnc/noVNC.git"
    su - "$VNC_USER" -c "cd ~/noVNC && git clone https://github.com/novnc/websockify.git"

    cat << EOF > /etc/systemd/system/novnc.service
[Unit]
Description=noVNC Server
After=network.target

[Service]
Type=simple
ExecStart=/home/$VNC_USER/noVNC/utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $NOVNC_PORT
Restart=always
User=$VNC_USER

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable novnc
    systemctl start novnc
    ln -s /home/$VNC_USER/noVNC/vnc.html /home/$VNC_USER/noVNC/index.html

  fi

  ufw allow $NOVNC_PORT
  ufw allow $VNC_PORT
  
clear
echo "+------------------------------------------------+"
echo "        POMYSLNIE ZAINSTALOWANO NOVNC"
echo "  "
echo "       ZALOGUJ SIE DO PULPITU POD ADRESEM:"
echo "          http://$PUBLIC_IP:$NOVNC_PORT"
echo "  "
echo "+------------------------------------------------+"

read -p "Czy chcesz uruchomic menu glowne? (t/n): " odpowiedz

if [[ "$odpowiedz" =~ ^[tT]$ ]]; then
    clear
    if [ -n "$MENU_LINK" ]; then
        bash <(curl -sSf "$MENU_LINK")
    fi
else
    clear
    exit 0
fi
