#!/bin/bash
#
# Regards, the Alveare Solutions society.
#
declare -A DEFAULT

CONF_FILE_PATH="$1"
if [ ! -z "$CONF_FILE_PATH" ]; then
    source $CONF_FILE_PATH
fi

# FETCHERS

function fetch_block_devices () {
    BLOCK_DEVICES=(
        `lsblk | grep -e disk | sed 's/^/\/dev\//g' | awk '{print $1}'`
    )
    echo ${BLOCK_DEVICES[@]}
    return 0
}

function fetch_file_size_in_bytes () {
    local FILE_PATH="$1"
    if [ ! -f "$FILE_PATH" ]; then
        touch $FILE_PATH
    fi
    BYTES=`ls -la "$FILE_PATH" | awk '{print $5}'`
    echo $BYTES
    return 0
}

function fetch_device_size () {
    local TARGET_DEVICE="$1"
    check_device_exists $TARGET_DEVICE
    if [ $? -ne 0 ]; then
        warning_msg "Device $TARGET_DEVICE not found."
        return 2
    fi
    local SIZE=`lsblk -bo NAME,SIZE "$TARGET_DEVICE" | \
        grep -e '^[a-z].*' | \
        awk '{print $NF}'`
    if [ -z "$SIZE" ]; then
        return 1
    fi
    echo "$SIZE"
    return 0
}

function fetch_all_available_devices () {
    AVAILABLE_DEVS=(
        `lsblk | \
        grep -e '^[a-z].*' -e 'disk' | \
        awk '{print $1}' | \
        sed 's:^:/dev/:g'`
    )
    if [ ${#AVAILABLE_DEVS[@]} -eq 0 ]; then
        error_msg "Could not detect any devices connected to machine."
        return 1
    fi
    echo "${AVAILABLE_DEVS[@]}"
    return 0
}

function fetch_data_from_user () {
    local PROMPT="$1"
    while :
    do
        read -p "$PROMPT> " DATA
        if [ -z "$DATA" ]; then
            continue
        elif [[ "$DATA" == ".back" ]]; then
            return 1
        fi
        echo "$DATA"; break
    done
    return 0
}

function fetch_ultimatum_from_user () {
    PROMPT="$1"
    while :
    do
        local ANSWER=`fetch_data_from_user "$PROMPT"`
        case "$ANSWER" in
            'y' | 'Y' | 'yes' | 'Yes' | 'YES')
                return 0
                ;;
            'n' | 'N' | 'no' | 'No' | 'NO')
                return 1
                ;;
            *)
        esac
    done
    return 2
}

function fetch_selection_from_user () {
    local PROMPT="$1"
    local OPTIONS=( "${@:2}" "Back" )
    local OLD_PS3=$PS3
    PS3="$PROMPT> "
    select opt in "${OPTIONS[@]}"; do
        case $opt in
            'Back')
                PS3="$OLD_PS3"
                return 1
                ;;
            *)
                local CHECK=`check_item_in_set "$opt" "${OPTIONS[@]}"`
                if [ $? -ne 0 ]; then
                    warning_msg "Invalid option."
                    continue
                fi
                PS3="$OLD_PS3"
                echo "$opt"
                return 0
                ;;
        esac
    done
    PS3="$OLD_PS3"
    return 1
}

# SETTERS

function set_imported_file () {
    IMPORTED_FILE=$1
    if [ -z "$IMPORTED_FILE" ]; then
        echo; error_msg "No Imported File path specified."
        echo; return 1
    fi
    DEFAULT['imported-file']=$IMPORTED_FILE
    return 0
}

function set_default_out_mode () {
    local OUT_MODE="$1"
    if [ -z "$OUT_MODE" ]; then
        echo; error_msg "No Out Mode specified."
        echo; return 1
    fi
    if [[ "$OUT_MODE" != "append" ]] && [[ "$OUT_MODE" != "overwrite" ]]; then
        echo; error_msg "Invalid value ${RED}$OUT_MODE${RESET}"\
            "for file output mode setting."
        echo; return 2
    fi
    DEFAULT['out-mode']=$OUT_MODE
    return 0
}

