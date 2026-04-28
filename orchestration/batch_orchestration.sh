#!/bin/bash
SCRIPT_START_DIR="$(pwd)"

#########################
# MadGraph Batch Processor with Orchestration
#########################
#
# Processes all files in __ins/ directory sequentially:
# 1. Run mg5_aMC on each file
# 2. Enter SubProcesses directory
# 3. Link and run orchestration
# 4. Wait for completion
# 5. Clean up and move to next
#
#########################

set -euo pipefail

#########################
# Configuration
#########################

# Directories
INS_DIR="__ins"

MG5_PATH="${MG5_PATH:-./bin/mg5_aMC}"
CADNA_TOOLBOX_PATH="${CADNA_TOOLBOX_PATH:-/path/to/cadna/toolbox}"
#ORCHESTRATION_SCRIPT="$CADNA_TOOLBOX_PATH/orchestration/orchestrate_process_evaluation.sh"
ORCHESTRATION_SCRIPT="$CADNA_TOOLBOX_PATH/orchestration/orchestrate_Energy_study.sh"
SCRIPT_NAME="orchestrate_Energy_study.sh"

# Logging
BATCH_LOG_DIR="$(pwd)/batch_logs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BATCH_LOG_DIR"

SCRIPT_START_DIR="$(pwd)"
#########################
# Color output
#########################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$BATCH_LOG_DIR/batch.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$BATCH_LOG_DIR/batch.log"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$BATCH_LOG_DIR/batch.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$BATCH_LOG_DIR/batch.log"
}

log_step() {
    echo -e "${MAGENTA}[STEP]${NC} $*" | tee -a "$BATCH_LOG_DIR/batch.log"
}

#########################
# Validation
#########################

validate_setup() {
    log_info "Validating setup..."
    
    # Check __ins directory exists
    if [ ! -d "$INS_DIR" ]; then
        log_error "__ins directory not found: $INS_DIR"
        exit 1
    fi
    
    # Check mg5_aMC exists
    if [ ! -f "$MG5_PATH" ]; then
        log_error "mg5_aMC not found: $MG5_PATH"
        exit 1
    fi
    
    # Check orchestration script exists
    if [ ! -f "$ORCHESTRATION_SCRIPT" ]; then
        log_error "Orchestration script not found: $ORCHESTRATION_SCRIPT"
        exit 1
    fi
    
    # Count files in __ins
    local file_count=$(find "$INS_DIR" -type f | wc -l)
    if [ $file_count -eq 0 ]; then
        log_error "No files found in $INS_DIR"
        exit 1
    fi

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

   
#    if ! promise > /dev/null 2>&1; then
#	    log_error "PROMISE was not sourced please source"
#	    exit 1
#    fi
 
    
    log_success "Validation passed"
    log_info "Found $file_count files to process"
}

#########################
# Process Single File
#########################

