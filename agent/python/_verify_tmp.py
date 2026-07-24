# -*- coding: utf-8 -*-
# Python 2.7-compatible replica of the pure parsing logic from extract_pdf_text.py
# (type hints stripped) to validate regex/JSON behavior without PyMuPDF/Py3.
import re, json

DOI_PATTERN = re.compile(r"\b10\.\d{4,9}/[-._;()/:A-Za-z0-9]+", re.IGNORECASE)
YEAR_PATTERN = re.compile(r"\b(?:19|20)\d{2}\b")
KEYWORDS_START_REGEX = re.compile(r"(?:^|\n)\s*(?:Key\s*words?|Keywords|Index\s+Terms|Index\s+terms)\s*[:：]", re.IGNORECASE)
REFERENCES_START_REGEX = re.compile(r"\n\s*(?:References|Reference|Bibliography|REFERENCES)\b", re.IGNORECASE)
REFERENCES_END_REGEX = re.compile(r"\n\s*(?:Appendix|Appendices|Acknowledg(?:e?ments?|ment)|Supporting\s+Information|Supplementary\s+(?:Material|Information)|Author\s+Contributions|Conflict\s+of\s+Interest|CRediT\s+authorship)\b", re.IGNORECASE)
REFERENCE_ITEM_REGEX = re.compile(r"\n\s*(?:\[(\d{1,3})\]|\((\d{1,3})\)|(\d{1,3})[.)\]])")

def extract_year(full_text):
    if not full_text: return ""
    m = re.search(r"\u00a9\s*\d{4}\s*(?:[-–]\s*\d{4})?", full_text)
    if m:
        ym = YEAR_PATTERN.search(m.group(0))
        if ym: return ym.group(0)
    m = re.search(r"\b(?:Published|Online|Print|Available)\b[^\n]{0,30}?\b((?:19|20)\d{2})\b", full_text, re.IGNORECASE)
    if m: return m.group(1)
    m = re.search(r"\b(?:Received|Accepted)\b[^\n]{0,40}?\b((?:19|20)\d{2})\b", full_text, re.IGNORECASE)
    if m: return m.group(1)
    m = YEAR_PATTERN.search(full_text)
    if m: return m.group(0)
    return ""

def extract_journal(full_text, first_page_text=""):
    if not full_text: return ""
    candidates = []
    if first_page_text: candidates.append(first_page_text)
    candidates.append(full_text)
    for text in candidates:
        m = re.search(r"\b(?:The\s+)?(?:Journal\s+of\s+[\w\s&\-]+|Journal\s+[A-Z][\w\s&\-]+|IEEE\s+[\w\s]+|Proceedings\s+of\s+[\w\s&\-]+)", text)
        if m:
            name = m.group(0).strip(); name = re.sub(r"\s+", " ", name)
            if 3 <= len(name) <= 120: return name
        m = re.search(r"\u00a9\s*\d{4}[^\n]{0,60}?\b([A-Z][\w\s&\-]+(?:Journal|Press|Publications|Magazine|Transactions|Letters|Reviews|Reports|Science|Springer|Elsevier))\b", text, re.IGNORECASE)
        if m: return m.group(1).strip()
    return ""

def extract_keywords(full_text):
    if not full_text: return []
    m = KEYWORDS_START_REGEX.search(full_text)
    if not m: return []
    after = full_text[m.end():]
    line_end = after.find("\n")
    if line_end == -1: block = after[:1000]
    else: block = after[:line_end]
    rest = after[line_end+1:]
    for _ in range(3):
        nxt = rest.find("\n")
        piece = rest[:nxt] if nxt != -1 else rest
        if re.match(r"^\s*(?:[A-Za-z0-9].{2,60})\s*[,;]$", piece) or re.match(r"^\s*(?:and\s+)?[A-Za-z0-9].{2,60}\s*$", piece):
            block += " " + piece
            if nxt == -1: break
            rest = rest[nxt+1:]
        else: break
    block = re.sub(r"^\s*[:：]\s*", "", block).strip()
    parts = re.split(r"[;,]", block)
    return [p.strip().strip('.\"\'') for p in parts if p.strip() and len(p.strip()) <= 80]

