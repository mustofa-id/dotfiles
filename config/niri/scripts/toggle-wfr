#!/usr/bin/env bash
# Toggle wf-recorder
pid=$(pgrep -x wf-recorder)

if [ -z "$pid" ]; then
	# Start recording — use slurp to select or full screen
	wf-recorder -g "$(slurp)" -f "$HOME/Videos/Screencast_$(date +%Y%m%d_%H%M%S).mkv" &
else
	# Stop recording
	kill -INT "$pid"
fi