process_file() {
    local input_file="$1"
    local file_number="$2"
    local total_files="$3"
    
    local file_basename=$(basename "$input_file")
    local file_name="${file_basename%.*}"  # Remove extension
    
    log_step "========================================="
    log_step "Processing file $file_number/$total_files: $file_basename"
    log_step "========================================="
    
    local step_start_time=$(date +%s)

    local starting_dir=$(pwd)    

    #########################
    # Step 1: Run mg5_aMC
    #########################
    
    log_info "Step 1: Running mg5_aMC on $file_basename"
    
    local mg5_log="$BATCH_LOG_DIR/${file_name}_mg5.log"
    
    if "$MG5_PATH" "$INS_DIR/$file_basename" > "$mg5_log" 2>&1; then
        log_success "mg5_aMC completed for $file_basename"
    else
        log_error "mg5_aMC failed for $file_basename"
        log_error "Check log: $mg5_log"
        return 1
    fi
    
    #########################
    # Step 2: Find and enter SubProcesses directory
    #########################
    
    log_info "Step 2: Locating SubProcesses directory"
    
    # Try to find the generated directory
    local process_dir=""
    
    # Common patterns for MadGraph output directories
    if [ -d "$file_name/SubProcesses" ]; then
        process_dir="$file_name/SubProcesses"
    elif [ -d "${file_name}/SubProcesses" ]; then
        process_dir="${file_name}/SubProcesses"
    else
        # Search for it
        process_dir=$(find . -maxdepth 2 -type d -name "SubProcesses" -path "*${file_name}*" | head -1)
    fi
    
    if [ -z "$process_dir" ]; then
        log_error "SubProcesses directory not found for $file_name"
        log_error "Expected: $file_name/SubProcesses"
        return 1
    fi
    
    log_success "Found SubProcesses at: $process_dir"
    
    cd "$process_dir"
    local subprocess_dir=$(pwd)
    
    #########################
    # Step 3: Link orchestration script
    #########################
    
    log_info "Step 3: Linking orchestration script"
    
    if [ -L $SCRIPT_NAME ]; then
        log_info "Orchestration script already linked, removing old link"
        rm -f $SCRIPT_NAME
    fi
    
    ln -s "$ORCHESTRATION_SCRIPT" $SCRIPT_NAME
    
    if [ ! -x $SCRIPT_NAME ]; then
        chmod +x $SCRIPT_NAME
    fi
    
    log_success "Orchestration script linked"
     
    #########################
    # Step 4: Copy cuts.toml to SubProcesses dir 
    #########################
    
    local cuts_file="$SCRIPT_START_DIR/$INS_DIR/cuts/$file_name.toml" 

    if [ -f  $cuts_file ]; then
	    cp -f $cuts_file "./cuts.toml"
	    echo "Successfully copied cuts to respective SubProcesses dir."
    else	
	    echo "Were not able to find the cuts.toml as:"
	    echo $cuts_file
    fi

    #########################
    # Step 5: Run orchestration
    #########################
    
    log_info "Step 5: Running orchestration for $file_name"
    
    local orch_log="$BATCH_LOG_DIR/${file_name}_orchestration.log"
    local orch_pid_file="$BATCH_LOG_DIR/${file_name}_orchestration.pid"
    
    # Run orchestration in background with nohup
    nohup ./$SCRIPT_NAME "$(pwd)" \
        > "$orch_log" 2>&1 &
    
    local orch_pid=$!
    echo "$orch_pid" > "$orch_pid_file"
    
    log_success "Orchestration started (PID: $orch_pid)"
    log_info "Log file: $orch_log"
    
    #########################
    # Step 6: Wait for orchestration to complete
    #########################
    
    log_info "Step 6: Waiting for orchestration to complete..."
    log_info "Monitoring for step completions (won't spam logs)"
    
    local wait_interval=10  # Check every 10 seconds
    local last_logged_line=""
    
    while ps -p "$orch_pid" > /dev/null 2>&1; do
        sleep $wait_interval
        
        # Check for new step completions in the log
        if [ -f "$orch_log" ]; then
            # Look for SUCCESS step completions
            local latest_step=$(grep -E "\[SUCCESS\] Step [0-9]" "$orch_log" | tail -1)
            
            # If we found a new step completion, log it
            if [ -n "$latest_step" ] && [ "$latest_step" != "$last_logged_line" ]; then
                log_success "Orchestration: $latest_step"
                last_logged_line="$latest_step"
            fi
        fi
    done
    
    # Check exit status by looking at the orchestration log
    local orch_exit_code=1  # Assume failure
    
    if [ -f "$orch_log" ]; then
        # Check if orchestration completed successfully
        if grep -q "Process evaluation orchestration complete!" "$orch_log"; then
            orch_exit_code=0
            log_success "Orchestration completed successfully for $file_name"
        elif grep -q "\[ERROR\].*Cleanup complete (script failed)" "$orch_log"; then
            log_error "Orchestration failed for $file_name"
            log_error "Check log: $orch_log"
            
            # Show last 20 lines of log
            log_error "Last 20 lines of orchestration log:"
            tail -20 "$orch_log" | sed 's/^/  | /'
            
            return 1
        else
            log_warn "Orchestration status unclear for $file_name"
            log_warn "Check log: $orch_log"
            # Don't return 1 - continue processing
        fi
    else
        log_error "Orchestration log not found: $orch_log"
        return 1
    fi
    
    #########################
    # Step 7: Clean up (optional - can be disabled)
    #########################
    
    cd "$SCRIPT_START_DIR"

    if [ "${KEEP_PROCESS_DIRS:-false}" != "true" ]; then
        log_info "Step 7: Cleaning up process directory"
        
        # Get the base process directory (parent of SubProcesses)
        local base_dir=$(dirname "$subprocess_dir")
        
        log_warn "Removing directory: $base_dir"
        #rm -rf "$base_dir"
        
        log_success "Cleanup completed"
    else
        log_info "Step 6: Keeping process directory (KEEP_PROCESS_DIRS=true)"
    fi
    
    # Calculate step duration
    local step_end_time=$(date +%s)
    local step_duration=$((step_end_time - step_start_time))
    local step_hours=$((step_duration / 3600))
    local step_minutes=$(((step_duration % 3600) / 60))
    local step_seconds=$((step_duration % 60))
    
    log_success "File $file_basename processed in ${step_hours}h ${step_minutes}m ${step_seconds}s"
    
    return 0
}

