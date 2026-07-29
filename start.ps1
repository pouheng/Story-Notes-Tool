# 快速啟動 Local HTTP Server for 故事紀要工具
# 開啟後瀏覽器訪問 http://localhost:8000/story_timeline_tool.html
$port=8000
Write-Host "=== 故事紀要工具 - HTTP Server ===" -ForegroundColor Cyan
Write-Host "啟動於 http://localhost:$port/story_timeline_tool.html" -ForegroundColor Green
Write-Host "按 Ctrl+C 停止伺服器" -ForegroundColor Yellow
python -m http.server $port --bind 127.0.0.1
