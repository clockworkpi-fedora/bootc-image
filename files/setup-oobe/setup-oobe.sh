#!/bin/bash

export TOP_PID=$$

HOST=0

GLOBAL_TITLE="ClockworkPi Fedora"

RANDOM_ID=$(($RANDOM % 10000))
PADDED_ID=$(printf "%04d" "$RANDOM_ID")
DEFAULT_HOSTNAME="clockpi-$PADDED_ID"

DEFAULT_USERNAME="clockpi"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

if [ $HOST -ne 1 ] && getent passwd 1000 > /dev/null; then
    # Setup is already done. Disable self and exit.
    systemctl disable setup-oobe.service
    exit 0
fi

if ! tty -s; then
    echo "Error: No interactive TTY found."
    exit 1
fi

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
if [ -z "$TERM" ] || [ "$TERM" == "dumb" ]; then
    export TERM=linux
fi

term() {
  kill -s TERM $TOP_PID
}

get_len() {
  echo $(echo -n "$1" | wc -m)
}

confirm() {
  # $1 = Title, $2 = Question, $3 Default to no?, $4 Height
  
  DEFAULT_NO=
  if [ "$3" = "1" ]; then
    DEFAULT_NO=--defaultno
  fi

  HEIGHT=12
  if [ "$4" != "" ]; then
    HEIGHT=$4
  fi

  whiptail --title "$1" --backtitle "$GLOBAL_TITLE" --yesno "$2" \
    $HEIGHT 60 $DEFAULT_NO 3>&1 1>&2 2>&3

  echo $?
}

on_interrupt() {
  trap "" SIGINT
  INPUT=$(confirm "Abort Setup" "Are you sure you want to abort setup and POWER OFF your device?" 1)
  if [ $INPUT -ne 1 ]; then
      if [ $HOST -ne 1 ]; then
        poweroff
      fi
      term
  fi
}

trap "on_interrupt" SIGINT

msg() {
  # $1 = Title, $2 = Message, $3 = Height
  HEIGHT=12
  if [ "$3" != "" ]; then
    HEIGHT=$3
  fi

  whiptail --title "$1" --backtitle "$GLOBAL_TITLE" --msgbox "$2" \
    $HEIGHT 60 3>&1 1>&2 2>&3
}

ask() {
    # $1 = Title, $2 = Question, $3 = Optional?, $4 Password?, $5 = Default Value, 
    
    while true; do
      INPUT_TYPE="--inputbox"
      if [ "$4" = "1" ]; then
        INPUT_TYPE="--passwordbox"
      fi
      INPUT=$(whiptail --title "$1" --backtitle "$GLOBAL_TITLE" \
        $INPUT_TYPE "$2" 12 60 --cancel-button "Poweroff" "$5" 3>&1 1>&2 2>&3)
      if [ $? -ne 0 ]; then
        on_interrupt
        continue
      fi
      if [ $3 -eq 1 ] || [ -n "$INPUT" ]; then
        break
      fi
      msg "Error" "Cannot be empty."
    done
    echo "$INPUT"
   }

ask_pass() {
    # $1 = Title

    while true; do
      PASS=$(ask "$1" "Please enter a password." 1 1)
      if [ ! -n "$PASS" ]; then
        EMPTY=$(confirm "$1" "Are you sure you want an empty password?" 1)
        if [ $EMPTY -eq 0 ]; then
          break
        else
          continue
        fi
      fi
        
      CONFIRM=$(ask "$1" "Please enter the password again." 1 1)

      if [ "$PASS" = "$CONFIRM" ]; then
        break
      fi
      msg "Error" "Passwords must match."
    done
    echo $PASS
}

select_opt() {
  # $1 = Title, $2 = Question, $3 = Default Item, $4... = Menu Options (Tag Item pairs)
  TITLE="$1"
  QUESTION="$2"
  DEFAULT="$3"
  shift 3
  
  # We capture the choice. The "${@}" passes all remaining arguments as the list
  CHOICE=$(whiptail --title "$TITLE" --backtitle "$GLOBAL_TITLE" \
    --menu "$QUESTION" 25 45 18 --notags --cancel-button "Poweroff" \
    --default-item "$DEFAULT" \
    "${@}" 3>&1 1>&2 2>&3)
  
  if [ $? -ne 0 ]; then
    on_interrupt
    # If they chose not to abort, we return empty to signal a retry/loop
    echo "" 
  else
    echo "$CHOICE"
  fi
}

