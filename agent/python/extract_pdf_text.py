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

# 年份：四位数字 19xx 或 20xx —— 注意捕获组要包住整个 4 位年份
YEAR_PATTERN = re.compile(r"\b((?:19|20)\d{2})\b")

# 常见的"摘要结束"标志词（用于截断摘要）
ABSTRACT_END_PATTERNS = [
    r"\n\s*Keywords?\b",
    r"\n\s*Key\s*words\b",
    r"\n\s*Index\s+Terms\b",
    r"\n\s*1\s*\.?\s*Introduction\b",
    r"\n\s*Introduction\b",
    r"\n\s*I\s*\.?\s*Introduction\b",
    r"\n\s*1\s*\.?\s*[A-Z][a-z]",
    r"\n\s*Background\b",
    r"\n\s*Materials\s+and\s+Methods\b",
    r"\n\s*Methods\b",
    r"\n\s*Results\b",
    r"\n\s*Address\b",
    r"\n\s*Author\s+Contributions\b",
    r"\n\s*1\s*\.?\s*[A-Z][a-z]",
]
ABSTRACT_END_REGEX = re.compile("|".join(ABSTRACT_END_PATTERNS), re.IGNORECASE)

# 摘要起始标志：支持 "Abstract", "ABSTRACT", "A B S T R A C T"（带空格的字母）
ABSTRACT_START_REGEX = re.compile(
    r"(?:\bAbstract\b|A\s*B\s*S\s*T\s*R\s*A\s*C\s*T)",
    re.IGNORECASE,
)

# 关键词起始标志：冒号可选（有些期刊用 "KEYWORDS" 后直接换行列关键词）
KEYWORDS_START_REGEX = re.compile(
    r"(?:^|\n)\s*(?:Key\s*words?|Keywords|Index\s+Terms|Index\s+terms|KEYWORDS)\s*[:：]?\s*",
    re.IGNORECASE,
)

# 关键词结束标志（遇到这些就停止收集关键词）
KEYWORDS_END_REGEX = re.compile(
    r"\n\s*(?:"
    r"1\s*\.?\s*Introduction|"
    r"Introduction\b|"
    r"Background\b|"
    r"Materials\s+and\s+Methods|"
    r"Methods\b|"
    r"Results\b|"
    r"Discussion\b|"
    r"Abstract\b|"
    r"A\s*B\s*S\s*T\s*R\s*A\s*C\s*T|"
    r"1\s*\.?\s*[A-Z][a-z]|"
    r"©\s*\d{4}|"
    r"1\.\s+[A-Z]"
    r")",
    re.IGNORECASE,
)

# 参考文献章节起始标志
REFERENCES_START_REGEX = re.compile(
    r"\n\s*(?:References|Reference|Bibliography|REFERENCES|References\s*\n)\b",
    re.IGNORECASE,
)

# 参考文献章节结束标志（章节标题或文档尾部）
REFERENCES_END_REGEX = re.compile(
    r"\n\s*(?:Appendix|Appendices|Acknowledg(?:e?ments?|ment)|Supporting\s+Information|"
    r"Supplementary\s+(?:Material|Information|Data)|Author\s+Contributions|"
    r"CRediT\s+authorship|Conflict\s+of\s+Interest|Funding|"
    r"Data\s+Availability|Code\s+Availability|Ethics\s+Statement)\b",
    re.IGNORECASE,
)

# 参考文献条目编号： 1.  [1]  (1)  1]  1)  等
REFERENCE_ITEM_REGEX = re.compile(
    r"\n\s*(?:\[(\d{1,3})\]|\((\d{1,3})\)|(\d{1,3})[.)\]])"
)

