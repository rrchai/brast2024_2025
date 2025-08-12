#!/bin/bash

# Docker Container Runner Script
# Usage: ./run_docker.sh -i <input_dir> -o <output_dir> --image <docker_image>

set -e  # Exit on any error

# Initialize variables
INPUT_DIR=""
OUTPUT_DIR=""
DOCKER_IMAGE=""
LOG_FILE="model_inference.log"

# Function to display usage
usage() {
    echo "Usage: $0 -i <input_directory> -o <output_directory> --image <docker_image> [OPTIONS]"
    echo ""
    echo "       NVIDIA Docker runtime for GPU support is required."
    echo ""
    echo "Required flags:"
    echo "  -i, --input       Input directory for testing dataset (mounted as read-only)"
    echo "  -o, --output      Output directory for prediction (mounted as read-write)"
    echo "  --image           Docker image to run"
    echo ""
    echo "Optional flags:"
    echo "  --log             Log file path (default: model_inference.log)"
    echo "  -h, --help        Show this help message"
    echo ""
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            INPUT_DIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --image)
            DOCKER_IMAGE="$2"
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
if [ -z "$INPUT_DIR" ]; then
    echo "Error: Input directory (-i/--input) is required"
    echo ""
    usage
fi

if [ -z "$OUTPUT_DIR" ]; then
    echo "Error: Output directory (-o/--output) is required"
    echo ""
    usage
fi

if [ -z "$DOCKER_IMAGE" ]; then
    echo "Error: Docker image (--image) is required"
    echo ""
    usage
fi

# Validate input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory '$INPUT_DIR' does not exist"
    exit 1
fi

# Create output directory if it doesn't exist
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Convert to absolute paths
INPUT_DIR=$(realpath "$INPUT_DIR")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")

# Extract just the folder name (without parent path) for container naming
INPUT_FOLDER_NAME=$(basename "$INPUT_DIR")

# Clean image name for container naming (replace special chars with underscores)
CLEAN_IMAGE_NAME=$(echo "$DOCKER_IMAGE" | sed 's/[^a-zA-Z0-9._-]/_/g')

# Create container name from input folder and image
CONTAINER_NAME="${INPUT_FOLDER_NAME}_${CLEAN_IMAGE_NAME}"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi

# Check if NVIDIA Docker runtime is available
if ! docker info | grep -q "nvidia"; then
    echo "Warning: NVIDIA Docker runtime may not be available"
    echo "GPU functionality might not work properly"
fi

# Display configuration
echo "============================================"
echo "Docker Container Runner"
echo "============================================"
echo "Input Directory:  $INPUT_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Docker Image:     $DOCKER_IMAGE"
echo "Container Name:   $CONTAINER_NAME"
echo "Log File:         $LOG_FILE"
echo "============================================"

# Confirm before running
read -p "Proceed with execution? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Execution cancelled"
    exit 0
fi

# Create output directory if it doesn't exist
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi


# Create parent directory for log file if it doesn't exist
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ]; then
    echo "Creating log directory: $LOG_DIR"
    mkdir -p "$LOG_DIR"
fi


# Run the Docker container
echo "Starting Docker container in detached mode..."
echo "Container name: $CONTAINER_NAME"
echo "Command: docker run -v $INPUT_DIR:/input:ro -v $OUTPUT_DIR:/output:rw --network none --gpus all -d --name $CONTAINER_NAME $DOCKER_IMAGE"
echo ""

# Record start time
START_TIME=$(date +%s)
START_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

CONTAINER_ID=$(docker run \
    -v "$INPUT_DIR":/input:ro \
    -v "$OUTPUT_DIR":/output:rw \
    --network none \
    --user root \
    --gpus all \
    --shm-size=8g \
    -d \
    --name "$CONTAINER_NAME" \
    "$DOCKER_IMAGE")

echo "Container: $CONTAINER_NAME started ($CONTAINER_ID)"

# Background process to monitor completion and log runtime
(
    # Wait for container to finish
    docker wait "$CONTAINER_NAME" > /dev/null 2>&1
    
    # Calculate runtime
    END_TIME=$(date +%s)
    RUNTIME=$((END_TIME - START_TIME))
    
    # Get exit code and determine status
    EXIT_CODE=$(docker inspect "$CONTAINER_NAME" --format='{{.State.ExitCode}}' 2>/dev/null || echo "unknown")
    
    if [ "$EXIT_CODE" = "0" ]; then
        STATUS="Completed"
        ERROR_MESSAGE=""
    elif [ "$EXIT_CODE" = "unknown" ]; then
        STATUS="Unknown"
        ERROR_MESSAGE="Container inspection failed"
    else
        STATUS="Failed"
        ERROR_MESSAGE=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -20)
    fi
    
    # Log completion with status
    echo "Docker Image: $DOCKER_IMAGE, Input Folder: $INPUT_DIR, Start Time: $START_TIMESTAMP, Runtime: $RUNTIME (s), Status: $STATUS, Error: $ERROR_MESSAGE" >> "$LOG_FILE"

    # Create zip file if container completed successfully
    if [ "$EXIT_CODE" = "0" ]; then
        echo "Creating zip file from NIfTI files in output directory..."
        OUTPUT_DIR_NAME=$(basename "$OUTPUT_DIR")
        
        # zip all .nii.gz files
        cd "$OUTPUT_DIR"
        if ls *.nii.gz 2>/dev/null | head -1 > /dev/null; then
            zip -r "../${OUTPUT_DIR_NAME}.zip" *.nii.gz 2>/dev/null || true
            echo "Zip file created: $(dirname "$OUTPUT_DIR")/${OUTPUT_DIR_NAME}.zip"
        else
            echo "No NIfTI files found in output directory"
        fi
        cd - > /dev/null
    fi
) &