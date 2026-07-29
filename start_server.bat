@echo off
echo Starting server...
start /min python -m http.server 8000 --bind 127.0.0.1
echo Opening browser...
start http://localhost:8000/story_timeline_tool.html
echo Server running at http://localhost:8000/story_timeline_tool.html
echo Close this window to stop.
pause