# 已知期刊名模式（用于期刊识别）
# 注意：使用贪婪匹配 + 后置边界（数字/句号/换行）来避免截断
JOURNAL_NAME_PATTERNS = [
    # "Medicine in Microecology" (Elsevier)
    r"Medicine\s+in\s+Microecology",
    # "Journal of Microbiology, Immunology and Infection" (JMII)
    r"Journal\s+of\s+Microbiology,\s+Immunology\s+and\s+Infection",
    # "J Microbiol Immunol Infect" (abbreviated JMII)
    r"J\s+Microbiol\s+Immunol\s+Infect",
    # "Journal of XXX" / "The Journal of XXX"
    r"(?:The\s+)?Journal\s+of\s+[A-Z][A-Za-z\s&,\'\-]+?(?=\s*(?:\d|\.|\n|;|,|\||\)|$))",
    # "Frontiers in XXX"
    r"Frontiers\s+in\s+[A-Z][A-Za-z\s&,\'\-]+?(?=\s*(?:\d|\.|\n|;|,|\||\)|$))",
    # "Current Opinion in XXX"
    r"Current\s+Opinion\s+in\s+[A-Z][A-Za-z\s&,\'\-]+?(?=\s*(?:\d|\.|\n|;|,|\||\)|$))",
    # "Current Research in XXX"
    r"Current\s+Research\s+in\s+[A-Z][A-Za-z\s&,\'\-]+?(?=\s*(?:\d|\.|\n|;|,|\||\)|$))",
    # "Current Biology" / "Current Medicinal Chemistry"
    r"Current\s+(?:Biology|Medicinal\s+Chemistry|Opinion\s+in\s+Biotechnology)",
    # "Cell Host & Microbe" / "Cell Reports" 等 Cell 系
    r"Cell\s+Host\s+(?:and|&)\s+Microbe",
    r"Cell\s+Reports(?:\s+Medicine)?",
    r"Cell\s+(?:Chemical\s+Biology|Metabolism|Systems)",
    # "Nature Communications" / "Nature Microbiology" 等 Nature 系
    r"Nature\s+(?:Communications|Microbiology|Medicine|Biotechnology|Methods|"
    r"Structural\s+&\s+Molecular\s+Biology|Chemical\s+Biology|Genetics|"
    r"Immunology|Neuroscience|Cell\s+Biology|Materials)",
    # "PNAS" / "Proceedings of the National Academy of Sciences"
    r"Proc(?:eedings)?\s+\.?\s*Natl\.?\s+Acad\.?\s+Sci\.?",
    r"Proceedings\s+of\s+the\s+National\s+Academy\s+of\s+Sciences",
    # "Science" / "Science Translational Medicine" 等
    r"Science\s+(?:Translational\s+Medicine|Advances|Signaling|Immunology)",
    # "PLoS ONE" / "PLoS Pathogens" 等
    r"PLoS\s+(?:ONE|Pathogens|Biology|Medicine|Genetics|Neglected\s+Tropical\s+Diseases)",
    # "mBio" / "mSystems" / "mSphere" 等 ASM 系
    r"\bmBio\b",
    r"\bmSystems\b",
    r"\bmSphere\b",
    # "Nucleic Acids Research"
    r"Nucleic\s+Acids\s+Research",
    # "Antimicrobial Agents and Chemotherapy"
    r"Antimicrobial\s+Agents\s+and\s+Chemotherapy",
    # "Journal of Bacteriology" / "Journal of Virology" 等
    r"Journal\s+of\s+(?:Bacteriology|Virology|Clinical\s+Microbiology|"
    r"Immunology|Biological\s+Chemistry|Infectious\s+Diseases)",
    # "Clinical Infectious Diseases"
    r"Clinical\s+Infectious\s+Diseases",
    # "The Lancet" / "Lancet Infectious Diseases"
    r"\bLancet(?:\s+Infectious\s+Diseases|\s+Microbiology)?\b",
    # "New England Journal of Medicine"
    r"New\s+England\s+Journal\s+of\s+Medicine",
    # "British Medical Journal"
    r"British\s+Medical\s+Journal",
    # "JAMA"
    r"\bJAMA\b(?:\s+Internal\s+Medicine)?",
    # "Gut Microbes"
    r"Gut\s+Microbes",
    # "Microbiome"
    r"\bMicrobiome\b",
    # "ISME Journal"
    r"ISME\s+Journal",
    # "Applied and Environmental Microbiology"
    r"Applied\s+and\s+Environmental\s+Microbiology",
    # "Environmental Microbiology"
    r"Environmental\s+Microbiology",
    # "Molecular Microbiology"
    r"Molecular\s+Microbiology",
    # "Trends in Microbiology" / "Trends in ..."
    r"Trends\s+in\s+[A-Z][A-Za-z\s&,\'\-]+?(?=\s*(?:\d|\.|\n|;|,|\||\)|$))",
    # "FEMS Microbiology ..."
    r"FEMS\s+Microbiology\s+(?:Letters|Reviews|Ecology)",
    # "Annual Review of ..."
    r"Annual\s+Review\s+of\s+[A-Z][A-Za-z\s&,\'\-]+?(?=\s*(?:\d|\.|\n|;|,|\||\)|$))",
    # "Microbiology and Molecular Biology Reviews"
    r"Microbiology\s+and\s+Molecular\s+Biology\s+Reviews",
    # "Infection and Immunity"
    r"Infection\s+and\s+Immunity",
    # "International Journal of ..."
    r"International\s+Journal\s+of\s+[A-Z][A-Za-z\s&,\'\-]+?(?=\s*(?:\d|\.|\n|;|,|\||\)|$))",
    # "BMC Microbiology" / "BMC ..."
    r"BMC\s+(?:Microbiology|Biology|Medicine|Genomics|Infectious\s+Diseases)",
    # "Emerging Microbes & Infections"
    r"Emerging\s+Microbes\s+(?:and|&)\s+Infections",
    # "Antibiotics" (MDPI) —— 注意：放在最后，优先级最低
    r"\bAntibiotics\b",
    # "Pathogens" (MDPI)
    r"\bPathogens\b",
    # "Microorganisms" (MDPI)
    r"\bMicroorganisms\b",
]

