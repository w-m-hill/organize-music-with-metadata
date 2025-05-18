#!/bin/bash

# Script to rename and organize music files based on metadata using ffmpeg

# --- Configuration ---
# Base directory to search for music files.
# If the script is in the directory you want to organize, you can use:
# MUSIC_BASE_DIR="."
# Or specify an absolute or relative path:
# MUSIC_BASE_DIR="/path/to/your/music"
MUSIC_BASE_DIR="."

# --- Helper Functions ---

# Function to extract metadata using ffprobe (part of ffmpeg)
get_metadata() {
  local file_path="$1"
  local metadata_field="$2" # e.g., album, artist, title
  local value

  # ffprobe can output in various formats. We'll use a simple key=value format.
  # We look for the tag with the specified name.
  # Different file types might store tags with slightly different names.
  # Common tags: album, artist, title, track
  # For track name, ffmpeg usually uses 'title'.
  # For artist name, ffmpeg usually uses 'artist'.
  # For album name, ffmpeg usually uses 'album'.

  # Attempt to get the metadata tag
  value=$(ffprobe -v quiet -show_entries format_tags="$metadata_field" -of default=noprint_wrappers=1:nokey=1 "$file_path")

  # If ffprobe didn't find the tag directly, try with common variations
  if [ -z "$value" ]; then
    if [ "$metadata_field" == "title" ]; then
      value=$(ffprobe -v quiet -show_entries format_tags=TITLE -of default=noprint_wrappers=1:nokey=1 "$file_path")
    elif [ "$metadata_field" == "artist" ]; then
      value=$(ffprobe -v quiet -show_entries format_tags=ARTIST -of default=noprint_wrappers=1:nokey=1 "$file_path")
    elif [ "$metadata_field" == "album" ]; then
      value=$(ffprobe -v quiet -show_entries format_tags=ALBUM -of default=noprint_wrappers=1:nokey=1 "$file_path")
    fi
  fi
  
  # Sanitize the value: remove characters that are problematic for filenames
  # This removes / \ : * ? " < > | and leading/trailing spaces/dots
  if [ -n "$value" ]; then
    value=$(echo "$value" | sed 's/[][\\\/:\*\?"<>|]//g' | sed 's/^[. ]*//;s/[. ]*$//')
  fi

  echo "$value"
}

# --- Main Script ---

echo "Music Organization Script"
echo "-------------------------"
echo "Base directory: $MUSIC_BASE_DIR"
echo ""

# Check if ffmpeg (ffprobe) is installed
if ! command -v ffprobe &> /dev/null; then
  echo "Error: ffprobe (from ffmpeg) is not installed. Please install ffmpeg."
  exit 1
fi

