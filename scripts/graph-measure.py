#!/usr/bin/env python3

import json
import glob
import matplotlib.pyplot as plt
import numpy as np
import sys
import os
from pathlib import Path

def load_measurement_files():
    """Load all measure-*.json files from current directory"""
    files = glob.glob("measure-*.json")
    if not files:
        print("No measure-*.json files found in current directory")
        sys.exit(1)
    
    data = {}
    for file_path in files:
        # Extract the wildcard part (everything between measure- and .json)
        filename = Path(file_path).name
        label = filename[8:-5]  # Remove "measure-" prefix and ".json" suffix
        
        try:
            with open(file_path, 'r') as f:
                measurements = json.load(f)
                data[label] = measurements
        except json.JSONDecodeError as e:
            print(f"Error reading {file_path}: {e}")
            continue
        except FileNotFoundError:
            print(f"File not found: {file_path}")
            continue
    
    return data

def create_graph(data):
    """Create a matplotlib graph with all measurements"""
    plt.figure(figsize=(12, 8))
    
    # Colors for different datasets
    colors = plt.cm.Set1(np.linspace(0, 1, len(data)))
    
    # Store statistics for later analysis
    stats = {}
    
    for i, (label, measurements) in enumerate(data.items()):
        if not measurements:
            continue
            
        # Extract durations and run numbers
        runs = [m['run'] for m in measurements]
        durations = [float(m['duration_seconds']) for m in measurements]
        
        # Plot line with markers
        plt.plot(runs, durations, 'o-', color=colors[i], label=label, linewidth=2, markersize=6)
        
        # Calculate and store statistics
        avg_duration = np.mean(durations)
        median_duration = np.median(durations)
        std_duration = np.std(durations)
        
        stats[label] = {
            'avg': avg_duration,
            'median': median_duration,
            'std': std_duration,
            'durations': durations
        }
    
    plt.xlabel('Run Number')
    plt.ylabel('Response Time (seconds)')
    plt.title('Query Response Time Measurements')
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    
    # Save the plot
    output_file = 'measurement_graph.png'
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Graph saved as {output_file}")
    
    # Show the plot
    plt.show()
    
    # Print detailed statistics after closing the graph
    print_statistics(stats)

def print_statistics(stats):
    """Print detailed statistics and comparisons"""
    print("\n" + "="*60)
    print("MEASUREMENT STATISTICS")
    print("="*60)
    
    labels = list(stats.keys())
    
    # Print individual statistics
    for label in labels:
        s = stats[label]
        print(f"\n{label.upper()}:")
        print(f"  Average:  {s['avg']:.3f}s")
        print(f"  Median:   {s['median']:.3f}s")
        print(f"  Std Dev:  {s['std']:.3f}s")
        print(f"  Min:      {min(s['durations']):.3f}s")
        print(f"  Max:      {max(s['durations']):.3f}s")
    
    # Compare datasets if we have more than one
    if len(labels) >= 2:
        print(f"\n" + "-"*60)
        print("PERFORMANCE COMPARISONS")
        print("-"*60)
        
        # Sort by average for consistent comparison order
        sorted_labels = sorted(labels, key=lambda x: stats[x]['avg'])
        
        for i in range(len(sorted_labels)):
            for j in range(i + 1, len(sorted_labels)):
                label1, label2 = sorted_labels[i], sorted_labels[j]
                avg1, avg2 = stats[label1]['avg'], stats[label2]['avg']
                
                # Calculate percentage difference
                if avg1 != 0:
                    percent_diff = ((avg2 - avg1) / avg1) * 100
                    if percent_diff > 0:
                        print(f"\n{label1} vs {label2}:")
                        print(f"  {label1} is {percent_diff:.1f}% faster than {label2}")
                        print(f"  ({avg1:.3f}s vs {avg2:.3f}s)")
                    else:
                        print(f"\n{label1} vs {label2}:")
                        print(f"  {label2} is {abs(percent_diff):.1f}% faster than {label1}")
                        print(f"  ({avg2:.3f}s vs {avg1:.3f}s)")
                        
                # Also compare medians
                med1, med2 = stats[label1]['median'], stats[label2]['median']
                if med1 != 0:
                    median_percent_diff = ((med2 - med1) / med1) * 100
                    if median_percent_diff > 0:
                        print(f"  Median: {label1} is {median_percent_diff:.1f}% faster")
                    else:
                        print(f"  Median: {label2} is {abs(median_percent_diff):.1f}% faster")

def main():
    print("Loading measurement files...")
    data = load_measurement_files()
    
    if not data:
        print("No valid measurement data found")
        sys.exit(1)
    
    print(f"Found {len(data)} datasets: {list(data.keys())}")
    create_graph(data)

if __name__ == "__main__":
    main()