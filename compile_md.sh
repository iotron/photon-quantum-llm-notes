#!/bin/bash

# Set the output file
OUTPUT_FILE="/Users/anik/Documents/Obsidian/Claude/llm.txt"

# Clear the output file if it exists
> "$OUTPUT_FILE"

# Find and concatenate all markdown files
find "/Users/anik/Documents/Obsidian/Claude" -name "*.md" -print0 | sort -z | while read -d $'\0' file; do
    echo "FILE: $file" >> "$OUTPUT_FILE"
    echo "---" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo -e "\n\n" >> "$OUTPUT_FILE"
done