function set_final_sector () {
    local FINAL_SECTOR=$1
    if [ -z "$FINAL_SECTOR" ]; then
        echo; error_msg "No Final Sector specified."
        echo; return 1
    fi
    DEFAULT['final-sector']=$FINAL_SECTOR
    return 0
}

function set_default_block_size () {
    local BLOCK_SIZE=$1
    if [ -z "$BLOCK_SIZE" ]; then
        echo; error_msg "No default Block Size specified."
        echo; return 1
    fi
    DEFAULT['block-size']=$BLOCK_SIZE
    return 0
}

function set_default_block_device () {
    local BLOCK_DEVICE=$1
    if [ -z "$BLOCK_DEVICE" ]; then
        echo; error_msg "No default Block Device specified."
        echo; return 1
    fi
    DEFAULT['block-device']=$BLOCK_DEVICE
    return 0
}

function set_default_initial_sector () {
    local SECTOR_NUMBER=$1
    if [ -z "$SECTOR_NUMBER" ]; then
        echo; error_msg "No default Initial Sector number specified."
        echo; return 1
    fi
    DEFAULT['initial-sector']=$SECTOR_NUMBER
    return 0
}

function set_default_block_count () {
    local BLOCK_COUNT=$1
    if [ -z "$BLOCK_COUNT" ]; then
        echo; error_msg "No default Block Count specified."
        echo; return 1
    fi
    DEFAULT['block-count']=$BLOCK_COUNT
    return 0
}

function set_default_output_file () {
    OUTPUT_FILE=$1
    if [ -z "$OUTPUT_FILE" ]; then
        echo; error_msg "No default Output File specified."
        echo; return 1
    fi
    DEFAULT['out-file']=$OUTPUT_FILE
    return 0
}

function set_default_temporary_file () {
    TEMPORARY_FILE=$1
    if [ -z "$TEMPORARY_FILE" ]; then
        echo; error_msg "No default Temporary File specified."
        echo; return 1
    fi
    DEFAULT['tmp-file']=$TEMPORARY_FILE
    return 0
}

function set_safety_off () {
    if [[ "$STREAM_INJECTION_SAFETY" == "off" ]]; then
        info_msg "Stream Injection safety is already ${RED}OFF${RESET}."
        echo; return 1
    fi
    qa_msg "Taking off the training wheels. Are you sure about this?"
    fetch_ultimatum_from_user "Y/N"
    if [ $? -ne 0 ]; then
        echo; info_msg "Aborting action."
        echo; return 1
    else
        STREAM_INJECTION_SAFETY='off'
        echo; ok_msg "Safety is ${RED}OFF${RESET}."
    fi
    echo; return 0
}

function set_safety_on () {
    if [[ "$STREAM_INJECTION_SAFETY" == "on" ]]; then
        info_msg "Stream Injection safety is already ${GREEN}ON${RESET}."
        echo; return 1
    fi
    qa_msg "Getting scared, are we?"
    fetch_ultimatum_from_user "Y/N"
    if [ $? -ne 0 ]; then
        echo; info_msg "Aborting action."
        echo; return 1
    else
        STREAM_INJECTION_SAFETY='on'
        echo; ok_msg "Safety is ${GREEN}ON${RESET}."
    fi
    echo; return 0
}

function set_block_size () {
    echo; info_msg "Type block size for device or ${MAGENTA}.back${RESET}:"
    local BLOCK_SIZE=`fetch_data_from_user 'BlockSize'`
    if [ $? -ne 0 ]; then
        echo; return 1
    fi
    echo; info_msg "Setting default block size to $BLOCK_SIZE."
    set_default_block_size $BLOCK_SIZE
    echo; return $?
}

# CHECKERS

function check_valid_tmp_file () {
    if [ -z ${DEFAULT['tmp-file']} ] || [ ! -f ${DEFAULT['tmp-file']} ]; then
        error_msg "Temporary file ${RED}${DEFAULT['tmp-file']}${RESET}"\
            "not found."
        return 1
    fi
    return 0
}

