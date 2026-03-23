#!/bin/bash

#########################
# Process Evaluation Orchestration Script
# Centre-of-mass energy study variant
#########################
#
# WORKFLOW:
# Step 1: Copy P1_* directories to create P1_*_<energy>TeV_double and P1_*_<energy>TeV_float versions
# Step 2: Serial compilation + immediate execution launch
#         - Patch check_sa.cc energy value
#         - Run Cadnize.sh
#         - Compile double version
#         - Launch check_cpp.exe immediately (before next distclean!)
#         - Compile float version
#         - Launch check_cpp.exe immediately
#         - Repeat for all directories and energies
# Step 3: Wait for all check_cpp.exe processes to complete
# Step 4: Run histogram.py in each directory (float and double)
# Step 5: Run histogram_mul_sub.py per base P1_ directory
# Step 6: Copy results to OUTPUT_PATH
#
#########################

set -euo pipefail

#########################
# Configuration
#########################
# Expand denominators with Double word expansions
EXPAND_DENOM="true"

# Maximum number of parallel check_cpp.exe processes
MAX_PARALLEL_CHECKS=120

# Maximum number of parallel analysis processes
MAX_PARALLEL_ANALYSIS=120

# Number of ITERATIONS
#ITERATIONS=320
ITERATIONS=100000

# Centre-of-mass energies in TeV to study
#ECMS_TEV=(1 2 4 6 8 10 12 14)
ECMS_TEV=(1 5 10 14)
#ECMS_TEV=(1)


MAIL_ON_SUCCESS="true"
USER="${USER}" #if not same as lxplus username, change accordingly

# CADNA toolbox path (set this to your actual path or pass as environment variable)
CADNA_TOOLBOX_PATH="${CADNA_TOOLBOX_PATH:-/path/to/cadna/toolbox}"
CADNA_PATH="${CADNA_PATH:-/path/to/cadna}"
OUTPUT_PATH="${OUTPUT_PATH:-/path/to/output}"

# CUDA_HOME setting for compilation
CUDA_HOME_VAL="${CUDA_HOME_VAL:-}"

#########################
# Global variables for process tracking
#########################

# Array to store all check_cpp.exe PIDs
CHECK_CPP_PIDS=()

# Variable to pass last launched PID from run_check_cpp to caller
LAST_CHECK_PID=0

#########################
# Working directory setup
#########################