get_timezone() {
    REGIONS=($(timedatectl list-timezones | cut -d/ -f1 | uniq | awk '{print $1 " " $1}'))

    REGIONS=(
        "Africa"      "Africa"
        "America"     "Americas (North/South)"
        "Antarctica"  "Antarctica"
        "Asia"        "Asia"
        "Atlantic"    "Atlantic Ocean"
        "Australia"   "Australia"
        "Europe"      "Europe"
        "Indian"      "Indian Ocean"
        "Pacific"     "Pacific Ocean"
    )

    REGION=$(select_opt "Timezone" "Select your Region:" "America" "${REGIONS[@]}")

    CITIES=($(timedatectl list-timezones | grep "^$REGION/" | cut -d/ -f2- | uniq | awk '{print $1 " " $1}'))

    CITY=$(select_opt "Timezone" "Select your City in $REGION:" "" "${CITIES[@]}")
    echo "$REGION/$CITY"
}

msg "Welcome" "Welcome to $GLOBAL_TITLE!\n\nWe need to configure a few basics before you can start using your device."

msg "Tip" 'If you ever make a mistake, just complete setup, and choose "No" when asked "Does everything look correct?"' 9

while true; do

  TIMEZONE=$(get_timezone)

  HOSTNAME=$(ask "Hostname" "Please enter a name for your device." 0 0 "$DEFAULT_HOSTNAME")
 
  FULLNAME=$(ask "User Setup" "Please enter your full name (optional)." 1)
  if [ $(get_len "$FULLNAME") -eq 0 ]; then
    FULLNAME_PRETTY="(None)"
  else
    FULLNAME_PRETTY="$FULLNAME"
  fi

  USERNAME=$(ask "User Setup" "Please enter a username." 0 0 $DEFAULT_USERNAME)

  PASSWORD=$(ask_pass "User Setup")
  PASSWORD_LEN=$(get_len "$PASSWORD")
  if [ $PASSWORD_LEN -eq 0 ]; then
    PASSWORD_PRETTY="(None)"
  else
    PASSWORD_PRETTY="$(printf "%${PASSWORD_LEN}s\n" | tr ' ' '*')"
  fi

  CONFIRM=$(confirm "Confirm Settings" "Timezone: $TIMEZONE\nHostname: $HOSTNAME\nFull name: $FULLNAME_PRETTY\nUsername: $USERNAME\nPassword: $PASSWORD_PRETTY\n\nDoes everything look correct?" 0 13)

  if [ $CONFIRM -eq 0 ]; then
    break
  fi
done

msg "Important" "The system will now apply your configuration.\n\nPlease do not power off your device or interrupt the process in any way." 11

if [ $HOST -ne 1 ]; then
  {
    echo "XXX\n25\nGrowing filesystem...\nXXX"
    growpart /dev/mmcblk0 3 >/dev/null
    partprobe /dev/mmcblk0 >/dev/null
    resize2fs /dev/mmcblk0p3 echo 0 >/dev/null
    echo "Setting Timezone ($TIMEZONE)..."
    timedatectl set-timezone "$TIMEZONE" >/dev/null
    sleep 1

    echo "XXX\n50\nApplying hotname ($HOSTNAME)...\nXXX"
    hostnamectl set-hostname "$HOSTNAME" >/dev/null
    sleep 1

    echo "XXX\n75\nCreating user ($USERNAME)...\nXXX"
    if ! id "$USERNAME" &>/dev/null; then
      useradd -m -G wheel -c "$FULLNAME" -s /bin/bash "$USERNAME" >/dev/null
      echo "$USERNAME:$PASSWORD" | chpasswd >/dev/null
    fi
    sleep 1

    systemctl disable setup-oobe.service >/dev/null
  } | whiptail --gauge "Configuring System..." 10 60 0
fi

msg "Finish" "Done! Your device will reboot to complete setup.\nThank you for choosing $GLOBAL_TITLE." 10

if [ $HOST -ne 1 ]; then
  reboot
fi
