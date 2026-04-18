#!/bin/bash
# Este script é executado atraves de um script primario

rm -rf /home/.tmp
rm -rf /home/.tmp/
mkdir -p /home/.tmp/

w=$(tput sgr0)
r=$(tput setaf 1)
g=$(tput setaf 2)
y=$(tput setaf 3)
p=$(tput setaf 5)
pb=$(tput bold)

USAGE="USAGE: $0 -n <nodename>"

while getopts n: option
do
case "${option}" in
n) node_name=${OPTARG};;
esac
done

if [ "$node_name" = "" ]; then
    echo "${g}Error, missing arguments:${y} -n | Node hostname | <string>"
    echo "${w}$USAGE"
    exit 1
fi

echo "${y}"
echo "---------------------------------------------------------------------------------"
echo "----------------- Phase 1: Identify the Cluster and the node --------------------"
echo "---------------------------------------------------------------------------------"
echo ""
echo "---------------------------------------------------------------------------------"
echo "${g}Node hostname:${w}"
echo "$node_name"
echo "${g}---------------------------------------------------------------------"
echo "${w}"

echo "---------------------------------------------------------------------"
echo "                       Setting up hardware"
echo "---------------------------------------------------------------------"
echo "${w}"

# SETUP FAN SPEED - modo continuo

echo "${g}Creating remote fan control script...${w}"
ssh "$node_name" 'cat > /usr/local/bin/fan-max.sh << "EOF"
#!/bin/bash

set -u

while true; do
    PWM="$(find /sys/devices/platform/pwm-fan/hwmon/ -name pwm1 2>/dev/null | head -n1)"

    if [ -n "$PWM" ]; then
        PWM_ENABLE="${PWM}_enable"

        if [ -e "$PWM_ENABLE" ]; then
            echo 1 > "$PWM_ENABLE" 2>/dev/null || true
        fi

        echo 255 > "$PWM" 2>/dev/null || true
    fi

    sleep 1
done
EOF
chmod +x /usr/local/bin/fan-max.sh'

if [ $? -ne 0 ]; then
    echo "${r}Error creating /usr/local/bin/fan-max.sh on ${node_name}${w}"
    exit 1
fi

echo "${g}Creating/replacing remote systemd service...${w}"
ssh "$node_name" 'cat > /etc/systemd/system/fan-max.service << "EOF"
[Unit]
Description=Keep fan at maximum speed
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/fan-max.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF'

if [ $? -ne 0 ]; then
    echo "${r}Error creating /etc/systemd/system/fan-max.service on ${node_name}${w}"
    exit 1
fi

echo "${g}Reloading systemd, enabling and restarting service...${w}"
ssh "$node_name" 'systemctl daemon-reload && systemctl enable fan-max.service && systemctl restart fan-max.service'

if [ $? -ne 0 ]; then
    echo "${r}Error enabling or restarting fan-max.service on ${node_name}${w}"
    exit 1
fi

echo "${g}Checking service status...${w}"
ssh "$node_name" 'systemctl status fan-max.service --no-pager'

echo "${g}Checking PWM state...${w}"
ssh "$node_name" '
PWM="$(find /sys/devices/platform/pwm-fan/hwmon/ -name pwm1 2>/dev/null | head -n1)"
echo "PWM=$PWM"
if [ -n "$PWM" ]; then
    if [ -e "${PWM}_enable" ]; then
        echo -n "enable="
        cat "${PWM}_enable"
    fi
    echo -n "value="
    cat "$PWM"
else
    echo "PWM nao encontrado"
fi
'

# Descomente se quiser reiniciar automaticamente o node no final
# echo "${y}Rebooting node...${w}"
 ssh "$node_name" reboot