def _parse_reference_entry(raw):
    entry = {"title":"","doi":"","year":"","journal":""}
    if not raw: return entry
    text = raw.strip()
    doi_m = DOI_PATTERN.search(text)
    if doi_m:
        entry["doi"] = re.sub(r"[.,;:)\]\}]+$", "", doi_m.group(0)).strip()
        text = text[:doi_m.start()] + text[doi_m.end():]
    years = YEAR_PATTERN.findall(text)
    if years: entry["year"] = years[-1]
    jour_m = re.search(r"\b(?:in|In)\s+([A-Z][\w\s&\-]{2,60}?)(?:,|\.|\b\d)", text)
    if jour_m: entry["journal"] = jour_m.group(1).strip()
    title_text = text
    title_text = re.sub(r"^[A-Z][\w.\-]*(?:,?\s*(?:and\s+)?[A-Z][\w.\-]*){0,10}\.?", "", title_text).strip()
    title_text = re.sub(r"\b(?:19|20)\d{2}\b[.,]?", "", title_text).strip()
    if entry["journal"]: title_text = title_text.replace(entry["journal"], "")
    title_text = re.sub(r"\s+", " ", title_text).strip(" .,")
    entry["title"] = title_text
    return entry

def extract_reference_list(full_text):
    if not full_text: return []
    start_m = REFERENCES_START_REGEX.search(full_text)
    if not start_m: return []
    body = full_text[start_m.end():]
    end_m = REFERENCES_END_REGEX.search(body)
    if end_m: body = body[:end_m.start()]
    items = []; last = 0
    for m in REFERENCE_ITEM_REGEX.finditer(body):
        if items: items[-1] = body[last:m.start()]
        items.append(body[m.start():]); last = m.start()
    if not items: return [{"title": body.strip(), "doi":"","year":"","journal":""}]
    return [_parse_reference_entry(r.strip()) for r in items if r.strip()]

sample = (
    "\n(c) 2021 Elsevier Ltd. All rights reserved. Published in Journal of Computational Biology.\n"
    "This work was Received 2020 and Accepted 2021.\n\n"
    "Abstract\nWe study the alignment of genomic sequences using a novel method.\n\n"
    "Keywords: bioinformatics; sequence alignment, genomics\n\n"
    "1. Introduction\nSome text here.\n\n"
    "References\n"
    "[1] Smith J, Doe A. A novel method for alignment. Journal of Computational Biology, 2020, 12(3):45-67. https://doi.org/10.1234/abc.def\n"
    "[2] Lee K. Deep learning in genomics. Nature, 2019, 8:100-110. doi:10.5678/xyz.uvw\n"
)

year = extract_year(sample)
journal = extract_journal(sample, sample)
keywords = extract_keywords(sample)
refs = extract_reference_list(sample)

print("YEAR:", year)
print("JOURNAL:", journal)
print("KEYWORDS:", keywords)
print("REFS:", json.dumps(refs, ensure_ascii=False, indent=2))

metadata = {"doi":"10.1234/abc.def","year":year,"journal":journal,"keywords":keywords}
metadata_json = json.dumps(metadata, ensure_ascii=False)
references_json = json.dumps(refs, ensure_ascii=False)
content = "\n".join(["A Novel Method for Genomic Sequence Alignment", metadata_json, references_json, "", sample.strip()])

m = json.loads(metadata_json); r = json.loads(references_json)
print("OK metadata keys:", set(m.keys()) == {"doi","year","journal","keywords"})
print("OK references structure:", all(set(x.keys()) >= {"title","doi","year","journal"} for x in r))
lines = content.split("\n")
print("TOTAL LINES:", len(lines), "| LINE1=title LINE2=metadata LINE3=references LINE4=blank:", lines[3]=="")
print("LINE1:", lines[0])
print("LINE2:", lines[1])
print("LINE3(trunc):", lines[2][:150])