function check_valid_block_device () {
    check_device_exists ${DEFAULT['block-device']}
    if [ $? -ne 0 ]; then
        error_msg "Block device ${RED}${DEFAULT['block-device']}${RESET}"\
            "not found."
        return 1
    fi
    return 0
}

function check_valid_initial_sector () {
    check_value_is_number ${DEFAULT['initial-sector']}
    if [ $? -ne 0 ]; then
        error_msg "Initial sector ${RED}${DEFAULT['initial-sector']}${RESET}"\
            "has to be a number."
        return 1
    fi
    return 0
}

function check_valid_block_count () {
    check_value_is_number ${DEFAULT['block-count']}
    if [ $? -ne 0 ]; then
        error_msg "Block count value ${RED}${DEFAULT['block-count']}${RESET}"\
            "has to be a number."
        return 1
    fi
    return 0
}
function check_valid_block_size () {
    check_value_is_number ${DEFAULT['block-size']}
    if [ $? -ne 0 ]; then
        error_msg "Block size value ${RED}${DEFAULT['block-size']}${RESET}"\
            "has to be a number."
        return 1
    fi
    return 0
}

function check_valid_data_set_for_action_write_to_sector_range () {
    check_valid_tmp_file
    if [ $? -ne 0 ]; then
        return $?
    fi
    check_valid_block_device
    if [ $? -ne 0 ]; then
        return $?
    fi
    check_valid_initial_sector
    if [ $? -ne 0 ]; then
        return $?
    fi
    check_valid_block_count
    if [ $? -ne 0 ]; then
        return $?
    fi
    check_valid_block_size
    if [ $? -ne 0 ]; then
        return $?
    fi
    return 0
}

function check_device_exists () {
    local DEVICE_PATH="$1"
    fdisk -l $DEVICE_PATH &> /dev/null
    return $?
}

function check_value_is_number () {
    local VALUE=$1
    test $VALUE -eq $VALUE &> /dev/null
    if [ $? -ne 0 ]; then
        return 1
    fi
    return 0
}

function check_item_in_set () {
    local ITEM="$1"
    ITEM_SET=( "${@:2}" )
    for SET_ITEM in "${ITEM_SET[@]}"; do
        if [[ "$ITEM" == "$SET_ITEM" ]]; then
            return 0
        fi
    done
    return 1
}

# GENERAL

# CLEANUP

function stream_injection_cleanup () {
    cleanup_temporary_file
    return $?
}

function cleanup_temporary_file () {
    remove_file ${DEFAULT['tmp-file']}
    if [ $? -ne 0 ]; then
        nok_msg "Something went wrong."\
            "Could not remove temporary file"\
            "${RED}${DEFAULT['tmp-file']}${RESET}."
        return 1
    else
        ok_msg "Temporary file ${GREEN}${DEFAULT['tmp-file']}${REET}"\
            "successfully cleaned."
    fi
    return 0
}

# SHREDDERS

function remove_file () {
    local FILE_PATH="$1"
    if [ ! -f $FILE_PATH ]; then
        error_msg "No file found at $FILE_PATH."
        return 1
    fi
    rm $FILE_PATH
    return $?
}

# INSTALLERS

function apt_install_dependency() {
    local UTIL="$1"
    echo; symbol_msg "${GREEN}+${RESET}" "Installing package ${YELLOW}$UTIL${RESET}..."
    apt-get install $UTIL
    return $?
}

