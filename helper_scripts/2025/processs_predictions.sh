#!/bin/bash

# Parse command line arguments
LOG_FILE="process_predictions.log"

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            input_folder="$2"
            shift 2
            ;;
        -p|--pred)
            pred_folder="$2"
            shift 2
            ;;
        -o|--output)
            output_folder="$2"
            shift 2
            ;;
        --log)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 -i <input_folder> -p <pred_folder> -o <output_folder> [--log <log_file>]"
            echo "  -i, --input     Folder for testing data"
            echo "  -p, --pred      Folder for predictions"
            echo "  -o, --output    Folder for final output"
            echo "  --log           Log file path (default: process_predictions.log)"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Check if all required arguments are provided
if [[ -z "$input_folder" || -z "$pred_folder" || -z "$output_folder" ]]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 -i <input_folder> -p <pred_folder> -o <output_folder>"
    exit 1
fi

# Create local tmp directory in current working directory
LOCAL_TMP="$(pwd)/tmp"
mkdir -p "$LOCAL_TMP"

# Set derived folder names - use local tmp for writable space
temp_input_folder="$LOCAL_TMP/$(basename "${input_folder%/}")_copy"
merged_folder="$LOCAL_TMP/$(basename "${pred_folder%/}")_merged"
temp_output_folder="$LOCAL_TMP/$(basename "${pred_folder%/}")_final"

# Create parent directory for log file if it doesn't exist
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ]; then
    echo "Creating log directory: $LOG_DIR"
    mkdir -p "$LOG_DIR"
fi

echo "Input folder: $input_folder"
echo "Prediction folder: $pred_folder"
echo "Output folder: $output_folder"
echo "Temp input folder: $temp_input_folder"
echo "Merged folder: $merged_folder"
echo "Temp output folder: $temp_output_folder"
echo "Log file: $LOG_FILE"

# Copy input folder to temp location for modification
echo "Copying input folder to temp location for modification..."
cp -r "$input_folder" "$temp_input_folder"

# Restructure and merge predictions
echo "Restructuring and merging predictions..."
# synapse get syn68790795
MERGE_OUTPUT=$(python merge_folders.py -f "$temp_input_folder" -i "$pred_folder" -o "$merged_folder" 2>&1)
MERGE_EXIT_CODE=$?

echo "$MERGE_OUTPUT"

if [ $MERGE_EXIT_CODE -eq 0 ] && [[ ! "$MERGE_OUTPUT" =~ "Error:" ]]; then
    echo "Merge completed successfully"
else
    echo "Error: Merge failed. Stopping execution."
    echo "Output: $MERGE_OUTPUT"
    # Cleanup temp input folder on failure
    rm -rf "$temp_input_folder" "$temp_output_folder"
    exit 1
fi

# Generate final segmentation output with runtime logging
echo "Generating final segmentation output..."
# synapse get syn68790793

# Record start time
START_TIME=$(date +%s)
START_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Run segmentation and capture exit code
if python segmentation.py -i "$merged_folder" -o "$temp_output_folder"; then
    EXIT_CODE=0
    STATUS="Completed"
    ERROR_MESSAGE=""
    echo "Segmentation completed successfully"
else
    EXIT_CODE=$?
    STATUS="Failed"
    ERROR_MESSAGE="Segmentation script failed with exit code $EXIT_CODE"
    echo "Segmentation failed with exit code: $EXIT_CODE"
fi

# Calculate runtime
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

# Log segmentation completion with runtime only
echo "Folder: $merged_folder, Runtime: $RUNTIME (s), Status: $STATUS, Error: $ERROR_MESSAGE" >> "$LOG_FILE"

# Check if segmentation was successful before proceeding
if [ $EXIT_CODE -ne 0 ]; then
    echo "Error: Segmentation failed. Stopping execution."
    exit 1
fi

# Zip final output
echo "Finalizing results..."

# Check if temp output folder exists
if [[ ! -d "$temp_output_folder" ]]; then
    echo "Error: Temp output folder '$temp_output_folder' does not exist!"
    echo "Segmentation may have failed. Please check the previous steps."
    exit 1
fi

# Create final output directory
mkdir -p "$output_folder"

# Rename files to remove "-seg" before zipping
cd "$temp_output_folder"
for file in *-seg.nii.gz; do
    if [ -f "$file" ]; then
        new_name="${file/-seg.nii.gz/.nii.gz}"
        mv "$file" "$new_name"
        echo "Renamed: $file -> $new_name"
    fi
done

# Create zip with renamed files
echo "Creating zip file from: $temp_output_folder"
zip -r "../$(basename ${temp_output_folder}).zip" *.nii.gz
cd - > /dev/null

# Move zip file to output directory
zip_filename="$(basename ${temp_output_folder}).zip"
echo "Moving zip file to output directory: $output_folder"
mv "$LOCAL_TMP/$zip_filename" "$output_folder/"

# Remove intermediate folders
echo "Cleaning up intermediate folders..."
rm -rf "$merged_folder" "$temp_output_folder" "$temp_input_folder"

echo "Runtime log saved to: $LOG_FILE"