#!/bin/bash

# serial port
SERIALPORT=$1

# bootloader serial port
DFUSERIALPORT=$3

# tundev
TUNDEV=$2

# UART transfer speed. Ignored for USB serial.
BAUDRATE=460800
DFUBAUDRATE=115200

# Log file
LOG_DIR=/home/ghaf/log/
LOG_FILE=/home/ghaf/log/osf52.log

# osf interface check interval
CHECK_INTERVAL_IN_SECONDS=1

TIMEOUT="timeout"
SLIPCMD="slipcmd"
TUNSLIP6="tunslip6"

# path to firmware files
FWPATH1="/run/current-system/sw/lib/firmware/osf/nrf52/nrf52fwboard1*.zip"
FWPATH2="/run/current-system/sw/lib/firmware/osf/nrf52/nrf52fwboard2*.zip"

# path to nrf utility
NRF="nrf"

# constants
MTU=1460
MSS=940

# OSF's PHY
PHY_BLE_1M=3                
PHY_BLE_2M=4
PHY_BLE_500K=6
PHY_BLE_125K=5
PHY_IEEE=15

# variables
FWVER=0
FWVERSION=0

#######################################
# Checks log file existence and creates if needed
#######################################
log_setup()
{
  if [ ! -f $LOG_FILE ]; then
    mkdir -p $LOG_DIR &>/dev/null
    touch $LOG_FILE &>/dev/null
  fi
}

#######################################
# Controls nrf IO lines
#######################################
set_nrf() {
  # Fetch pcb version
  . /etc/comms_pcb_version

  case "$0""$1" in
  powerdown)
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf52_en"=0
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf53_en"=0
    ;;
  powerdown5*)
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf""$2""_en"=0
    ;;
  powerup)
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf52_en"=1
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf53_en"=1
    ;;
  powerup5*)
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf""$2""_en"=1
    ;;
  reset)
    [ "$COMMS_PCB_VERSION" -eq 0 ] && gpioset -p 1ms -t 0 "nrf52_rst"=0
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf52_reset"=0
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf53_reset"=0
    sleep 0.1
    [ "$COMMS_PCB_VERSION" -eq 0 ] && gpioset -p 1ms -t 0 "nrf52_rst"=1
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf52_reset"=1
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf53_reset"=1
    ;;
  reset5*)
    gpioset -p 1ms -t 0 "nrf""$2""_reset"=0
    sleep 0.1
    gpioset -p 1ms -t 0 "nrf""$2""_reset"=1
    ;;
  dfuon)
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf52_dfu_mode"=0
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf53_dfu_mode"=0
    ;;
  dfuon5*)
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf""$2""_dfu_mode"=0
    ;;
  dfuoff)
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf52_dfu_mode"=1
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf53_dfu_mode"=1
    ;;
  dfuoff5*)
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf""$2""_dfu_mode"=1
    ;;
  down)
    [ "$COMMS_PCB_VERSION" -eq 0 ] && gpioset -p 1ms -t 0 "nrf52_rst"=0
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf52_reset"=0
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf53_reset"=0
    ;;
  down5*)
    [ "$COMMS_PCB_VERSION" -eq 0 ] && gpioset -p 1ms -t 0 "nrf""$2""_rst"=0
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf""$2""_reset"=0
    ;;
  up)
    [ "$COMMS_PCB_VERSION" -eq 0 ] && gpioset -p 1ms -t 0 "nrf52_rst"=1
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf52_reset"=1
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf53_reset"=1
    ;;
  up5*)
    [ "$COMMS_PCB_VERSION" -eq 0 ] && gpioset -p 1ms -t 0 "nrf""$2""_rst"=1
    [ "$COMMS_PCB_VERSION" -eq 1 ] && gpioset -p 1ms -t 0 "nrf""$2""_reset"=1
    ;;
  *)
    echo "Incorrect nrf argument"
    ;;
  esac
}