JOURNAL_NAME_REGEX = re.compile(
    r"(?:" + "|".join(JOURNAL_NAME_PATTERNS) + r")"
)


# ----------------------------------------------------------------------
# 文本规范化工具
# ----------------------------------------------------------------------
# Unicode 连字（ligatures）→ 普通字母映射
LIGATURE_MAP = {
    "\ufb00": "ff",   # ﬀ
    "\ufb01": "fi",   # ﬁ
    "\ufb02": "fl",   # ﬂ
    "\ufb03": "ffi",  # ﬃ
    "\ufb04": "ffl",  # ﬄ
    "\ufb05": "st",   # ﬅ
    "\ufb06": "st",   # ﬆ
    "\u2019": "'",    # ' right single quote
    "\u2018": "'",    # ' left single quote
    "\u201c": '"',    # " left double quote
    "\u201d": '"',    # " right double quote
    "\u2013": "-",    # – en dash
    "\u2014": "-",    # — em dash
    "\u2026": "...",  # … ellipsis
    "\u00a0": " ",    # non-breaking space
    "\u2022": " ",    # bullet
    "\u25aa": " ",    # small square
    "\u25cf": " ",    # black circle
    "\u25cb": " ",    # white circle
    "\u2219": " ",    # bullet operator
    "\u00b7": " ",    # middle dot
    "\uff0c": ",",    # fullwidth comma
    "\uff1a": ":",    # fullwidth colon
    "\uff1b": ";",    # fullwidth semicolon
    "\uff08": "(",    # fullwidth left paren
    "\uff09": ")",    # fullwidth right paren
    "\u3001": ",",    # ideographic comma
    "\u3002": ".",    # ideographic full stop
}

# 控制字符（除 \t \n \r 外）—— 替换为空
CONTROL_CHAR_REGEX = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")


def normalize_text(text: str) -> str:
    """
    规范化文本：
      1. 将 Unicode 连字（ﬁ ﬂ ﬀ ﬃ ﬄ 等）替换为普通字母
      2. 将特殊引号/破折号/省略号替换为 ASCII 等价物
      3. 去除控制字符（保留 \\t \\n）
      4. 将不间断空格等替换为普通空格
    """
    if not text:
        return ""
    # 1. 连字与特殊符号替换
    for src, dst in LIGATURE_MAP.items():
        text = text.replace(src, dst)
    # 2. 去除控制字符
    text = CONTROL_CHAR_REGEX.sub("", text)
    return text


def clean_text(text: str) -> str:
    """清理文本：规范化连字、去除多余空白、合并连字符换行等。"""
    if not text:
        return ""
    # 先做字符级规范化（连字、控制字符、特殊符号）
    text = normalize_text(text)
    # 合并被连字符断开的单词： exam-\nple -> example
    text = re.sub(r"-\n(\w)", r"\1", text)
    # 统一换行符
    text = re.sub(r"\r\n", "\n", text)
    text = re.sub(r"\r", "\n", text)
    # 压缩空白
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    # 去除每行首尾空格
    text = "\n".join(line.strip() for line in text.split("\n"))
    return text.strip()


# ----------------------------------------------------------------------
# 字段提取函数
# ----------------------------------------------------------------------
def extract_doi(full_text: str) -> str:
    """从全文中提取 DOI 号。"""
    if not full_text:
        return ""
    matches = DOI_PATTERN.findall(full_text)
    if not matches:
        return ""
    # 取第一个匹配，清理末尾标点
    doi = matches[0]
    doi = re.sub(r"[.,;:)\]\}]+$", "", doi)
    return doi.strip()