function apt_install_underground_view_dependencies () {
    if [ ${#APT_DEPENDENCIES[@]} -eq 0 ]; then
        info_msg 'No dependencies to fetch using the apt package manager.'
        return 1
    fi
    local FAILURE_COUNT=0
    info_msg "Installing dependencies using apt package manager:"
    for package in "${APT_DEPENDENCIES[@]}"; do
        apt_install_dependency $package
        if [ $? -ne 0 ]; then
            nok_msg "Failed to install ${YELLOW}$SCRIPT_NAME${RESET}"\
                "dependency ${RED}$package${RESET}!"
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
        else
            ok_msg "Successfully installed ${YELLOW}$SCRIPT_NAME${RESET}"\
                "dependency ${GREEN}$package${RESET}."
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
        fi
    done
    if [ $FAILURE_COUNT -ne 0 ]; then
        echo; warning_msg "${RED}$FAILURE_COUNT${RESET} dependency"\
            "installation failures! Try installing the packages manually."
    fi
    return 0
}

# ACTIONS

function action_install_file_system_stream_injection_dependencies () {
    echo; info_msg "About to install ${WHITE}${#APT_DEPENDENCIES[@]}${RESET}"\
        "${YELLOW}$SCRIPT_NAME${RESET} dependencies."
    ANSWER=`fetch_ultimatum_from_user "Are you sure about this? ${YELLOW}Y/N${RESET}"`
    if [ $? -ne 0 ]; then
        echo; info_msg "Aborting action."
        return 1
    fi
    echo; apt_install_underground_view_dependencies
    local EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        nok_msg "Software failure!"\
            "Could not install ${RED}$SCRIPT_NAME${RESET} dependencies."
        echo; return 1
    else
        ok_msg "${GREEN}$SCRIPT_NAME${RESET}"\
            "dependency installation complete."
    fi
    echo; return $EXIT_CODE
}

function action_set_temporary_file () {
    echo; info_msg "Type absolute temporary file path or ${MAGENTA}.back${RESET}."
    while :
    do
        FILE_PATH=`fetch_data_from_user "FilePath"`
        if [ $? -ne 0 ]; then
            echo; info_msg "Aborting action."
            echo; return 1
        elif [ ! -f $FILE_PATH ]; then
            echo; warning_msg "Must be a file path, not ${RED}$FILE_PATH${RESET}."
            echo; continue
        fi
        cat "$FILE_PATH" > ${DEFAULT['tmp-file']}
        set_default_temporary_file "$FILE_PATH"
        echo; break
    done
    return 0
}

function action_import_data_from_file () {
    echo; info_msg "Type absolute import file path or ${MAGENTA}.back${RESET}."
    while :
    do
        FILE_PATH=`fetch_data_from_user "FilePath"`
        if [ $? -ne 0 ]; then
            echo; info_msg "Aborting action."
            echo; return 1
        elif [ ! -f $FILE_PATH ]; then
            echo; warning_msg "Must be a file path, not ${RED}$FILE_PATH${RESET}."
            echo; continue
        fi
        cat "$FILE_PATH" > ${DEFAULT['tmp-file']}
        set_imported_file "$FILE_PATH"
        echo; break
    done
    return 0
}

function action_insert_data_manually () {
    ${DEFAULT['editor']} ${DEFAULT['tmp-file']}
    if [ -z "`cat ${DEFAULT['tmp-file']}`" ]; then
        warning_msg "${RED}${DEFAULT['tmp-file']}${RESET} file empty."
        return 1
    fi
    if [ ! -z ${DEFAULT['imported-file']} ]; then
        DEFAULT['imported-file']=
    fi
    return 0
}

function action_compute_sectors_occupied () {
    if [ ! -z "${DEFAULT['initial-sector']}" ]; then
        INITIAL_SECTOR=${DEFAULT['initial-sector']}
    else
        INITIAL_SECTOR=1
        set_default_initial_sector $INITIAL_SECTOR
    fi
    FILE_SIZE=`fetch_file_size_in_bytes ${DEFAULT['tmp-file']}`
    BLOCK_COUNT=$(((FILE_SIZE / ${DEFAULT['block-size']}) + 1))
    FINAL_SECTOR=$(((INITIAL_SECTOR + $BLOCK_COUNT) - 1))
    SECTORS_OCCUPIED=$(((FINAL_SECTOR - $INITIAL_SECTOR) + 1))
    set_final_sector $FINAL_SECTOR
    set_default_block_count $BLOCK_COUNT
    echo; ok_msg "Data file ${GREEN}${DEFAULT['tmp-file']}${RESET}"\
        "of ${WHITE}$FILE_SIZE${RESET} bytes"\
        "occupy ${WHITE}$SECTORS_OCCUPIED${RESET} sectors:"\
        "${WHITE}${DEFAULT['initial-sector']}${RESET}"\
        "- ${WHITE}${DEFAULT['final-sector']}${RESET}."
    echo; return 0
}

function action_set_file_writer_mode () {
    echo; info_msg "Select file writer output mode."; echo
    while :
    do
        MODE=`fetch_selection_from_user "OutMode" "append" "overwrite"`
        if [ $? -ne 0 ]; then
            echo; return 1
        elif [ -z "$MODE" ]; then
            echo; warning_msg "Invalid input."
            echo; continue
        fi
        break
    done
    set_default_out_mode "$MODE"
    return 0
}

function action_set_default_block_device () {
    display_block_devices
    info_msg "Type full block device path or ${MAGENTA}.back${RESET}."
    VALID_DEVICE_PATHS=( `fetch_block_devices` )
    while :
    do
        BLOCK_DEVICE=`fetch_data_from_user "BlockDevice"`
        if [ $? -ne 0 ]; then
            echo; return 1
        fi
        check_item_in_set "$BLOCK_DEVICE" ${VALID_DEVICE_PATHS[@]}
        if [ $? -ne 0 ]; then
            echo; warning_msg "Invalid block device path ${RED}$BLOCK_DEVICE${RESET}."
            echo; continue
        fi
        set_default_block_device "$BLOCK_DEVICE"
        echo; break
    done
    return 0
}

function action_set_default_block_size () {
    echo; info_msg "Type sector size in bytes or ${MAGENTA}.back${RESET}."
    while :
    do
        BLOCK_SIZE=`fetch_data_from_user "BlockSize"`
        if [ $? -ne 0 ]; then
            echo; return 1
        fi
        check_value_is_number $BLOCK_SIZE
        if [ $? -ne 0 ]; then
            echo; warning_msg "Sector size must be a number,"\
                "not ${RED}$BLOCK_SIZE${RESET}."
            echo; continue
        fi
        set_default_block_size $BLOCK_SIZE
        echo; break
    done
    return 0
}

function action_set_default_initial_sector_number () {
    echo; info_msg "Type initial sector number or ${MAGENTA}.back${RESET}."
    while :
    do
        START_SECTOR=`fetch_data_from_user "InitialSector"`
        if [ $? -ne 0 ]; then
            echo; return 1
        fi
        check_value_is_number $START_SECTOR
        if [ $? -ne 0 ]; then
            echo; warning_msg "Initial sector must be a number,"\
                "not ${RED}$START_SECTOR${RESET}."
            echo; continue
        fi
        set_default_initial_sector $START_SECTOR
        if [ $START_SECTOR -gt ${DEFAULT['final-sector']} ]; then
            action_compute_sectors_occupied
        fi
        break
    done
    return 0
}

function action_write_to_sector_range () {
    local DATA_FILE="$1"
    local FILE_SIZE="$2"
    local TARGET_DEV="$3"
    local START_BLOCK="$4"
    local BLOCKS="$5"
    if [[ "$STREAM_INJECTION_SAFETY" == "on" ]]; then
        warning_msg "Stream Injection safety is ${GREEN}ON${RESET}."\
            "Device ${YELLOW}$TARGET_DEV${RESET} is not beeing written to."
    else
        info_msg "Attempting to write data file"\
            "${YELLOW}${DEFAULT['tmp-file']}${RESET}"\
            "content to device ${YELLOW}$TARGET_DEV${RESET}..."; echo
        dd if=$DATA_FILE bs=${DEFAULT['block-size']} count=$BLOCKS | \
            pv -ptebar --size $FILE_SIZE | \
            dd of=$TARGET_DEV bs=${DEFAULT['block-size']} count=$BLOCKS seek=$START_BLOCK &> /dev/null
    fi
    echo; info_msg "Data file content:"
    echo; display_file_content "$DATA_FILE"; echo
    if [ $? -ne 0 ]; then
        nok_msg "Software failure!"\
            "Could not write data file ${RED}$DATA_FILE${RESET}"\
            "content to device ${RED}$TARGET_DEV${RESET}.
            "
        return 1
    else
        ok_msg "Successfully written data file ${GREEN}$DATA_FILE${RESET}"\
        "content to device ${GREEN}$TARGET_DEV${RESET}.
        "
    fi
    return 0
}

# HANDLERS

function handle_action_write_to_sector_range () {
    check_valid_data_set_for_action_write_to_sector_range
    if [ $? -ne 0 ]; then
        warning_msg "Invalid data set."\
            "Make sure you have a valid data set for"\
            "StreamInjection action Write."
        return 1
    fi
    FILE_SIZE=`fetch_file_size_in_bytes ${DEFAULT['tmp-file']}`
    action_write_to_sector_range \
        ${DEFAULT['tmp-file']} \
        $FILE_SIZE \
        ${DEFAULT['block-device']} \
        ${DEFAULT['initial-sector']} \
        ${DEFAULT['block-count']}
    if [ $? -ne 0 ]; then
        return 2
    fi
    qa_msg "Do you want to overwrite?"
    fetch_ultimatum_from_user "${YELLOW}Y/N${RESET}"
    return $?
}

# CONTROLLERS

function file_system_stream_injection_control_panel () {
    local OPTIONS=(
        "Set ${RED}Safety OFF${RESET}"
        "Set ${GREEN}Safety ON${RESET}"
        "Set Block Device"
        "Set Block Size"
        "Set Initial Sector Number"
        "Set Temporary File"
        "Compute Sectors Occupied"
        "Import Data From File"
        "Edit Data Manually"
        "Install Dependencies"
        "Back"
    )
    symbol_msg "${BLUE}$SCRIPT_NAME"${RESET} \
        "${CYAN}Control Panel${RESET}"
    display_file_system_stream_injection_settings
    select opt in "${OPTIONS[@]}"; do
        case "$opt" in
            "Set ${RED}Safety OFF${RESET}")
                echo; set_safety_off; break
                ;;
            "Set ${GREEN}Safety ON${RESET}")
                echo; set_safety_on; break
                ;;
            "Set Block Device")
                action_set_default_block_device; break
                ;;
            "Set Block Size")
                action_set_default_block_size; break
                ;;
            "Set Initial Sector Number")
                action_set_default_initial_sector_number; break
                ;;
            "Set Temporary File")
                action_set_temporary_file; break
                ;;
            "Compute Sectors Occupied")
                action_compute_sectors_occupied; break
                ;;
            "Import Data From File")
                action_import_data_from_file; break
                ;;
            "Edit Data Manually")
                action_insert_data_manually; break
                ;;
            "Install Dependencies")
                action_install_file_system_stream_injection_dependencies
                ;;
            "Back")
                return 1
                ;;
            *)
                warning_msg "Invalid option."; continue
                ;;
        esac
    done
    return 0
}

