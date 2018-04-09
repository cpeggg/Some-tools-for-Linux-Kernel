#!/bin/bash

#
# Copyright 2016, Mariusz "mzet" Ziulek
#
# kernel-check-sec.sh comes with ABSOLUTELY NO WARRANTY.
# This is free software, and you are welcome to redistribute it
# under the terms of the GNU General Public License. See LICENSE
# file for usage of this software.
#

VERSION=v0.1

ARGS=
SHORTOPTS="hV"
LONGOPTS="help,version"

# bash colors
txtred="\e[0;31m"
txtgrn="\e[0;32m"
txtblu="\e[0;36m"
txtrst="\e[0m"

KCONFIG=''
KERNEL= 

# kernel security mechanisms database
declare -a MAINLINE_FEATURES

############################################################
n=0

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: GCC stack protector support
available: CONFIG_CC_STACKPROTECTOR=y
enabled: CONFIG_CC_STACKPROTECTOR=y
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: GCC stack protector STRONG support
available: CONFIG_CC_STACKPROTECTOR_STRONG=y,ver>=3.14
enabled: CONFIG_CC_STACKPROTECTOR=y
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: Low address space to protect from user allocation
available: CONFIG_DEFAULT_MMAP_MIN_ADDR
enabled: sysctl:vm.mmap_min_addr!=0
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: Hiding kernel pointers in /proc/kallsyms 
available: ver>=2.6.28 
enabled: sysctl:kernel.kptr_restrict!=0
url: 2.6.28
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: Restrict unprivileged access to kernel syslog
available: ver>=2.6.37
enabled: sysctl:kernel.dmesg_restrict!=0
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: Supervisor Mode Execution Protection (SMEP) support
available: ver>=3.0
enabled: cmd:grep -qi smep /proc/cpuinfo
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: Hardened user copy support 
available: CONFIG_HARDENED_USERCOPY=y
enabled: CONFIG_HARDENED_USERCOPY=y
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: Mark Memory As Read-Only/No-Execute
available: CONFIG_DEBUG_RODATA=y
enabled: CONFIG_DEBUG_RODATA=y
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: Restrict /dev/mem access
available: CONFIG_STRICT_DEVMEM=y
enabled: CONFIG_STRICT_DEVMEM=y
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: Restrict I/O access to /dev/mem
available: CONFIG_IO_STRICT_DEVMEM=y
enabled: CONFIG_IO_STRICT_DEVMEM=y
EOF
)

MAINLINE_FEATURES[((n++))]=$(cat <<EOF
feature: Restrict /dev/kmem access
available: CONFIG_DEVKMEM=y
enabled: CONFIG_DEVKMEM=y
EOF
)

version() {
    echo "kernel-check-sec "$VERSION", mzet, http://z-labs.eu, November 2016"
}

usage() {
    echo "Usage: kernel-check-sec.sh [OPTIONS]"
    echo
    echo " -V | --version               - print version of this script"
    echo " -h | --help                  - print this help"
    echo
}

exitWithErrMsg() {
    echo "$1" 1>&2
    exit 1
}

# taken from checksec.sh and modified accordingly
getKernelConfig() {
    if [ -f /proc/config.gz ] ; then
        KCONFIG="zcat /proc/config.gz"
        printf "Config: ${txtgrn}/proc/config.gz${txtrst}\n\n"
    elif [ -f /boot/config-`uname -r` ] ; then
        KCONFIG="cat /boot/config-`uname -r`"
        printf "Config: ${txtgrn}/boot/config-`uname -r`${txtrst}\n\n"
        printf "  Warning: The config on disk may not represent running kernel config!\n\n";
    elif [ -f "${KBUILD_OUTPUT:-/usr/src/linux}"/.config ] ; then
        KCONFIG="cat ${KBUILD_OUTPUT:-/usr/src/linux}/.config"
        printf "Config: ${txtgrn}%s${txtrst}\n\n" "${KBUILD_OUTPUT:-/usr/src/linux}/.config"
        printf "  Warning: The config on disk may not represent running kernel config!\n\n";
    else
        printf "Config: ${txtred}NOT FOUND${txtgrn}\n\n"
        printf "  Warning: The kernel config is not present. Script's output will be based only on /proc/sys (sysctl -a) and /proc/cmdline content which could generate false/incomplete results.\n\n";
    fi
}

# from: https://stackoverflow.com/questions/4023830/how-compare-two-strings-in-dot-separated-version-format-in-bash
verComparision() {

    if [[ $1 == $2 ]]
    then
        return 0
    fi

    local IFS=.
    local i ver1=($1) ver2=($2)

    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done

    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done

    return 0
}