#######################################
# Enable/disable timesync role on the node
#######################################
set_timesync() {
  # serial port
  SERIALPORT="/dev/nrf0"

  # Default value - enable
  SFTS_VAL=0

  if [ "$1" = "disable_ts" ]; then
    SFTS_VAL=255
  fi

  # root only
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root !"
    exit 1
  fi


  # stop OSF setup service
  systemctl stop osf.service
  sleep 2

  # request timesync node_id
  STATUS=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?SFTS' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$STATUS" ] ; then
    echo "?SFTS" slipcmd error : "$?" or "$STATUS"
    return 1
  fi
  STATUS=${STATUS:6:1};
  echo Timesync node_id : "$STATUS"

  # stop OSF driver
  STATUS=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'!S0' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$STATUS" ] ; then
    echo "!S0" slipcmd error : "$?" or "$STATUS"
    return 1
  fi
  STATUS=${STATUS:2:1};
  echo OSF driver status : "$STATUS"

  # toggle timesync role
  STATUS=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R"!SFTS $SFTS_VAL" "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$STATUS" ] ; then
    echo "!SFTS" slipcmd error : "$?" or "$STATUS"
    return 1
  fi
  STATUS=${STATUS:6:3};
  echo Set timesync node_id to : "$STATUS"

  # save configuration and reboot
  STATUS=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'!S3' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$STATUS" ] ; then
    echo "!S3" slipcmd error : "$?" or "$STATUS"
  else
    STATUS=${STATUS:2:1};
    echo OSF driver status : "$STATUS"
  fi

  sleep 2

  # get driver status after reboot
  STATUS=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?S' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$STATUS" ] ; then
    echo "?S" slipcmd error : "$?" or "$STATUS"
    #exit 1
  fi
  STATUS=${STATUS:2:1};
  echo OSF driver status : "$STATUS"

  # restart OSF setup service
  systemctl start osf.service
  sleep 2

  return 0
}


#######################################
# Add date prefix to line
# Globals:
# Arguments:
#   debug print lines
#######################################
add_date() {
  while IFS= read -r line; do
    printf '[%s]: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$line"
  done
}

#######################################
# Flush serial port garbage
#######################################
serial_flush() {
  for (( c=1; c<4; c++ ))
  do 
    NN=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?N' "$SERIALPORT")
    if [ "$?" -ne 0 ] || [ -z "$NN" ] || [ "${NN:0:2}" != "!N" ] ; then
      #echo 1st slipcmd error : "$?" or "$NN" | add_date |& tee -a "$LOG_FILE"
      sleep 0.1 
    else
      break 
    fi
  done

  return
}