function file_system_stream_injection_controller_main () {
    local OPTIONS=(
        "Stream Injection"
        "Control Panel"
        "Back"
    )
    echo; symbol_msg "${BLUE}$SCRIPT_NAME${RESET}" \
        "${CYAN}Land && Expand${RESET}"; echo
    select opt in "${OPTIONS[@]}"; do
        case "$opt" in
            "Stream Injection")
                echo; init_stream_injection
                break
                ;;
            "Control Panel")
                echo; init_file_system_stream_injection_control_panel
                break
                ;;
            "Back")
                stream_injection_cleanup
                return 1
                ;;
            *)
                echo; continue
                ;;
        esac
    done
    return 0
}

# INIT

function init_stream_injection () {
    while :
    do
        handle_action_write_to_sector_range
        if [ $? -ne 0 ]; then
            break
        fi
    done
    return 0
}

function init_underground_view () {
    while :
    do
        handle_action_read_from_sector_range
        if [ $? -ne 0 ]; then
            break
        fi
    done
    return 0
}

function init_file_system_stream_injection_control_panel () {
    while :
    do
        file_system_stream_injection_control_panel
        if [ $? -ne 0 ]; then
            break
        fi
    done
    return 0
}

function init_file_system_stream_injection () {
    while :
    do
        file_system_stream_injection_controller_main
        EXIT_CODE=$?
        if [ $EXIT_CODE -ne 0 ]; then
            clear; ok_msg "Terminating $SCRIPT_NAME."; exit $EXIT_CODE
        fi
    done
    return 0
}

