#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
extract_pdf_text.py
===================
从指定文件夹中的所有论文 PDF 文件提取文献元数据
（title, doi, year, journal, abstract, keywords, reference_list, fulltext），
并以同名 .txt 文件的形式保存回源文件夹。

所有字段均为离线（不联网）正则启发式解析，解析失败/缺失时回退为空值，
保证输出 .txt 始终符合固定格式且可被程序解析。

输出 .txt 格式（每行含义）：
    第 1 行： title（文献标题）
    第 2 行： 元数据 JSON 字符串 {"doi":..,"year":..,"journal":..,"keywords":[..]}
    第 3 行： 参考文献数组 JSON 字符串 [{"title":..,"doi":..,"year":..,"journal":..}, ...]
    第 4 行： 空白行
    第 5 行起： 经格式化、清理乱码后的文献全文（含参考文献章节）

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
import json
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

# 年份：四位数字 19xx 或 20xx（含可选择的括号/逗号上下文）
YEAR_PATTERN = re.compile(r"\b(19|20)\d{2}\b")

# 关键词起始标志
KEYWORDS_START_REGEX = re.compile(
    r"(?:^|\n)\s*(?:Key\s*words?|Keywords|Index\s+Terms|Index\s+terms)\s*[:：]",
    re.IGNORECASE,
)

# 参考文献章节起始标志
REFERENCES_START_REGEX = re.compile(
    r"\n\s*(?:References|Reference|Bibliography|REFERENCES)\b",
    re.IGNORECASE,
)

# 参考文献章节结束标志（章节标题或文档尾部）
REFERENCES_END_REGEX = re.compile(
    r"\n\s*(?:Appendix|Appendices|Acknowledg(?:e?ments?|ment)|Supporting\s+Information|"
    r"Supplementary\s+(?:Material|Information)|Author\s+Contributions|Conflict\s+of\s+Interest|"
    r"CRediT\s+authorship)\b",
    re.IGNORECASE,
)

# 参考文献条目编号： 1.  [1]  (1)  1]  1)  等
REFERENCE_ITEM_REGEX = re.compile(
    r"\n\s*(?:\[(\d{1,3})\]|\((\d{1,3})\)|(\d{1,3})[.)\]])"
)


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


def extract_year(full_text: str) -> str:
    """
    启发式提取论文发表年份。
    优先级：版权声明 '© YYYY' > 'Published YYYY'/'Online/Print YYYY'
    > Received/Accepted YYYY > 全文首个 19xx/20xx 年份。
    返回如 '2021' 的字符串；未找到返回 ''。
    """
    if not full_text:
        return ""

    # 1. 版权符号 © YYYY
    m = re.search(r"©\s*\d{4}\s*(?:[-–]\s*\d{4})?", full_text)
    if m:
        ym = YEAR_PATTERN.search(m.group(0))
        if ym:
            return ym.group(0)

    # 2. Published / Online / Print 后的年份
    m = re.search(
        r"\b(?:Published|Online|Print|Available)\b[^\n]{0,30}?"
        r"\b((?:19|20)\d{2})\b",
        full_text,
        re.IGNORECASE,
    )
    if m:
        return m.group(1)

    # 3. Received / Accepted 后的年份
    m = re.search(
        r"\b(?:Received|Accepted)\b[^\n]{0,40}?\b((?:19|20)\d{2})\b",
        full_text,
        re.IGNORECASE,
    )
    if m:
        return m.group(1)

    # 4. 全文首个四位年份
    m = YEAR_PATTERN.search(full_text)
    if m:
        return m.group(0)

    return ""


def extract_journal(full_text: str, first_page_text: str = "") -> str:
    """
    启发式提取期刊名。
    策略：优先从第一页的 'Journal of ...' 模式、版权行 '© ... <期刊名>'、
    以及常见的 "Published in <期刊名>" 模式中提取。未找到返回 ''。
    """
    if not full_text:
        return ""

    candidates = []
    if first_page_text:
        candidates.append(first_page_text)
    candidates.append(full_text)

    for text in candidates:
        # 模式 A: Journal of / Journal für / IEEE ... 等以 Journal 开头的名称
        m = re.search(
            r"\b(?:The\s+)?(?:Journal\s+of\s+[\w\s&\-]+?|"
            r"Journal\s+[A-Z][\w\s&\-]+?|IEEE\s+[\w\s]+?|"
            r"Proceedings\s+of\s+[\w\s&\-]+?)\b",
            text,
        )
        if m:
            name = m.group(0).strip()
            name = re.sub(r"\s+", " ", name)
            # 简单长度 sanity check，避免误抓过短/过长的片段
            if 3 <= len(name) <= 120:
                return name

        # 模式 B: 版权行 © ... <期刊名>
        m = re.search(
            r"©\s*\d{4}[^\n]{0,60}?\b([A-Z][\w\s&\-]+(?:Journal|Press|Publications|"
            r"Magazine|Transactions|Letters|Reviews|Reports|Science|Springer|Elsevier))\b",
            text,
            re.IGNORECASE,
        )
        if m:
            return m.group(1).strip()

    return ""


