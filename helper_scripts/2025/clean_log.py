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
        match = re.match(r'(.+)_(model_inference|process|score)\.log$', filename)
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
            
            # Extract error (can be empty after "Error:")
            error_match = re.search(r'Error:\s*(.*)', content)
            if error_match:
                error = error_match.group(1).strip()
                # If error is empty, set to None
                if not error:
                    error = None
            else:
                error = None
                
        except Exception as e:
            print(f"Error reading {log_file}: {e}")
            runtime = None
            status = None
            error = None
        
        data.append({
            'model_name': model_name,
            'task': task,
            'runtime': runtime,
            'status': status,
            'error': error
        })
    
    # Create DataFrame
    df = pd.DataFrame(data)
    
    # Sort by model_name and task for better readability
    df = df.sort_values(['model_name', 'task']).reset_index(drop=True)
    
    return df

if __name__ == "__main__":
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Parse log files and extract model performance data")
    parser.add_argument("--log", default="~/log/", 
                        help="Directory containing log files (default: ~/log/)")
    
    args = parser.parse_args()
    
    # Parse logs and create DataFrame
    df = parse_log_files(args.log)
    
    # Get the expanded log path for saving CSV
    log_path = Path(args.log).expanduser()
    
    # Display the DataFrame
    print("Parsed Log Data:")
    print(df.to_string(index=False))
    
    # Save to CSV in current working directory
    output_file = "log_summary.csv"
    df.to_csv(output_file, index=False)
    print(f"\nData saved to: {output_file}")
    
    # Optional: Show some basic statistics
    print(f"\nSummary:")
    print(f"Total entries: {len(df)}")
    print(f"Unique models: {df['model_name'].nunique()}")
    print(f"Tasks: {df['task'].unique().tolist()}")