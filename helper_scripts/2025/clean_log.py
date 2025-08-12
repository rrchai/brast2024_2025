#!/usr/bin/env python3

import os
import re
import pandas as pd
import argparse
from pathlib import Path


def parse_log_files(log_dir="~/log/"):
    """Parse log files and extract model_name, task, and runtime into a DataFrame"""

    log_path = Path(log_dir).expanduser()
    data = []

    # Get all log files
    log_files = list(log_path.glob("*.log"))

    for log_file in log_files:
        filename = log_file.name

        # Extract model name and task from filename
        # Pattern: {model_name}_{task}.log
        match = re.match(
            r'(.+)_(model_inference|process|score)\.log$', filename)
        if not match:
            continue

        model_name = match.group(1)
        task = match.group(2)

        # Read the log file and extract runtime
        try:
            with open(log_file, 'r') as f:
                content = f.read().strip()

            # Extract runtime using regex
            runtime_match = re.search(r'Runtime:\s*(\d+)\s*\(s\)', content)
            if runtime_match:
                runtime = int(runtime_match.group(1))
            else:
                runtime = None

            # Extract status
            status_match = re.search(r'Status:\s*([^,]+)', content)
            if status_match:
                status = status_match.group(1).strip()
            else:
                status = None

            # Extract error - get summary directly
            error_match = re.search(
                r'Error:\s*(.*?)(?=\n\n|\Z)', content, re.DOTALL)
            if error_match:
                error_text = error_match.group(1).strip()
                if error_text:
                    # Extract concise error summary
                    error = extract_error_summary(error_text)
                else:
                    error = ""
            else:
                error = ""

        except Exception as e:
            print(f"Error reading {log_file}: {e}")
            runtime = None
            status = None
            error = ""

        data.append({
            'model_name': model_name,
            'task': task,
            'runtime_s': runtime,
            'runtime_min': round(runtime / 60, 2) if runtime else None,
            'runtime_h': round(runtime / 3600, 2) if runtime else None,
            'status': status,
            'error': error
        })

    # Create DataFrame
    df = pd.DataFrame(data)

    # Sort by model_name and task for better readability
    df = df.sort_values(['model_name', 'task']).reset_index(drop=True)

    return df


def extract_error_summary(error_text):
    """Extract a concise error summary from full error text"""
    if not error_text:
        return ""

    # Common error patterns to extract
    patterns = [
        r'([A-Za-z]+Error): (.+?)(?:\n|$)',
        r'([A-Za-z]+Exception): (.+?)(?:\n|$)',
        r'socket\.gaierror: (.+?)(?:\n|$)',
        r'PermissionError: (.+?)(?:\n|$)',
        r'FileNotFoundError: (.+?)(?:\n|$)',
        r'RuntimeError: (.+?)(?:\n|$)'
    ]

    for pattern in patterns:
        match = re.search(pattern, error_text)
        if match:
            if len(match.groups()) == 2:
                return f"{match.group(1)}: {match.group(2)}"
            else:
                return match.group(1)

    # If no specific pattern matches, return first line or truncated text
    first_line = error_text.split('\n')[0].strip()
    if len(first_line) > 100:
        return first_line[:100] + "..."
    return first_line


if __name__ == "__main__":
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description="Parse log files and extract model performance data")
    parser.add_argument("--log", default="~/log/",
                        help="Directory containing log files (default: ~/log/)")

    args = parser.parse_args()

    # Parse logs and create DataFrame
    df = parse_log_files(args.log)

    # Save to CSV in current working directory
    output_file = "log_summary.csv"
    df.to_csv(output_file, index=False)
    print(f"\nData saved to: {output_file}")

    # Summary statistics
    print(f"Total submissions: {df['model_name'].nunique()}")

    # Calculate completed vs failed submissions
    completed_count = 0
    failed_count = 0

    for model in df['model_name'].unique():
        model_data = df[df['model_name'] == model]

        # Check if all 3 tasks are present and completed
        expected_tasks = {'model_inference', 'process', 'score'}
        present_tasks = set(model_data['task'])
        completed_tasks = set(
            model_data[model_data['status'] == 'Completed']['task'])

        # Completed: all 3 tasks present AND all completed
        if expected_tasks == present_tasks and expected_tasks.issubset(completed_tasks):
            completed_count += 1
        else:
            # Failed: missing tasks OR any task failed/not completed
            failed_count += 1

    print(f"    Complete: {completed_count}")
    print(f"    Fail: {failed_count}")
