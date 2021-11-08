#!/bin/bash

# Yet Another Bench Script by Mason Rowe
# Initial Oct 2019; Last update Oct 2021
#
# Disclaimer: This project is a work in progress. Any errors or suggestions should be
#             relayed to me via the GitHub project page linked below.
#
# Purpose:    The purpose of this script is to quickly gauge the performance of a Linux-
#             based server by benchmarking network performance via iperf3, CPU and
#             overall system performance via Geekbench 4/5, and random disk
#             performance via fio. The script is designed to not require any dependencies
#             - either compiled or installed - nor admin privileges to run.
#

echo -e '# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #'
echo -e '#              Yet-Another-Bench-Script              #'
echo -e '#                     v2021-10-09                    #'
echo -e '# https://github.com/masonr/yet-another-bench-script #'
echo -e '# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #'

echo -e
date

# override locale to eliminate parsing errors (i.e. using commas as delimiters rather than periods)
export LC_ALL=C

# determine architecture of host
ARCH=$(uname -m)
if [[ $ARCH = *aarch* || $ARCH = *arm* ]]; then
	KERNEL_BIT=`getconf LONG_BIT`
	if [[ $KERNEL_BIT = *64* ]]; then
		# host is running an ARM 64-bit kernel
		ARCH="aarch64"
	else
		# host is running an ARM 32-bit kernel
		ARCH="arm"
	fi
	echo -e "\nARM-compatibility is considered *experimental*"
elif [[ $ARCH = *x86_64* ]]; then
	# host is running a 64-bit kernel
	ARCH="x64"
elif [[ $ARCH = *i?86* ]]; then
	# host is running a 32-bit kernel
	ARCH="x86"
else
	# host is running a non-supported kernel
	echo -e "Architecture not supported by YABS."
	exit 1
fi

# flags to skip certain performance tests
unset SKIP_FIO SKIP_IPERF SKIP_GEEKBENCH PRINT_HELP REDUCE_NET GEEKBENCH_4 GEEKBENCH_5 DD_FALLBACK IPERF_DL_FAIL
GEEKBENCH_5="True" # gb5 test enabled by default

# get any arguments that were passed to the script and set the associated skip flags (if applicable)
while getopts 'fdighr49' flag; do
	case "${flag}" in
		f) SKIP_FIO="True" ;;
		d) SKIP_FIO="True" ;;
		i) SKIP_IPERF="True" ;;
		g) SKIP_GEEKBENCH="True" ;;
		h) PRINT_HELP="True" ;;
		r) REDUCE_NET="True" ;;
		4) GEEKBENCH_4="True" && unset GEEKBENCH_5 ;;
		9) GEEKBENCH_4="True" && GEEKBENCH_5="True" ;;
		*) exit 1 ;;
	esac
done

# check for local fio/iperf installs
command -v fio >/dev/null 2>&1 && LOCAL_FIO=true || unset LOCAL_FIO
if [[ "$OSTYPE" == *arwin* && "$LOCAL_FIO" != "true" ]]; then
	SKIP_FIO="True"
fi
command -v iperf3 >/dev/null 2>&1 && LOCAL_IPERF=true || unset LOCAL_IPERF
if [[ "$OSTYPE" == *arwin* && "$LOCAL_IPERF" != "true" ]]; then
	SKIP_IPERF="True"
fi

# test if the host has IPv4/IPv6 connectivity
if [[ $OSTYPE == *arwin* ]]; then
	CMD_PING_6=ping6
	OPT_PING_4=""
else
	CMD_PING_6="ping -6"
	OPT_PING_4="-4"
fi
IPV4_CHECK=$((ping $OPT_PING_4 -c 1 -W 4 ipv4.google.com >/dev/null 2>&1 && echo true) || curl -s -4 -m 4 icanhazip.com 2> /dev/null)
IPV6_CHECK=$(($CMD_PING_6 -c 1 -W 4 ipv6.google.com >/dev/null 2>&1 && echo true) || curl -s -6 -m 4 icanhazip.com 2> /dev/null)

# print help and exit script, if help flag was passed
if [ ! -z "$PRINT_HELP" ]; then
	echo -e
	echo -e "Usage: ./yabs.sh [-fdighr49]"
	echo -e "       curl -sL yabs.sh | bash"
	echo -e "       curl -sL yabs.sh | bash -s -- -{fdighr49}"
	echo -e
	echo -e "Flags:"
	echo -e "       -f/d : skips the fio disk benchmark test"
	echo -e "              On OSX, to obtain fio : brew install fio"
	echo -e "       -i : skips the iperf network test"
	echo -e "              On OSX, to obtain iperf : brew install iperf3"
	echo -e "       -g : skips the geekbench performance test"
	echo -e "       -h : prints this lovely message, shows any flags you passed,"
	echo -e "            shows if fio/iperf3 local packages have been detected,"
	echo -e "            then exits"
	echo -e "       -r : reduce number of iperf3 network locations (to only three)"
	echo -e "            to lessen bandwidth usage"
	echo -e "       -4 : use geekbench 4 instead of geekbench 5"
	echo -e "       -9 : use both geekbench 4 AND geekbench 5"
	echo -e
	echo -e "Detected Arch: $ARCH"
	echo -e
	echo -e "Detected Flags:"
	[[ ! -z $SKIP_FIO ]] && echo -e "       -f/d, skipping fio disk benchmark test"
	[[ ! -z $SKIP_IPERF ]] && echo -e "       -i, skipping iperf network test"
	[[ ! -z $SKIP_GEEKBENCH ]] && echo -e "       -g, skipping geekbench test"
	[[ ! -z $REDUCE_NET ]] && echo -e "       -r, using reduced (3) iperf3 locations"
	[[ ! -z $GEEKBENCH_4 ]] && echo -e "       running geekbench 4"
	[[ ! -z $GEEKBENCH_5 ]] && echo -e "       running geekbench 5"
	echo -e
	echo -e "Local Binary Check:"
	[[ -z $LOCAL_FIO ]] && echo -e "       fio not detected, will download precompiled binary" ||
		echo -e "       fio detected, using local package"
	[[ -z $LOCAL_IPERF ]] && echo -e "       iperf3 not detected, will download precompiled binary" ||
		echo -e "       iperf3 detected, using local package"
	echo -e
	echo -e "Detected Connectivity:"
	[[ ! -z $IPV4_CHECK ]] && echo -e "       IPv4 connected" ||
		echo -e "       IPv4 not connected"
	[[ ! -z $IPV6_CHECK ]] && echo -e "       IPv6 connected" ||
		echo -e "       IPv6 not connected"
	echo -e
	echo -e "Exiting..."

	exit 0
