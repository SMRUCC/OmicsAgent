#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""将HTML报告转换为PDF"""

import subprocess
import sys
import os

html_path = r"G:/OmicsWorks/test/metabolism/demo/analysis/report.html"
pdf_path = r"G:/OmicsWorks/test/metabolism/demo/analysis/report.pdf"

#检查HTML文件是否存在
if not os.path.exists(html_path):
 print(f"错误: HTML文件不存在: {html_path}")
 sys.exit(1)

print(f"HTML文件大小: {os.path.getsize(html_path)}字节")

#尝试多种可能的wkhtmltopdf路径
possible_paths = [
 "wkhtmltopdf",
 r"C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe",
 r"C:\Program Files (x86)\wkhtmltopdf\bin\wkhtmltopdf.exe",
]

wkhtmltopdf_cmd = None
for cmd in possible_paths:
 try:
 result = subprocess.run([cmd, "--version"], capture_output=True, text=True, timeout=10)
 if result.returncode ==0:
 wkhtmltopdf_cmd = cmd
 print(f"找到 wkhtmltopdf: {cmd}")
 print(f"版本信息: {result.stdout.strip()[:100]}")
 break
 except (FileNotFoundError, subprocess.TimeoutExpired):
 continue

if wkhtmltopdf_cmd is None:
 print("未找到 wkhtmltopdf，尝试使用 Python pdfkit库...")
 try:
 import pdfkit
 print("pdfkit库可用，尝试转换...")
 options = {
 'page-size': 'A3',
 'margin-top': '15mm',
 'margin-bottom': '15mm',
 'margin-left': '15mm',
 'margin-right': '15mm',
 'enable-local-file-access': '',
 'encoding': 'UTF-8',
 }
 pdfkit.from_file(html_path, pdf_path, options=options)
 print(f"PDF已生成: {pdf_path}")
 print(f"PDF文件大小: {os.path.getsize(pdf_path)}字节")
 sys.exit(0)
 except ImportError:
 print("pdfkit库不可用")
 print("请安装: pip install pdfkit")
 print("或安装 wkhtmltopdf: https://wkhtmltopdf.org/downloads.html")
 sys.exit(1)

#使用wkhtmltopdf命令行转换
cmd_args = [
 wkhtmltopdf_cmd,
 "--page-size", "A3",
 "--margin-top", "15mm",
 "--margin-bottom", "15mm",
 "--margin-left", "15mm",
 "--margin-right", "15mm",
 "--enable-local-file-access",
 "--encoding", "UTF-8",
 html_path,
 pdf_path
]

print(f"执行命令: {' '.join(cmd_args)}")
result = subprocess.run(cmd_args, capture_output=True, text=True, timeout=120)

print(f"返回码: {result.returncode}")
if result.stdout:
 print(f"标准输出: {result.stdout[:500]}")
if result.stderr:
 print(f"标准错误: {result.stderr[:500]}")

if result.returncode ==0 and os.path.exists(pdf_path):
 print(f"PDF成功生成: {pdf_path}")
 print(f"PDF文件大小: {os.path.getsize(pdf_path)}字节")
else:
 print("PDF生成失败")
 sys.exit(1)
