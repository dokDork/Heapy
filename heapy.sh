#!/bin/bash

# --- Configuration ---
OUTPUT_FILE="memory_dump_TOT.bin"
TEMP_FILE="memory_dump_PARZ.bin"
STRINGS_OUTPUT_FILE="out_strings.txt"
# --- End Configuration ---

# Function to display usage and an explanation of the parameter
usage() {
    echo "Usage: $0 -l <min_length>"
    echo ""
    echo "Error: The minimum string length (-l) is a required parameter."
    echo ""
    echo "Explanation:"
    echo "  -l <min_length>  This parameter sets the minimum length for a string"
    echo "                  to be considered 'interesting' and extracted from memory."
    echo "                  Memory dumps contain a huge amount of binary data and"
    echo "                  very short, meaningless strings. By setting a minimum"
    echo "                  length, you filter out the noise and focus on data that"
    echo "                  is more likely to be useful, such as passwords, keys,"
    echo "                  URLs, or configuration parameters."
    echo ""
    echo "  Example: To find strings longer than 10 characters:"
    echo "           $0 -l 10"
    exit 1
}

# --- Argument Parsing ---
# Check if no arguments were provided at all
if [ "$#" -eq 0 ]; then
    usage
fi

MIN_STRING_LENGTH=""
while getopts ":l:" opt; do
  case ${opt} in
    l )
      MIN_STRING_LENGTH=${OPTARG}
      # Check if the provided argument is a positive integer
      if ! [[ "$MIN_STRING_LENGTH" =~ ^[0-9]+$ ]] || [ "$MIN_STRING_LENGTH" -le 0 ]; then
        echo "Error: Minimum length must be a positive integer."
        usage
      fi
      ;;
    \? )
      echo "Invalid Option: -$OPTARG" 1>&2
      usage
      ;;
  esac
done

# Check if the required argument -l was actually provided
if [ -z "$MIN_STRING_LENGTH" ]; then
    usage
fi
# --- End Argument Parsing ---


# --- Main Script ---
echo "Starting memory dump for processes owned by the current user..."
echo "Minimum string length for analysis will be: $MIN_STRING_LENGTH"
echo "------------------------------------------------------------"

# Create an empty file for the final memory dump and the strings output
> "$OUTPUT_FILE"
> "$STRINGS_OUTPUT_FILE"

# Get the UID of the user running the script (important when using sudo)
if [ -n "$SUDO_USER" ]; then
    TARGET_USER=$(id -u "$SUDO_USER")
    echo "Script run with sudo, targeting user: $SUDO_USER (UID: $TARGET_USER)"
else
    TARGET_USER=$(id -u)
    echo "Script run as user: $(whoami) (UID: $TARGET_USER)"
fi

found_memory=false

# Loop through the processes in /proc/
for pid_dir in /proc/*/; do
    if [ ! -d "$pid_dir" ]; then continue; fi

    pid=$(basename "$pid_dir")
    pid_dir="${pid_dir%/}"
    
    if [ -r "$pid_dir/maps" ] && [ -r "$pid_dir/mem" ]; then
        process_owner=$(stat -c %u "$pid_dir")
        if [ "$TARGET_USER" -eq "$process_owner" ]; then
            echo "Analyzing process with PID $pid..."

            # --- 1. Analyze the [heap] segment first (for compatibility) ---
            heap_line=$(grep '$$heap$$' "$pid_dir/maps")
            if [ -n "$heap_line" ]; then
                echo "  -> [heap] segment found."
                heap_range=$(echo "$heap_line" | awk '{print $1}')
                heap_start_hex=${heap_range%-*}
                heap_end_hex=${heap_range#*-}

                heap_start_dec=$((16#$heap_start_hex))
                heap_end_dec=$((16#$heap_end_hex))
                heap_size=$((heap_end_dec - heap_start_dec))

                if [ "$heap_size" -gt 0 ]; then
                    if dd if="/proc/$pid/mem" of="$TEMP_FILE" bs=1 skip="$heap_start_dec" count="$heap_size" status=none 2>/dev/null; then
                        if [ -s "$TEMP_FILE" ]; then
                            cat "$TEMP_FILE" >> "$OUTPUT_FILE"
                            echo "  -> Heap for PID $pid dumped and appended."
                            found_memory=true
                        fi
                    else
                        echo "  -> [I/O Error] Could not read heap region for PID $pid."
                    fi
                fi
            else
                echo "  -> [heap] segment not found."
            fi

            # --- 2. Analyze other writable, private, non-file-backed regions ---
            echo "  -> Searching for other writable regions..."
            
            # Use process substitution to avoid the subshell and correctly update found_memory
            while IFS= read -r line; do
                if [[ "$line" == *"[heap]"* ]]; then continue; fi

                mem_range=$(echo "$line" | awk '{print $1}')
                mem_start_hex=${mem_range%-*}
                mem_end_hex=${mem_range#*-}
                
                mem_start_dec=$((16#$mem_start_hex))
                mem_end_dec=$((16#$mem_end_hex))
                mem_size=$((mem_end_dec - mem_start_dec))

                if [ "$mem_size" -gt 0 ]; then
                    if dd if="/proc/$pid/mem" of="$TEMP_FILE" bs=1 skip="$mem_start_dec" count="$mem_size" status=none 2>/dev/null; then
                        if [ -s "$TEMP_FILE" ]; then
                            cat "$TEMP_FILE" >> "$OUTPUT_FILE"
                            echo "  -> Dumped writable region [$mem_start_hex-$mem_end_hex]"
                            found_memory=true
                        fi
                    else
                         echo "  -> [I/O Error] Could not read region [$mem_start_hex-$mem_end_hex] for PID $pid."
                    fi
                fi
            done < <(grep -E 'rw-p.*\s+$|^rw-p.*$$' "$pid_dir/maps")
        fi
    fi
done

# Remove the temporary file
rm -f "$TEMP_FILE"

echo "------------------------------------------------------------"
if [ "$found_memory" = true ]; then
    echo "Memory dump complete. All readable writable regions saved in $OUTPUT_FILE"
else
    echo "No writable memory regions were successfully read and dumped. Output file is empty."
fi

# --- String Analysis ---
if [ "$found_memory" = true ]; then
    echo ""
    echo "Starting string analysis on $OUTPUT_FILE..."

    password_keywords="password|passwd|pass|pwd|secret|key|token"

    echo "--- Strings longer than $MIN_STRING_LENGTH characters ---" | tee -a "$STRINGS_OUTPUT_FILE"
    strings -n "$MIN_STRING_LENGTH" "$OUTPUT_FILE" | tee -a "$STRINGS_OUTPUT_FILE"

    echo "" | tee -a "$STRINGS_OUTPUT_FILE"

    echo "--- Potential password-related strings ---" | tee -a "$STRINGS_OUTPUT_FILE"
    strings -n "$MIN_STRING_LENGTH" "$OUTPUT_FILE" | grep -iE "$password_keywords" | tee -a "$STRINGS_OUTPUT_FILE"

    echo ""
    echo "Analysis complete. Results saved in $STRINGS_OUTPUT_FILE"
else
    echo "Skipping string analysis as no memory was dumped."
fi