#########################
# Main batch processing
#########################

main() {
    local start_time=$(date +%s)
    
    log_info "========================================="
    log_info "MadGraph Batch Processor Started"
    log_info "========================================="
    log_info "Start time: $(date)"
    log_info "Batch log directory: $BATCH_LOG_DIR"
    log_info "Input directory: $INS_DIR"
    log_info "MadGraph binary: $MG5_PATH"
    log_info "Orchestration script: $ORCHESTRATION_SCRIPT"
    
        echo ""
    
    # Validate setup
    validate_setup
    
    echo ""
    
    # Get list of files to process
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$INS_DIR" -type f ! -name '*.toml' -print0 | sort -z)
    
    local total_files=${#files[@]}
    local processed=0
    local failed=0
    local failed_files=()
    
    log_info "Processing $total_files files sequentially"
    echo ""

    # Process each file
    for i in "${!files[@]}"; do
        local file="${files[$i]}"
        local file_number=$((i + 1))
        
        log_info "=== Loop iteration $file_number of $total_files ==="
        log_info "Processing: $file"
        
        if process_file "$file" "$file_number" "$total_files"; then
            processed=$((processed + 1))
            log_info "=== File $file_number succeeded, processed count: $processed ==="
        else
            failed=$((failed + 1))
            failed_files+=("$(basename "$file")")
            log_warn "=== File $file_number failed, failed count: $failed ==="
        fi
        
        log_info "=== End of iteration $file_number, continuing loop... ==="
        echo ""
    done

       # Summary
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    local total_hours=$((total_duration / 3600))
    local total_minutes=$(((total_duration % 3600) / 60))
    local total_seconds=$((total_duration % 60))
    
    log_info "========================================="
    log_info "Batch Processing Summary"
    log_info "========================================="
    log_info "Total files: $total_files"
    log_success "Processed successfully: $processed"
    
    if [ $failed -gt 0 ]; then
        log_error "Failed: $failed"
        log_error "Failed files:"
        for failed_file in "${failed_files[@]}"; do
            log_error "  - $failed_file"
        done
    fi
    
    log_info "Total duration: ${total_hours}h ${total_minutes}m ${total_seconds}s"
    log_info "Logs saved in: $BATCH_LOG_DIR"
    log_info "========================================="
    
    if [ $failed -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main "$@"