#######################################
# Update FW
#######################################
fw_update() {
  # check if we have firmware update file at known location
  # version   module
  # 0         cm4io board, CSL1.0, CSL1.5
  # 0.5       CM1.5
  # 1         CM2.01 - version gpio index starts from 1
  # 2         CM2.02
  BOARD=$(cat /etc/comms_pcb_version)
  echo "PCB_BOARD : ""$BOARD"| add_date |& tee -a "$LOG_FILE"
  if [ "$BOARD" == "COMMS_PCB_VERSION=1" ] || [ "$BOARD" == "COMMS_PCB_VERSION=2" ]; then  
    FWFILE=$(ls $FWPATH2)
  elif  [ "$BOARD" == "COMMS_PCB_VERSION=0" ] || [ "$BOARD" == "COMMS_PCB_VERSION=0.5" ]; then  
    FWFILE=$(ls $FWPATH1)
  else
    echo "Unknown PCB_BOARD ..." | add_date |& tee -a "$LOG_FILE"
    echo "Exit..."
    return 0  
  fi

  # if file exists, extract version of firmware
  if [ -z "$FWFILE" ]; then
    echo "Firmware update file is not provisioned!" | add_date |& tee -a "$LOG_FILE"
    echo "Exit..."
    return 0
  else
    FWVER=$(echo "$FWFILE" | grep -o -P '(?<=_v).*(?=.zip)')
    echo "Firmware update file ""$FWFILE"" version ""$FWVER"" available" | add_date |& tee -a "$LOG_FILE"
  fi

  if [ -z "$FWVER" ]; then
    echo "Firmware version have unknown format !" | add_date |& tee -a "$LOG_FILE"
    echo "Exit..."
    return 0
  fi  

  # check if MCU is up and running
  serial_flush
  if ls "$SERIALPORT" &>/dev/null; then
    echo "Read current nRF52 firmware version ... "
    slip_output=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?SFVER' "$SERIALPORT")
    if [ "$?" -ne 0 ] || [ -z "$slip_output" ] || [ "${slip_output:0:6}" != "!SFVER" ]; then
      echo "slipcmd error or timeout [ ""${slip_output:0:50}"" ] !"
    else
      FWVERSION="${slip_output:6:8}"
      echo "Current nRF52 Firmware version : ""$FWVERSION"| add_date |& tee -a "$LOG_FILE"
    fi
  fi

  # check if MCU in DFU mode
  if ls "$DFUSERIALPORT" &>/dev/null; then
    echo "nRF52 in DFU mode !" | add_date |& tee -a "$LOG_FILE"
    echo "MCU have bootloader only !"
    echo "Initiate firmware flashing !" | add_date |& tee -a "$LOG_FILE"
  else
    echo "Check if available version is newer :" "$FWVER"" > ""$FWVERSION"" ?" | add_date |& tee -a "$LOG_FILE"
    if (( FWVER > FWVERSION )); then
      echo "DFU serial port does not detected. Force nRF52 to DFU mode ... " | add_date |& tee -a "$LOG_FILE"
      # dfu pin settings are  ignored for early versions of boards
      if [ "$BOARD" == "COMMS_PCB_VERSION=1" ] || [ "$BOARD" == "COMMS_PCB_VERSION=2" ]; then  
        "$NRF" dfuon 52
        sleep 0.1
        "$NRF" reset 52
        sleep 2
        "$NRF" dfuoff 52
        sleep 0.1
      else
        "$NRF" reset
        sleep 2
      fi
    else
      echo "MCU have newest or equal FW version already !" | add_date |& tee -a "$LOG_FILE"
      echo "Exit..."
      return 0
    fi
  fi

  # check if MCU in DFU mode
  if ls "$DFUSERIALPORT" &>/dev/null; then
    echo "DFU serial port ""$DFUSERIALPORT"" is detected !" | add_date |& tee -a "$LOG_FILE"
  else
    echo "DFU serial port does not detected. Flash bootloader by using JTAG interface !" | add_date |& tee -a "$LOG_FILE"
    echo "Exit..."
    return 1
  fi

  # Update FW
  echo "Initiate firmware flashing to version ""$FWVER"" !" | add_date |& tee -a "$LOG_FILE"
  SECONDS=0
  status=$(nrfutil -v dfu usb-serial -p "$DFUSERIALPORT" -b "$DFUBAUDRATE" -pkg "$FWFILE" -cd 1 -t 1 -fc 1)
  echo "nRF52 Firmware update status " "$status" | add_date |& tee -a "$LOG_FILE"
  if [[ "$status" =~ "Device programmed." ]]; then
    echo "Firmware successfully updated ," "$SECONDS"" seconds elapsed !" | add_date |& tee -a "$LOG_FILE"
  else
    echo "Firmware update failed ! Status : ""$status" | add_date |& tee -a "$LOG_FILE"
    echo "Power off/on board for initiate firmware update again !" | add_date |& tee -a "$LOG_FILE"
    return 1
  fi  

  sleep 2

  # Read new FW version
  # check if MCU is up and running
  if ls "$SERIALPORT" &>/dev/null; then
    echo "Read MCU firmware version "
    slip_output=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?SFVER' "$SERIALPORT")
    if [ "$?" -ne 0 ] || [ -z "$slip_output" ] || [ "${slip_output:0:6}" != "!SFVER" ]; then
      echo "slipcmd error or timeout [ ""${slip_output:0:50}"" ] !"
      FWVERSION=0
      echo "Can't read nRF52 Firmware version !" | add_date |& tee -a "$LOG_FILE"
      echo "Unknown firmware ? Power off/on board for initiate firmware update again !" | add_date |& tee -a "$LOG_FILE"
      return 1
    else
      FWVERSION="${slip_output:6:8}"
      echo "New nRF52 Firmware version ""$FWVERSION" | add_date |& tee -a "$LOG_FILE"
    fi
  else
    echo "MCU serial port is not available !" | add_date |& tee -a "$LOG_FILE"
    echo "Unknown firmware ? Power off/on board for initiate firmware update again !" | add_date |& tee -a "$LOG_FILE"
    return 1
  fi
      
  return 0
}

