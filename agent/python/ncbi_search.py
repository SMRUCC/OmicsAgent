# ============================================================================
# NCBI PubMed 在线检索脚本
# 由 NcbiOnlineSearcher.vb 调用
# 用法: python ncbi_search.py "<keywords>" <output_dir> <max_results>
# ============================================================================
import sys
import os
import time
import re
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET

def esearch(keywords, max_results=20):
    """通过 NCBI E-utilities esearch 检索 PubMed PMID 列表"""
    base = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
    params = {
        "db": "pubmed",
        "term": keywords,
        "retmax": str(max_results),
        "retmode": "json",
        "sort": "relevance"
    }
    url = base + "?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "OmicsAgent/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            import json
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("esearchresult", {}).get("idlist", [])
    except Exception as e:
        print(f"esearch error: {e}", file=sys.stderr)
        return []

def efetch(pmids):
    """通过 NCBI E-utilities efetch 获取文献详细信息"""
    if not pmids:
        return ""
    base = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    data = urllib.parse.urlencode({
        "db": "pubmed",
        "id": ",".join(pmids),
        "retmode": "xml",
        "rettype": "abstract"
    }).encode("utf-8")
    try:
        req = urllib.request.Request(base, data=data, headers={"User-Agent": "OmicsAgent/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"efetch error: {e}", file=sys.stderr)
        return ""

def parse_papers(xml_text):
    """解析 efetch 返回的 XML"""
    papers = []
    try:
        root = ET.fromstring(xml_text)
    except Exception as e:
        print(f"XML parse error: {e}", file=sys.stderr)
        return papers

    for art in root.findall(".//PubmedArticle"):
        pmid = get_text(art, ".//PMID")
        title = get_text(art, ".//ArticleTitle")
        abstract_parts = []
        for ab in art.findall(".//Abstract/AbstractText"):
            label = ab.get("Label", "")
            text = "".join(ab.itertext()).strip()
            if label:
                abstract_parts.append(f"{label}: {text}")
            else:
                abstract_parts.append(text)
        abstract = " ".join(abstract_parts)
        journal = get_text(art, ".//Journal/Title")
        year = get_text(art, ".//PubDate/Year") or get_text(art, ".//PubDate/MedlineDate")[:4]
        doi = ""
        for aid in art.findall(".//ArticleId"):
            if aid.get("IdType") == "doi":
                doi = aid.text or ""
                break
        authors = []
        for au in art.findall(".//Author"):
            last = get_text(au, "LastName")
            init = get_text(au, "Initials")
            if last:
                authors.append(f"{last} {init}".strip())
        papers.append({
            "pmid": pmid,
            "title": re.sub(r"<[^>]+>", "", title),
            "abstract": re.sub(r"<[^>]+>", "", abstract),
            "journal": re.sub(r"<[^>]+>", "", journal),
            "year": year,
            "doi": doi,
            "authors": "; ".join(authors)
        })
    return papers

def get_text(elem, path):
    node = elem.find(path)
    return (node.text or "").strip() if node is not None and node.text else ""

def main():
    if len(sys.argv) < 3:
        print("Usage: python ncbi_search.py <keywords> <output_dir> [max_results]")
        sys.exit(1)
    keywords = sys.argv[1]
    output_dir = sys.argv[2]
    max_results = int(sys.argv[3]) if len(sys.argv) > 3 else 20

    os.makedirs(output_dir, exist_ok=True)
    print(f"Searching PubMed for: {keywords}")
    pmids = esearch(keywords, max_results)
    print(f"Found {len(pmids)} PMIDs")
    if not pmids:
        return
    time.sleep(0.5)
    xml_text = efetch(pmids)
    if not xml_text:
        return
    papers = parse_papers(xml_text)
    print(f"Parsed {len(papers)} papers")
    for i, p in enumerate(papers, 1):
        fname = os.path.join(output_dir, f"ncbi_paper_{i:02d}_{p['pmid']}.txt")
        with open(fname, "w", encoding="utf-8") as f:
            f.write(f"Title: {p['title']}\n")
            f.write(f"PMID: {p['pmid']}\n")
            f.write(f"Authors: {p['authors']}\n")
            f.write(f"Journal: {p['journal']}\n")
            f.write(f"Year: {p['year']}\n")
            f.write(f"DOI: {p['doi']}\n\n")
            f.write("Abstract:\n")
            f.write(p["abstract"])
            f.write("\n")
        print(f"Saved: {fname}")

if __name__ == "__main__":
    main()