# Get the work directory from argument or use current directory
if [ $# -ge 1 ]; then
    WORK_DIR="$1"
else
    WORK_DIR="."
fi

#Config file to change the precision   
MGONGPU_CONFIG="$WORK_DIR/../src/mgOnGpuConfig.h"

# Convert to absolute path - this must happen before any cd commands
# Save current directory first
SCRIPT_START_DIR="$(pwd)"

# Convert WORK_DIR to absolute path
if [[ "$WORK_DIR" = /* ]]; then
    # Already absolute
    WORK_DIR="$WORK_DIR"
else
    # Relative path - convert to absolute
    WORK_DIR="$(cd "$WORK_DIR" 2>/dev/null && pwd)" || {
        echo "ERROR: Cannot access directory: $1"
        exit 1
    }
fi

# get process name
PROC_NAME=$(sed -E 's|.*PROC_||; s|/SubProcesses.*||' <<< "$WORK_DIR")

# Return to starting directory
cd "$SCRIPT_START_DIR"

# Verify WORK_DIR exists and is a directory
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory does not exist: $WORK_DIR"
    exit 1
fi

#########################
# Color output
#########################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


#########################
# Step 0.5: Copy log file to EOS
#########################

log_to_outputpath() {
    local msg="$1"
    local status="$2"

    printf '[%s] %s\n' "$status" "$msg" \
        >> "$OUTPUT_PATH/$PROC_NAME/log_of_progress.txt"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log_to_outputpath "$*" "SUCCESS"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    log_to_outputpath "$*" "ERROR"
}

#########################
# Helper: energy in GeV from TeV value
#########################

tev_to_gev() {
     echo $(( $1 * 1000 ))
}

#########################
# Step 1: Copy P1_* directories for each energy and precision
#########################

step1_copy_directories() {
    log_info "Step 1: Copying P1_* directories for energies: ${ECMS_TEV[*]} TeV (double + float each)..."

    cd "$WORK_DIR"

    local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" | sed 's|^\./||' | sort))

    if [ ${#p1_dirs[@]} -eq 0 ]; then
        log_error "No P1_* directories found!"
        exit 1
    fi

    log_info "Found ${#p1_dirs[@]} base P1_* directories"

    for dir in "${p1_dirs[@]}"; do
        for tev in "${ECMS_TEV[@]}"; do
            local tag="${tev}TeV"
            local double_dir="${dir}_${tag}_double"
            local float_dir="${dir}_${tag}_float"

            if [ -d "$double_dir" ]; then
                log_warn "$double_dir already exists, skipping"
            else
                log_info "Copying $dir -> $double_dir"
                cp -rP "$dir" "$double_dir"
            fi

            if [ -d "$float_dir" ]; then
                log_warn "$float_dir already exists, skipping"
            else
                log_info "Copying $dir -> $float_dir"
                cp -rP "$dir" "$float_dir"
            fi
        done
    done

    log_success "Step 1 completed"
}

#########################
# Step 2: Compile directories serially
#########################
patch_energy() {
    local dir="$1"
    local tev="$2"
    local energy_gev
    energy_gev=$(tev_to_gev "$tev")
    local sa_file="$WORK_DIR/$dir/check_sa.cc"

    if [ ! -f "$sa_file" ]; then
        log_error "check_sa.cc not found in $dir"
        return 1
    fi

    if ! grep -q "const fptype energy" "$sa_file"; then
        log_error "No 'const fptype energy' line found in $sa_file"
        return 1
    fi

    sed -i "s|^\([[:space:]]*\)const fptype energy = [^;]*;.*|\1const fptype energy = ${energy_gev}; // Ecms = ${energy_gev} GeV = ${tev} TeV|" "$sa_file"
    log_info "Patched check_sa.cc in $dir: energy = ${energy_gev} GeV (${tev} TeV)"
}

setup_symlinks() {
    local dir="$1"
    local LOC_P1="$WORK_DIR/$dir"

    ln -sf "$CADNA_TOOLBOX_PATH/Cadnize.sh"   "$LOC_P1/Cadnize.sh"
    ln -sf "$CADNA_TOOLBOX_PATH/histogram.py" "$LOC_P1/histogram.py"
    ln -sf "$CADNA_TOOLBOX_PATH/srcpy" "$LOC_P1/srcpy"
}


patch_precision() {
    # $1: "double" | "float"
    if [ "$1" = "double" ]; then
        sed -i 's/\bfloat_st\b/double_st/g' "$MGONGPU_CONFIG"
    else
        sed -i 's/\bdouble_st\b/float_st/g' "$MGONGPU_CONFIG"
    fi
}

compile_directory() {
    local dir="$1"
    local fptype="$2"
    local dir_type="$3"  # "double" or "float"
    local compile_status=0 
    
    log_info "Compiling $dir with FPTYPE=$fptype ($dir_type)"
    
    # Change to the directory (using absolute path from WORK_DIR)
    cd "$WORK_DIR/$dir"
    
    # Clean first (suppress normal output, log everything, show errors on failure)
    sleep 1
    make distclean > "distclean_${dir_type}.log" 2>&1
    local distclean_status=$?
    
    if [ $distclean_status -ne 0 ]; then
        log_warn "make distclean had issues for $dir"
        # Show only the error lines from the log
        if [ -s "distclean_${dir_type}.log" ]; then
            echo "Errors from distclean:"
            grep -i "error\|fatal" "distclean_${dir_type}.log" || cat "distclean_${dir_type}.log" | tail -20
        fi
    fi

    #Compile
    if make -j12 \
        OPTFLAGS="-O3" \
        -f cudacpp.mk \
        FPTYPE="$fptype" \
        CUDA_HOME="$CUDA_HOME_VAL" \
        AVX=none \
        HASCURAND=hasNoCurand \
        USEOPENMP=1 \
        GTESTLIBS= \
        > "compile_${dir_type}.log" 2>&1; then
        log_success "Compilation successful for $dir ($dir_type)"
    else
        log_error "Compilation failed for $dir ($dir_type)"
        log_error "Check compile_${dir_type}.log for details"
        compile_status=1
    fi
    
    # CRITICAL: Return to WORK_DIR before exiting function
    cd "$WORK_DIR"
    
    return $compile_status
}


step2_compile_all() {
    log_info "Step 2: Compiling all directories serially and launching check_cpp.exe..."

    cd "$WORK_DIR"

    local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" | sed 's|^\./||' | sort))

    local failed_dirs=()
    CHECK_CPP_PIDS=()

    for dir in "${p1_dirs[@]}"; do
        for tev in "${ECMS_TEV[@]}"; do
            local tag="${tev}TeV"
            local double_dir="${dir}_${tag}_double"

            # --- Double ---
            if [ -d "$double_dir" ]; then
                if patch_energy "$double_dir" "$tev"; then
                    setup_symlinks "$double_dir"
                    log_info "Running Cadnize.sh in $double_dir"
                    (cd "$WORK_DIR/$double_dir" && bash Cadnize.sh > cadnize_double.log 2>&1) \
                        || log_warn "Cadnize.sh reported non-zero for $double_dir"

                    patch_precision "double"
                    if ! compile_directory "$double_dir" "d" "double"; then
                        failed_dirs+=("$double_dir (double)")
                    else
                        log_info "Launching check_cpp.exe for $double_dir (double)..."
                        run_check_cpp "$double_dir" "double"
                        CHECK_CPP_PIDS+=($LAST_CHECK_PID)
                    fi
                else
                    failed_dirs+=("$double_dir (patch)")
                fi
            fi

                       # Throttle parallel check_cpp.exe
            while [ $(count_running_check_cpp) -ge "$MAX_PARALLEL_CHECKS" ]; do
                log_info "Parallel limit reached ($(count_running_check_cpp)/$MAX_PARALLEL_CHECKS), waiting..."
                sleep 5
            done
        done
    done

    if [ "$EXPAND_DENOM" = "true" ]; then
        log_info "Expanding denominator for float dirs."
        mkdir -p "$WORK_DIR/../src/Arithmetics"
        ln -sf "$CADNA_TOOLBOX_PATH/Arithmetics/"* "$WORK_DIR/../src/Arithmetics"
        log_info "Inside $(pwd)"
        (cd "$WORK_DIR/../src/Arithmetics" && python3 HelAmpsDenomExpand.py) \
            || { log_error "HelAmpsDenomExpand.py failed"; exit 1; }
    fi

    patch_precision "float"  # restore
    for dir in "${p1_dirs[@]}"; do
        for tev in "${ECMS_TEV[@]}"; do
            local tag="${tev}TeV"
            local float_dir="${dir}_${tag}_float"

            # --- Float ---
            if [ -d "$float_dir" ]; then
                if patch_energy "$float_dir" "$tev"; then
                    setup_symlinks "$float_dir"
                    log_info "Running Cadnize.sh in $float_dir"
                    (cd "$WORK_DIR/$float_dir" && bash Cadnize.sh > cadnize_float.log 2>&1) \
                        || log_warn "Cadnize.sh reported non-zero for $float_dir"

                    patch_precision "float"
                    if ! compile_directory "$float_dir" "f" "float"; then
                        failed_dirs+=("$float_dir (float)")
                    else
                        log_info "Launching check_cpp.exe for $float_dir (float)..."
                        run_check_cpp "$float_dir" "float"
                        CHECK_CPP_PIDS+=($LAST_CHECK_PID)
                    fi
                else
                    failed_dirs+=("$float_dir (patch)")
                fi
            fi

            # Throttle parallel check_cpp.exe
            while [ $(count_running_check_cpp) -ge "$MAX_PARALLEL_CHECKS" ]; do
                log_info "Parallel limit reached ($(count_running_check_cpp)/$MAX_PARALLEL_CHECKS), waiting..."
                sleep 5
            done
        done
    done
    
    if [ ${#failed_dirs[@]} -gt 0 ]; then
        log_error "Compilation failed for the following directories:"
        printf '%s\n' "${failed_dirs[@]}"
        exit 1
    fi
    
    log_success "Step 2 completed - all compilations successful"
    log_info "All check_cpp.exe processes have been launched in background"
    log_info "Total processes launched: ${#CHECK_CPP_PIDS[@]}"
}

#########################
# Step 3: Run check_cpp.exe in parallel
#########################

run_check_cpp() {
    local dir="$1"
    local fptype_name="$2"
    local dir_name
    dir_name="$(basename "$dir")"

    cd "$WORK_DIR/$dir"
    
    local output_file="${fptype_name}_${dir_name}.out"
    
    log_info "Running check_cpp.exe in $dir -> $output_file"
    
    # Use nohup instead of setsid for better portability and job control
    # Also redirect stdin from /dev/null and detach properly
    nohup ./check_cpp.exe -p -v ${ITERATIONS} 1 1 \
        > "$output_file" 2>&1 \
        < /dev/null &
    
    local pid=$!
    
    # Store PID in global variable for caller to track
    LAST_CHECK_PID=$pid
    
    echo "$pid" > "${output_file}.pid"
    
    log_info "Started check_cpp.exe for $dir (PID: $pid)"
    
    # Return to WORK_DIR
    cd "$WORK_DIR"
    
    return 0
}

wait_for_running_jobs() {
    local max_jobs="$1"
    
    while [ $(jobs -r | wc -l) -ge "$max_jobs" ]; do
        sleep 2
    done
}

# Alternative: Check specific PIDs from our tracking array
count_running_check_cpp() {
    local count=0
    for pid in "${CHECK_CPP_PIDS[@]}"; do
        if ps -p "$pid" > /dev/null 2>&1; then
            ((count++))
        fi
    done
    echo $count
}

step3_run_all_checks() {
    log_info "Step 3: Waiting for all check_cpp.exe processes to complete..."

    cd "$WORK_DIR"
    
    if [ ${#CHECK_CPP_PIDS[@]} -eq 0 ]; then
        log_error "No check_cpp.exe PIDs to wait for!"
        log_error "This shouldn't happen - check Step 2"
        exit 1
    fi

    log_info "Tracking ${#CHECK_CPP_PIDS[@]} processes. PIDs: ${CHECK_CPP_PIDS[*]}"
    sleep 2

    local initially_running=0
    local already_finished=0
    
    for pid in "${CHECK_CPP_PIDS[@]}"; do
        if ps -p "$pid" > /dev/null 2>&1; then
            initially_running=$((initially_running + 1))
        else
            already_finished=$((already_finished + 1))
            log_info "PID $pid has already completed"
        fi
    done
    
    # Check if ALL processes have already finished
    if [ $initially_running -eq 0 ]; then
        log_success "All check_cpp.exe processes already completed"
        log_success "Step 3 completed"
        return 0
    fi
    
    # Poll until all processes complete
    local max_iterations=7200  # 10 hours max (at 5 second intervals)
    local iteration=0
    local last_count=-1
    
    while [ $iteration -lt $max_iterations ]; do
        local running_count=0
        local running_pids=()
        
        for pid in "${CHECK_CPP_PIDS[@]}"; do
            # Check if PID is running - use || true to prevent set -e from exiting
            if ps -p "$pid" > /dev/null 2>&1 || true; then
                if ps -p "$pid" > /dev/null 2>&1; then
                    running_pids+=($pid)
                    running_count=$((running_count + 1))
                fi
            fi
        done
        
        if [ $running_count -eq 0 ]; then
            log_success "All check_cpp.exe processes have completed!"
            break
        fi
        
        # Only log if count changed or every minute
        if [ $running_count -ne $last_count ] || [ $((iteration % 12)) -eq 0 ]; then
            local completed=$((${#CHECK_CPP_PIDS[@]} - running_count))
            log_info "Progress: $completed/${#CHECK_CPP_PIDS[@]} completed, $running_count still running"
            if [ $running_count -le 5 ]; then
                log_info "Remaining PIDs: ${running_pids[*]}"
            fi
            last_count=$running_count
        fi
        
        sleep 5
        iteration=$((iteration + 1))
    done
    
    # Final check
    local still_running=0
    for pid in "${CHECK_CPP_PIDS[@]}"; do
        if ps -p "$pid" > /dev/null 2>&1; then
            still_running=$((still_running + 1))
            log_error "PID $pid still running after timeout!"
        fi
    done
    
    if [ $still_running -gt 0 ]; then
        log_error "$still_running processes still running - may be stuck!"
        log_error "Check output files and consider killing stuck processes"
        exit 1
    fi
    
    log_success "Step 3 completed - all check_cpp.exe runs finished"
    log_success "Total processes completed: ${#CHECK_CPP_PIDS[@]}"
}

#########################
# Step 4: Run histogram.py in each energy-tagged directory
#########################

run_histogram() {
    local dir="$1"
    local fptype_name="$2"   # "double" or "float"
    local dir_name
    dir_name="$(basename "$dir")"

    local output_file="${fptype_name}_${dir_name}.out"

    log_info "Running histogram.py for $dir ($fptype_name)"

    cd "$WORK_DIR/$dir"

    if [ ! -f "$output_file" ]; then
        log_error "Output file not found: $WORK_DIR/$dir/$output_file"
        cd "$WORK_DIR"
        return 1
    fi

    local hist_status=0
    if python3 histogram.py "$output_file" "$fptype_name" \
        > "histogram_${fptype_name}.log" 2>&1; then
        log_success "histogram.py completed for $dir ($fptype_name)"
    else
        log_error "histogram.py failed for $dir ($fptype_name)"
        hist_status=1
    fi

    cd "$WORK_DIR"
    return $hist_status
}

step4_run_histograms() {
    log_info "Step 4: Running histogram.py in all energy-tagged directories (max $MAX_PARALLEL_ANALYSIS parallel)..."

    cd "$WORK_DIR"

    local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" | sed 's|^\./||' | sort))
        
    if [ ${#p1_dirs[@]} -eq 0 ]; then
        log_error "No P1_* directories found!"
        exit 1
    fi
    
    for dir in "${p1_dirs[@]}"; do
        for tev in "${ECMS_TEV[@]}"; do
            local tag="${tev}TeV"

            wait_for_running_jobs "$MAX_PARALLEL_ANALYSIS"
            run_histogram "${dir}_${tag}_double" "double" &

            wait_for_running_jobs "$MAX_PARALLEL_ANALYSIS"
            run_histogram "${dir}_${tag}_float" "float" &
        done
    done

    log_info "Waiting for all histogram.py runs to complete..."
    wait

    log_success "Step 4 completed"
}

#########################
# Step 5: Run histogram_mul_sub.py per base P1_ directory
#########################

step5_histogram_mul_sub() {
    log_info "Step 5: Running energy_histograms.py per base P1_ directory..."

    cd "$WORK_DIR"

    # Ensure symlink exists in SubProcesses (WORK_DIR)
    if [ ! -L "energy_histograms.py" ]; then
        ln -sf "$CADNA_TOOLBOX_PATH/energy_histograms.py" "energy_histograms.py"
    fi


    log_info "Running histogram_mul_sub.py for base "
    if python3 energy_histograms.py  \
        > "energy_histograms.log" 2>&1; then
        log_success "energy_histograms.py completed "
    else
        log_error "energy_histograms.py failed "
    fi

    log_info "Waiting for all energy_histograms.py runs to complete..."
    wait

    log_success "Step 5 completed"
}

#########################
# Step 6: Gather and copy results
#########################

step6_copy_results() {
    log_info "Step 6: Gathering and copying results to $OUTPUT_PATH" 
    
    cd "$WORK_DIR"
    name=$PROC_NAME

    log_info  " Process name separated is ${name}"

    if [ ! -d "$OUTPUT_PATH/$name" ]; then
        mkdir -p "$OUTPUT_PATH/$name"
    fi

    local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" | sed 's|^\./||' | sort))

    for dir in "${p1_dirs[@]}"; do
        # Copy histograms_"dir" produced by histogram_mul_sub.py
        local mul_hist_dir="histograms"
        if [ -d "$mul_hist_dir" ]; then
            cp -r "$mul_hist_dir" "$OUTPUT_PATH/$name/"
            log_success "Copied $mul_hist_dir"
        else
            log_warn "$mul_hist_dir not found, skipping"
        fi

        # Copy per-energy ./histogram subdirectories
        for tev in "${ECMS_TEV[@]}"; do
            local tag="${tev}TeV"

            for variant in "double" "float"; do
                local energy_dir="${dir}_${tag}_${variant}"
                local dest="$OUTPUT_PATH/$name/${energy_dir}"

                if [ ! -d "$dest" ]; then
                    mkdir -p "$dest"
                fi

                if [ -d "$WORK_DIR/$energy_dir/histograms" ]; then
                    cp -r "$WORK_DIR/$energy_dir/histograms" "$dest/"
                    log_success "Copied $energy_dir/histograms"
                else
                    log_warn "histograms/ not found in $energy_dir"
                fi
                
                cp "$WORK_DIR/$energy_dir/${variant}_"*.out "$dest/"

            done
        done
    done

    log_success "Step 6 completed"
}
#########################
# Step: Send mail on completition 
#########################

send_email_notification() {
    log_info "Sending mail to the $USER"

    local status="$1"
    local duration="$2"

    local name=$PROC_NAME

    local size=$(du -sh . | cut -f1)

    # Skip if email disabled
    if [ "$MAIL_ON_SUCCESS" != "true" ]; then
        return 0
    fi

    # Format duration
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    local duration_str="${hours}h ${minutes}m ${seconds}s"

    # Subject
    local subject
    if [ "$status" = "SUCCESS" ]; then
        subject="$name Ecms Study Completed Successfully"
    else
        subject="$name Ecms Study FAILED"
    fi

    local email_body
read -r -d '' email_body <<EOF || true
Process Evaluation Orchestration Report (Ecms Study)
=====================================================

Status: $status
Duration: $duration_str
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
Working Directory: $WORK_DIR
Energies studied: ${ECMS_TEV[*]} TeV
Size: $size

$(if [ "$status" = "SUCCESS" ]; then
    echo "All steps completed successfully!"
else
    echo "The orchestration encountered an error."
fi)

- Log files are in: $OUTPUT_PATH/$name
  or at CERNBox
EOF

    # Send mail via lxplus
    ssh -o BatchMode=yes "$USER@lxplus.cern.ch" \
        "mailx -s \"$subject\" \"$USER@cern.ch\"" > /dev/null 2>&1 <<EOF
$email_body
EOF
}


#########################
# Cleanup and signal handling
#########################

cleanup() {
    local exit_code=$?
    
    log_info "Cleanup initiated (exit code: $exit_code)"

    # Send failure email if script failed
    if [ $exit_code -ne 0 ] && [ "$MAIL_ON_SUCCESS" = "true" ]; then
        local elapsed=$(($(date +%s) - ${START_TIME:-$(date +%s)}))
        send_email_notification "FAILURE" "$elapsed" 
    fi

    
    # Kill any remaining background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Update status file if it exists
    if [ -f "${WORK_DIR}/orchestration.status" ]; then
        if [ $exit_code -eq 0 ]; then
            echo "COMPLETED" > "${WORK_DIR}/orchestration.status"
        else
            echo "FAILED" > "${WORK_DIR}/orchestration.status"
        fi
    fi
    
    # Remove PID file
    [ -f "${WORK_DIR}/orchestration.pid" ] && rm -f "${WORK_DIR}/orchestration.pid"
    
    if [ $exit_code -eq 0 ]; then
        log_success "Cleanup complete"
    else
        log_error "Cleanup complete (script failed)"
    fi
}

trap cleanup EXIT

handle_interrupt() {
    log_warn "Received interrupt signal (SIGINT/SIGTERM)"
    log_warn "Cleaning up background processes..."
    exit 130
}

trap handle_interrupt SIGINT SIGTERM

#########################
# Main execution
#########################

main() {

    if [ ! -d "$OUTPUT_PATH/$PROC_NAME" ]; then
        mkdir "$OUTPUT_PATH/$PROC_NAME"
    fi

    if [ -f "$OUTPUT_PATH/$PROC_NAME/log_of_progress.txt" ]; then
        mv -f "$OUTPUT_PATH/$PROC_NAME/log_of_progress.txt" \
              "$OUTPUT_PATH/$PROC_NAME/log_of_progress_old.txt"
        touch "$OUTPUT_PATH/$PROC_NAME/log_of_progress.txt"
    else
        touch "$OUTPUT_PATH/$PROC_NAME/log_of_progress.txt"
    fi

    log_info "========================================="
    log_info "Process Evaluation Orchestration Started"
    log_info "========================================="
    log_info "Start time: $(date)"
    log_info "Working directory: $WORK_DIR"
    log_info "Energies: ${ECMS_TEV[*]} TeV"
    log_info "Iterations: $ITERATIONS"
    log_info "Max parallel checks: $MAX_PARALLEL_CHECKS"
    log_info "Max parallel analyses: $MAX_PARALLEL_ANALYSIS"
    log_info "CADNA toolbox path: $CADNA_TOOLBOX_PATH"
    log_info "PID: $$"
    
    # Verify CADNA_TOOLBOX_PATH exists
    if [ ! -d "$CADNA_TOOLBOX_PATH" ]; then
        log_error "CADNA_TOOLBOX_PATH does not exist: $CADNA_TOOLBOX_PATH"
        log_error "Please set the correct path via environment variable or edit the script"
        exit 1
    fi

    if [ ! -d "$OUTPUT_PATH" ]; then
        log_error "OUTPUT_PATH does not exist: $OUTPUT_PATH"
        log_error "Please set the correct path via environment variable or edit the script"
        exit 1
    fi

    if [ ! -d "$CADNA_PATH" ]; then
        log_error "CADNA_PATH does not exist: $CADNA_PATH"
        log_error "Please set the correct path via environment variable or edit the script"
        exit 1
    fi
    	if [ "$MAIL_ON_SUCCESS" = "true" ] && \
    		! ssh "$USER@lxplus.cern.ch" 'echo "TRY OUT"' > /dev/null 2>&1
    	then
    		log_error "Can't access lxplus. Possibly expired kerberos certificate"
    		log_info  "Run - kinit -f $USER@CERN.CH or set MAIL_ON_SUCCESS variable"
    	exit 1
    fi

    if grep "override FPTYPE" ../Source/make_opts > /dev/null ; then
	    log_warn "Removing override FPTYPE from make_opts"
	    sed '1{/^override FPTYPE/d;}' ../Source/make_opts > make_opts.tmp && mv make_opts.tmp ../Source/make_opts
    fi
    

    # Verify P1_* directories exist in work directory
    log_info "Checking for P1_* directories in work directory..."
    cd "$WORK_DIR"
    local p1_check=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" 2>/dev/null \
        | sed 's|^\./||' | sort))

    if [ ${#p1_check[@]} -eq 0 ]; then
        log_error "========================================="
        log_error "No P1_* directories found!"
        log_error "========================================="
        log_error "Work directory: $WORK_DIR"
        log_error "Expected: Directories named P1_*"
        log_error ""
        log_error "Current directory contents:"
        ls -lah "$WORK_DIR" | head -30
        log_error ""
        log_error "Suggestions:"
        log_error "1. Check you're in the right directory"
        log_error "2. Ensure directories are named P1_* (case sensitive)"
        log_error "3. Try running with explicit path:"
        log_error "   ./orchestrate_process_evaluation.sh /full/path/to/work/dir"
        exit 1
    fi
    
    log_success "Found ${#p1_check[@]} P1_* directories to process"
    
    # Record start time
    local start_time=$(date +%s)
    
#    # Execute all steps
    step1_copy_directories
    step2_compile_all
    step3_run_all_checks
    step4_run_histograms
    step5_histogram_mul_sub
    step6_copy_results
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    
    log_success "========================================="
    log_success "Ecms study orchestration complete!"
    log_success "========================================="
    log_success "End time: $(date)"
    log_success "Total duration: ${hours}h ${minutes}m ${seconds}s"

    if [ $MAIL_ON_SUCCESS == "true" ]; then
        send_email_notification "SUCCESS" "$duration" 
    fi
}

# Run main function
main "$@"