compareValues() {
    curVal=$1
    val=$2
    sign=$3

    if [ "$sign" == "==" ]; then
        [ "$val" == "$curVal" ] && return 0
    elif [ "$sign" == "!=" ]; then
        [ "$val" != "$curVal" ] && return 0
    fi

    return 1
}

checkRequirement() {
    #echo "Checking requirement: $1"
    local IN="$1"

    if [[ "$IN" =~ ^CONFIG_.*$ ]]; then
        if $KCONFIG | grep -qi $IN; then
            return 0;
        fi
    elif [[ "$IN" =~ ^ver.*$ ]]; then
        req_kernel="${IN//[^0-9.]/}"
        verComparision $KERNEL $req_kernel
        [ $? = 0 -o $? = 1 ] && return 0
    elif [[ "$IN" =~ ^sysctl:.*$ ]]; then
        sysctlCondition="${IN:7}"
  
        # extract sysctl entry, relation sign and required value
        if echo $sysctlCondition | grep -qi "!="; then
            sign="!="
        elif echo $sysctlCondition | grep -qi "=="; then
            sign="=="
        else
            exitWithErrMsg "Wrong sysctl condition. There is syntax error in your features DB. Aborting."
        fi
        val=$(echo "$sysctlCondition" | awk -F "$sign" '{print $2}')
        entry=$(echo "$sysctlCondition" | awk -F "$sign" '{print $1}')

        # get current setting of sysctl entry
        curVal=$(sysctl -a 2> /dev/null | grep $entry | awk -F'=' '{print $2}')

        # compare & return result
        compareValues $curVal $val $sign && return 0

    elif [[ "$IN" =~ ^cmd:.*$ ]]; then
        cmd="${IN:4}"
        if eval "$cmd"; then
            return 0
        fi
    fi

    return 1
}

# parse command line parameters
ARGS=$(getopt --options $SHORTOPTS  --longoptions $LONGOPTS -- "$@")
[ $? != 0 ] && exitWithErrMsg "Aborting."

eval set -- "$ARGS"

while true; do
    case "$1" in
        -V|--version)
            version
            exit 0
            ;;
        -h|--help)
            usage 
            exit 0
            ;;
        *)
            shift
            if [ "$#" != "0" ] ; then
                 exitWithErrMsg "Unknown option '$1'. Aborting."
            fi
            break
            ;;
    esac
    shift
done

getKernelConfig

KERNEL=$(uname -a | awk '{print $3}' | cut -d '-' -f 1)

# start analysis
for FEATURE in "${MAINLINE_FEATURES[@]}"; do

    # create array from current exploit here doc and fetch needed lines
    i=0
    # ('-r' is used to not interpret backslash used for bash colors)
    while read -r line
    do
        arr[i]="$line"
        i=$((i + 1))
    done <<< "$FEATURE"

    NAME="${arr[0]}" && NAME="${NAME:9}"
    AVAILABLE="${arr[1]}" && AVAILABLE="${AVAILABLE:11}"
    ENABLE="${arr[2]}" && ENABLE="${ENABLE:9}"

    # split line with availability requirements & loop thru all availability reqs one by one & check whether it is met
    IFS=',' read -r -a array <<< "$AVAILABLE"
    AVAILABLE_REQS_NUM=${#array[@]}
    AVAILABLE_PASSED_REQ=0
    for REQ in "${array[@]}"; do
        if (checkRequirement "$REQ"); then
            AVAILABLE_PASSED_REQ=$(($AVAILABLE_PASSED_REQ + 1))
        else
            break
        fi
    done

    # split line with enablement requirements & loop thru all enablement reqs one by one & check whether it is met
    IFS=',' read -r -a array <<< "$ENABLE"
    ENABLE_REQS_NUM=${#array[@]}
    ENABLE_PASSED_REQ=0
    for REQ in "${array[@]}"; do
        if (checkRequirement "$REQ"); then
            ENABLE_PASSED_REQ=$(($ENABLE_PASSED_REQ + 1))
        else
            break
        fi
    done

    feature=$(echo "$FEATURE" | grep "feature: " | cut -d' ' -f 2-)

    available="${txtred}Available${txtrst}"
    enabled="${txtred}Disabled${txtrst}"

    if [ $AVAILABLE_PASSED_REQ -eq $AVAILABLE_REQS_NUM ]; then
        available="${txtgrn}Available${txtrst}"
    fi

    if [ $ENABLE_PASSED_REQ -eq $ENABLE_REQS_NUM ]; then
        enabled="${txtgrn}Enabled${txtrst}"
    fi

    echo -e "[ $available ][ $enabled ] $feature"

done