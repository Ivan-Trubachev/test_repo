#!/bin/bash

# common constants
readonly PASS=1     # constant for PASS value
readonly FAIL=0     # constant for FAIL value

# OSF constants
readonly tests_dir="/run/current-system/sw/bin/osf/test"
readonly log_dir="/home/ghaf/osf"
readonly log_file="/home/ghaf/osf/functional_tests_debug.log"
readonly results_file="/home/ghaf/osf/functional_tests_results.log"
readonly SERIALPORT="/dev/nrf0"
readonly BAUDRATE=460800
readonly OSF_IPV6_PREFIX="fde3:"
readonly OSF_INTERFACE="osf0"
readonly OSF_MCAST_IPV6_ADDR="ff13::77"
readonly OSF_MCAST_IPV6_PORT=5007
readonly OSF52SERVICE="osf.service"

#######################################
# Check execution rights
# Globals:
# Arguments:
#######################################
check_root() {
	if [[ $EUID -ne 0 ]]; then
	    echo "This script must be run as root"
    	exit 1
	fi
}

#######################################
# Add date prefix to line and write to log
# Globals:
# Arguments:
#   debug print lines
#######################################
print_log() {

    time_stamp="$(date +'%Y-%m-%dT%H:%M:%S%z')"
    
    # create log files and give permission for all users
    mkdir -p "$log_dir"
    touch "$results_file"
    touch "$log_file"
    chmod -R a+rwx "$log_file"
    chmod -R a+rwx "$results_file"

 
    while IFS= read -r line; do
       if [ "$1" = "result" ]; then
          printf '[%s]: %s\n' "$time_stamp" "$line" |& tee -a "$results_file" |& tee -a "$log_file"
       else
          printf '[%s]: %s\n' "$time_stamp" "$line" |& tee -a "$log_file"
       fi
    done
}