fi

# format_size
# Purpose: Formats raw disk and memory sizes from kibibytes (KiB) to largest unit
# Parameters:
#          1. RAW - the raw memory size (RAM/Swap) in kibibytes
# Returns:
#          Formatted memory size in KiB, MiB, GiB, or TiB
function format_size {
	RAW=$1 # mem size in KiB
	RESULT=$RAW
	local DENOM=1
	local UNIT="KiB"

	# ensure the raw value is a number, otherwise return blank
	re='^[0-9]+$'
	if ! [[ $RAW =~ $re ]] ; then
		echo "" 
		return 0
	fi

	if [ "$RAW" -ge 1073741824 ]; then
		DENOM=1073741824
		UNIT="TiB"
	elif [ "$RAW" -ge 1048576 ]; then
		DENOM=1048576
		UNIT="GiB"
	elif [ "$RAW" -ge 1024 ]; then
		DENOM=1024
		UNIT="MiB"
	fi

	# divide the raw result to get the corresponding formatted result (based on determined unit)
	RESULT=$(awk -v a="$RESULT" -v b="$DENOM" 'BEGIN { print a / b }')
	# shorten the formatted result to two decimal places (i.e. x.x)
	RESULT=$(echo $RESULT | awk -F. '{ printf "%0.1f",$1"."substr($2,1,2) }')
	# concat formatted result value with units and return result
	RESULT="$RESULT $UNIT"
	echo $RESULT
}

# gather basic system information (inc. CPU, AES-NI/virt status, RAM + swap + disk size)
echo -e 
echo -e "Basic System Information:"
echo -e "---------------------------------"
if [[ $OSTYPE = *arwin*  && $ARCH = "x64" ]]; then
	CPU_PROC=$(sysctl machdep.cpu.brand_string | sed 's/^.*: //g')
elif [[ $OSTYPE = *arwin*  && $ARCH = *aarch64* ]]; then
	CPU_PROC=$(sysctl machdep.cpu.brand_string | sed 's/^.*: //g')
elif [[ $ARCH = *aarch64* || $ARCH = *arm* ]]; then
	CPU_PROC=$(lscpu | grep "Model name" | sed 's/Model name: *//g')
else
	CPU_PROC=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
fi

echo -e "Processor  : $CPU_PROC"
if [[ $OSTYPE = *arwin*  && $ARCH == "x64" ]]; then
	CPU_CORES=$(sysctl machdep.cpu.core_count | sed 's/^.*: //g')
	CPU_FREQ=$(sysctl machdep.cpu.brand_string | sed -e 's/^.*@ //g' | sed 's/G/ G/g' | sed 's/M/ M/g')
elif [[ $OSTYPE = *arwin* && $ARCH == *aarch64*  ]]; then
	identif=$( system_profiler SPHardwareDataType | grep -i "Identifier" | sed 's/^.*: //' | tr '[:upper:]' '[:lower:]')
	CPU_FREQ=""
#	case $identif in
#		macmini9,1 ) 
#			CPU_FREQ="3.2Ghz"
#			;;
#		*) 
#			CPU_FREQ="3.2Ghz"
#			;;
#	esac
	CPU_CORES=$(sysctl machdep.cpu.core_count | sed 's/^.*: //g')
elif [[ $ARCH = *aarch64* || $ARCH = *arm* ]]; then
	CPU_CORES=$(lscpu | grep "^[[:blank:]]*CPU(s):" | sed 's/CPU(s): *//g')
	CPU_FREQ=$(lscpu | grep "CPU max MHz" | sed 's/CPU max MHz: *//g')
	[[ -z "$CPU_FREQ" ]] && CPU_FREQ="???"
	CPU_FREQ="${CPU_FREQ} MHz"
