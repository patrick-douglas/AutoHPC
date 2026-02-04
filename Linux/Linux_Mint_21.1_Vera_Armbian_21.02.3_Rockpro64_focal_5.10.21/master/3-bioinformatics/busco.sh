#!/bin/bash
set -euo pipefail

w=$(tput sgr0)
r=$(tput setaf 1)
g=$(tput setaf 2)
y=$(tput setaf 3)

USAGE="USAGE: $0 -u <username>"

# ---- args ----
user_name=""

while getopts ":u:" option; do
  case "${option}" in
    u) user_name="$OPTARG" ;;
    *) echo -e "${r}Invalid option.${w}\n$USAGE"; exit 1 ;;
  esac
done

if [ -z "$user_name" ]; then
  echo -e "${r}Error: missing argument:${y} -u <username>${w}\n$USAGE"
  exit 1
fi

threads=$(nproc)

# ---- check if ~/busco exists for that user ----
BUSCO_DIR=$(su - "$user_name" -c 'echo "$HOME/busco"')

if su - "$user_name" -c "[ -d \"$BUSCO_DIR\" ]"; then
  echo -e "${y}Detected existing BUSCO directory:${w} $BUSCO_DIR"

  # Prompt
while true; do
  echo -ne "Do you want to replace it and reinstall BUSCO + dependencies? [y/N]: "
  read -n 1 -r ans
  echo    # newline after keypress

  case "$ans" in
    [yY])
      echo -e "${y}Removing existing BUSCO directory...${w}"
      su - "$user_name" -c "rm -rf \"$BUSCO_DIR\""
      REINSTALL=1
      break
      ;;
    [nN]|"")
      echo -e "${g}Keeping existing BUSCO directory.${w}"
      REINSTALL=0
      break
      ;;
    *)
      echo "Please press y or n."
      ;;
  esac
done
else
  REINSTALL=1
fi

# ---- install/clone only if needed ----
if [ "$REINSTALL" -eq 1 ]; then
  echo -e "${g}Cloning BUSCO...${w}"
  su - "$user_name" -c 'cd "$HOME" && git clone https://gitlab.com/ezlab/busco.git'
fi

# ---- copy config + run your check script ----
echo -e "${g}Copying config.ini...${w}"
su -c 'cp config.ini ~/busco/config' $user_name

echo -e "${g}Installing requirements...${w}"
./requirements.sh -u "$user_name"

echo -e "${g}Running requirements/version check...${w}"
./check_requ_versions.sh -u "$user_name"