# Find all specified music files recursively
# -o means OR, -print0 and while read -d $'\0' handle filenames with spaces/special chars
find "$MUSIC_BASE_DIR" -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" -o -iname "*.wav" \) -print0 | while IFS= read -r -d $'\0' file; do
  echo "Processing: $file"

  original_dir=$(dirname "$file")
  original_filename=$(basename "$file")
  extension="${original_filename##*.}"
  filename_no_ext="${original_filename%.*}"

  # Extract metadata
  album=$(get_metadata "$file" "album")
  artist=$(get_metadata "$file" "artist")
  track_name=$(get_metadata "$file" "title") # ffmpeg often uses 'title' for track name

  echo "  Album: '${album:-N/A}'"
  echo "  Artist: '${artist:-N/A}'"
  echo "  Track: '${track_name:-N/A}'"

  # Determine target directory
  target_dir_name=""
  if [ -n "$album" ]; then
    # Sanitize album name for directory creation
    sane_album_name=$(echo "$album" | sed 's/[][\\\/:\*\?"<>|]//g' | sed 's/^[. ]*//;s/[. ]*$//')
    if [ -n "$sane_album_name" ]; then
        target_dir_name="$sane_album_name"
    fi
  fi

  # If target_dir_name is empty, it means no album or sanitized album name is empty
  if [ -z "$target_dir_name" ]; then
    target_path_base="$MUSIC_BASE_DIR"
    echo "  No valid album name found. Target base directory: $MUSIC_BASE_DIR"
  else
    target_path_base="$MUSIC_BASE_DIR/$target_dir_name"
    echo "  Target album directory: $target_path_base"
  fi

  # Create target directory if it doesn't exist
  if [ ! -d "$target_path_base" ]; then
    echo "  Creating directory: $target_path_base"
    mkdir -p "$target_path_base"
    if [ $? -ne 0 ]; then
        echo "  Error: Could not create directory '$target_path_base'. Skipping file."
        continue
    fi
  fi

  # Determine new filename
  new_filename_no_ext=""
  if [ -n "$artist" ] && [ -n "$track_name" ]; then
    sane_artist=$(echo "$artist" | sed 's/[][\\\/:\*\?"<>|]//g' | sed 's/^[. ]*//;s/[. ]*$//')
    sane_track_name=$(echo "$track_name" | sed 's/[][\\\/:\*\?"<>|]//g' | sed 's/^[. ]*//;s/[. ]*$//')
    if [ -n "$sane_artist" ] && [ -n "$sane_track_name" ]; then
        new_filename_no_ext="${sane_artist} - ${sane_track_name}"
    fi
  elif [ -n "$track_name" ]; then
    sane_track_name=$(echo "$track_name" | sed 's/[][\\\/:\*\?"<>|]//g' | sed 's/^[. ]*//;s/[. ]*$//')
     if [ -n "$sane_track_name" ]; then
        new_filename_no_ext="$sane_track_name"
    fi
  fi

  final_new_filename="$original_filename" # Default to original if no new name could be formed
  if [ -n "$new_filename_no_ext" ]; then
    final_new_filename="${new_filename_no_ext}.${extension}"
  fi
  
  # Sanitize the final filename again just in case
  final_new_filename_sanitized=$(echo "$final_new_filename" | sed 's/[][\\\/:\*\?"<>|]//g' | sed 's/^[. ]*//;s/[. ]*$//')
  if [ -z "$final_new_filename_sanitized" ]; then # if sanitization results in empty string
    echo "  Warning: Sanitized new filename is empty. Using original filename part: $filename_no_ext"
    final_new_filename_sanitized="${filename_no_ext}.${extension}"
    if [ "$final_new_filename_sanitized" == "." ]; then # if filename was just an extension
        echo "  Error: Could not determine a valid filename for '$file'. Skipping."
        continue
    fi
  fi


  target_file_path="$target_path_base/$final_new_filename_sanitized"

  # Avoid overwriting: if target file exists, append a number
  counter=1
  temp_target_file_path="$target_file_path"
  temp_filename_no_ext="${final_new_filename_sanitized%.*}"
  temp_extension="${final_new_filename_sanitized##*.}"
  if [ "$temp_filename_no_ext" == "$temp_extension" ]; then # If there's no extension
      temp_extension=""
  fi


  while [ -f "$temp_target_file_path" ]; do
    # Ensure we don't double-dot the extension if it's not present
    if [ -z "$temp_extension" ]; then
        temp_target_file_path="${target_path_base}/${temp_filename_no_ext}_${counter}"
    else
        temp_target_file_path="${target_path_base}/${temp_filename_no_ext}_${counter}.${temp_extension}"
    fi
    counter=$((counter + 1))
  done
  target_file_path="$temp_target_file_path"


  # Move the file if the target is different from the source
  if [ "$file" != "$target_file_path" ]; then
    echo "  Moving '$file' to '$target_file_path'"
    # Check if source and target directories are the same
    # This is to prevent moving a file onto itself if only the name changes within the same directory
    source_dir_check=$(dirname "$file")
    dest_dir_check=$(dirname "$target_file_path")

    if [ "$source_dir_check" != "$dest_dir_check" ] && [ ! -d "$dest_dir_check" ]; then
        echo "  Creating destination directory for move: $dest_dir_check"
        mkdir -p "$dest_dir_check"
        if [ $? -ne 0 ]; then
            echo "  Error: Could not create directory '$dest_dir_check' during move. Skipping file."
            continue
        fi
    fi
    
    mv -n "$file" "$target_file_path" # -n for no-clobber, though we handled it above
    if [ $? -eq 0 ]; then
      echo "  Successfully moved."
    else
      echo "  Error: Failed to move '$file' to '$target_file_path'."
    fi
  else
    echo "  File is already in the correct location with the correct name: $file"
  fi
  echo "-------------------------"
done

echo ""
echo "Music organization complete."

# Optional: Clean up empty directories
# read -p "Do you want to remove empty directories in '$MUSIC_BASE_DIR'? (y/N): " cleanup_choice
# if [[ "$cleanup_choice" =~ ^[Yy]$ ]]; then
#   echo "Cleaning up empty directories..."
#   find "$MUSIC_BASE_DIR" -mindepth 1 -type d -empty -delete
#   echo "Empty directory cleanup complete."
# fi

exit 0