# DISPLAY

function display_block_devices () {
    echo; echo -n "${CYAN}DEVICE${RESET}" && \
        echo ${CYAN}`lsblk | grep -e MOUNTPOINT`${RESET} && \
        lsblk | grep -e disk | sed 's/^/\/dev\//g'
    EXIT_CODE=$?
    echo
    return $EXIT_CODE
}

function display_file_system_stream_injection_settings () {
    case $STREAM_INJECTION_SAFETY in
        'on')
            local DISPLAY_SAFETY="${GREEN}$STREAM_INJECTION_SAFETY${RESET}"
            ;;
        'off')
            local DISPLAY_SAFETY="${RED}$STREAM_INJECTION_SAFETY${RESET}"
            ;;
        *)
            local DISPLAY_SAFETY=$STREAM_INJECTION_SAFETY
            ;;
    esac
    echo "
[ ${CYAN}Block Device${RESET}   ]: ${YELLOW}${DEFAULT['block-device']}${RESET}
[ ${CYAN}Block Size${RESET}     ]: ${WHITE}${DEFAULT['block-size']}${RESET}
[ ${CYAN}Block Count${RESET}    ]: ${WHITE}${DEFAULT['block-count']}${RESET}
[ ${CYAN}Initial Sector${RESET} ]: ${WHITE}${DEFAULT['initial-sector']}${RESET}
[ ${CYAN}Final Sector${RESET}   ]: ${WHITE}${DEFAULT['final-sector']}${RESET}
[ ${CYAN}Temporary File${RESET} ]: ${YELLOW}${DEFAULT['tmp-file']}${RESET}
[ ${CYAN}Safety${RESET}         ]: $DISPLAY_SAFETY"
    if [ ! -z ${DEFAULT['imported-file']} ]; then
        echo "[ ${CYAN}Imported File${RESET}  ]: ${YELLOW}${DEFAULT['imported-file']}${RESET}"
    fi
    echo; return 0
}

