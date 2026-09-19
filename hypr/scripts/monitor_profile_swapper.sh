#!/bin/bash

MONITOR_DIR="$HOME/.config/hypr"
PROFILE_LINK="$MONITOR_DIR/monitors_active.lua"
PROFILE_DOCKED=$(readlink -f "$MONITOR_DIR/monitors_docked.lua")
PROFILE_UNDOCKED=$(readlink -f "$MONITOR_DIR/monitors_undocked.lua")

# Check which profile is currently active
if [ -L "$PROFILE_LINK" ]; then
  CURRENT_PROFILE=$(readlink -f "$PROFILE_LINK")
else
  # Default to undocked if no link exists
  CURRENT_PROFILE="$PROFILE_UNDOCKED"
fi

# Toggle between profiles
if [ "$CURRENT_PROFILE" = "$PROFILE_UNDOCKED" ]; then
  # Switch to docked profile
  ln -sfn "$PROFILE_DOCKED" "$PROFILE_LINK"
  echo "Switched to DOCKED profile"
else
  # Switch to Undocked profile
  ln -sfn "$PROFILE_UNDOCKED" "$PROFILE_LINK"
  echo "Switched to UNDOCKED profile"
fi

hyprctl reload
