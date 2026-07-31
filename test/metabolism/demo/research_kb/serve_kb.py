#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
开启 CORS 的极简本地静态文件服务，用于托管文献知识库目录 (research_kb)。

用途：
    使 agent/apps/kb.html 可以直接以 file:// 方式在浏览器打开，
    并通过 fetch 绝对地址 http://localhost/... 跨域访问知识库文件。

运行：
    python serve_kb.py                 # 默认端口 80，托管脚本所在目录
    python serve_kb.py --port 8000    # 指定端口
    python serve_kb.py --dir D:/path   # 指定托管目录

访问示例：
    http://localhost/files.txt
    http://localhost/kb.json
    http://localhost/41467_2022_Article_31334.txt
    http://localhost/per_doc_3.json
"""

import argparse
import os
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class CORSRequestHandler(SimpleHTTPRequestHandler):
    """在响应中注入 CORS 头，允许跨域 (file:// 页面也能 fetch)。"""

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS, HEAD")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        # 精简日志，仅输出请求行
        sys.stderr.write("[serve_kb] %s - %s\n" % (self.address_string(), fmt % args))


def main():
    default_dir = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="CORS-enabled static server for research_kb")
    parser.add_argument("--port", type=int, default=80, help="监听端口 (默认 80)")
    parser.add_argument("--dir", type=str, default=default_dir, help="托管目录 (默认脚本所在目录)")
    args = parser.parse_args()

    directory = os.path.abspath(args.dir)
    if not os.path.isdir(directory):
        print(f"[serve_kb] 错误：目录不存在 -> {directory}", file=sys.stderr)
        sys.exit(1)

    handler = partial(CORSRequestHandler, directory=directory)
    httpd = ThreadingHTTPServer(("0.0.0.0", args.port), handler)

    print(f"[serve_kb] 正在托管: {directory}")
    print(f"[serve_kb] 访问地址: http://localhost:{args.port}/")
    print(f"[serve_kb] 按 Ctrl+C 停止")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[serve_kb] 已停止")
        httpd.shutdown()


if __name__ == "__main__":
    main()