else
	CPU_CORES=$(awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo)
	CPU_FREQ=$(awk -F: ' /cpu MHz/ {freq=$2} END {print freq " MHz"}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
fi
echo -e "CPU cores  : $CPU_CORES @ $CPU_FREQ"
if [[ "$OSTYPE" == *"arwin"* ]]; then
	CPU_AES=$(sysctl machdep.cpu.features | grep -i aes)
else
	CPU_AES=$(cat /proc/cpuinfo | grep aes)
fi
[[ -z "$CPU_AES" ]] && CPU_AES="\xE2\x9D\x8C Disabled" || CPU_AES="\xE2\x9C\x94 Enabled"
echo -e "AES-NI     : $CPU_AES"
if [[ "$OSTYPE" == *"arwin"* ]]; then
	CPU_VIRT=$(sysctl machdep.cpu.features | grep -i 'vmx\|svm')
else
	CPU_VIRT=$(cat /proc/cpuinfo | grep 'vmx\|svm')
fi
[[ -z "$CPU_VIRT" ]] && CPU_VIRT="\xE2\x9D\x8C Disabled" || CPU_VIRT="\xE2\x9C\x94 Enabled"
echo -e "VM-x/AMD-V : $CPU_VIRT"
if [[ "$OSTYPE" == *"arwin"* ]]; then
	TOTAL_RAM=$(system_profiler SPHardwareDataType | grep -i "Memory" | awk '{print $2" "$3}')
else
	TOTAL_RAM=$(format_size "$(free | awk 'NR==2 {print $2}')")
fi
echo -e "RAM        : $TOTAL_RAM"
if [[ "$OSTYPE" == *"arwin"* ]]; then
	TOTAL_SWAP=$(sysctl vm.swapusage | sed 's/^.*l = //' | sed 's/used.*$//'  |  sed -r 's/([0-9])([a-zA-Z])/\1 \2iB/g')
else
	TOTAL_SWAP=$(format_size "$(free | grep Swap | awk '{ print $2 }')")
fi
echo -e "Swap       : $TOTAL_SWAP"
# total disk size is calculated by adding all partitions of the types listed below (after the -t flags)
if [[ $OSTYPE == *arwin* ]]; then
	TOTAL_DISK=$(df -h | head -2 | tail -1| awk '{print $2}')
else
	TOTAL_DISK=$(format_size $(df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs -t swap --total 2>/dev/null | grep total | awk '{ print $2 }'))
fi
echo -e "Disk       : $TOTAL_DISK"

# create a directory in the same location that the script is being run to temporarily store YABS-related files
if [[ "$OSTYPE" == *"arwin"* ]]; then
	DATE=$(date '+%Y-%m-%d%Z%H_%M_%S+%s')
else
	DATE=$(date -Iseconds | sed -e "s/:/_/g")
fi
YABS_PATH=./$DATE
touch $DATE.test 2> /dev/null
# test if the user has write permissions in the current directory and exit if not
if [ ! -f "$DATE.test" ]; then
	echo -e
	echo -e "You do not have write permission in this directory. Switch to an owned directory and re-run the script.\nExiting..."
	exit 1
fi
rm $DATE.test
mkdir -p $YABS_PATH

# trap CTRL+C signals to exit script cleanly
trap catch_abort INT

# catch_abort
# Purpose: This method will catch CTRL+C signals in order to exit the script cleanly and remove
#          yabs-related files.
function catch_abort() {
	echo -e "\n** Aborting YABS. Cleaning up files...\n"
	rm -rf $YABS_PATH
	unset LC_ALL
	exit 0
}

# format_speed
# Purpose: This method is a convenience function to format the output of the fio disk tests which
#          always returns a result in KB/s. If result is >= 1 GB/s, use GB/s. If result is < 1 GB/s
#          and >= 1 MB/s, then use MB/s. Otherwise, use KB/s.
# Parameters:
#          1. RAW - the raw disk speed result (in KB/s)
# Returns:
#          Formatted disk speed in GB/s, MB/s, or KB/s
function format_speed {
	RAW=$1 # disk speed in KB/s
	RESULT=$RAW
	local DENOM=1
	local UNIT="KB/s"

	# ensure raw value is not null, if it is, return blank
	if [ -z "$RAW" ]; then
		echo ""
		return 0
	fi

	# check if disk speed >= 1 GB/s
	if [ "$RAW" -ge 1000000 ]; then
		DENOM=1000000
		UNIT="GB/s"
	# check if disk speed < 1 GB/s && >= 1 MB/s
	elif [ "$RAW" -ge 1000 ]; then
		DENOM=1000
		UNIT="MB/s"
	fi

	# divide the raw result to get the corresponding formatted result (based on determined unit)
	RESULT=$(awk -v a="$RESULT" -v b="$DENOM" 'BEGIN { print a / b }')
	# shorten the formatted result to two decimal places (i.e. x.xx)
	RESULT=$(echo $RESULT | awk -F. '{ printf "%0.2f",$1"."substr($2,1,2) }')
	# concat formatted result value with units and return result
	RESULT="$RESULT $UNIT"
	echo $RESULT
}

# format_iops
# Purpose: This method is a convenience function to format the output of the raw IOPS result
# Parameters:
#          1. RAW - the raw IOPS result
# Returns:
#          Formatted IOPS (i.e. 8, 123, 1.7k, 275.9k, etc.)
function format_iops {
	RAW=$1 # iops
	RESULT=$RAW

	# ensure raw value is not null, if it is, return blank
	if [ -z "$RAW" ]; then
		echo ""
		return 0
	fi

	# check if IOPS speed > 1k
	if [ "$RAW" -ge 1000 ]; then
		# divide the raw result by 1k
		RESULT=$(awk -v a="$RESULT" 'BEGIN { print a / 1000 }')
		# shorten the formatted result to one decimal place (i.e. x.x)
		RESULT=$(echo $RESULT | awk -F. '{ printf "%0.1f",$1"."substr($2,1,1) }')
		RESULT="$RESULT"k
	fi

	echo $RESULT
}

# disk_test
# Purpose: This method is designed to test the disk performance of the host using the partition that the
#          script is being run from using fio random read/write speed tests.
# Parameters:
#          - (none)
function disk_test {
	if [[ "$ARCH" = "aarch64" || "$ARCH" = "arm" ]]; then
		FIO_SIZE=512M
	else
		FIO_SIZE=2G
	fi

	if [[ "$OSTYPE" == *arwin* ]]; then
		# Image libaio not available on OSX
		CMD_TIMEOUT=""
		OPT_IOENGINE=""
	else
		CMD_TIMEOUT="timeout 35 "
		OPT_IOENGINE="--ioengine=libaio "
	fi
	# run a quick test to generate the fio test file to be used by the actual tests
	echo -en "Generating fio test file..."
	$FIO_CMD --name=setup $OPT_IOENGINE --rw=read --bs=64k --iodepth=64 --numjobs=2 --size=$FIO_SIZE --runtime=1 --gtod_reduce=1 --filename=$DISK_PATH/test.fio --direct=1 --minimal &> /dev/null
	echo -en "\r\033[0K"

	# get array of block sizes to evaluate
	BLOCK_SIZES=("$@")

	for BS in "${BLOCK_SIZES[@]}"; do
		# run rand read/write mixed fio test with block size = $BS
		echo -en "Running fio random mixed R+W disk test with $BS block size..."
		DISK_TEST=$(timeout 35 $FIO_CMD --name=rand_rw_$BS $OPT_IOENGINE --rw=randrw --rwmixread=50 --bs=$BS --iodepth=64 --numjobs=2 --size=$FIO_SIZE --runtime=30 --gtod_reduce=1 --direct=1 --filename=$DISK_PATH/test.fio --group_reporting --minimal 2> /dev/null | grep rand_rw_$BS)
		DISK_IOPS_R=$(echo $DISK_TEST | awk -F';' '{print $8}')
		DISK_IOPS_W=$(echo $DISK_TEST | awk -F';' '{print $49}')
		DISK_IOPS=$(format_iops $(awk -v a="$DISK_IOPS_R" -v b="$DISK_IOPS_W" 'BEGIN { print a + b }'))
		DISK_IOPS_R=$(format_iops $DISK_IOPS_R)
		DISK_IOPS_W=$(format_iops $DISK_IOPS_W)
		DISK_TEST_R=$(echo $DISK_TEST | awk -F';' '{print $7}')
		DISK_TEST_W=$(echo $DISK_TEST | awk -F';' '{print $48}')
		DISK_TEST=$(format_speed $(awk -v a="$DISK_TEST_R" -v b="$DISK_TEST_W" 'BEGIN { print a + b }'))
		DISK_TEST_R=$(format_speed $DISK_TEST_R)
		DISK_TEST_W=$(format_speed $DISK_TEST_W)

		DISK_RESULTS+=( "$DISK_TEST" "$DISK_TEST_R" "$DISK_TEST_W" "$DISK_IOPS" "$DISK_IOPS_R" "$DISK_IOPS_W" )
		echo -en "\r\033[0K"
	done
}

# dd_test
# Purpose: This method is invoked if the fio disk test failed. dd sequential speed tests are
#          not indiciative or real-world results, however, some form of disk speed measure 
#          is better than nothing.
# Parameters:
#          - (none)
function dd_test {
	I=0
	DISK_WRITE_TEST_RES=()
	DISK_READ_TEST_RES=()
	DISK_WRITE_TEST_AVG=0
	DISK_READ_TEST_AVG=0

	# run the disk speed tests (write and read) thrice over
	while [ $I -lt 3 ]
	do
		# write test using dd, "direct" flag is used to test direct I/O for data being stored to disk
		oflag="oflag=direct"
		copied="copied"
		if [[ $OSTYPE == *arwin* ]]; then
			# OSX doesn't support oflag
			oflag=""
			copied="transferred"
		fi
		DISK_WRITE_TEST=$(dd if=/dev/zero of=$DISK_PATH/$DATE.test bs=64k count=16k $oflag 2>&1 | grep $copied | awk '{ print $(NF-1) " " $(NF)}')
		if [[ $OSTYPE == *arwin* ]]; then 
			if [[ $(echo "$DISK_WRITE_TEST" | grep "bytes/sec") ]]; then
				DISK_WRITE_TEST=$(echo $DISK_WRITE_TEST | sed -E -e 's/\(|\)//g')
				num=$(echo $DISK_WRITE_TEST | sed 's/ .*$//g')
				if [[ $num -gt 1024 ]]; then
					num=$(( num / 1024 ))
					DISK_WRITE_TEST="$num KB/s"
					if [[ $num -gt 1024 ]]; then
						num=$(( num / 1024 ))
						DISK_WRITE_TEST="$num MB/s"
					fi
				else
					DISK_WRITE_TEST="$num B/s"
				fi
			fi
		fi
		VAL=$(echo $DISK_WRITE_TEST | cut -d " " -f 1)
		[[ "$DISK_WRITE_TEST" == *"GB"* ]] && VAL=$(awk -v a="$VAL" 'BEGIN { print a * 1000 }')
		DISK_WRITE_TEST_RES+=( "$DISK_WRITE_TEST" )
		DISK_WRITE_TEST_AVG=$(awk -v a="$DISK_WRITE_TEST_AVG" -v b="$VAL" 'BEGIN { print a + b }')

		# read test using dd using the 1G file written during the write test-E
		DISK_READ_TEST=$(dd if=$DISK_PATH/$DATE.test of=/dev/null bs=8k 2>&1 | grep $copied | awk '{ print $(NF-1) " " $(NF)}')
		if [[ $OSTYPE == *arwin* ]]; then 
			if [[ $(echo "$DISK_READ_TEST" | grep "bytes/sec") ]]; then
				DISK_READ_TEST=$(echo $DISK_READ_TEST | sed -E -e 's/\(|\)//g')
				num=$(echo $DISK_READ_TEST | sed 's/ .*$//g')
				if [[ $num -gt 1024 ]]; then
					num=$(( num / 1024 ))
					DISK_READ_TEST="$num KB/s"
					if [[ $num -gt 1024 ]]; then
						num=$(( num / 1024 ))
						DISK_READ_TEST="$num MB/s"
					fi
				else
					DISK_READ_TEST="$num B/s"
				fi
			fi
		fi
		VAL=$(echo $DISK_READ_TEST | cut -d " " -f 1)
		[[ "$DISK_READ_TEST" == *"GB"* ]] && VAL=$(awk -v a="$VAL" 'BEGIN { print a * 1000 }')
		DISK_READ_TEST_RES+=( "$DISK_READ_TEST" )
		DISK_READ_TEST_AVG=$(awk -v a="$DISK_READ_TEST_AVG" -v b="$VAL" 'BEGIN { print a + b }')

		I=$(( $I + 1 ))
	done
	# calculate the write and read speed averages using the results from the three runs
	DISK_WRITE_TEST_AVG=$(awk -v a="$DISK_WRITE_TEST_AVG" 'BEGIN { print a / 3 }')
	DISK_READ_TEST_AVG=$(awk -v a="$DISK_READ_TEST_AVG" 'BEGIN { print a / 3 }')
}

# check if disk performance is being tested and the host has required space (2G)
AVAIL_SPACE=`df -k . | awk 'NR==2{print $4}'`
if [[ -z "$SKIP_FIO" && "$AVAIL_SPACE" -lt 2097152 && "$ARCH" != "aarch64" && "$ARCH" != "arm" ]]; then # 2GB = 2097152KB
	echo -e "\nLess than 2GB of space available. Skipping disk test..."
elif [[ -z "$SKIP_FIO" && "$AVAIL_SPACE" -lt 524288 && ("$ARCH" = "aarch64" || "$ARCH" = "arm") ]]; then # 512MB = 524288KB
	echo -e "\nLess than 512MB of space available. Skipping disk test..."
# if the skip disk flag was set, skip the disk performance test, otherwise test disk performance
elif [ -z "$SKIP_FIO" ]; then
	# Perform ZFS filesystem detection and determine if we have enough free space according to spa_asize_inflation
	ZFSCHECK="/sys/module/zfs/parameters/spa_asize_inflation"
	if [[ -f "$ZFSCHECK" ]];then
		mul_spa=$((($(cat /sys/module/zfs/parameters/spa_asize_inflation)*2)))
		warning=0
		poss=()

		for pathls in $(df -Th | awk '{print $7}' | tail -n +2)
		do
			if [[ "${PWD##$pathls}" != "${PWD}" ]]; then
				poss+=($pathls)
			fi
		done

		long=""
		m=-1
		for x in ${poss[@]}
		do
			if [ ${#x} -gt $m ];then
				m=${#x}
				long=$x
			fi
		done

		size_b=$(df -Th | grep -w $long | grep -i zfs | awk '{print $5}' | tail -c 2 | head -c 1)
		free_space=$(df -Th | grep -w $long | grep -i zfs | awk '{print $5}' | head -c -2)

		if [[ $size_b == 'T' ]]; then
			free_space=$(bc <<< "$free_space*1024")
			size_b='G'
		fi

		if [[ $(df -Th | grep -w $long) == *"zfs"* ]];then

			if [[ $size_b == 'G' ]]; then
				if [[ $(echo "$free_space < $mul_spa" | bc) -ne 0 ]];then
					warning=1
				fi
			else
				warning=1
			fi

		fi

		if [[ $warning -eq 1 ]];then
			echo -en "\nWarning! You are running YABS on a ZFS Filesystem and your disk space is too low for the fio test. Your test results will be inaccurate. You need at least $mul_spa GB free in order to complete this test accurately. For more information, please see https://github.com/masonr/yet-another-bench-script/issues/13\n"
		fi
	fi
	
	echo -en "\nPreparing system for disk tests..."

	# create temp directory to store disk write/read test files
	DISK_PATH=$YABS_PATH/disk
	mkdir -p $DISK_PATH

	if [ ! -z "$LOCAL_FIO" ]; then # local fio has been detected, use instead of pre-compiled binary
		FIO_CMD=fio
	else
		# download fio binary
		if [ ! -z "$IPV4_CHECK" ]; then # if IPv4 is enabled
			curl -s -4 --connect-timeout 5 --retry 5 --retry-delay 0 https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/fio_$ARCH -o $DISK_PATH/fio
		else # no IPv4, use IPv6 - below is necessary since raw.githubusercontent.com has no AAAA record
			curl -s -6 --connect-timeout 5 --retry 5 --retry-delay 0 -k -g --header 'Host: raw.githubusercontent.com' https://[2a04:4e42::133]/masonr/yet-another-bench-script/master/bin/fio_$ARCH -o $DISK_PATH/fio
		fi

		if [ ! -f "$DISK_PATH/fio" ]; then # ensure fio binary download successfully
			echo -en "\r\033[0K"
			echo -e "Fio binary download failed. Running dd test as fallback...."
			DD_FALLBACK=True
		else
			chmod +x $DISK_PATH/fio
			FIO_CMD=$DISK_PATH/fio
		fi
	fi

	if [ -z "$DD_FALLBACK" ]; then # if not falling back on dd tests, run fio test
		echo -en "\r\033[0K"

		# init global array to store disk performance values
		declare -a DISK_RESULTS
		# disk block sizes to evaluate
		BLOCK_SIZES=( "4k" "64k" "512k" "1m" )

		# execute disk performance test
		disk_test "${BLOCK_SIZES[@]}"
	fi

	if [[ ! -z "$DD_FALLBACK" || ${#DISK_RESULTS[@]} -eq 0 ]]; then # fio download failed or test was killed or returned an error, run dd test instead
		if [ -z "$DD_FALLBACK" ]; then # print error notice if ended up here due to fio error
			echo -e "fio disk speed tests failed. Run manually to determine cause.\nRunning dd test as fallback..."
		fi

		dd_test

		# format the speed averages by converting to GB/s if > 1000 MB/s
		if [ $(echo $DISK_WRITE_TEST_AVG | cut -d "." -f 1) -ge 1000 ]; then
			DISK_WRITE_TEST_AVG=$(awk -v a="$DISK_WRITE_TEST_AVG" 'BEGIN { print a / 1000 }')
			DISK_WRITE_TEST_UNIT="GB/s"
		else
			DISK_WRITE_TEST_UNIT="MB/s"
		fi
		if [ $(echo $DISK_READ_TEST_AVG | cut -d "." -f 1) -ge 1000 ]; then
			DISK_READ_TEST_AVG=$(awk -v a="$DISK_READ_TEST_AVG" 'BEGIN { print a / 1000 }')
			DISK_READ_TEST_UNIT="GB/s"
		else
			DISK_READ_TEST_UNIT="MB/s"
		fi

		# print dd sequential disk speed test results
		echo -e
		echo -e "dd Sequential Disk Speed Tests:"
		echo -e "---------------------------------"
		printf "%-6s | %-6s %-4s | %-6s %-4s | %-6s %-4s | %-6s %-4s\n" "" "Test 1" "" "Test 2" ""  "Test 3" "" "Avg" ""
		printf "%-6s | %-6s %-4s | %-6s %-4s | %-6s %-4s | %-6s %-4s\n"
		printf "%-6s | %-11s | %-11s | %-11s | %-6.2f %-4s\n" "Write" "${DISK_WRITE_TEST_RES[0]}" "${DISK_WRITE_TEST_RES[1]}" "${DISK_WRITE_TEST_RES[2]}" "${DISK_WRITE_TEST_AVG}" "${DISK_WRITE_TEST_UNIT}" 
		printf "%-6s | %-11s | %-11s | %-11s | %-6.2f %-4s\n" "Read" "${DISK_READ_TEST_RES[0]}" "${DISK_READ_TEST_RES[1]}" "${DISK_READ_TEST_RES[2]}" "${DISK_READ_TEST_AVG}" "${DISK_READ_TEST_UNIT}" 
	else # fio tests completed successfully, print results
		DISK_RESULTS_NUM=$(expr ${#DISK_RESULTS[@]} / 6)
		DISK_COUNT=0

		# print disk speed test results
		echo -e "fio Disk Speed Tests (Mixed R/W 50/50):"
		echo -e "---------------------------------"

		while [ $DISK_COUNT -lt $DISK_RESULTS_NUM ] ; do
			if [ $DISK_COUNT -gt 0 ]; then printf "%-10s | %-20s | %-20s\n"; fi
			printf "%-10s | %-11s %8s | %-11s %8s\n" "Block Size" "${BLOCK_SIZES[DISK_COUNT]}" "(IOPS)" "${BLOCK_SIZES[DISK_COUNT+1]}" "(IOPS)"
			printf "%-10s | %-11s %8s | %-11s %8s\n" "  ------" "---" "---- " "----" "---- "
			printf "%-10s | %-11s %8s | %-11s %8s\n" "Read" "${DISK_RESULTS[DISK_COUNT*6+1]}" "(${DISK_RESULTS[DISK_COUNT*6+4]})" "${DISK_RESULTS[(DISK_COUNT+1)*6+1]}" "(${DISK_RESULTS[(DISK_COUNT+1)*6+4]})"
			printf "%-10s | %-11s %8s | %-11s %8s\n" "Write" "${DISK_RESULTS[DISK_COUNT*6+2]}" "(${DISK_RESULTS[DISK_COUNT*6+5]})" "${DISK_RESULTS[(DISK_COUNT+1)*6+2]}" "(${DISK_RESULTS[(DISK_COUNT+1)*6+5]})"
			printf "%-10s | %-11s %8s | %-11s %8s\n" "Total" "${DISK_RESULTS[DISK_COUNT*6]}" "(${DISK_RESULTS[DISK_COUNT*6+3]})" "${DISK_RESULTS[(DISK_COUNT+1)*6]}" "(${DISK_RESULTS[(DISK_COUNT+1)*6+3]})"
			DISK_COUNT=$(expr $DISK_COUNT + 2)
		done
	fi
fi

# iperf_test
# Purpose: This method is designed to test the network performance of the host by executing an
#          iperf3 test to/from the public iperf server passed to the function. Both directions 
#          (send and receive) are tested.
# Parameters:
#          1. URL - URL/domain name of the iperf server
#          2. PORTS - the range of ports on which the iperf server operates
#          3. HOST - the friendly name of the iperf server host/owner
#          4. FLAGS - any flags that should be passed to the iperf command
function iperf_test {
	URL=$1
	PORTS=$2
	HOST=$3
	FLAGS=$4
	
	# attempt the iperf send test 5 times, allowing for a slot to become available on the
	#   server or to throw out any bad/error results
	I=1
	while [ $I -le 5 ]
	do
		echo -en "Performing $MODE iperf3 send test to $HOST (Attempt #$I of 5)..."
		# select a random iperf port from the range provided
		PORT=$(shuf -i $PORTS -n 1)
		# run the iperf test sending data from the host to the iperf server; includes
		#   a timeout of 15s in case the iperf server is not responding; uses 8 parallel
		#   threads for the network test
		IPERF_RUN_SEND="$(timeout 15 $IPERF_CMD $FLAGS -c $URL -p $PORT -P 8 2> /dev/null)"
		# check if iperf exited cleanly and did not return an error
		if [[ "$IPERF_RUN_SEND" == *"receiver"* && "$IPERF_RUN_SEND" != *"error"* ]]; then
			# test did not result in an error, parse speed result
			SPEED=$(echo "${IPERF_RUN_SEND}" | grep SUM | grep receiver | awk '{ print $6 }')
			# if speed result is blank or bad (0.00), rerun, otherwise set counter to exit loop
			[[ -z $SPEED || "$SPEED" == "0.00" ]] && I=$(( $I + 1 )) || I=11
		else
			# if iperf server is not responding, set counter to exit, otherwise increment, sleep, and rerun
			[[ "$IPERF_RUN_SEND" == *"unable to connect"* ]] && I=11 || I=$(( $I + 1 )) && sleep 2
		fi
		echo -en "\r\033[0K"
	done

	# small sleep necessary to give iperf server a breather to get ready for a new test
	sleep 1

	# attempt the iperf receive test 5 times, allowing for a slot to become available on
	#   the server or to throw out any bad/error results
	J=1
	while [ $J -le 5 ]
	do
		echo -n "Performing $MODE iperf3 recv test from $HOST (Attempt #$J of 5)..."
		# select a random iperf port from the range provided
		PORT=$(shuf -i $PORTS -n 1)
		# run the iperf test receiving data from the iperf server to the host; includes
		#   a timeout of 15s in case the iperf server is not responding; uses 8 parallel
		#   threads for the network test
		IPERF_RUN_RECV="$(timeout 15 $IPERF_CMD $FLAGS -c $URL -p $PORT -P 8 -R 2> /dev/null)"
		# check if iperf exited cleanly and did not return an error
		if [[ "$IPERF_RUN_RECV" == *"receiver"* && "$IPERF_RUN_RECV" != *"error"* ]]; then
			# test did not result in an error, parse speed result
			SPEED=$(echo "${IPERF_RUN_RECV}" | grep SUM | grep receiver | awk '{ print $6 }')
			# if speed result is blank or bad (0.00), rerun, otherwise set counter to exit loop
			[[ -z $SPEED || "$SPEED" == "0.00" ]] && J=$(( $J + 1 )) || J=11
		else
			# if iperf server is not responding, set counter to exit, otherwise increment, sleep, and rerun
			[[ "$IPERF_RUN_RECV" == *"unable to connect"* ]] && J=11 || J=$(( $J + 1 )) && sleep 2
		fi
		echo -en "\r\033[0K"
	done

	# parse the resulting send and receive speed results
	IPERF_SENDRESULT="$(echo "${IPERF_RUN_SEND}" | grep SUM | grep receiver)"
	IPERF_RECVRESULT="$(echo "${IPERF_RUN_RECV}" | grep SUM | grep receiver)"
}

# launch_iperf
# Purpose: This method is designed to facilitate the execution of iperf network speed tests to
#          each public iperf server in the iperf server locations array.
# Parameters:
#          1. MODE - indicates the type of iperf tests to run (IPv4 or IPv6)
function launch_iperf {
	MODE=$1
	[[ "$MODE" == *"IPv6"* ]] && IPERF_FLAGS="-6" || IPERF_FLAGS="-4"

	# print iperf3 network speed results as they are completed
	echo -e
	echo -e "iperf3 Network Speed Tests ($MODE):"
	echo -e "---------------------------------"
	printf "%-15s | %-25s | %-15s | %-15s\n" "Provider" "Location (Link)" "Send Speed" "Recv Speed"
	printf "%-15s | %-25s | %-15s | %-15s\n"
	
	# loop through iperf locations array to run iperf test using each public iperf server
	for (( i = 0; i < IPERF_LOCS_NUM; i++ )); do
		# test if the current iperf location supports the network mode being tested (IPv4/IPv6)
		if [[ "${IPERF_LOCS[i*5+4]}" == *"$MODE"* ]]; then
			# call the iperf_test function passing the required parameters
			iperf_test "${IPERF_LOCS[i*5]}" "${IPERF_LOCS[i*5+1]}" "${IPERF_LOCS[i*5+2]}" "$IPERF_FLAGS"
			# parse the send and receive speed results
			IPERF_SENDRESULT_VAL=$(echo $IPERF_SENDRESULT | awk '{ print $6 }')
			IPERF_SENDRESULT_UNIT=$(echo $IPERF_SENDRESULT | awk '{ print $7 }')
			IPERF_RECVRESULT_VAL=$(echo $IPERF_RECVRESULT | awk '{ print $6 }')
			IPERF_RECVRESULT_UNIT=$(echo $IPERF_RECVRESULT | awk '{ print $7 }')
			# if the results are blank, then the server is "busy" and being overutilized
			[[ -z $IPERF_SENDRESULT_VAL || "$IPERF_SENDRESULT_VAL" == *"0.00"* ]] && IPERF_SENDRESULT_VAL="busy" && IPERF_SENDRESULT_UNIT=""
			[[ -z $IPERF_RECVRESULT_VAL || "$IPERF_RECVRESULT_VAL" == *"0.00"* ]] && IPERF_RECVRESULT_VAL="busy" && IPERF_RECVRESULT_UNIT=""
			# print the speed results for the iperf location currently being evaluated
			printf "%-15s | %-25s | %-15s | %-15s\n" "${IPERF_LOCS[i*5+2]}" "${IPERF_LOCS[i*5+3]}" "$IPERF_SENDRESULT_VAL $IPERF_SENDRESULT_UNIT" "$IPERF_RECVRESULT_VAL $IPERF_RECVRESULT_UNIT"
		fi
	done
}

# if the skip iperf flag was set, skip the network performance test, otherwise test network performance
if [ -z "$SKIP_IPERF" ]; then

	if [ ! -z "$LOCAL_IPERF" ]; then # local iperf has been detected, use instead of pre-compiled binary
		IPERF_CMD=iperf3
	else
		# create a temp directory to house the required iperf binary and library
		IPERF_PATH=$YABS_PATH/iperf
		mkdir -p $IPERF_PATH

		# download iperf3 binary
		if [ ! -z "$IPV4_CHECK" ]; then # if IPv4 is enabled
			curl -s -4 --connect-timeout 5 --retry 5 --retry-delay 0 https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/iperf3_$ARCH -o $IPERF_PATH/iperf3
		else # no IPv4, use IPv6 - below is necessary since raw.githubusercontent.com has no AAAA record
			curl -s -6 --connect-timeout 5 --retry 5 --retry-delay 0 -k -g --header 'Host: raw.githubusercontent.com' https://[2a04:4e42::133]/masonr/yet-another-bench-script/master/bin/iperf3_$ARCH -o $IPERF_PATH/iperf3
		fi

		if [ ! -f "$IPERF_PATH/iperf3" ]; then # ensure iperf3 binary downloaded successfully
			IPERF_DL_FAIL=True
		else
			chmod +x $IPERF_PATH/iperf3
			IPERF_CMD=$IPERF_PATH/iperf3
		fi
	fi
	
	# array containing all currently available iperf3 public servers to use for the network test
	# format: "1" "2" "3" "4" "5" \
	#   1. domain name of the iperf server
	#   2. range of ports that the iperf server is running on (lowest-highest)
	#   3. friendly name of the host/owner of the iperf server
	#   4. location and advertised speed link of the iperf server
	#   5. network modes supported by the iperf server (IPv4 = IPv4-only, IPv4|IPv6 = IPv4 + IPv6, etc.)
	IPERF_LOCS=( \
		"lon.speedtest.clouvider.net" "5200-5209" "Clouvider" "London, UK (10G)" "IPv4|IPv6" \
		"ping.online.net" "5200-5209" "Online.net" "Paris, FR (10G)" "IPv4" \
		"ping6.online.net" "5200-5209" "Online.net" "Paris, FR (10G)" "IPv6" \
		"iperf.worldstream.nl" "5201-5201" "WorldStream" "The Netherlands (10G)" "IPv4|IPv6" \
		#"iperf.biznetnetworks.com" "5201-5203" "Biznet" "Jakarta, Indonesia (1G)" "IPv4" \
		"iperf.sgp.webhorizon.in" "9201-9205" "WebHorizon" "Singapore (1G)" "IPv4|IPv6" \
		"nyc.speedtest.clouvider.net" "5200-5209" "Clouvider" "NYC, NY, US (10G)" "IPv4|IPv6" \
		"iperf3.velocityonline.net" "5201-5210" "Velocity Online" "Tallahassee, FL, US (10G)" "IPv4" \
		"la.speedtest.clouvider.net" "5200-5209" "Clouvider" "Los Angeles, CA, US (10G)" "IPv4|IPv6" \
		"speedtest.iveloz.net.br" "5201-5209" "Iveloz Telecom" "Sao Paulo, BR (2G)" "IPv4" \
	)

	# if the "REDUCE_NET" flag is activated, then do a shorter iperf test with only three locations
	# (Clouvider London, Clouvider NYC, and Online.net France)
	if [ ! -z "$REDUCE_NET" ]; then
		IPERF_LOCS=( \
			"lon.speedtest.clouvider.net" "5200-5209" "Clouvider" "London, UK (10G)" "IPv4|IPv6" \
			"ping.online.net" "5200-5209" "Online.net" "Paris, FR (10G)" "IPv4" \
			"ping6.online.net" "5200-5209" "Online.net" "Paris, FR (10G)" "IPv6" \
			"nyc.speedtest.clouvider.net" "5200-5209" "Clouvider" "NYC, NY, US (10G)" "IPv4|IPv6" \
		)
	fi
	
	# get the total number of iperf locations (total array size divided by 5 since each location has 5 elements)
	IPERF_LOCS_NUM=${#IPERF_LOCS[@]}
	IPERF_LOCS_NUM=$((IPERF_LOCS_NUM / 5))
	
	if [ -z "$IPERF_DL_FAIL" ]; then
		# check if the host has IPv4 connectivity, if so, run iperf3 IPv4 tests
		[ ! -z "$IPV4_CHECK" ] && launch_iperf "IPv4"
		# check if the host has IPv6 connectivity, if so, run iperf3 IPv6 tests
		[ ! -z "$IPV6_CHECK" ] && launch_iperf "IPv6"
	else
		echo -e "\niperf3 binary download failed. Skipping iperf network tests..."
	fi
fi

get_geekbench_version() {
	local VERSION=$1
	local bench_url="https://cdn.geekbench.com"

	if [[ $VERSION == *4* ]]; then
		local bench_bin_url="Geekbench-4.3.3-Mac.zip"
	else
		local bench_bin_url="Geekbench-5.4.3-Mac.zip"
	fi

	GEEKBENCH_PATH_OSX="Geekbench $VERSION.app"
	curl -s $bench_url/$bench_bin_url -o "$GEEKBENCH_PATH/$bench_bin_url"
	unzip "$GEEKBENCH_PATH/$bench_bin_url" -d "$GEEKBENCH_PATH/" 2>/dev/null 1>&2 || exit 1
	mv "$GEEKBENCH_PATH/$GEEKBENCH_PATH_OSX" "$GEEKBENCH_PATH/geekbench" 2>/dev/null 1>&2 || exit 1
	if [[ $ARCH == *aarch64* ]]; then
		bench_bin="geekbench/Contents/Resources/geekbench_aarch64"
	else
		bench_bin="geekbench/Contents/Resources/geekbench$VERSION"
	fi
	rm "$GEEKBENCH_PATH/$bench_bin_url" 1>/dev/null 2>&1
}
# launch_geekbench
# Purpose: This method is designed to run the Primate Labs' Geekbench 4/5 Cross-Platform Benchmark utility
# Parameters:
#          1. VERSION - indicates which Geekbench version to run
function launch_geekbench {
	VERSION=$1

	# create a temp directory to house all geekbench files
	GEEKBENCH_PATH=$YABS_PATH/geekbench_$VERSION
	mkdir -p $GEEKBENCH_PATH

	if [[ $VERSION == *4* && ($ARCH = *aarch64* || $ARCH = *arm*) ]]; then
		echo -e "\nARM architecture not supported by Geekbench 4, use Geekbench 5."
	elif [[ $VERSION == *4* && $ARCH != *aarch64* && $ARCH != *arm* ]]; then # Geekbench v4
		echo -en "\nRunning GB4 benchmark test... *cue elevator music*"
		# download the latest Geekbench 4 tarball and extract to geekbench temp directory
		if [[ "$OSTYPE" == *arwin* ]]; then
			get_geekbench_version $VERSION
		else
			curl -s https://cdn.geekbench.com/Geekbench-4.4.4-Linux.tar.gz  | tar xz --strip-components=1 -C $GEEKBENCH_PATH &>/dev/null
		fi

		if [[ "$ARCH" == *"x86"* ]]; then
			# check if geekbench file exists
			if test -f "geekbench.license"; then
				$GEEKBENCH_PATH/geekbench_x86_32 --unlock `cat geekbench.license` > /dev/null 2>&1
			fi

			# run the Geekbench 4 test and grep the test results URL given at the end of the test
			GEEKBENCH_TEST=$($GEEKBENCH_PATH/geekbench_x86_32 --upload 2>/dev/null | grep "https://browser")
		else
			# check if geekbench file exists
			if test -f "geekbench.license"; then
				$GEEKBENCH_PATH/$bench_bin --unlock `cat geekbench.license` > /dev/null 2>&1
			fi
			
			# run the Geekbench 4 test and grep the test results URL given at the end of the test
			GEEKBENCH_TEST=$($GEEKBENCH_PATH/$bench_bin --upload 2>/dev/null | grep "https://browser")
		fi
	fi

	if [[ $VERSION == *5* ]]; then # Geekbench v5
		if [[ $ARCH = *x86* && $GEEKBENCH_4 == *False* ]]; then # don't run Geekbench 5 if on 32-bit arch
			echo -e "\nGeekbench 5 cannot run on 32-bit architectures. Re-run with -4 flag to use"
			echo -e "Geekbench 4, which can support 32-bit architectures. Skipping Geekbench 5."
		elif [[ $ARCH = *x86* && $GEEKBENCH_4 == *True* ]]; then
			echo -e "\nGeekbench 5 cannot run on 32-bit architectures. Skipping test."
		else
			echo -en "\nRunning GB5 benchmark test... *cue elevator music*"
			# download the latest Geekbench 5 tarball and extract to geekbench temp directory
			bench_bin="geekbench5"
			if [[ "$OSTYPE" == *arwin* ]]; then
				get_geekbench_version $VERSION
			elif [[ $ARCH = *aarch64* || $ARCH = *arm* ]]; then
				curl -s https://cdn.geekbench.com/Geekbench-5.4.1-LinuxARMPreview.tar.gz  | tar xz --strip-components=1 -C $GEEKBENCH_PATH &>/dev/null
			else
				curl -s https://cdn.geekbench.com/Geekbench-5.4.1-Linux.tar.gz | tar xz --strip-components=1 -C $GEEKBENCH_PATH &>/dev/null
			fi

			# check if geekbench file exists
			if test -f "geekbench.license"; then
				$GEEKBENCH_PATH/$bench_bin --unlock `cat geekbench.license` > /dev/null 2>&1
			fi

			GEEKBENCH_TEST=$($GEEKBENCH_PATH/$bench_bin --upload 2>/dev/null | grep "https://browser")
		fi
	fi

	# ensure the test ran successfully
	if [ -z "$GEEKBENCH_TEST" ]; then
		if [[ -z "$IPV4_CHECK" ]]; then
			# Geekbench test failed to download because host lacks IPv4 (cdn.geekbench.com = IPv4 only)
			echo -e "\r\033[0KGeekbench releases can only be downloaded over IPv4. FTP the Geekbench files and run manually."
		elif [[ $ARCH != *x86* ]]; then
			# if the Geekbench test failed for any reason, exit cleanly and print error message
			echo -e "\r\033[0KGeekbench $VERSION test failed. Run manually to determine cause."
		fi
	else
		# if the Geekbench test succeeded, parse the test results URL
		GEEKBENCH_URL=$(echo -e $GEEKBENCH_TEST | head -1)
		GEEKBENCH_URL_CLAIM=$(echo $GEEKBENCH_URL | awk '{ print $2 }')
		GEEKBENCH_URL=$(echo $GEEKBENCH_URL | awk '{ print $1 }')
		# sleep a bit to wait for results to be made available on the geekbench website
		sleep 20
		# parse the public results page for the single and multi core geekbench scores
		[[ $VERSION == *5* ]] && GEEKBENCH_SCORES=$(curl -s $GEEKBENCH_URL | grep "div class='score'") ||
			GEEKBENCH_SCORES=$(curl -s $GEEKBENCH_URL | grep "span class='score'")
		GEEKBENCH_SCORES_SINGLE=$(echo $GEEKBENCH_SCORES | awk -v FS="(>|<)" '{ print $3 }')
		GEEKBENCH_SCORES_MULTI=$(echo $GEEKBENCH_SCORES | awk -v FS="(>|<)" '{ print $7 }')
	
		# print the Geekbench results
		echo -en "\r\033[0K"
		echo -e "Geekbench $VERSION Benchmark Test:"
		echo -e "---------------------------------"
		printf "%-15s | %-30s\n" "Test" "Value"
		printf "%-15s | %-30s\n"
		printf "%-15s | %-30s\n" "Single Core" "$GEEKBENCH_SCORES_SINGLE"
		printf "%-15s | %-30s\n" "Multi Core" "$GEEKBENCH_SCORES_MULTI"
		printf "%-15s | %-30s\n" "Full Test" "$GEEKBENCH_URL"

		# write the geekbench claim URL to a file so the user can add the results to their profile (if desired)
		[ ! -z "$GEEKBENCH_URL_CLAIM" ] && echo -e "$GEEKBENCH_URL_CLAIM" >> geekbench_claim.url 2> /dev/null
	fi
}

# if the skip geekbench flag was set, skip the system performance test, otherwise test system performance
if [ -z "$SKIP_GEEKBENCH" ]; then
	if [[ $GEEKBENCH_4 == *True* ]]; then
		launch_geekbench 4
	fi

	if [[ $GEEKBENCH_5 == *True* ]]; then
		launch_geekbench 5
	fi
fi

# finished all tests, clean up all YABS files and exit
echo -e
rm -rf $YABS_PATH

# reset locale settings
unset LC_ALL
