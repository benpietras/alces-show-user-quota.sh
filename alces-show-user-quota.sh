#!/bin/bash
# Enhanced disk usage quotas display with visual ASCII bars
# B.Pietras, University of Liverpool, Research IT. 15/12/25.
# Run on any node of barkla2

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
ORANGE='\033[38;5;208m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'
BOLD_RED='\033[1;31m'

msg="\
Usage: $(basename $0) [user]
Display the disk usage quotas on NFS and Lustre file systems for the specified user.
Examples could be:
$(basename $0)
$(basename $0) testuser
"

if [ "$#" -gt 1 ]; then
    echo "Error: Illegal number of arguments, exiting" >&2
    echo "$msg"
    exit 1
fi

currentuser=$USER
uname=${1:-$currentuser}

# Check if user exists
if id "$uname" &>/dev/null; then
    echo -e "${BOLD}Display the disk usage quotas on NFS and Lustre file systems for user $uname.${NC}"
else
    echo "Error: User '$uname' does not exist, existing" >&2
    echo "$msg"
    exit 1
fi

# Function to convert file count notation to numbers (handles k, M suffixes)
convert_to_number() {
    local value=$1
    local num=$(echo $value | sed 's/[^0-9.]//g')
    local unit=$(echo $value | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
    
    case $unit in
        K) echo "scale=0; $num * 1000" | bc ;;
        M) echo "scale=0; $num * 1000000" | bc ;;
        *) echo "$num" ;;
    esac
}

# Function to convert human-readable sizes to MB
convert_to_mb() {
    local size=$1
    local num=$(echo $size | sed 's/[^0-9.]//g')
    local unit=$(echo $size | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
    
    case $unit in
        K) echo "scale=2; $num / 1024" | bc ;;
        M) echo "$num" ;;
        G) echo "scale=2; $num * 1024" | bc ;;
        T) echo "scale=2; $num * 1024 * 1024" | bc ;;
        *) echo "0" ;;
    esac
}

