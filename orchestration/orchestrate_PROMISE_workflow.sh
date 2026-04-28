#!/bin/bash

#########################
# Process Evaluation Orchestration Script
#########################
#
# WORKFLOW:
# Step 1: Copy P1_* directories to create P1_*_float versions
# Step 2: Serial compilation + immediate execution launch
#         - Compile double version
#         - Launch check_cpp.exe immediately (before next distclean!)
#         - Compile float version
#         - Launch check_cpp.exe immediately
#         - Repeat for all directories
#         CRITICAL: check_cpp.exe must launch right after compilation
#                   because the next make distclean will delete it!
# Step 3: Wait for all check_cpp.exe processes to complete
# Step 4: Compare double vs float results (parallel)
# Step 5: Run PROMISE analysis (parallel)
#
#########################

set -euo pipefail

#########################
# Configuration
#########################

# Maximum number of parallel check_cpp.exe processes
MAX_PARALLEL_CHECKS=20

# Maximum number of parallel analysis processes
MAX_PARALLEL_ANALYSIS=20

# Number of ITERATIONS
ITERATIONS=10000000
#ITERATIONS=10000

# Centre-of-mass energy in TeV (optional - leave empty for default no-energy mode)
 ECM_TEV=14

# Enable mail on successful completition
MAIL_ON_SUCCESS="true"
USER="${USER}" #if not same as lxplus username, change accordingly

# CADNA toolbox path (set this to your actual path or pass as environment variable)
CADNA_TOOLBOX_PATH="${CADNA_TOOLBOX_PATH:-/path/to/cadna/toolbox}"
CADNA_PATH="${CADNA_PATH:-/path/to/cadna}"
OUTPUT_PATH="${OUTPUT_PATH:-/path/to/cadna}"

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
# Helper: convert TeV to GeV
#########################

tev_to_gev() {
    echo $(( $1 * 1000 ))
}

#########################
# Helper: patch energy in check_sa.cc
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

#########################
# Step 1: Find and copy P1_* directories
#########################

