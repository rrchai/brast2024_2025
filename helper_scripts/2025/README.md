# BraTS 2025 Global Synthesis Evaluation Pipeline

This pipeline evaluates submissions for the BraTS 2025 Global Synthesis Challenge, providing automated model inference, prediction processing, and scoring capabilities.

## Prerequisites

- Docker (for running submitted models)
- Conda/Miniconda
- Synapse account with appropriate permissions
- Access to BraTS 2025 - Global Synthesis challenge testing data

## Quick Start

### 1. Environment Setup

Create and activate a conda environment with required dependencies:

```bash
conda create -n synapse python=3.10 -y
conda activate synapse
pip install synapseclient brats cwltool
```

### 2. Workspace Preparation

```bash
mkdir -p workspace && cd workspace
```

1. Download testing data (modalitiy dropped) and groundtruth
2. Get post-processing scripts, `merge_folders.py` and `segmentation.py` from [here](https://www.synapse.org/Synapse:syn68790778) provided by Bran.
3. Get scoring workflow file

```bash
wget https://raw.githubusercontent.com/Sage-Bionetworks-Challenges/brats-infra/refs/heads/main/wf-segmentation/steps/score.cwl
```

### 3. Configure Environment Variables

Set up the required environment variables for your submission:

```bash
export SUBMISSION=<team_name>_<submission_id>
export DOCKER_IMAGE=<docker_image>

export COHORT=<cohort>
export MODEL_NAME=${SUBMISSION}_${COHORT}

export INPUT_DIR=/absolute_path/to/testing_data_directory
export GT_FILE=/absolute_path/to/groundtruth_zip_file

export OUTPUT_DIR=/absolute_path/to/testing_data_directory/output_directory
export LOG_DIR=/absolute_path/to/log_directory
```

**Example configuration:**

```bash
export SUBMISSION=team_9123456
export DOCKER_IMAGE=docker.synapse.org/syn123456/team123@sha123

export COHORT=MET
export MODEL_NAME=${SUBMISSION}_${COHORT}

export INPUT_DIR=$HOME/challenge-data/BraTS2023-MET-Challenge-TestingData_synthesis/
export GT_FILE=$HOME/challenge-data/BraTS2023-MET-Challenge-TestingGT.zip
export OUTPUT_DIR=$HOME/output
export LOG_DIR=$HOME/log
```

## Evaluation Pipeline

The evaluation process consists of three stages:

### Stage 1: Model Inference

Run the submitted Docker model on the test dataset:

```bash
bash run_model.sh \
 -i $INPUT_DIR \
 -o $OUTPUT_DIR/$MODEL_NAME \
 --image $DOCKER_IMAGE \
 --log $LOG_DIR/${MODEL_NAME}_model_inference.log
```

**What it does:**

- Executes the Docker container with test data
- Generates raw predictions and `{MODEL_NAME}.zip`
- Logs runtime and status information

### Stage 2: Prediction Processing

Process and validate the model predictions (runs in background):

```bash
nohup bash process_predictions.sh \
  -i $INPUT_DIR \
  -p $OUTPUT_DIR/$MODEL_NAME/ \
  -o $OUTPUT_DIR \
  --log $LOG_DIR/${MODEL_NAME}_process.log \
  > ${MODEL_NAME}_process_nohup.log 2>&1 &
```

**What it does:**

- Applies post-processing steps to generates final outputs used to score and `{MODEL_NAME}_final.zip`

### Stage 3: Scoring

Evaluate predictions against ground truth:

```bash
nohup bash score.sh \
  --parentId syn68830590 \
  --input_file $OUTPUT_DIR/${MODEL_NAME}_final.zip \
  --goldstandard $GT_FILE \
  --cohort $COHORT \
  --log $LOG_DIR/${MODEL_NAME}_score.log \
  > ${MODEL_NAME}_score_nohup.log 2>&1 &
```

**What it does:**

- Calculates evaluation metrics
- Uploads `all_scores.csv` and `all_full_scores.csv`results to Synapse

## Data Upload to Synapse

### Upload Original Predictions

Upload raw model predictions:

```bash
for file in $OUTPUT_DIR/*.zip; do
  [[ ! "$file" =~ _final ]] && synapse store $file --parentId syn123
done
```

### Upload Processed Outputs

Upload final processed outputs:

```bash
for file in $OUTPUT_DIR/*_final.zip; do
  synapse store $file --parentId syn123
done
```

## Monitoring and Logging

### Log Files

The pipeline generates detailed logs for each stage:

- `{MODEL_NAME}_model_inference.log` - Docker execution logs `$$LOG_DIR`
- `{MODEL_NAME}_process.log` - Processingg logs `$$LOG_DIR`
- `{MODEL_NAME}_score.log` - Scoring and evaluation logs in `$$LOG_DIR`
- `{MODEL_NAME}_*_nohup.log` - Background process outputs in workding directory

### Log Analysis

Use the below script to summarize results from the logs:

```bash
python clean_log.py --log $LOG_DIR
```

This generates `log_summary.csv` with model_info, runtime, status, and error information for all submissions.