# Function to format grace period with units
format_grace_period() {
    local grace=$1
    
    # Check for special cases
    if [[ "$grace" == "none" ]] || [[ "$grace" =~ expired ]] || [[ "$grace" =~ ^0 ]]; then
        echo "$grace"
        return
    fi
    
    # Handle format like "43:26" (hours:minutes)
    if [[ "$grace" =~ ^[0-9]+:[0-9]+$ ]]; then
        local hours=$(echo "$grace" | cut -d: -f1)
        local mins=$(echo "$grace" | cut -d: -f2)
        
        # Convert to days if hours >= 24
        if [ "$hours" -ge 24 ]; then
            local days=$((hours / 24))
            local remaining_hours=$((hours % 24))
            local day_word="days"
            local hour_word="hours"
            [ "$days" -eq 1 ] && day_word="day"
            [ "$remaining_hours" -eq 1 ] && hour_word="hour"
            
            if [ "$remaining_hours" -eq 0 ]; then
                echo "${days} ${day_word}, ${mins} minutes"
            else
                echo "${days} ${day_word}, ${remaining_hours} ${hour_word}, ${mins} minutes"
            fi
        else
            local hour_word="hours"
            [ "$hours" -eq 1 ] && hour_word="hour"
            echo "${hours} ${hour_word}, ${mins} minutes"
        fi
        return
    fi
    
    # Handle format like "6days"
    if [[ "$grace" =~ ^([0-9]+)(days?)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local day_word="days"
        [ "$num" -eq 1 ] && day_word="day"
        echo "$num ${day_word}"
        return
    fi
    
    # Handle format like "12hours"
    if [[ "$grace" =~ ^([0-9]+)(hours?)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local hour_word="hours"
        [ "$num" -eq 1 ] && hour_word="hour"
        echo "$num ${hour_word}"
        return
    fi
    
    # Handle format like "30minutes" or "30mins"
    if [[ "$grace" =~ ^([0-9]+)(minutes?|mins?)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local min_word="minutes"
        [ "$num" -eq 1 ] && min_word="minute"
        echo "$num ${min_word}"
        return
    fi
    
    # If format is not recognized, just add space between number and letters
    echo "$grace" | sed 's/\([0-9]\)\([a-zA-Z]\)/\1 \2/'
}

# Function to check if quotas match defaults
check_default_quotas() {
    local filesystem=$1
    local quota=$2
    local limit=$3
    local files_quota=$4
    local files_limit=$5
    
    local is_default_space=false
    local is_default_files=false
    
    # Check based on filesystem
    if [[ "$filesystem" =~ /export/data ]]; then
        # data1/data3 defaults: 2500G soft / 3000G hard, 300k/500k files
        # Convert to MB for comparison (2500G = 2560000M, 3000G = 3072000M)
        local quota_mb=$(convert_to_mb "$quota")
        local limit_mb=$(convert_to_mb "$limit")
        
        # Allow small rounding differences (within 1%)
        if (( $(echo "$quota_mb >= 2560000 * 0.99 && $quota_mb <= 2560000 * 1.01" | bc -l) )) && \
           (( $(echo "$limit_mb >= 3072000 * 0.99 && $limit_mb <= 3072000 * 1.01" | bc -l) )); then
            is_default_space=true
        fi
        
        # Convert file quotas (300k = 300000, 500k = 500000)
        local files_quota_num=$(convert_to_number "$files_quota")
        local files_limit_num=$(convert_to_number "$files_limit")
        [[ "$files_quota_num" == "300000" && "$files_limit_num" == "500000" ]] && is_default_files=true
        
    elif [[ "$filesystem" =~ /export/users ]]; then
        # users defaults: 75000M soft / 100000M hard, 100k/150k files
        local quota_mb=$(convert_to_mb "$quota")
        local limit_mb=$(convert_to_mb "$limit")
        
        # Allow small rounding differences (within 1%)
        if (( $(echo "$quota_mb >= 75000 * 0.99 && $quota_mb <= 75000 * 1.01" | bc -l) )) && \
           (( $(echo "$limit_mb >= 100000 * 0.99 && $limit_mb <= 100000 * 1.01" | bc -l) )); then
            is_default_space=true
        fi
        
        local files_quota_num=$(convert_to_number "$files_quota")
        local files_limit_num=$(convert_to_number "$files_limit")
        [[ "$files_quota_num" == "100000" && "$files_limit_num" == "150000" ]] && is_default_files=true
        
    elif [[ "$filesystem" =~ /mnt/scratch ]]; then
        # /mnt/scratch defaults: 2.0T soft / 2.5T hard, 300k/500k files
        # Convert quota values to MB for comparison (2T = 2097152M, 2.5T = 2621440M)
        local quota_mb=$(convert_to_mb "$quota")
        local limit_mb=$(convert_to_mb "$limit")
        
        # Allow small rounding differences (within 1%)
        if (( $(echo "$quota_mb >= 2097152 * 0.99 && $quota_mb <= 2097152 * 1.01" | bc -l) )) && \
           (( $(echo "$limit_mb >= 2621440 * 0.99 && $limit_mb <= 2621440 * 1.01" | bc -l) )); then
            is_default_space=true
        fi
        
        local files_quota_num=$(convert_to_number "$files_quota")
        local files_limit_num=$(convert_to_number "$files_limit")
        [[ "$files_quota_num" == "300000" && "$files_limit_num" == "500000" ]] && is_default_files=true
        
    elif [[ "$filesystem" =~ /mnt/fastscratch ]]; then
        # /mnt/fastscratch defaults: 500G soft / 750G hard, 500k/700k files
        # Convert to MB for comparison (500G = 512000M, 750G = 768000M)
        local quota_mb=$(convert_to_mb "$quota")
        local limit_mb=$(convert_to_mb "$limit")
        
        # Allow small rounding differences (within 1%)
        if (( $(echo "$quota_mb >= 512000 * 0.99 && $quota_mb <= 512000 * 1.01" | bc -l) )) && \
           (( $(echo "$limit_mb >= 768000 * 0.99 && $limit_mb <= 768000 * 1.01" | bc -l) )); then
            is_default_space=true
        fi
        
        local files_quota_num=$(convert_to_number "$files_quota")
        local files_limit_num=$(convert_to_number "$files_limit")
        [[ "$files_quota_num" == "500000" && "$files_limit_num" == "700000" ]] && is_default_files=true
    fi
    
    if $is_default_space && $is_default_files; then
        echo "both"
    elif $is_default_space; then
        echo "space"
    elif $is_default_files; then
        echo "files"
    else
        echo "custom"
    fi
}

# Function to draw a usage bar
draw_bar() {
    local used=$1
    local soft=$2
    local hard=$3
    local label=$4
    local soft_label=$5
    local hard_label=$6
    local grace=$7
    local bar_width=50
    
    # Calculate percentages
    local pct_soft=$(awk "BEGIN {printf \"%.1f\", ($used / $soft) * 100}")
    local pct_hard=$(awk "BEGIN {printf \"%.1f\", ($used / $hard) * 100}")
    
    # Determine color based on usage
    local color=$GREEN
    
    # Check if grace period expired or none (soft limit exceeded with no grace)
    local grace_expired=false
    local soft_exceeded=false
    
    # Check if soft limit is exceeded
    if (( $(echo "$pct_soft >= 100" | bc -l) )); then
        soft_exceeded=true
    fi
    
    # Determine if grace is expired
    # Empty grace when soft limit exceeded means grace expired (Lustre often doesn't report grace)
    if [[ "$grace" == "none" ]] || [[ "$grace" =~ expired ]] || [[ "$grace" =~ ^0 ]]; then
        grace_expired=true
    elif [ -z "$grace" ] && $soft_exceeded; then
        # Empty grace with soft limit exceeded - treat as expired
        grace_expired=true
    fi
    
    if (( $(echo "$pct_hard >= 100" | bc -l) )); then
        # Hard limit reached - use red
        color=$RED
    elif $soft_exceeded && $grace_expired; then
        # Soft limit exceeded and grace expired - use red
        color=$RED
    elif (( $(echo "$pct_soft >= 75" | bc -l) )); then
        # Over 75% of soft limit - use orange
        color=$ORANGE
    fi
    
    # Calculate bar segments
    local used_chars=$(awk "BEGIN {printf \"%.0f\", ($used / $hard) * $bar_width}")
    local soft_pos=$(awk "BEGIN {printf \"%.0f\", ($soft / $hard) * $bar_width}")
    
    # Ensure we don't exceed bar width
    [ $used_chars -gt $bar_width ] && used_chars=$bar_width
    [ $soft_pos -gt $bar_width ] && soft_pos=$bar_width
    
    # Build the bar
    echo -n "  "
    for ((i=0; i<$bar_width; i++)); do
        if [ $i -eq $soft_pos ] && [ $i -lt $used_chars ]; then
            # Soft limit position is within the used portion - make it stand out
            echo -n -e "${YELLOW}┃${NC}"
        elif [ $i -lt $used_chars ]; then
            echo -n -e "${color}█${NC}"
        elif [ $i -eq $soft_pos ]; then
            echo -n -e "${YELLOW}┃${NC}"
        else
            echo -n "░"
        fi
    done
    
    # Add red hard limit marker at the end of the bar
    echo -n -e "${RED}┃${NC}"
    
    # Print usage statistics
    echo -e " ${pct_soft}% of soft limit (${pct_hard}% of hard limit)"
    echo -e "  ${CYAN}Used:${NC} $label  ${YELLOW}Soft:${NC} $soft_label  ${RED}Hard:${NC} $hard_label"
}

# Function to format size value for display (MB input)
format_size_mb() {
    local size_mb=$1
    if (( $(echo "$size_mb < 1024" | bc -l) )); then
        echo "$(awk "BEGIN {printf \"%.0f\", $size_mb}")M"
    elif (( $(echo "$size_mb < 1048576" | bc -l) )); then
        echo "$(awk "BEGIN {printf \"%.1f\", $size_mb / 1024}")G"
    else
        echo "$(awk "BEGIN {printf \"%.1f\", $size_mb / 1048576}")T"
    fi
}

# Function to format number for display (for files/inodes)
format_number() {
    local num=$1
    if (( $(echo "$num < 1000" | bc -l) )); then
        echo "$(awk "BEGIN {printf \"%.0f\", $num}")"
    elif (( $(echo "$num < 1000000" | bc -l) )); then
        echo "$(awk "BEGIN {printf \"%.1f\", $num / 1000}")k"
    else
        echo "$(awk "BEGIN {printf \"%.1f\", $num / 1000000}")M"
    fi
}

# Function to parse and display quota info with bars
parse_and_display() {
    local filesystem=$1
    local used=$2
    local quota=$3
    local limit=$4
    local files=$5
    local files_quota=$6
    local files_limit=$7
    local grace=${8:-}
    local files_grace=${9:-}
    
    echo -e "\n${BOLD}${BLUE}Filesystem: $filesystem${NC}"
    
    # Check if using default quotas
    local quota_type=$(check_default_quotas "$filesystem" "$quota" "$limit" "$files_quota" "$files_limit")
    if [[ "$quota_type" == "both" ]]; then
        echo -e "  ${CYAN}Using default quotas (space & files)${NC}"
    elif [[ "$quota_type" == "space" ]]; then
        echo -e "  ${CYAN}Using default space quota${NC} | Custom file quota"
    elif [[ "$quota_type" == "files" ]]; then
        echo -e "  Custom space quota | ${CYAN}Using default file quota${NC}"
    else
        echo -e "  ${GREEN}Custom quotas configured${NC}"
    fi
    
    # Convert to MB for comparison
    local used_mb=$(convert_to_mb "$used")
    local quota_mb=$(convert_to_mb "$quota")
    local limit_mb=$(convert_to_mb "$limit")
    
    # Display space usage bar
    if [ "$quota_mb" != "0" ] && [ "$limit_mb" != "0" ]; then
        echo -e "${BOLD}  Space Usage:${NC}"
        local used_fmt=$(format_size_mb "$used_mb")
        local soft_fmt=$(format_size_mb "$quota_mb")
        local hard_fmt=$(format_size_mb "$limit_mb")
        draw_bar "$used_mb" "$quota_mb" "$limit_mb" "$used_fmt" "$soft_fmt" "$hard_fmt" "$grace"
        
        # Calculate percentage for space quota
        local pct_soft=$(awk "BEGIN {printf \"%.1f\", ($used_mb / $quota_mb) * 100}")
        
        # Display grace period if present or if soft limit exceeded
        if (( $(echo "$pct_soft >= 100" | bc -l) )); then
            if [ -z "$grace" ]; then
                echo -e "  ${BOLD_RED}⚠ Soft limit exceeded - grace period may have expired${NC}"
            elif [[ "$grace" == "none" ]]; then
                echo -e "  ${BOLD_RED}⚠ Hard limit reached - no grace period${NC}"
            elif [[ "$grace" =~ expired ]] || [[ "$grace" =~ ^0 ]]; then
                echo -e "  ${BOLD_RED}⚠ Grace period expired${NC}"
            else
                local formatted_grace=$(format_grace_period "$grace")
                echo -e "  ${ORANGE}⚠ Grace period:${NC} $formatted_grace remaining"
            fi
        elif [ ! -z "$grace" ] && [[ ! "$grace" == "none" ]]; then
            # Grace period present but soft limit not exceeded yet (shouldn't normally happen)
            local formatted_grace=$(format_grace_period "$grace")
            echo -e "  ${ORANGE}⚠ Grace period:${NC} $formatted_grace remaining"
        fi
    fi
    
    # Display files usage bar
    if [ ! -z "$files" ] && [ ! -z "$files_quota" ] && [ ! -z "$files_limit" ]; then
        # Convert file counts (handle k, M suffixes)
        local files_num=$(convert_to_number "$files")
        local files_quota_num=$(convert_to_number "$files_quota")
        local files_limit_num=$(convert_to_number "$files_limit")
        
        if [ ! -z "$files_num" ] && [ ! -z "$files_quota_num" ] && [ ! -z "$files_limit_num" ] && [ "$files_quota_num" != "0" ] && [ "$files_limit_num" != "0" ]; then
            echo -e "${BOLD}  Files/Inodes:${NC}"
            local used_files_fmt=$(format_number "$files_num")
            local soft_files_fmt=$(format_number "$files_quota_num")
            local hard_files_fmt=$(format_number "$files_limit_num")
            draw_bar "$files_num" "$files_quota_num" "$files_limit_num" "$used_files_fmt" "$soft_files_fmt" "$hard_files_fmt" "$files_grace"
            
            # Calculate percentage for files quota
            local pct_files_soft=$(awk "BEGIN {printf \"%.1f\", ($files_num / $files_quota_num) * 100}")
            
            # Display files grace period if present or if soft limit exceeded
            if (( $(echo "$pct_files_soft >= 100" | bc -l) )); then
                if [ -z "$files_grace" ]; then
                    echo -e "  ${BOLD_RED}⚠ Soft limit exceeded - grace period may have expired${NC}"
                elif [[ "$files_grace" == "none" ]]; then
                    echo -e "  ${BOLD_RED}⚠ Hard limit reached - no grace period${NC}"
                elif [[ "$files_grace" =~ expired ]] || [[ "$files_grace" =~ ^0 ]]; then
                    echo -e "  ${BOLD_RED}⚠ Grace period expired${NC}"
                else
                    local formatted_files_grace=$(format_grace_period "$files_grace")
                    echo -e "  ${ORANGE}⚠ Grace period:${NC} $formatted_files_grace remaining"
                fi
            elif [ ! -z "$files_grace" ] && [[ ! "$files_grace" == "none" ]]; then
                # Grace period present but soft limit not exceeded yet (shouldn't normally happen)
                local formatted_files_grace=$(format_grace_period "$files_grace")
                echo -e "  ${ORANGE}⚠ Grace period:${NC} $formatted_files_grace remaining"
            fi
        fi
    fi
}

echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  NFS File Systems${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"

# Capture and parse NFS quota output
nfs_output=$(quota -s -u $uname 2>/dev/null)
fs=""
while IFS= read -r line; do
    # Check if line is a filesystem path (starts with non-whitespace, could be IP or path)
    if [[ $line =~ ^[^[:space:]] ]] && [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:.*$ || $line =~ ^/.* ]]; then
        # This is a filesystem line - store it and wait for data line
        fs=$(echo "$line" | awk '{print $1}')
    elif [[ $line =~ ^[[:space:]]+ ]] && [ ! -z "$fs" ]; then
        # This line starts with whitespace and we have a filesystem - it's the data line
        # Remove leading whitespace and parse
        line=$(echo "$line" | sed 's/^[[:space:]]*//')
        
        # Parse all fields from quota output
        # The quota output has 8 columns but awk treats consecutive whitespace as single delimiter
        # When grace is empty, awk compresses fields. We need to parse more carefully.
        # Read the entire line into an array
        read -ra fields <<< "$line"
        
        # Remove quota markers (* or +) from first field
        used=$(echo "${fields[0]}" | sed 's/[*+]//g')
        quota="${fields[1]}"
        limit="${fields[2]}"
        
        # Now determine if field 3 is a grace period or files count
        # Grace periods contain letters (like "6days", "none") or are numeric with "days"
        # Files are numeric possibly with k/M suffix
        if [[ "${fields[3]}" =~ ^[0-9]+[kKmM]?\*?$ ]]; then
            # Field 3 is files count (no space grace period)
            grace=""
            files=$(echo "${fields[3]}" | sed 's/[*+]//g')
            files_quota="${fields[4]}"
            files_limit="${fields[5]}"
            files_grace="${fields[6]}"
        else
            # Field 3 is space grace period
            grace="${fields[3]}"
            files=$(echo "${fields[4]}" | sed 's/[*+]//g')
            files_quota="${fields[5]}"
            files_limit="${fields[6]}"
            files_grace="${fields[7]}"
        fi
        
        parse_and_display "$fs" "$used" "$quota" "$limit" "$files" "$files_quota" "$files_limit" "$grace" "$files_grace"
        fs=""
    fi
done <<< "$(echo "$nfs_output" | tail -n +3)"

echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  Lustre File Systems${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"

# Process /mnt/scratch
scratch_output=$(lfs quota -h -u $uname /mnt/scratch 2>/dev/null)
if [ ! -z "$scratch_output" ]; then
    scratch_line=$(echo "$scratch_output" | grep -E "^\s*/mnt/scratch")
    if [ ! -z "$scratch_line" ]; then
        used=$(echo "$scratch_line" | awk '{print $2}')
        quota=$(echo "$scratch_line" | awk '{print $3}')
        limit=$(echo "$scratch_line" | awk '{print $4}')
        grace=$(echo "$scratch_line" | awk '{print $5}')
        files=$(echo "$scratch_line" | awk '{print $6}')
        files_quota=$(echo "$scratch_line" | awk '{print $7}')
        files_limit=$(echo "$scratch_line" | awk '{print $8}')
        files_grace=$(echo "$scratch_line" | awk '{print $9}')
        
        # Clean up grace fields (remove asterisks and handle '-' as empty)
        [[ "$grace" == "-" ]] && grace=""
        [[ "$files_grace" == "-" ]] && files_grace=""
        grace=$(echo "$grace" | sed 's/[*]//g')
        files_grace=$(echo "$files_grace" | sed 's/[*]//g')
        
        parse_and_display "/mnt/scratch" "$used" "$quota" "$limit" "$files" "$files_quota" "$files_limit" "$grace" "$files_grace"
    fi
fi

# Process /mnt/fastscratch
fastscratch_output=$(lfs quota -h -u $uname /mnt/fastscratch 2>/dev/null)
if [ ! -z "$fastscratch_output" ]; then
    # Check if filesystem name is on its own line
    fs_line=$(echo "$fastscratch_output" | grep "^/mnt/fastscratch$")
    if [ ! -z "$fs_line" ]; then
        # Data is on the next line after the filesystem line
        data_line=$(echo "$fastscratch_output" | grep -A1 "^/mnt/fastscratch$" | tail -n1)
        if [ ! -z "$data_line" ] && [[ ! "$data_line" =~ ^/mnt/fastscratch ]]; then
            read -r used quota limit grace files files_quota files_limit files_grace <<< "$data_line"
            
            # Clean up grace fields
            [[ "$grace" == "-" ]] && grace=""
            [[ "$files_grace" == "-" ]] && files_grace=""
            grace=$(echo "$grace" | sed 's/[*]//g')
            files_grace=$(echo "$files_grace" | sed 's/[*]//g')
            
            parse_and_display "/mnt/fastscratch" "$used" "$quota" "$limit" "$files" "$files_quota" "$files_limit" "$grace" "$files_grace"
        fi
    fi
fi

# Check if fastscratch2 exists
if [ -d "/mnt/fastscratch2/users/$uname" ]; then
    fastscratch2_output=$(lfs quota -h -u $uname /mnt/fastscratch2 2>/dev/null)
    if [ ! -z "$fastscratch2_output" ]; then
        # Check if filesystem name is on its own line (no data after it)
        fs_line=$(echo "$fastscratch2_output" | grep "^/mnt/fastscratch2$")

        if [ ! -z "$fs_line" ]; then
            # Filesystem name is on its own line, data is on the next line
            # Get the line after the filesystem line and trim leading whitespace
            data_line=$(echo "$fastscratch2_output" | grep -A1 "^/mnt/fastscratch2$" | tail -n1 | sed 's/^[[:space:]]*//')
            if [ ! -z "$data_line" ] && [[ ! "$data_line" =~ ^/mnt/fastscratch2 ]]; then
                # Parse the trimmed data line
                read -r used quota limit grace files files_quota files_limit files_grace <<< "$data_line"

                # Clean up grace fields
                [[ "$grace" == "-" ]] && grace=""
                [[ "$files_grace" == "-" ]] && files_grace=""
                grace=$(echo "$grace" | sed 's/[*]//g')
                files_grace=$(echo "$files_grace" | sed 's/[*]//g')

                parse_and_display "/mnt/fastscratch2" "$used" "$quota" "$limit" "$files" "$files_quota" "$files_limit" "$grace" "$files_grace"
            fi
        else
            # Try to find data on same line as filesystem (with leading whitespace and data)
            fastscratch2_line=$(echo "$fastscratch2_output" | grep -E "^\s*/mnt/fastscratch2\s+[0-9]")
            if [ ! -z "$fastscratch2_line" ]; then
                # Data is on the same line as the filesystem name
                used=$(echo "$fastscratch2_line" | awk '{print $2}')
                quota=$(echo "$fastscratch2_line" | awk '{print $3}')
                limit=$(echo "$fastscratch2_line" | awk '{print $4}')
                grace=$(echo "$fastscratch2_line" | awk '{print $5}')
                files=$(echo "$fastscratch2_line" | awk '{print $6}')
                files_quota=$(echo "$fastscratch2_line" | awk '{print $7}')
                files_limit=$(echo "$fastscratch2_line" | awk '{print $8}')
                files_grace=$(echo "$fastscratch2_line" | awk '{print $9}')

                # Clean up grace fields
                [[ "$grace" == "-" ]] && grace=""
                [[ "$files_grace" == "-" ]] && files_grace=""
                grace=$(echo "$grace" | sed 's/[*]//g')
                files_grace=$(echo "$files_grace" | sed 's/[*]//g')

                parse_and_display "/mnt/fastscratch2" "$used" "$quota" "$limit" "$files" "$files_quota" "$files_limit" "$grace" "$files_grace"
            fi
        fi
    fi
fi

echo ""
echo -e "${BOLD}Legend:${NC} ${GREEN}█${NC} Used space  ${YELLOW}┃${NC} Soft limit  ${RED}┃${NC} Hard limit  ░ Available"
echo -e "         ${GREEN}█${NC} < 75% of soft  ${ORANGE}█${NC} ≥ 75% of soft (warning/exceeded)"
echo -e "         Grace periods are 7 days, unless otherwise specified."
