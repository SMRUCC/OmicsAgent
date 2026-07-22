#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
extract_pdf_text.py
===================
从指定文件夹中的所有论文 PDF 文件提取：标题、DOI、摘要、全文，
并以同名 .txt 文件的形式保存回源文件夹。

适用于 Windows 环境（也兼容 Linux/macOS）。

依赖：
    pip install PyMuPDF

用法：
    python extract_pdf_text.py <包含 PDF 文件的文件夹路径>

示例：
    python extract_pdf_text.py D:\\Papers\\my_papers
    python extract_pdf_text.py "C:\\Users\\xxx\\Desktop\\papers"
"""

import os
import re
import sys
import argparse
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:
    sys.stderr.write(
        "[错误] 未安装 PyMuPDF。请先执行：pip install PyMuPDF\n"
    )
    sys.exit(1)


# ----------------------------------------------------------------------
# 正则表达式
# ----------------------------------------------------------------------
# DOI 标准格式：10.xxxx/xxxxxxx
DOI_PATTERN = re.compile(
    r"\b10\.\d{4,9}/[-._;()/:A-Za-z0-9]+",
    re.IGNORECASE,
)

# 常见的"摘要结束"标志词（用于截断摘要）
ABSTRACT_END_PATTERNS = [
    r"\n\s*Keywords?\b",
    r"\n\s*Index\s+Terms\b",
    r"\n\s*1\s*\.?\s*Introduction\b",
    r"\n\s*Introduction\b",
    r"\n\s*I\s*\.?\s*Introduction\b",
    r"\n\s*1\s*\.?\s*[A-Z]",
    r"\n\s*Key\s+words\b",
]
ABSTRACT_END_REGEX = re.compile("|".join(ABSTRACT_END_PATTERNS), re.IGNORECASE)

# 摘要起始标志
ABSTRACT_START_REGEX = re.compile(r"\bAbstract\b", re.IGNORECASE)


# ----------------------------------------------------------------------
# 工具函数
# ----------------------------------------------------------------------
def clean_text(text: str) -> str:
    """清理文本：去除多余空白、连字符换行等。"""
    if not text:
        return ""
    # 合并被连字符断开的单词： exam-\nple -> example
    text = re.sub(r"-\n(\w)", r"\1", text)
    # 将单独的换行符替换为空格（保留段落结构由双换行处理）
    # 但保留段落分隔（连续两个以上换行）
    text = re.sub(r"\r\n", "\n", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    # 去除每行末尾空格
    text = "\n".join(line.strip() for line in text.split("\n"))
    return text.strip()


def extract_doi(full_text: str) -> str:
    """从全文中提取 DOI 号。"""
    if not full_text:
        return ""
    matches = DOI_PATTERN.findall(full_text)
    if not matches:
        return ""
    # 取第一个匹配，清理末尾标点
    doi = matches[0]
    # 去掉末尾可能粘连的标点
    doi = re.sub(r"[.,;:)\]\}]+$", "", doi)
    return doi.strip()


def extract_title(doc: fitz.Document, first_page_text: str) -> str:
    """
    提取论文标题。
    策略：
      1. 优先使用第一页中字体最大的文本块（排除页眉页脚）。
      2. 若失败，则取第一页第一段非空文本。
    """
    try:
        page = doc[0]
        blocks = page.get_text("dict")["blocks"]
        # 收集所有文本行及其字体大小
        lines_info = []
        for block in blocks:
            if block.get("type", 0) != 0:  # 0 = 文本块
                continue
            for line in block.get("lines", []):
                line_text = ""
                max_size = 0.0
                for span in line.get("spans", []):
                    line_text += span.get("text", "")
                    size = span.get("size", 0.0)
                    if size > max_size:
                        max_size = size
                line_text = line_text.strip()
                # 跳过空行、纯数字行（页码）、过短行
                if not line_text:
                    continue
                if line_text.isdigit():
                    continue
                # 跳过明显的页眉页脚（通常在页面顶部/底部极小字体）
                bbox = line.get("bbox", [0, 0, 0, 0])
                page_height = page.rect.height
                y0 = bbox[1]
                # 跳过页面最上方 5% 和最下方 5% 区域的极小字体
                if (y0 < page_height * 0.05 or y0 > page_height * 0.95) and max_size < 9:
                    continue
                lines_info.append((max_size, line_text, y0))

        if lines_info:
            # 找最大字体大小
            max_font_size = max(info[0] for info in lines_info)
            # 取所有接近最大字体的行（容差 0.5）
            title_lines = [
                info[1] for info in lines_info
                if abs(info[0] - max_font_size) < 0.5
            ]
            # 按页面位置排序后拼接
            # 由于 lines_info 已按读取顺序，直接拼接即可
            title = " ".join(title_lines).strip()
            # 去除标题中可能粘连的期刊名等冗余（简单清理）
            title = re.sub(r"\s+", " ", title).strip()
            if title and len(title) > 5:
                return title
    except Exception:
        pass

    # 回退策略：取第一页第一段非空文本
    if first_page_text:
        for line in first_page_text.split("\n"):
            line = line.strip()
            if len(line) > 10 and not line.isdigit():
                return line
    return ""


def extract_abstract(full_text: str) -> str:
    """
    从全文中提取摘要。
    策略：定位 'Abstract' 关键词，截取到下一个常见章节标题。
    """
    if not full_text:
        return ""

    # 找到 Abstract 的位置
    start_match = ABSTRACT_START_REGEX.search(full_text)
    if not start_match:
        return ""

    # 从 Abstract 之后开始
    after_abstract = full_text[start_match.end():]

    # 找到摘要结束位置
    end_match = ABSTRACT_END_REGEX.search(after_abstract)
    if end_match:
        abstract = after_abstract[:end_match.start()]
    else:
        # 若找不到结束标志，取前 N 个字符作为摘要
        abstract = after_abstract[:3000]

    # 清理：去掉开头的冒号、空格
    abstract = abstract.lstrip(" :·—-\n\t")
    # 截断到合理长度（避免误抓过多）
    if len(abstract) > 5000:
        # 尝试在句号处截断
        cut = abstract[:5000]
        last_period = max(cut.rfind(". "), cut.rfind("。"))
        if last_period > 1000:
            abstract = abstract[:last_period + 1]

    return clean_text(abstract)


def extract_full_text(doc: fitz.Document) -> str:
    """提取 PDF 全文。"""
    pages_text = []
    for i, page in enumerate(doc):
        try:
            text = page.get_text("text")
            if text:
                pages_text.append(text)
        except Exception as e:
            pages_text.append(f"[第 {i+1} 页提取失败: {e}]")
    return "\n\n".join(pages_text)


def process_pdf(pdf_path: Path) -> dict:
    """处理单个 PDF 文件，返回提取结果字典。"""
    result = {
        "title": "",
        "doi": "",
        "abstract": "",
        "full_text": "",
        "error": "",
    }
    try:
        doc = fitz.open(str(pdf_path))
    except Exception as e:
        result["error"] = f"无法打开 PDF: {e}"
        return result

    try:
        # 第一页文本（用于标题回退）
        first_page_text = ""
        if len(doc) > 0:
            first_page_text = doc[0].get_text("text")

        # 全文
        full_text = extract_full_text(doc)
        result["full_text"] = clean_text(full_text)

        # 标题
        result["title"] = extract_title(doc, first_page_text)

        # DOI
        result["doi"] = extract_doi(result["full_text"])

        # 摘要
        result["abstract"] = extract_abstract(result["full_text"])

    except Exception as e:
        result["error"] = f"提取过程中出错: {e}"
    finally:
        doc.close()

    return result


def write_output_txt(pdf_path: Path, result: dict) -> Path:
    """将提取结果写入与 PDF 同名的 .txt 文件。"""
    txt_path = pdf_path.with_suffix(".txt")
    content_parts = []

    content_parts.append("=" * 70)
    content_parts.append("论文信息提取结果")
    content_parts.append("=" * 70)
    content_parts.append("")

    content_parts.append(f"【源文件】{pdf_path.name}")
    content_parts.append("")

    content_parts.append("-" * 70)
    content_parts.append("【标题 / Title】")
    content_parts.append("-" * 70)
    content_parts.append(result["title"] if result["title"] else "[未识别到标题]")
    content_parts.append("")

    content_parts.append("-" * 70)
    content_parts.append("【DOI】")
    content_parts.append("-" * 70)
    content_parts.append(result["doi"] if result["doi"] else "[未识别到 DOI]")
    content_parts.append("")

    content_parts.append("-" * 70)
    content_parts.append("【摘要 / Abstract】")
    content_parts.append("-" * 70)
    content_parts.append(result["abstract"] if result["abstract"] else "[未识别到摘要]")
    content_parts.append("")

    content_parts.append("-" * 70)
    content_parts.append("【全文 / Full Text】")
    content_parts.append("-" * 70)
    content_parts.append(result["full_text"] if result["full_text"] else "[未提取到全文]")

    if result["error"]:
        content_parts.append("")
        content_parts.append("-" * 70)
        content_parts.append("【错误信息】")
        content_parts.append("-" * 70)
        content_parts.append(result["error"])

    content = "\n".join(content_parts)

    # 使用 utf-8 编码写入
    with open(txt_path, "w", encoding="utf-8") as f:
        f.write(content)

    return txt_path


def main():
    parser = argparse.ArgumentParser(
        description="从文件夹中的 PDF 论文提取标题、DOI、摘要、全文，保存为同名 .txt 文件",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例：
    python extract_pdf_text.py D:\\Papers\\my_papers
    python extract_pdf_text.py "C:\\Users\\xxx\\Desktop\\papers"
        """,
    )
    parser.add_argument(
        "folder",
        help="包含 PDF 论文文件的文件夹路径",
    )
    args = parser.parse_args()

    folder = Path(args.folder).expanduser().resolve()

    if not folder.exists():
        sys.stderr.write(f"[错误] 文件夹不存在: {folder}\n")
        sys.exit(1)

    if not folder.is_dir():
        sys.stderr.write(f"[错误] 路径不是文件夹: {folder}\n")
        sys.exit(1)

    # 查找所有 PDF 文件（不区分大小写）
    pdf_files = sorted(
        [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() == ".pdf"]
    )

    if not pdf_files:
        sys.stderr.write(f"[提示] 文件夹中没有找到 PDF 文件: {folder}\n")
        sys.exit(0)

    print(f"[信息] 在文件夹中找到 {len(pdf_files)} 个 PDF 文件")
    print(f"[信息] 文件夹路径: {folder}")
    print("=" * 70)

    success_count = 0
    fail_count = 0

    for i, pdf_path in enumerate(pdf_files, 1):
        print(f"\n[{i}/{len(pdf_files)}] 正在处理: {pdf_path.name}")

        result = process_pdf(pdf_path)

        if result["error"] and not result["full_text"]:
            print(f"    [失败] {result['error']}")
            fail_count += 1
            continue

        try:
            txt_path = write_output_txt(pdf_path, result)
            print(f"    [成功] 标题: {result['title'][:60]}{'...' if len(result['title']) > 60 else ''}")
            print(f"           DOI:  {result['doi'] if result['doi'] else '(未识别)'}")
            print(f"           摘要: {len(result['abstract'])} 字符")
            print(f"           全文: {len(result['full_text'])} 字符")
            print(f"           输出: {txt_path.name}")
            success_count += 1
        except Exception as e:
            print(f"    [失败] 写入文件出错: {e}")
            fail_count += 1

    print("\n" + "=" * 70)
    print(f"[完成] 成功: {success_count} 个, 失败: {fail_count} 个")
    print(f"[输出] 所有 .txt 文件已保存至源文件夹: {folder}")


if __name__ == "__main__":
    main()
