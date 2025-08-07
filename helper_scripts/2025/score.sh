#!/bin/bash

# CWL Scoring Script
# Usage: ./score.sh --parentId <synapse_parent_id> --input_file <input_file> --goldstandard <goldstandard> --cohort <cohort> [--log <log_file>]

set -e  # Exit on any error

# Initialize variables
PARENT_ID=""
INPUT_FILE=""
GOLDSTANDARD=""
COHORT=""
LOG_FILE="scoring_results.log"

# Function to display usage
usage() {
    echo "Usage: $0 --parentId <synapse_parent_id> --input_file <input_file> --goldstandard <goldstandard> --cohort <cohort> [OPTIONS]"
    echo ""
    echo "Required flags:"
    echo "  --parentId        Synapse parent ID for creating result folder"
    echo "  --input_file      Segmentation results file (zip) path"
    echo "  --goldstandard    Gold standard (zip) file path"
    echo "  --cohort          Cohort name (e.g., GLI, MEN, MET)"
    echo ""
    echo "Optional flags:"
    echo "  --log             Log file path (default: scoring_results.log)"
    echo "  -h, --help        Show this help message"
    echo ""
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --parentId)
            PARENT_ID="$2"
            shift 2
            ;;
        --input_file)
            INPUT_FILE="$2"
            shift 2
            ;;
        --goldstandard)
            GOLDSTANDARD="$2"
            shift 2
            ;;
        --cohort)
            COHORT="$2"
            shift 2
            ;;
        --log)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option '$1'"
            echo ""
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$PARENT_ID" ]; then
    echo "Error: Parent ID (--parentId) is required"
    echo ""
    usage
fi

if [ -z "$INPUT_FILE" ]; then
    echo "Error: Input file (--input_file) is required"
    echo ""
    usage
fi

if [ -z "$GOLDSTANDARD" ]; then
    echo "Error: Gold standard (--goldstandard) is required"
    echo ""
    usage
fi

if [ -z "$COHORT" ]; then
    echo "Error: Cohort (--cohort) is required"
    echo ""
    usage
fi

# Validate input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist"
    exit 1
fi

# Validate goldstandard file exists
if [ ! -f "$GOLDSTANDARD" ]; then
    echo "Error: Gold standard file '$GOLDSTANDARD' does not exist"
    exit 1
fi

# Extract model name from input file path
MODEL_NAME=$(basename "$INPUT_FILE" | sed 's/_final\.zip$//')

# Create parent directory for log file if it doesn't exist
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ]; then
    echo "Creating log directory: $LOG_DIR"
    mkdir -p "$LOG_DIR"
fi

# Display configuration
echo "============================================"
echo "CWL Scoring Runner"
echo "============================================"
echo "Parent ID:        $PARENT_ID"
echo "Input File:       $INPUT_FILE"
echo "Gold Standard:    $GOLDSTANDARD"
echo "Cohort:           $COHORT"
echo "Model Name:       $MODEL_NAME"
echo "Log File:         $LOG_FILE"
echo "============================================"

# Record start time
START_TIME=$(date +%s)

echo "Starting scoring process..."

# Create Synapse folder for results
echo "Creating Synapse folder: $MODEL_NAME"
FOLDER_CREATE_OUTPUT=$(synapse create Folder --name "$MODEL_NAME" --parentId "$PARENT_ID" 2>&1)
FOLDER_ID=$(echo "$FOLDER_CREATE_OUTPUT" | grep -oP 'syn\d+' | tail -1)

if [ -z "$FOLDER_ID" ]; then
    echo "Error: Failed to create Synapse folder"
    echo "Output: $FOLDER_CREATE_OUTPUT"
    exit 1
fi

echo "Created Synapse folder: $FOLDER_ID"

# Run CWL scoring process
echo "Running CWL scoring process..."

# Run cwltool directly (no nohup needed since script itself will be run with nohup)
cwltool score.cwl \
    --parent_id "$FOLDER_ID" \
    --synapse_config ~/.synapseConfig \
    --input_file "$INPUT_FILE" \
    --goldstandard "$GOLDSTANDARD" \
    --label "BraTS-${COHORT}"

# Capture exit code
EXIT_CODE=$?

# Calculate runtime
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

# Determine status based on exit code
if [ "$EXIT_CODE" = "0" ]; then
    STATUS="Completed"
    ERROR_MESSAGE=""
    echo "Scoring completed successfully"
else
    STATUS="Failed"
    ERROR_MESSAGE="CWL scoring failed with exit code $EXIT_CODE"
    echo "Scoring failed with exit code: $EXIT_CODE"
fi

# Log completion with status
echo "CWL Scoring: score.cwl, Model: $MODEL_NAME, Cohort: $COHORT, Synapse Folder: $FOLDER_ID, Start Time: $START_TIME, Runtime: $RUNTIME (s), Status: $STATUS, Error: $ERROR_MESSAGE" >> "$LOG_FILE"

# Clean up - no temporary files to remove

echo "============================================"
echo "Scoring Process Summary"
echo "============================================"
echo "Status: $STATUS"
echo "Runtime: $RUNTIME seconds"
echo "Synapse Folder: $FOLDER_ID"
echo "Log saved to: $LOG_FILE"
echo "============================================"

# Exit with original exit code
exit $EXIT_CODE