def extract_keywords(full_text: str) -> list:
    """
    提取关键词数组。定位 'Keywords:' 行，按分号/逗号切分并去空白。
    返回 list[str]；未找到返回 []。
    """
    if not full_text:
        return []

    m = KEYWORDS_START_REGEX.search(full_text)
    if not m:
        return []

    # 从该标志之后取到行尾（或下一个空行/章节标题）
    after = full_text[m.end():]
    # 取到第一个换行后内容，或最多 1000 字符
    line_end = after.find("\n")
    if line_end == -1:
        block = after[:1000]
    else:
        block = after[:line_end]
        # 关键词可能跨多行（罕见），最多再取后续 3 行
        rest = after[line_end + 1:]
        for _ in range(3):
            nxt = rest.find("\n")
            piece = rest[:nxt] if nxt != -1 else rest
            if re.match(r"^\s*(?:[A-Za-z0-9].{2,60})\s*[,;]$", piece) or \
               re.match(r"^\s*(?:and\s+)?[A-Za-z0-9].{2,60}\s*$", piece):
                block += " " + piece
                if nxt == -1:
                    break
                rest = rest[nxt + 1:]
            else:
                break

    # 清理并切分
    block = re.sub(r"^\s*[:：]\s*", "", block)
    block = block.strip()
    # 按分号或逗号切分（保留逗号序列）
    parts = re.split(r"[;,]", block)
    keywords = [p.strip().strip(".\"')") for p in parts]
    keywords = [k for k in keywords if k and len(k) <= 80]
    return keywords


def _parse_reference_entry(raw: str) -> dict:
    """对单条参考文献原始文本做尽力而为的结构化解析。"""
    entry = {
        "title": "",
        "doi": "",
        "year": "",
        "journal": "",
    }
    if not raw:
        return entry

    text = raw.strip()
    # DOI
    doi_m = DOI_PATTERN.search(text)
    if doi_m:
        entry["doi"] = re.sub(r"[.,;:)\]\}]+$", "", doi_m.group(0)).strip()
        # 从文本中移除 doi，便于后续解析
        text = text[:doi_m.start()] + text[doi_m.end():]

    # 年份（最后一个或第一个四位年份，参考文献年份通常靠后）
    years = YEAR_PATTERN.findall(text)
    if years:
        entry["year"] = years[-1]

    # 期刊：引号/斜体标记间，或 'in <期刊>'，或逗号间的大写片段（尽力而为）
    jour_m = re.search(
        r"\b(?:in|In)\s+([A-Z][\w\s&\-]{2,60}?)(?:,|\.|\b\d)", text
    )
    if jour_m:
        entry["journal"] = jour_m.group(1).strip()

    # 标题：去掉编号、作者、年份、期刊、doi 后的剩余文本（尽力而为）
    title_text = text
    # 去掉开头的作者列表（如 "Smith J, Doe A." 或 "Smith J. and Doe A."）
    title_text = re.sub(
        r"^[A-Z][\w.\-]*(?:,?\s*(?:and\s+)?[A-Z][\w.\-]*){0,10}\.?",
        "", title_text,
    ).strip()
    # 去掉年份括号
    title_text = re.sub(r"\b(?:19|20)\d{2}\b[.,]?", "", title_text).strip()
    if entry["journal"]:
        title_text = title_text.replace(entry["journal"], "")
    title_text = re.sub(r"\s+", " ", title_text).strip(" .,")
    entry["title"] = title_text

    return entry


