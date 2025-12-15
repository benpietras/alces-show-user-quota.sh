#!/bin/bash
# Enhanced disk usage quotas display with visual ASCII bars
# B.Pietras, University of Liverpool, Research IT. 15/12/25.

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

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

# Function to draw a usage bar
draw_bar() {
    local used=$1
    local soft=$2
    local hard=$3
    local label=$4
    local soft_label=$5
    local hard_label=$6
    local bar_width=50
    
    # Calculate percentages
    local pct_soft=$(awk "BEGIN {printf \"%.1f\", ($used / $soft) * 100}")
    local pct_hard=$(awk "BEGIN {printf \"%.1f\", ($used / $hard) * 100}")
    
    # Determine color based on usage
    local color=$GREEN
    if (( $(echo "$pct_soft >= 90" | bc -l) )); then
        color=$RED
    elif (( $(echo "$pct_soft >= 75" | bc -l) )); then
        color=$YELLOW
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
        if [ $i -lt $used_chars ]; then
            echo -n -e "${color}█${NC}"
        elif [ $i -eq $soft_pos ]; then
            echo -n -e "${YELLOW}|${NC}"
        else
            echo -n "░"
        fi
    done
    
    # Add red hard limit marker at the end of the bar
    echo -n -e "${RED}|${NC}"
    
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
    local grace=$8
    local files_grace=$9
    
    echo -e "\n${BOLD}${BLUE}Filesystem: $filesystem${NC}"
    
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
        draw_bar "$used_mb" "$quota_mb" "$limit_mb" "$used_fmt" "$soft_fmt" "$hard_fmt"
        
        # Display grace period if present
        if [ ! -z "$grace" ]; then
            if [[ "$grace" == "none" ]]; then
                echo -e "  ${RED}▲ Hard limit reached - no grace period${NC}"
            elif [[ "$grace" =~ expired ]] || [[ "$grace" =~ ^0 ]]; then
                echo -e "  ${RED}▲ Grace period expired${NC}"
            elif [[ "$grace" =~ [a-zA-Z] ]] || [[ "$grace" =~ [0-9] ]]; then
                # Format grace period: "6days" -> "6 days"
                local formatted_grace=$(echo "$grace" | sed 's/\([0-9]\)\([a-zA-Z]\)/\1 \2/')
                echo -e "  ${YELLOW}▲ Grace period:${NC} $formatted_grace remaining"
            fi
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
            draw_bar "$files_num" "$files_quota_num" "$files_limit_num" "$used_files_fmt" "$soft_files_fmt" "$hard_files_fmt"
            
            # Display files grace period if present
            if [ ! -z "$files_grace" ]; then
                if [[ "$files_grace" == "none" ]]; then
                    echo -e "  ${RED}▲ Hard limit reached - no grace period${NC}"
                elif [[ "$files_grace" =~ expired ]] || [[ "$files_grace" =~ ^0 ]]; then
                    echo -e "  ${RED}▲ Grace period expired${NC}"
                elif [[ "$files_grace" =~ [a-zA-Z] ]] || [[ "$files_grace" =~ [0-9] ]]; then
                    # Format grace period: "6days" -> "6 days"
                    local formatted_files_grace=$(echo "$files_grace" | sed 's/\([0-9]\)\([a-zA-Z]\)/\1 \2/')
                    echo -e "  ${YELLOW}▲ Grace period:${NC} $formatted_files_grace remaining"
                fi
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
        files=$(echo "$scratch_line" | awk '{print $6}')
        files_quota=$(echo "$scratch_line" | awk '{print $7}')
        files_limit=$(echo "$scratch_line" | awk '{print $8}')
        
        parse_and_display "/mnt/scratch" "$used" "$quota" "$limit" "$files" "$files_quota" "$files_limit"
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
            parse_and_display "/mnt/fastscratch" "$used" "$quota" "$limit" "$files" "$files_quota" "$files_limit"
        fi
    else
        # Try single-line format
        fastscratch_line=$(echo "$fastscratch_output" | grep -E "^\s*/mnt/fastscratch\s")
        if [ -z "$fastscratch_line" ]; then
            fastscratch_line=$(echo "$fastscratch_output" | grep "^/mnt/fastscratch")
        fi
        if [ ! -z "$fastscratch_line" ]; then
            used=$(echo "$fastscratch_line" | awk '{print $2}')
            quota=$(echo "$fastscratch_line" | awk '{print $3}')
            limit=$(echo "$fastscratch_line" | awk '{print $4}')
            files=$(echo "$fastscratch_line" | awk '{print $6}')
            files_quota=$(echo "$fastscratch_line" | awk '{print $7}')
            files_limit=$(echo "$fastscratch_line" | awk '{print $8}')
            
            parse_and_display "/mnt/fastscratch" "$used" "$quota" "$limit" "$files" "$files_quota" "$files_limit"
        fi
    fi
fi

# Check if fastscratch2 exists
if [ -d "/mnt/fastscratch2/users/$uname" ]; then
    fastscratch2_output=$(lfs quota -h -u $uname /mnt/fastscratch2 2>/dev/null)
    if [ ! -z "$fastscratch2_output" ]; then
        fastscratch2_line=$(echo "$fastscratch2_output" | grep -E "^\s*/mnt/fastscratch2")
        if [ -z "$fastscratch2_line" ]; then
            fastscratch2_line=$(echo "$fastscratch2_output" | grep "^/mnt/fastscratch2")
        fi
        if [ ! -z "$fastscratch2_line" ]; then
            used=$(echo "$fastscratch2_line" | awk '{print $2}')
            quota=$(echo "$fastscratch2_line" | awk '{print $3}')
            limit=$(echo "$fastscratch2_line" | awk '{print $4}')
            files=$(echo "$fastscratch2_line" | awk '{print $6}')
            files_quota=$(echo "$fastscratch2_line" | awk '{print $7}')
            files_limit=$(echo "$fastscratch2_line" | awk '{print $8}')
            
            parse_and_display "/mnt/fastscratch2" "$used" "$quota" "$limit" "$files" "$files_quota" "$files_limit"
        fi
    fi
fi

echo ""
echo -e "${BOLD}Legend:${NC} ${GREEN}█${NC} Used space  ${YELLOW}|${NC} Soft limit  ${RED}|${NC} Hard limit  ░ Available"
echo ""