#######################################
# Setup loop
# Globals:
#   CHECK_INTERVAL_IN_SECONDS
#   LOG_FILE
# Arguments:
#   $1 siodev
#   $2 tundev
#   $3..$7 extra tunslip6 parameters
#######################################
setup() {
  # check input parameters
  if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage : setup siodev tundev suodfudev" | add_date |& tee -a "$LOG_FILE"
    exit 1
  fi

  # root only
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root !"
    exit 1
  fi

  # check if serial port available
  if [[ ! $(ls "$SERIALPORT") =~ "$SERIALPORT" ]] && [[ ! $(ls "$DFUSERIALPORT") =~ "$DFUSERIALPORT" ]]; then
    echo "osf serial port does not exist yet." | add_date |& tee -a "$LOG_FILE"
    echo "pause 5s .." | add_date |& tee -a "$LOG_FILE"
    sleep 5
  fi

  # measure osf interface mount time
  SECONDS=0
  # check if serial port available
  if [[ ! $(ls "$SERIALPORT") =~ "$SERIALPORT" ]] && [[ ! $(ls "$DFUSERIALPORT") =~ "$DFUSERIALPORT" ]]; then
    echo "osf serial port does not exist." | add_date |& tee -a "$LOG_FILE"
    echo "stop osf52 service.." | add_date |& tee -a "$LOG_FILE"
    systemctl stop osf.service
    exit 1
  fi

  # kill tunslip6 instanses
  killall "$TUNSLIP6" &>/dev/null
  sleep 0.5

  # update nRF52 firmware if possible
  fw_update
  sleep 0.5

  # test connection to the node; first symbols might be garbage
  serial_flush
  NN=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?N' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$NN" ] ; then
    echo 1st slipcmd error : "$?" or "$NN" | add_date |& tee -a "$LOG_FILE"
    echo "$1"" serial device is not responding, stop osf52 service.." | add_date |& tee -a "$LOG_FILE"
    systemctl stop osf.service
  fi
  #echo 1st "$SLIPCMD" "$SERIALPORT" output "$NN"  | add_date |& tee -a "$LOG_FILE"

  # request amount of provisioned nodes
  NNODES=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?N' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$NNODES" ] ; then
    echo "?N" slipcmd error : "$?" or "$NNODES" | add_date |& tee -a "$LOG_FILE"
    exit 1
  fi
  NNODES=${NNODES:2:3}; NNODES=${NNODES//[!0-9]/}
  echo Total nodes : "$NNODES" | add_date |& tee -a "$LOG_FILE"

  # request node_id of the connected node
  THENODEID=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?N0' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$THENODEID" ] ; then
    echo "?N0" slipcmd error : "$?" or "$THENODEID" | add_date |& tee -a "$LOG_FILE"
    exit 1
  fi
  THENODEID=${THENODEID:2:3}; THENODEID=${THENODEID//[!0-9]/}
  echo The node_id : "$THENODEID" | add_date |& tee -a "$LOG_FILE"

  # request node_id of the ISN node
  ISNNODEID=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?N255' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$ISNNODEID" ] ; then
    echo "?N255" slipcmd error : "$?" or "$ISNNODEID" | add_date |& tee -a "$LOG_FILE"
    #exit 1
  fi
  ISNNODEID=${ISNNODEID:2:3}; ISNNODEID=${ISNNODEID//[!0-9]/}
  echo ISN node_id : "${ISNNODEID}" | add_date |& tee -a "$LOG_FILE"

  # request node_id of the TS node
  TSNODEID=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?SFTS' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$TSNODEID" ] ; then
    echo "?SFTS" slipcmd error : "$?" or "$TSNODEID" | add_date |& tee -a "$LOG_FILE"
    #exit 1
  fi
  TSNODEID=${TSNODEID:6:3}; TSNODEID=${TSNODEID//[!0-9]/}
  echo TS node_id  : "${TSNODEID}" | add_date |& tee -a "$LOG_FILE"

  # request PHY
  PHY=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?SFPHY' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$PHY" ] ; then
    echo slipcmd error : "$?" or "$PHY" | add_date |& tee -a "$LOG_FILE"
    #exit 1
  fi
  PHY=${PHY:7:2}
  echo PHY : "$PHY" | add_date |& tee -a "$LOG_FILE"

  # request NTX
  NTX=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?SFNTX' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$NTX" ] ; then
    echo slipcmd error : "$?" or "$NTX" | add_date |& tee -a "$LOG_FILE"
    #exit 1
  fi
  NTX=${NTX:7:2}
  echo NTX : "$NTX" | add_date |& tee -a "$LOG_FILE"

  # request expected address 1 of host
  HOSTADDR1=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?H' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$HOSTADDR1" ] ; then
    echo slipcmd error : "$?" or "$HOSTADDR1" | add_date |& tee -a "$LOG_FILE"
    exit 1
  fi
  HOSTADDR1=${HOSTADDR1:2:46}
  echo The Host address 1 : "$HOSTADDR1" | add_date |& tee -a "$LOG_FILE"

  # request expected address 1 of node
  NODEADDR1=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?Y' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$NODEADDR1" ] ; then
    echo slipcmd error : "$?" or "$NODEADDR1" | add_date |& tee -a "$LOG_FILE"
    exit 1
  fi
  NODEADDR1=${NODEADDR1:2:46}
  echo The Node address 1 : "$NODEADDR1" | add_date |& tee -a "$LOG_FILE"

  # request expected address 2 of host
  HOSTADDR2=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?R' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$HOSTADDR2" ] ; then
    echo slipcmd error : "$?" or "$HOSTADDR2" | add_date |& tee -a "$LOG_FILE"
    exit 1
  fi
  HOSTADDR2=${HOSTADDR2:2:46}
  echo The Host address 2 : "$HOSTADDR2" | add_date |& tee -a "$LOG_FILE"

  # request address of node with prefix2
  NODEADDR2=$("$TIMEOUT" --preserve-status 2s "$SLIPCMD" -H -b"$BAUDRATE" -sn -R'?X' "$SERIALPORT")
  if [ "$?" -ne 0 ] || [ -z "$NODEADDR2" ] ; then
    echo slipcmd error : "$?" or "$NODEADDR2" | add_date |& tee -a "$LOG_FILE"
    exit 1
  fi    
  NODEADDR2=${NODEADDR2:2:46}
  echo The Node address 2 : "$NODEADDR2" | add_date |& tee -a "$LOG_FILE"

  # start tunslip6 in background
  sysctl -w net.ipv6.conf.all.forwarding=1
  echo "$TUNSLIP6" "$HOSTADDR1"/64 -s "$SERIALPORT" -t "$TUNDEV" -d1 -M "$MTU" -H -B "$BAUDRATE" -v0 "$4" "$5" "$6" "$7" | add_date |& tee -a "$LOG_FILE"
  "$TUNSLIP6" "$HOSTADDR1"/64 -s "$SERIALPORT" -t "$TUNDEV" -d1 -M "$MTU" -H -B "$BAUDRATE" -v0 $3 $4 $5 $6 $7&
  if [ "$?" -ne 0 ] ; then
    echo tunslip6 error : "$?" | add_date |& tee -a "$LOG_FILE"
    exit 1
  fi

  # waiting mount of osf interface
  for (( c=1; c<10; c++ ))
  do 
    #echo "c=""$c" | add_date |& tee -a "$LOG_FILE"
    sleep 0.5 
    INTERFACE=$(ip link show | grep "$TUNDEV")
    if [ "$INTERFACE" ] ; then
      sleep 0.1
      break
    fi
  done

  # wake up interface one more time
  ip link set dev "$TUNDEV" up
  ip link set mtu "$MTU" dev "$TUNDEV"

  # check availability of network interface
  INTERFACE=$(ip link show | grep "$TUNDEV")
  if [ ! "$INTERFACE" ] ; then
    echo "$TUNDEV" "interface is not mounted yet.." | add_date |& tee -a "$LOG_FILE"
    # exit 1
  fi

  # add route to nodes and hosts with prefix2
  if [ "$HOSTADDR2" ] ; then
    ip address add dev "$TUNDEV" "$HOSTADDR2"/48
    ip -6 route add "$NODEADDR2"/48 dev "$TUNDEV"
  fi

  # limit UDP rate for avoid interface overflow
  # rate values are tested for OSF_ZT=1 and NTX=3
  RATE=250kbit
  if (( "$NTX" == 3 )) ; then
    if [ "$PHY" == "$PHY_BLE_1M" ] ; then
      RATE=155kbit
    elif [ "$PHY" == "$PHY_BLE_500K" ] ; then
      RATE=85kbit
    elif [ "$PHY" == "$PHY_BLE_125K" ] ; then
      RATE=25kbit
    elif [ "$PHY" == "$PHY_IEEE" ] ; then
      RATE=25kbit     
    fi
  fi   
  tc qdisc add dev "$TUNDEV" root tbf rate "$RATE" burst 12K latency 250ms

  # delete MSS settings for avoid multiple entries and set it again
  ip6tables -t mangle -D POSTROUTING -d "$HOSTADDR1"/64 -p tcp --tcp-flags SYN,RST SYN -o "$TUNDEV" -j TCPMSS --set-mss "$MSS"
  ip6tables -t mangle -A POSTROUTING -d "$HOSTADDR1"/64 -p tcp --tcp-flags SYN,RST SYN -o "$TUNDEV" -j TCPMSS --set-mss "$MSS"

  # dump interface configurations
  ip link show "$TUNDEV" | add_date |& tee -a "$LOG_FILE"
  ip -6 r | add_date |& tee -a "$LOG_FILE"
  ip6tables -t mangle -L | add_date |& tee -a "$LOG_FILE"
  tc -s qdisc show dev "$TUNDEV" | add_date |& tee -a "$LOG_FILE"
  echo "$TUNDEV"" interface mounted," "$SECONDS"" seconds elapsed !" | add_date |& tee -a "$LOG_FILE"

  # monitor availability of network interface
  while true; do
    INTERFACE=$(ip link show | grep "$TUNDEV")
    if [ ! "$INTERFACE" ] ; then
      echo "$TUNDEV" "interface is not available, Exiting..." | add_date |& tee -a "$LOG_FILE"
      # clean interface
      ip link set dev "$TUNDEV" down
      killall "$TUNSLIP6"
      sleep 0.1
      exit 0
    fi
    sleep "$CHECK_INTERVAL_IN_SECONDS" 
  done
}

log_setup

if [ "$1" = "setup" ] ; then
  setup "$2" "$3" "$4" "$5" "$6" "$7" "$8"
elif [ "$1" = "enable_ts" ] || [ "$1" = "disable_ts" ] ; then
  set_timesync "$1"
elif [ "$1" = "nrf" ] ; then
  set_nrf "$1" "$2"
else
  echo "osf_control - tool to control elements of osf service"
  echo "Usage:"
  echo " $0 setup [siodev] [tundev] <extra params ...> - perform osf service setup"
  echo " $0 enable_ts - enable timesync role"
  echo " $0 disable_ts - disable timesync role"
  echo " $0 nrf [powerdown|powerup|reset|down|up|dfu] [52|53|<empty is both>] - control nRF chip reset/pwr_en/dfu - lines"
  echo "    - powerdown, poweroff nRF device"
  echo "    - powerup, poweron nRF device"
  echo "    - reset, reset nRF device"
  echo "    - down, keep nRF device in reset"
  echo "    - up, release nRF device from reset"
  echo "    - dfuon, set dfu line on"
  echo "    - dfuof, set dfu line off"
  echo
  echo "    e.g. $0 reset 52"
  echo "    HOX! powerup/powerdown/dfu - commands are supported only with CM2.0"
fi