def extract_reference_list(full_text: str) -> list:
    """
    启发式提取参考文献列表。
    定位 References/Bibliography 章节，按条目编号切分，逐条结构化解析为
    {title, doi, year, journal}。无法结构化拆分的条目退化为
    {title: 原始条目, doi:'', year:'', journal:''}，保证数组结构稳定。
    返回 list[dict]；未找到章节返回 []。
    """
    if not full_text:
        return []

    start_m = REFERENCES_START_REGEX.search(full_text)
    if not start_m:
        return []

    body = full_text[start_m.end():]
    # 截断到结束标志（如有）
    end_m = REFERENCES_END_REGEX.search(body)
    if end_m:
        body = body[:end_m.start()]

    # 按编号切分条目
    items = []
    last = 0
    for m in REFERENCE_ITEM_REGEX.finditer(body):
        if items:
            items[-1] = body[last:m.start()]
        else:
            # 第一条之前可能有一些前言文本，忽略
            pass
        items.append(body[m.start():])
        last = m.start()
    # 处理最后一条的尾部（已在上面 push 了完整 slice，无需再截）

    # 若没有匹配到编号，则整体作为单条退化处理
    if not items:
        return [{"title": clean_text(body), "doi": "", "year": "", "journal": ""}]

    references = []
    for raw in items:
        raw = raw.strip()
        if not raw:
            continue
        references.append(_parse_reference_entry(raw))

    return references


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
        "year": "",
        "journal": "",
        "abstract": "",
        "keywords": [],
        "reference_list": [],
        "full_text": "",
        "error": "",
    }
    try:
        doc = fitz.open(str(pdf_path))
    except Exception as e:
        result["error"] = f"无法打开 PDF: {e}"
        return result

    try:
        # 第一页文本（用于标题回退、期刊识别）
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

        # 年份（启发式）
        result["year"] = extract_year(result["full_text"])

        # 期刊（启发式）
        result["journal"] = extract_journal(result["full_text"], first_page_text)

        # 关键词（启发式）
        result["keywords"] = extract_keywords(result["full_text"])

        # 参考文献列表（启发式）
        result["reference_list"] = extract_reference_list(result["full_text"])

    except Exception as e:
        result["error"] = f"提取过程中出错: {e}"
    finally:
        doc.close()

    return result


def write_output_txt(pdf_path: Path, result: dict) -> Path:
    """
    将提取结果按固定格式写入与 PDF 同名的 .txt 文件：

        第 1 行： title
        第 2 行： 元数据 {doi,year,journal,keywords[]} 的 JSON 字符串
        第 3 行： 参考文献数组 [{title,doi,year,journal}] 的 JSON 字符串
        第 4 行： 空白行
        第 5 行起： 经清理、格式化后的文献全文（含参考文献章节）

    各 JSON 行均使用 ensure_ascii=False 写出，保证可被 json.loads 解析。
    """
    txt_path = pdf_path.with_suffix(".txt")

    # 第 1 行：标题（为空时用占位串，保证行结构稳定）
    title = result.get("title", "") or ""

    # 第 2 行：元数据 JSON
    metadata = {
        "doi": result.get("doi", ""),
        "year": result.get("year", ""),
        "journal": result.get("journal", ""),
        "keywords": result.get("keywords", []) or [],
    }
    metadata_json = json.dumps(metadata, ensure_ascii=False)

    # 第 3 行：参考文献数组 JSON
    reference_list = result.get("reference_list", []) or []
    references_json = json.dumps(reference_list, ensure_ascii=False)

    # 第 4 行：空白行
    # 第 5 行起：清理后的全文
    full_text = result.get("full_text", "") or ""

    # 按行拼接：title / metadata_json / references_json / 空行 / full_text
    content_parts = [title, metadata_json, references_json, "", full_text]
    content = "\n".join(content_parts)

    # 使用 utf-8 编码写入
    with open(txt_path, "w", encoding="utf-8") as f:
        f.write(content)

    return txt_path


def main():
    parser = argparse.ArgumentParser(
        description="从文件夹中的 PDF 论文提取元数据(标题/DOI/年份/期刊/摘要/关键词/参考文献/全文)，保存为同名 .txt 文件",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
输出 .txt 格式：
    第 1 行    : 标题 title
    第 2 行    : 元数据 JSON  {"doi","year","journal","keywords":[...]}
    第 3 行    : 参考文献数组 JSON  [{"title","doi","year","journal"}, ...]
    第 4 行    : 空白行
    第 5 行起  : 清理后的文献全文（含参考文献章节）

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
