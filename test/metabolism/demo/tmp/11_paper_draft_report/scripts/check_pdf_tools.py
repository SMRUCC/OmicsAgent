import subprocess
import shutil
import sys

#检查系统中可用的HTML转PDF工具
tools = {
 "wkhtmltopdf": ["--version"],
 "weasyprint": ["--version"],
 "chromium": ["--version"],
 "chrome": ["--version"],
 "google-chrome": ["--version"],
 "google-chrome-stable": ["--version"],
 "msedge": ["--version"],
 "edge": ["--version"],
}

for tool, args in tools.items():
 path = shutil.which(tool)
 if path:
 print(f"找到 {tool}: {path}")
 try:
 result = subprocess.run([tool] + args, capture_output=True, text=True, timeout=5)
 print(f" stdout: {result.stdout.strip()[:100]}")
 print(f" stderr: {result.stderr.strip()[:100]}")
 except Exception as e:
 print(f" error: {e}")
 else:
 print(f"未找到: {tool}")

#检查Python库
print("\n检查Python库:")
libs = ["pdfkit", "weasyprint", "reportlab", "fpdf"]
for lib in libs:
 try:
 exec(f"import {lib}")
 print(f" {lib}:可用")
 except ImportError:
 print(f" {lib}:不可用")
