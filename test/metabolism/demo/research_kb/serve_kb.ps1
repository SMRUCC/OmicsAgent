<#
.SYNOPSIS
    开启 CORS 的极简本地静态文件服务（PowerShell 版，Windows 自带无需安装）。

.DESCRIPTION
    托管指定目录（默认脚本所在 research_kb），并注入 CORS 响应头，
    使 agent/apps/kb.html 可直接以 file:// 方式打开并跨域 fetch 绝对地址。

.PARAMETER Port
    监听端口，默认 80。若 80 被占用或需管理员权限，可改用 8000 等。

.PARAMETER Dir
    托管目录，默认脚本所在目录。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File serve_kb.ps1
    powershell -ExecutionPolicy Bypass -File serve_kb.ps1 -Port 8000
#>
param(
  [int]$Port = 80,
  [string]$Dir = (Split-Path -Parent $MyInvocation.MyCommand.Definition)
)

$Dir = Resolve-Path $Dir
$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
try {
  $listener.Start()
} catch {
  Write-Host "[serve_kb] 无法在端口 $Port 启动（可能需要以管理员身份运行，或端口被占用）: $_" -ForegroundColor Red
  exit 1
}

Write-Host "[serve_kb] 托管目录: $Dir"
Write-Host "[serve_kb] 访问地址: $prefix"
Write-Host "[serve_kb] 按 Ctrl+C 停止"

$mime = @{
  ".txt"  = "text/plain; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".html" = "text/html; charset=utf-8"
  ".htm"  = "text/html; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".js"   = "application/javascript; charset=utf-8"
  ".md"   = "text/markdown; charset=utf-8"
}

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $resp = $ctx.Response

    # CORS 头
    $resp.Headers.Add("Access-Control-Allow-Origin", "*")
    $resp.Headers.Add("Access-Control-Allow-Methods", "GET, OPTIONS, HEAD")
    $resp.Headers.Add("Access-Control-Allow-Headers", "*")
    $resp.Headers.Add("Cache-Control", "no-store")

    if ($req.HttpMethod -eq "OPTIONS") { $resp.StatusCode = 204; $resp.Close(); continue }

    $urlPath = $req.Url.LocalPath.TrimStart('/')
    if ($urlPath -eq "") { $urlPath = "index.html" }
    $filePath = Join-Path $Dir $urlPath

    # 防目录穿越
    $resolved = Resolve-Path -ErrorAction SilentlyContinue $filePath
    if (-not $resolved -or $resolved.Path -notlike "$Dir*") {
      $resp.StatusCode = 404
      $resp.Close()
      continue
    }

    $ext = [System.IO.Path]::GetExtension($resolved.Path).ToLower()
    if ($mime.ContainsKey($ext)) { $resp.ContentType = $mime[$ext] } else { $resp.ContentType = "application/octet-stream" }

    $bytes = [System.IO.File]::ReadAllBytes($resolved.Path)
    $resp.OutputStream.Write($bytes, 0, $bytes.Length)
    $resp.Close()
  }
} finally {
  $listener.Stop()
}