step1_copy_directories() {
    log_info "Step 1: Finding and copying P1_* directories..."

    cd "$WORK_DIR"

    local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" | sed 's|^\./||' | sort))

    if [ ${#p1_dirs[@]} -eq 0 ]; then
        log_error "No P1_* directories found!"
        exit 1
    fi

    log_info "Found ${#p1_dirs[@]} P1_* directories (excluding existing _float copies)"

    if [ -n "${ECM_TEV:-}" ]; then
        log_info "Energy mode: ECM = ${ECM_TEV} TeV"
    fi

    for dir in "${p1_dirs[@]}"; do
        if [ -n "${ECM_TEV:-}" ]; then
            local tag="${ECM_TEV}TeV"
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
        else
            local double_dir="${dir}_double"
            local float_dir="${dir}_float"

            if [ -d "$double_dir" ]; then
                log_warn "$double_dir already exists, skipping"
            else
                log_info "Copying $dir -> $double_dir"
                cp -rP "$dir" "$double_dir"
            fi

            if [ -d "$float_dir" ]; then
                log_warn "Directory $float_dir already exists, skipping copy"
            else
                log_info "Copying $dir -> $float_dir"
                cp -r "$dir" "$float_dir"
            fi
        fi
    done

    log_success "Step 1 completed"
}

#########################
# Step 2: Compile directories serially
#########################

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

    #symlink native_check_sa.py
    ln -sf "$CADNA_TOOLBOX_PATH/srcpy/native_check_sa.py"

    if python3 native_check_sa.py check_sa.cc; then
	    log_success "check_sa.cc transform successful for $dir"
    else
	    log_error "check_sa.cc failed for $dir"
	    compile_status=1
    fi
    
    # Compile
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
        if [ -n "${ECM_TEV:-}" ]; then
            local tag="${ECM_TEV}TeV"
            local double_dir="${dir}_${tag}_double"
            local float_dir="${dir}_${tag}_float"

            if [ -d "$double_dir" ]; then
                if patch_energy "$double_dir" "$ECM_TEV"; then
                    if ! compile_directory "$double_dir" "d" "double"; then
                        failed_dirs+=("$double_dir (double)")
                    else
                        log_info "Launching check_cpp.exe for $double_dir (double) immediately..."
                        run_check_cpp "$double_dir" "double"
                        CHECK_CPP_PIDS+=($LAST_CHECK_PID)
                    fi
                else
                    failed_dirs+=("$double_dir (patch)")
                fi
            fi

            while [ $(count_running_check_cpp) -ge "$MAX_PARALLEL_CHECKS" ]; do
                sleep 5
            done

            if [ -d "$float_dir" ]; then
                if patch_energy "$float_dir" "$ECM_TEV"; then
                    if ! compile_directory "$float_dir" "f" "float"; then
                        failed_dirs+=("$float_dir (float)")
                    else
                        log_info "Launching check_cpp.exe for $float_dir (float) immediately..."
                        run_check_cpp "$float_dir" "float"
                        CHECK_CPP_PIDS+=($LAST_CHECK_PID)
                    fi
                else
                    failed_dirs+=("$float_dir (patch)")
                fi
            fi
        else
            local double_dir="${dir}_double"
            local float_dir="${dir}_float"

            if [ -d "$double_dir" ]; then
                if ! compile_directory "$double_dir" "d" "double"; then
                    failed_dirs+=("$double_dir (double)")
                else
                    log_info "Launching check_cpp.exe for $double_dir (double) immediately..."
                    run_check_cpp "$double_dir" "double"
                    CHECK_CPP_PIDS+=($LAST_CHECK_PID)
                fi
            fi

            if [ -d "$float_dir" ]; then
                if ! compile_directory "$float_dir" "f" "float"; then
                    failed_dirs+=("$float_dir (float)")
                else
                    log_info "Launching check_cpp.exe for $float_dir (float) immediately..."
                    run_check_cpp "$float_dir" "float"
                    CHECK_CPP_PIDS+=($LAST_CHECK_PID)
                fi
            fi
        fi

        while [ $(count_running_check_cpp) -ge "$MAX_PARALLEL_CHECKS" ]; do
            sleep 5
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
    local fptype_name="$2"  # "double" or "float"
    local dir_name="$(basename "$dir")"
    
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
    
    log_info "Tracking ${#CHECK_CPP_PIDS[@]} check_cpp.exe processes"
    log_info "PIDs: ${CHECK_CPP_PIDS[*]}"
    
    # Give processes a moment to start up
    log_info "Waiting 2 seconds for processes to initialize..."
    sleep 2
    
    # Verify processes are actually running
    log_info "Verifying processes are running..."
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
        if [ $already_finished -eq ${#CHECK_CPP_PIDS[@]} ]; then
            log_success "All check_cpp.exe processes have already completed!"
            log_info "This is normal for fast-running processes"
            log_info "Verifying output files exist..."
            
            # Verify output files were created and have content
            local output_count=0
            local expected_files=0
            
            cd "$WORK_DIR"
            
            # Count expected output files based on directories
            for dir in P1_*; do
                if [ -d "$dir" ]; then
                    expected_files=$((expected_files + 1))
                fi
            done
            
            # Check each expected output file
            for dir in P1_*; do
                if [ -d "$dir" ]; then
                    # Check for double or float output based on directory name
                    if [[ "$dir" == *_float ]]; then
                        outfile="$dir/float_${dir}.out"
                    else
                        outfile="$dir/double_${dir}.out"
                    fi
                    
                    if [ -f "$outfile" ] && [ -s "$outfile" ]; then
                        # File exists and is not empty (-s checks size > 0)
                        output_count=$((output_count + 1))
                    else
                        if [ ! -f "$outfile" ]; then
                            log_warn "Expected output file $outfile not found"
                        else
                            log_warn "Output file $outfile is empty - may have failed"
                        fi
                    fi
                fi
            done
            
            log_info "Found $output_count valid output files (expected $expected_files)"
            
            if [ $output_count -ge $expected_files ]; then
                log_success "All output files present - processes completed successfully"
                # Skip the polling loop - we're done!
                log_success "Step 3 completed - all check_cpp.exe runs finished"
                log_success "Total processes completed: ${#CHECK_CPP_PIDS[@]}"
                return 0
            else
                log_warn "Only found $output_count output files, expected $expected_files"
                log_warn "Some processes may have failed - continuing anyway"
                # Don't exit - let the user decide
            fi
        else
            log_error "None of the check_cpp.exe processes are running!"
            log_error "They may have failed to start"
            log_error "Check the output files for errors:"
            ls -lh "$WORK_DIR"/P1_*/*.out 2>/dev/null | tail -20
            exit 1
        fi
    else
        log_info "Initially running: $initially_running/${#CHECK_CPP_PIDS[@]} processes"
        log_info "Already finished: $already_finished/${#CHECK_CPP_PIDS[@]} processes"
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
# Step 4: Compare double vs float results
#########################

compare_results() {
    local base_dir="$1"
    local dir_name
    local double_dir
    local float_dir
    local double_output
    local float_output
    local comparison_output
    
    if [ -n "${ECM_TEV:-}" ]; then
        local tag="${ECM_TEV}TeV"
        dir_name="${base_dir}_${tag}"
        double_dir="${WORK_DIR}/${base_dir}_${tag}_double"
        float_dir="${WORK_DIR}/${base_dir}_${tag}_float"
    else
        dir_name="${base_dir}"
        double_dir="${WORK_DIR}/${base_dir}_double"
        float_dir="${WORK_DIR}/${base_dir}_float"
    fi
    
    log_info "Comparing results for $dir_name..."
    
    cd "$double_dir"
    
    if [ ! -L "native_output_postprocess.py" ]; then
        ln -sf "$CADNA_TOOLBOX_PATH/native_output_postprocess.py" .
    fi
    
    double_output="double_${dir_name}_double.out"
    float_output="${float_dir}/float_${dir_name}_float.out"
    comparison_output="gdb_run_output_float-O3_1.out"
    
    if [ ! -f "$double_output" ]; then
        log_error "Double output file not found: $double_output"
        return 1
    fi
    
    if [ ! -f "$float_output" ]; then
        log_error "Float output file not found: $float_output"
        return 1
    fi

    if [ -f "$comparison_output" ]; then
        rm $comparison_output
    fi

    local comparison_status=0
    if python3 native_output_postprocess.py \
        "$float_output" \
        "$double_output" \
        "$comparison_output" \
        > "comparison_${dir_name}.log" 2>&1; then
        log_success "Comparison completed for $dir_name"
    else
        log_error "Comparison failed for $dir_name"
        tail -n 5 "comparison_${dir_name}.log" >&2
        comparison_status=1
    fi
    
    cd "$WORK_DIR"
    
    return $comparison_status
}

step4_compare_all() {
    log_info "Step 4: Comparing double vs float results (max $MAX_PARALLEL_ANALYSIS parallel)..."
    
    cd "$WORK_DIR"
    
    local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" | sed 's|^\./||' | sort))
    
    if [ ${#p1_dirs[@]} -eq 0 ]; then
        log_error "No P1_* directories found!"
        exit 1
    fi
    
    for dir in "${p1_dirs[@]}"; do
        wait_for_running_jobs "$MAX_PARALLEL_ANALYSIS"
        compare_results "$dir" &
    done
    
    log_info "Waiting for all comparisons to complete..."
    wait
    
    log_success "Step 4 completed - all comparisons finished"
}

#########################
# Step 5: Run PROMISE analysis
#########################

run_promise_analysis() {
    local double_dir="$1"
    local dir_name="$(basename "$double_dir")"
    
    log_info "Running PROMISE analysis for $dir_name..."
    
    cd "$WORK_DIR/$double_dir"
    
    # Create symlink to promiseAnalyse.py
    if [ ! -L "promiseAnalyse.py" ]; then
        ln -sf "$CADNA_TOOLBOX_PATH/boiler_plate/promiseAnalyse.py" .
    fi
    
    if [ ! -L "$CADNA_TOOLBOX_PATH/boiler_plate/srcpy" ]; then
        log_warn "Creating symlink in $CADNA_TOOLBOX_PATH/boiler_plate for /srcpy"
        ln -sf "$CADNA_TOOLBOX_PATH/srcpy" "$CADNA_TOOLBOX_PATH/boiler_plate"
    fi
    
    # Run analysis
    local analysis_status=0
    if python3 promiseAnalyse.py \
        > "promise_analysis_${dir_name}.log" 2>&1; then
        log_success "PROMISE analysis completed for $dir_name"
        analysis_status=0
    else
        log_error "PROMISE analysis failed for $dir_name"
        analysis_status=1
    fi
    
    # Return to WORK_DIR
    cd "$WORK_DIR"
    
    return $analysis_status
}

step5_promise_analysis() {
    log_info "Step 5: Running PROMISE analysis (max $MAX_PARALLEL_ANALYSIS parallel)..."
    
    cd "$WORK_DIR"
    
    local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*_double" ! -name "*TeV*" | sed 's|^\./||' | sort))
    
    if [ ${#p1_dirs[@]} -eq 0 ]; then
        log_error "No P1_* directories found!"
        exit 1
    fi
    
    for dir in "${p1_dirs[@]}"; do
        wait_for_running_jobs "$MAX_PARALLEL_ANALYSIS"
        
        if [ -n "${ECM_TEV:-}" ]; then
            local tag="${ECM_TEV}TeV"
            run_promise_analysis "${dir}_${tag}_double" &
        else
            run_promise_analysis "${dir}_double" &
        fi
    done
    
    log_info "Waiting for all PROMISE analyses to complete..."
    wait
    
    log_success "Step 5 completed - all PROMISE analyses finished"
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
        mkdir "$OUTPUT_PATH/$name"
    fi

    if [ ! -f "${WORK_DIR}/gatherPromiseMult.py" ]; then
        log_info "Linking gatherPromiseMult.py in ${WORK_DIR}"
        ln -s "$CADNA_TOOLBOX_PATH/script/gatherPromiseMult.py"
    fi

    if [ ! -f "${WORK_DIR}/histogram_mul_sub.py" ]; then
        log_info "Linking histogram_mul_sub.py in ${WORK_DIR}"
        ln -s "$CADNA_TOOLBOX_PATH/histogram_mul_sub.py"
    fi


    if python3 gatherPromiseMult.py \
       > "gatherPromise_log.txt" 2>&1; then
        log_success "Gathering promise result completed"
        cp promiseResultGathered.png "$OUTPUT_PATH/$name/proRes_$name.png"
    else 
       log_error "Gathering promise results failed" 
    fi

    if [ -n "${ECM_TEV:-}" ]; then
        local tag="${ECM_TEV}TeV"
        local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" | sed 's|^\./||' | sort))
        
        for dir in "${p1_dirs[@]}"; do
            local double_dir="${dir}_double"
            if [ -d "$double_dir" ]; then
                cd "$double_dir"
                if python3 histogram_mul_sub.py \
                   > "histogram_log.txt" 2>&1; then
                    log_success "Histogram postprocess of result completed"
                else 
                    log_error "Histogram of results failed" 
                fi
                cd "$WORK_DIR"
            fi
        done
    else
        cd "$WORK_DIR"
        local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" | sed 's|^\./||' | sort))
        for dir in "${p1_dirs[@]}"; do
            local double_dir="${dir}_double"
            if [ -d "$double_dir" ]; then
                cd "$double_dir"
                if python3 histogram_mul_sub.py \
                   > "histogram_log.txt" 2>&1; then
                    log_success "Histogram postprocess of result completed"
                else 
                    log_error "Histogram of results failed" 
                fi
                cd "$WORK_DIR"
            fi
        done
    fi

    local p1_dirs=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" ! -name "*TeV*" | sed 's|^\./||' | sort))
    
    if [ ${#p1_dirs[@]} -eq 0 ]; then
        log_error "No P1_* directories found!"
        exit 1
    fi
    
    for dir in "${p1_dirs[@]}"; do
        if [ -n "${ECM_TEV:-}" ]; then
            local tag="${ECM_TEV}TeV"
            local energy_dir="${dir}_${tag}_double"
            
            if [ ! -d "$OUTPUT_PATH/$name/$energy_dir" ]; then
                mkdir "$OUTPUT_PATH/$name/$energy_dir"
            fi
            
            if [ -f "$WORK_DIR/$energy_dir/gdb_run_output_float-O3_1.out" ]; then
                cp "$WORK_DIR/$energy_dir/gdb_run_output_float-O3_1.out" "$OUTPUT_PATH/$name/$energy_dir/."
            fi
            if [ -d "$WORK_DIR/$energy_dir/boiler_plate/output_promise_files" ]; then
                cp "$WORK_DIR/$energy_dir/boiler_plate/output_promise_files/src/boilerplate/promiseTypes.h" "$OUTPUT_PATH/$name/$energy_dir/."
            fi
        else
            if [ ! -d "$OUTPUT_PATH/$name/$dir" ]; then
                mkdir "$OUTPUT_PATH/$name/$dir"
            fi
        
            cp "$dir/gdb_run_output_float-O3_1.out" "$OUTPUT_PATH/$name/$dir/." 
            cp "$dir/boiler_plate/output_promise_files/src/boilerplate/promiseTypes.h" "$OUTPUT_PATH/$name/$dir/."
        fi
    done

    # Copy promise analysis log files and create summary
    log_info "Creating promise analysis summary..."
    
    {
        echo "PROMISE Analysis Summary"
        echo "========================"
        echo ""
    } > "$OUTPUT_PATH/$name/promise_summary.txt"
    
    for dir in "${p1_dirs[@]}"; do
        if [ -n "${ECM_TEV:-}" ]; then
            local energy_dir="${dir}_${ECM_TEV}TeV_double"
            local log_file="$WORK_DIR/$energy_dir/promise_analysis_${energy_dir}.log"
        else
            local log_file="$WORK_DIR/${dir}_double/promise_analysis_${dir}_double.log"
        fi
        
        if [ -f "$log_file" ]; then
            cp "$log_file" "$OUTPUT_PATH/$name/"
            
            # Extract key stats from the log
            local dir_name
            if [ -n "${ECM_TEV:-}" ]; then
                dir_name="${dir}_${ECM_TEV}TeV_double"
            else
                dir_name="${dir}_double"
            fi
            
            echo "=== $dir_name ===" >> "$OUTPUT_PATH/$name/promise_summary.txt"
            
            # Extract compilation and execution stats
            grep "compilations" "$log_file" | head -1 >> "$OUTPUT_PATH/$name/promise_summary.txt" 2>/dev/null || echo "compilations info not found" >> "$OUTPUT_PATH/$name/promise_summary.txt"
            grep "executions" "$log_file" | head -1 >> "$OUTPUT_PATH/$name/promise_summary.txt" 2>/dev/null || echo "executions info not found" >> "$OUTPUT_PATH/$name/promise_summary.txt"
            
            # Extract timing
            grep "took" "$log_file" | head -1 >> "$OUTPUT_PATH/$name/promise_summary.txt" 2>/dev/null || echo "timing info not found" >> "$OUTPUT_PATH/$name/promise_summary.txt"
            
            # Extract final result
            grep "final result" "$log_file" | head -1 >> "$OUTPUT_PATH/$name/promise_summary.txt" 2>/dev/null || echo "final result info not found" >> "$OUTPUT_PATH/$name/promise_summary.txt"
            
            echo "" >> "$OUTPUT_PATH/$name/promise_summary.txt"
        fi
    done
    
    if [ -f "$OUTPUT_PATH/$name/promise_summary.txt" ]; then
        log_success "Promise analysis summary created"
    fi

    log_success "Step 6 completed - all postprocessing of  analyses finished"
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
        subject="$name Completed Successfully"
    else
        subject="$name FAILED"
    fi

    # Build email body (heredoc)
    local email_body
read -r -d '' email_body <<EOF || true
Process Evaluation Orchestration Report
========================================

Status: $status
Duration: $duration_str
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
Working Directory: $WORK_DIR
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
        mv -f "$OUTPUT_PATH/$PROC_NAME/log_of_progress.txt" "$OUTPUT_PATH/$PROC_NAME/log_of_progress_old.txt"
        touch "$OUTPUT_PATH/$PROC_NAME/log_of_progress.txt"
    else
        touch "$OUTPUT_PATH/$PROC_NAME/log_of_progress.txt"
    fi

    log_info "========================================="
    log_info "Process Evaluation Orchestration Started"
    log_info "========================================="
    log_info "Start time: $(date)"
    log_info "Working directory: $WORK_DIR"
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
    
    if  ! ssh $USER@lxplus.cern.ch 'echo "TRY OUT"' > /dev/null 2>&1  && [ $MAIL_ON_SUCCESS == "true" ]; then
        log_error "Can't access lxplus. Possibly expired kerberos certificate"
        log_info  "Run - kinit -f $USER@CERN.CH or set MAIL_ON_SUCCESS variable"
        exit 1
    fi

    if grep "override FPTYPE" ../Source/make_opts > /dev/null ; then
	    log_warn "Removing override FPTYPE from make_opts"
	    sed '1{/^override FPTYPE/d;}' ../Source/make_opts > make_opts.tmp && mv make_opts.tmp ../Source/make_opts
    fi
    
    if ! promise > /dev/null 2>&1; then
	    log_error "PROMISE was not sourced please source"
	    exit 1
    fi
    # Verify P1_* directories exist in work directory
    log_info "Checking for P1_* directories in work directory..."
    cd "$WORK_DIR"
    
    local p1_check=($(find . -maxdepth 1 -type d -name "P1_*" ! -name "*_float" 2>/dev/null | sed 's|^\./||' | sort))
    
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
    
    # Execute all steps
    step1_copy_directories
    step2_compile_all
    step3_run_all_checks
    step4_compare_all
    step5_promise_analysis
    step6_copy_results
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    
    log_success "========================================="
    log_success "Process evaluation orchestration complete!"
    log_success "========================================="
    log_success "End time: $(date)"
    log_success "Total duration: ${hours}h ${minutes}m ${seconds}s"

    if [ $MAIL_ON_SUCCESS == "true" ]; then
        send_email_notification "SUCCESS" "$duration" 
    fi
}

# Run main function
main "$@"