function display_file_content () {
    local FILE_PATH="$1"
    if [ ! -f "$FILE_PATH" ]; then
        echo; nok_msg "File ${RED}$FILE_PATH${RESET} not found."
        return 1
    fi
    cat "$FILE_PATH"
    return 0
}

function done_msg () {
    local MSG="$@"
    if [ -z "$MSG" ]; then
        return 1
    fi
    echo "[ ${CYAN}DONE${RESET} ]: $MSG"
    return 0
}

function ok_msg () {
    MSG="$@"
    if [ -z "$MSG" ]; then
        return 1
    fi
    echo "[ ${GREEN}OK${RESET} ]: $MSG"
    return 0
}

function nok_msg () {
    MSG="$@"
    if [ -z "$MSG" ]; then
        return 1
    fi
    echo "[ ${RED}NOK${RESET} ]: $MSG"
    return 0
}

function qa_msg () {
    MSG="$@"
    if [ -z "$MSG" ]; then
        return 1
    fi
    echo "[ ${YELLOW}Q/A${RESET} ]: $MSG"
    return 0
}

function info_msg () {
    MSG="$@"
    if [ -z "$MSG" ]; then
        return 1
    fi
    echo "[ ${YELLOW}INFO${RESET} ]: $MSG"
    return 0
}

function error_msg () {
    MSG="$@"
    if [ -z "$MSG" ]; then
        return 1
    fi
    echo "[ ${RED}ERROR${RESET} ]: $MSG"
    return 0
}

function warning_msg () {
    MSG="$@"
    if [ -z "$MSG" ]; then
        return 1
    fi
    echo "[ ${RED}WARNING${RESET} ]: $MSG"
    return 0
}

function symbol_msg () {
    SYMBOL="$1"
    MSG="${@:2}"
    if [ -z "$MSG" ]; then
        return 1
    fi
    echo "[ $SYMBOL ]: $MSG"
    return 0
}

# MISCELLANEOUS

if [ $EUID -ne 0 ]; then
    warning_msg "$SCRIPT_NAME requiers elevated privileges."\
        "Current EUID is ${RED}$EUID${RESET}."
    exit 1
fi

init_file_system_stream_injection