def extract_title(doc: fitz.Document, first_page_text: str) -> str:
    """
    提取论文标题。
    策略：
      1. 优先使用第一页中字体最大的文本块（排除页眉页脚、期刊名等）。
      2. 若最大字体行是单个常见词（可能是期刊名），则取次大的多词行。
      3. 若失败，则取第一页第一段非空文本。
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
                line_text = normalize_text(line_text).strip()
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
                # 跳过控制字符行（如嵌入字体符号）
                if not re.search(r"[A-Za-z]", line_text):
                    continue
                lines_info.append((max_size, line_text, y0))

        if lines_info:
            # 按字体大小降序排序
            lines_info.sort(key=lambda x: (-x[0], x[2]))
            max_font_size = lines_info[0][0]

            # 收集所有接近最大字体的行（容差 0.5）
            title_candidates = []
            for size, line_text, y0 in lines_info:
                if abs(size - max_font_size) < 0.5:
                    title_candidates.append((y0, line_text))

            # 检查最大字体的行是否是"单个常见词"（可能是期刊名）
            # 如果是，则尝试取次大字体的行
            single_word_journal = False
            if title_candidates:
                # 合并所有最大字体行
                combined = " ".join(t for _, t in title_candidates).strip()
                word_count = len(combined.split())
                # 单词数 <= 1 且全小写或首字母大写 → 可能是期刊名
                if word_count <= 1 and len(combined) < 30:
                    single_word_journal = True

            if single_word_journal:
                # 取次大字体的行（容差 2.0 内）
                second_size = None
                for size, line_text, y0 in lines_info:
                    if size < max_font_size - 0.5:
                        second_size = size
                        break
                if second_size is not None:
                    title_candidates = []
                    for size, line_text, y0 in lines_info:
                        if abs(size - second_size) < 1.0:
                            title_candidates.append((y0, line_text))

            if title_candidates:
                # 按 y 坐标排序（从上到下）
                title_candidates.sort(key=lambda x: x[0])
                title = " ".join(t for _, t in title_candidates).strip()
                title = re.sub(r"\s+", " ", title).strip()
                # 去除标题开头可能的文章类型标记 "ARTICLE"
                title = re.sub(r"^(?:ARTICLE|Article|REVIEW|Review|PAPER|Paper)\s+", "", title)
                # 去除标题开头的品牌/平台名前缀（ScienceDirect, ELSEVIER 等）
                title = re.sub(
                    r"^(?:ScienceDirect|ELSEVIER|Elsevier|SpringerLink|Springer|"
                    r"PubMed|medRxiv|bioRxiv|Wiley\s+Online\s+Library|Taylor\s+&\s+Francis|"
                    r"Oxford\s+Academic|Cambridge\s+Core|ACS\s+[A-Za-z]+|"
                    r"ResearchGate|Mendeley|Scholar)\s+",
                    "", title
                )
                # 去除标题开头的期刊名前缀（如 "Medicine in Microecology ..."）
                # 匹配常见的期刊名开头
                title = re.sub(
                    r"^(?:Medicine\s+in\s+Microecology|Current\s+Opinion\s+in\s+Microbiology|"
                    r"Current\s+Research\s+in\s+[A-Za-z\s]+?|Cell\s+Host\s+(?:and|&)\s+Microbe|"
                    r"Nature\s+Communications|Frontiers\s+in\s+Microbiology|"
                    r"Journal\s+of\s+[A-Za-z\s,]+?|Antibiotics|Pathogens|Microorganisms)\s+",
                    "", title
                )
                if title and len(title) > 5:
                    return title
    except Exception:
        pass

    # 回退策略：取第一页第一段非空文本
    if first_page_text:
        for line in first_page_text.split("\n"):
            line = normalize_text(line).strip()
            if len(line) > 10 and not line.isdigit():
                return line
    return ""


def extract_abstract(full_text: str) -> str:
    """
    从全文中提取摘要。
    策略：
      1. 定位 'Abstract' / 'A B S T R A C T' 关键词，截取到下一个常见章节标题。
      2. 若找不到 Abstract 关键词，使用回退策略：
         在 Introduction / 1. Introduction / Keywords 等章节标题之前，
         寻找第一个长度 >= 300 字符的段落作为摘要。
    """
    if not full_text:
        return ""

    # ---- 策略 1：定位 Abstract 关键词 ----
    start_match = ABSTRACT_START_REGEX.search(full_text)
    if start_match:
        # 从 Abstract 之后开始
        after_abstract = full_text[start_match.end():]
        # 去掉开头的冒号、空格、换行
        after_abstract = after_abstract.lstrip(" :·—-\n\t")

        # 找到摘要结束位置
        end_match = ABSTRACT_END_REGEX.search(after_abstract)
        if end_match:
            abstract = after_abstract[:end_match.start()]
        else:
            # 若找不到结束标志，取前 N 个字符作为摘要
            abstract = after_abstract[:3000]

        abstract = abstract.strip()
        if len(abstract) >= 100:
            # 截断到合理长度
            if len(abstract) > 5000:
                cut = abstract[:5000]
                last_period = max(cut.rfind(". "), cut.rfind("。"))
                if last_period > 1000:
                    abstract = abstract[:last_period + 1]
            return clean_text(abstract)

    # ---- 策略 2：回退 —— 在文档前部寻找摘要段落 ----
    # 很多期刊（Nature Communications, Current Opinion, Frontiers 等）
    # 没有 "Abstract" 关键词，摘要直接跟在标题/作者之后。
    # 策略：在文档前 6000 字符内，找到最早的"摘要结束标志"，
    #       然后在其之前的文本中，跳过标题/作者/单位行，提取第一个长段落。

    search_region = full_text[:6000]

    # 摘要结束标志（按优先级排列）
    abstract_end_markers = [
        r"\n\s*Keywords?\s*[:：]?\s*\n",
        r"\n\s*Key\s*words\s*[:：]?\s*\n",
        r"\n\s*KEYWORDS\s*\n",
        r"\n\s*1\s*\.?\s*Introduction\b",
        r"\n\s*Introduction\b",
        r"\n\s*Background\b",
        r"\n\s*Address\b",
        r"\n\s*1\s+Department\b",
        r"\n\s*Department\s+of\b",
        r"\n\s*Affiliation",
        r"\n\s*\*\s*Corresponding",
        r"\n\s*Author\s+contributions",
        r"\n\s*©\s*\d{4}",
        r"\n\s*https?://doi\s*\.?\s*org/",
        r"\n\s*OPEN\b",
        r"\n\s*Citation:",
        r"\n\s*Available\s+online",
        r"\n\s*Received\s*[:：]",
        r"\n\s*Accepted\s*[:：]",
        r"\n\s*Published\s*[:：]",
        r"\n\s*Materials\s+and\s+Methods\b",
        r"\n\s*Methods\b",
        r"\n\s*Results\b",
    ]
    end_pos = len(search_region)
    for marker in abstract_end_markers:
        m = re.search(marker, search_region, re.IGNORECASE)
        if m and m.start() < end_pos:
            end_pos = m.start()

    before_end = search_region[:end_pos]

    # 将文本按行分割，跳过标题/作者/单位行，寻找第一个长段落
    lines = before_end.split("\n")
    # 收集候选段落：连续的非空行组成一个段落
    paragraphs = []
    current_lines = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            if current_lines:
                paragraphs.append(current_lines)
                current_lines = []
        else:
            current_lines.append(stripped)
    if current_lines:
        paragraphs.append(current_lines)

    # 非摘要标志（出现在段落中则跳过该段落）
    non_abstract_regex = re.compile(
        r"(?:^Department\b|^University\b|^Address\b|^Affiliation|"
        r"Corresponding\s+author|email\s*[:：]|@.*\.(?:edu|com|org)|"
        r"©\s*\d{4}|Received\s*[:：]|Accepted\s*[:：]|Published\s*[:：]|"
        r"Available\s+online|Citation\s*[:：]|Academic\s+Editor|"
        r"Author\s+contributions|Conflicts?\s+of\s+interest|"
        r"^\d+\s+Department|^These\s+authors\s+contributed|"
        r"^Volume\s+\d|^Article\s+ID|^https?://)",
        re.IGNORECASE | re.MULTILINE,
    )

    # 作者行特征：包含逗号分隔的人名、上标数字、"and"、首字母缩写
    author_line_regex = re.compile(
        r"^(?:[A-Z][a-z]+(?:\s+[A-Z]\.?){1,3}(?:\s*,\s*|\s+and\s+|"
        r"\s*\d+\s*,?\s*))+[A-Z][a-z]+",
    )

    for para_lines in paragraphs:
        para_text = " ".join(para_lines).strip()
        para_text = re.sub(r"\s+", " ", para_text)

        # 跳过太短的段落
        if len(para_text) < 200:
            continue

        # 跳过包含非摘要标志的段落
        if non_abstract_regex.search(para_text):
            continue

        # 跳过纯作者列表（多行短行）
        if len(para_lines) >= 3 and all(len(l) < 50 for l in para_lines):
            continue

        # 跳过看起来像作者列表的段落（第一行匹配作者模式且总长短）
        if author_line_regex.match(para_lines[0]) and len(para_lines) <= 2:
            continue

        # 找到候选摘要
        abstract = para_text
        if len(abstract) > 5000:
            cut = abstract[:5000]
            last_period = max(cut.rfind(". "), cut.rfind("。"))
            if last_period > 1000:
                abstract = abstract[:last_period + 1]
        return clean_text(abstract)

    # ---- 策略 3：最后回退 —— 在前 3000 字符中找第一个 >= 200 字符的连续文本 ----
    # 逐行扫描，找第一行长度 >= 40 的行，然后收集后续行直到空行或结束标志
    lines = full_text[:3000].split("\n")
    collecting = False
    abstract_lines = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            if collecting and len(" ".join(abstract_lines)) >= 200:
                break
            collecting = False
            abstract_lines = []
            continue
        if not collecting:
            # 寻找摘要起始行：长度 >= 40 且不像标题/作者
            if (len(stripped) >= 40
                    and not re.match(r"^(?:ARTICLE|REVIEW|PAPER|Volume|Article)", stripped)
                    and not non_abstract_regex.search(stripped)):
                collecting = True
                abstract_lines = [stripped]
        else:
            # 检查是否遇到结束标志
            if re.match(r"^(?:Keywords?|Introduction|Background|Address|Department|"
                        r"Affiliation|©|https?://|OPEN|Citation|Received|Accepted|Published)",
                        stripped, re.IGNORECASE):
                break
            abstract_lines.append(stripped)

    if abstract_lines:
        abstract = " ".join(abstract_lines)
        abstract = re.sub(r"\s+", " ", abstract).strip()
        if len(abstract) >= 200:
            return clean_text(abstract)

    return ""


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
    m = re.search(r"©\s*((?:19|20)\d{2})\s*(?:[-–]\s*(?:19|20)\d{2})?", full_text)
    if m:
        return m.group(1)

    # 2. Published / Online / Print 后的年份
    m = re.search(
        r"\b(?:Published|Available\s+online|Online|Print)\b[^\n]{0,30}?"
        r"\b((?:19|20)\d{2})\b",
        full_text,
        re.IGNORECASE,
    )
    if m:
        return m.group(1)

    # 3. Received / Accepted 后的年份
    m = re.search(
        r"\b(?:Accepted|Received)\b[^\n]{0,40}?\b((?:19|20)\d{2})\b",
        full_text,
        re.IGNORECASE,
    )
    if m:
        return m.group(1)

    # 4. Citation 行中的年份（如 "Antibiotics 2022, 11, 537"）
    m = re.search(
        r"\bCitation\b[^\n]{0,80}?\b((?:19|20)\d{2})\b",
        full_text,
        re.IGNORECASE,
    )
    if m:
        return m.group(1)

    # 5. 全文首个四位年份
    m = YEAR_PATTERN.search(full_text)
    if m:
        return m.group(1)

    return ""


def extract_journal(full_text: str, first_page_text: str = "") -> str:
    """
    启发式提取期刊名。
    策略（按优先级）：
      1. 从 "ScienceDirect <期刊名> journal homepage" 中提取。
      2. 从页眉/页脚行 "<期刊名> | (YYYY) Vol:Pages" 中提取。
      3. 从引用行 "Citation: ... <期刊名> YYYY" 中提取。
      4. 从 "<期刊名> YYYY, Vol:Pages" 模式中提取。
      5. 在去掉关键词/参考文献区块后的全文中匹配已知期刊名模式。
    未找到返回 ''。
    """
    if not full_text:
        return ""

    search_texts = []
    if first_page_text:
        search_texts.append(first_page_text)
    search_texts.append(full_text)

    for text in search_texts:
        # 模式 A: "ScienceDirect\n<期刊名>\njournal homepage"
        m = re.search(
            r"ScienceDirect\s*\n\s*([A-Z][A-Za-z\s&,\'\-]+?)\s*\n\s*journal\s+homepage",
            text, re.IGNORECASE,
        )
        if m:
            name = m.group(1).strip()
            name = re.sub(r"\s+", " ", name)
            name = re.sub(r"[.,;:\)\]\}]+$", "", name).strip()
            if 3 <= len(name) <= 120:
                return name

        # 模式 B: 页眉/页脚行 "<期刊名> | (YYYY) Vol:Pages | https://doi.org/..."
        m = re.search(
            r"\n\s*([A-Z][A-Z\s&]+?)\s*\|\s*\(?(?:19|20)\d{2}\)?\s*[,;:]?\s*\d+",
            text,
        )
        if m:
            name = m.group(1).strip()
            name = re.sub(r"\s+", " ", name)
            name = name.title().replace(" And ", " and ").replace(" In ", " in ").replace(" Of ", " of ")
            if 3 <= len(name) <= 120:
                return name

        # 模式 C: 引用行 "Citation: ... <期刊名> YYYY, Vol, Pages"
        m = re.search(
            r"Citation:.*?\.\s+([A-Z][A-Za-z\s&,\'\-]+?)\s+(?:19|20)\d{2}",
            text, re.IGNORECASE,
        )
        if m:
            name = m.group(1).strip()
            name = re.sub(r"\s+", " ", name)
            name = re.sub(r"[.,;:\)\]\}]+$", "", name).strip()
            if 3 <= len(name) <= 120:
                return name

        # 模式 D: "<期刊名> YYYY, Vol:Pages" 或 "<期刊名> YYYY, Vol, Pages"
        m = re.search(
            r"\n\s*([A-Z][A-Za-z\s&,\'\-]{5,80}?)\s+(?:19|20)\d{2}\s*[,;:]\s*\d+",
            text,
        )
        if m:
            name = m.group(1).strip()
            name = re.sub(r"\s+", " ", name)
            name = re.sub(r"[.,;:\)\]\}]+$", "", name).strip()
            if (name and 3 <= len(name) <= 120
                    and not re.search(r"(?:by\s+the\s+authors|All\s+rights|Author|Licensee|Published|Received|Accepted)",
                                      name, re.IGNORECASE)):
                return name

        # 模式 E: "<期刊名> Vol (Year) Pages" 或 "<期刊名> Vol, Pages (Year)"
        # 例如: "Journal of Microbiology, Immunology and Infection 54 (2021) 1011e1017"
        #       "Antibiotics 2022, 11, 537"
        m = re.search(
            r"\n\s*([A-Z][A-Za-z\s&,\'\-]{5,80}?)\s+\d+\s*\(?(?:19|20)\d{2}\)?",
            text,
        )
        if m:
            name = m.group(1).strip()
            name = re.sub(r"\s+", " ", name)
            name = re.sub(r"[.,;:\)\]\}]+$", "", name).strip()
            if (name and 3 <= len(name) <= 120
                    and not re.search(r"(?:by\s+the\s+authors|All\s+rights|Author|Licensee|Published|Received|Accepted|Volume|Vol\b)",
                                      name, re.IGNORECASE)):
                return name

    # ---- 在去掉关键词/参考文献区块后的全文中匹配已知期刊名模式 ----
    cleaned_text = full_text
    kw_match = KEYWORDS_START_REGEX.search(cleaned_text)
    if kw_match:
        after_kw = cleaned_text[kw_match.end():]
        end_match = KEYWORDS_END_REGEX.search(after_kw)
        if end_match:
            cleaned_text = (cleaned_text[:kw_match.start()]
                            + after_kw[end_match.start():])
    ref_match = REFERENCES_START_REGEX.search(cleaned_text)
    if ref_match:
        cleaned_text = cleaned_text[:ref_match.start()]

    for text in [first_page_text, cleaned_text]:
        if not text:
            continue
        for m in JOURNAL_NAME_REGEX.finditer(text):
            name = m.group(0).strip()
            name = re.sub(r"\s+", " ", name)
            name = re.sub(r"[.,;:\)\]\}]+$", "", name).strip()
            if 3 <= len(name) <= 120:
                return name

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

    # 从该标志之后取内容
    after = full_text[m.end():]
    # 去掉开头的冒号、空格、换行
    after = after.lstrip(" :·—-\n\t")

    # 找到关键词结束位置（章节标题等）
    end_match = KEYWORDS_END_REGEX.search(after)
    if end_match:
        block = after[:end_match.start()]
    else:
        # 回退：取到第一个双换行或最多 1000 字符
        double_nl = after.find("\n\n")
        if double_nl != -1 and double_nl < 1000:
            block = after[:double_nl]
        else:
            block = after[:1000]

    # 清理并切分
    block = block.strip()
    # 去掉末尾可能粘连的章节标题（如 "1. Introduction"）
    block = re.sub(r"\s*1\s*\.?\s*Introduction.*$", "", block, flags=re.IGNORECASE)
    block = re.sub(r"\s*Introduction\s*$", "", block, flags=re.IGNORECASE)

    # 切分关键词：优先按分号/逗号切分；若无分号逗号则按换行切分
    if re.search(r"[;,]", block):
        # 有关键词分隔符：将单个换行替换为空格（关键词可能跨行），再按 ; 或 , 切分
        block_flat = re.sub(r"\n+", " ", block)
        block_flat = re.sub(r"\s+", " ", block_flat).strip()
        parts = re.split(r"[;,]", block_flat)
    else:
        # 无分隔符：按换行切分，每行一个关键词
        parts = re.split(r"\n+", block)

    keywords = []
    for p in parts:
        p = p.strip().strip(".'\"')")
        # 跳过过短或过长的项
        if p and 2 <= len(p) <= 80:
            # 跳过明显是章节标题的项
            if re.match(r"^\d+\.?\s*(?:Introduction|Background|Methods|Results|Discussion)",
                        p, re.IGNORECASE):
                continue
            keywords.append(p)
    return keywords


def _parse_reference_entry(raw: str) -> dict:
    """
    对单条参考文献原始文本做尽力而为的结构化解析。
    返回 {title, doi, year, journal}。
    """
    entry = {
        "title": "",
        "doi": "",
        "year": "",
        "journal": "",
    }
    if not raw:
        return entry

    text = normalize_text(raw).strip()
    # 去掉开头的编号 [N] / (N) / N. / N)
    text = re.sub(r"^\s*(?:\[\d{1,3}\]|\(\d{1,3}\)|\d{1,3}[.)\]])\s*", "", text)
    # 去掉末尾的 [CrossRef] [PubMed] 等标签
    text = re.sub(r"\s*\[(?:CrossRef|PubMed|PubMed\s+Central|PMC|Google\s+Scholar)\]",
                  "", text).strip()
    # 去掉 DOI URL 前缀
    text = re.sub(r"https?://doi\.org/", "", text)

    if not text:
        return entry

    # ---- DOI ----
    doi_m = DOI_PATTERN.search(text)
    if doi_m:
        entry["doi"] = re.sub(r"[.,;:)\]\}]+$", "", doi_m.group(0)).strip()
        text = text[:doi_m.start()] + text[doi_m.end():]

    # ---- 年份 ----
    years = YEAR_PATTERN.findall(text)
    if years:
        # 参考文献年份通常靠后，取最后一个
        entry["year"] = years[-1]

    # ---- 清理文本 ----
    text = re.sub(r"\s+", " ", text).strip(" .,")

    # ---- 期刊名 ----
    # 尝试匹配已知期刊名
    jour_m = JOURNAL_NAME_REGEX.search(text)
    if jour_m:
        entry["journal"] = jour_m.group(0).strip()
        entry["journal"] = re.sub(r"[.,;:)\]\}]+$", "", entry["journal"]).strip()
    else:
        # 回退：寻找 "in <期刊名>" 模式
        jour_m = re.search(
            r"\b(?:in|In)\s+([A-Z][\w\s&,\-]{2,60}?)(?:,|\.|\b\d)",
            text,
        )
        if jour_m:
            entry["journal"] = jour_m.group(1).strip().rstrip(".,;")

    # ---- 标题 ----
    title_text = text
    # 去掉开头的作者列表
    # 常见作者格式：
    #   "Smith J, Doe A, and Roe B."  →  "Smith J., Doe A., Roe B."
    #   "Smith, J.; Doe, A.; Roe, B."
    #   "Smith J A, Doe A B"
    # 启发式：作者列表通常以 ". " 结束（最后一个作者后跟句号）
    # 尝试匹配 "作者列表. 标题. 期刊..."
    # 策略：找到第一个 ". " 之后的内容作为标题候选
    # 但要跳过作者名中的缩写点（如 "J. Smith"）

    # 尝试去掉作者列表：匹配开头的 "Name X.X., Name X.X., ... and Name X.X."
    # 或 "Name, X.X.; Name, X.X.; ..."
    author_pattern = re.compile(
        r"^[A-Z][A-Za-z\u00C0-\u017F'\-]+"
        r"(?:\s+[A-Z]\.?)+"
        r"(?:\s*[,;]\s*[A-Z][A-Za-z\u00C0-\u017F'\-]+(?:\s+[A-Z]\.?)+)*"
        r"(?:\s*(?:,|and|&)\s*[A-Z][A-Za-z\u00C0-\u017F'\-]+(?:\s+[A-Z]\.?)+)*"
        r"\s*\.+\s*"
    )
    author_m = author_pattern.match(title_text)
    if author_m:
        title_text = title_text[author_m.end():]
    else:
        # 另一种格式："Name, X. X.; Name, X. X.; ..."
        author_pattern2 = re.compile(
            r"^[A-Z][A-Za-z\u00C0-\u017F'\-]+,\s*[A-Z]\.?(?:\s*[A-Z]\.?)*"
            r"(?:\s*;\s*[A-Z][A-Za-z\u00C0-\u017F'\-]+,\s*[A-Z]\.?(?:\s*[A-Z]\.?)*\s*)*"
            r"(?:\s*(?:,|and|&)\s*[A-Z][A-Za-z\u00C0-\u017F'\-]+,\s*[A-Z]\.?(?:\s*[A-Z]\.?)*\s*)*"
            r"\.+\s*"
        )
        author_m2 = author_pattern2.match(title_text)
        if author_m2:
            title_text = title_text[author_m2.end():]

    # 去掉年份
    if entry["year"]:
        title_text = re.sub(
            r"\(?:" + entry["year"] + r"\)?[.,;]?\s*",
            " ", title_text, count=1
        )
    # 去掉期刊名
    if entry["journal"]:
        title_text = title_text.replace(entry["journal"], " ")

    # 去掉末尾的卷号/页码信息（如 "372, 825–834." 或 "60, 689–692."）
    title_text = re.sub(
        r"\s*\d{1,4}(?:\s*[-–,]\s*\d{1,5})*\s*[.,;]?\s*$",
        "", title_text
    )
    # 去掉末尾的 "e\d+" 页码（如 "e53757"）
    title_text = re.sub(r"\s+e\d+\s*[.,;]?\s*$", "", title_text)

    title_text = re.sub(r"\s+", " ", title_text).strip(" .,;")

    # 如果标题为空或过短，回退为清理后的原始文本（去掉编号、DOI、标签后）
    if len(title_text) < 10:
        title_text = text

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
        items.append(body[m.start():])
        last = m.start()

    # 若没有匹配到编号，则整体作为单条退化处理
    if not items:
        cleaned = clean_text(body)
        if cleaned and len(cleaned) > 20:
            return [{"title": cleaned, "doi": "", "year": "", "journal": ""}]
        return []

    references = []
    for raw in items:
        raw = raw.strip()
        if not raw:
            continue
        # 跳过过短的片段（可能是章节标题残留）
        if len(raw) < 15:
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
            first_page_text = normalize_text(doc[0].get_text("text"))

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
            title_display = result['title'][:60] + ('...' if len(result['title']) > 60 else '')
            print(f"    [成功] 标题: {title_display}")
            print(f"           DOI:  {result['doi'] if result['doi'] else '(未识别)'}")
            print(f"           年份: {result['year'] if result['year'] else '(未识别)'}")
            print(f"           期刊: {result['journal'] if result['journal'] else '(未识别)'}")
            print(f"           关键词: {len(result['keywords'])} 个")
            print(f"           摘要: {len(result['abstract'])} 字符")
            print(f"           参考文献: {len(result['reference_list'])} 条")
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
