#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PubMed 在线检索脚本
====================
通过 NCBI E-utilities 接口检索 PubMed 文献，获取文献标题、引用信息、摘要，
若可获取则下载 PMC 全文。检索结果以 txt 文件形式保存到指定目录。

使用方式：
    python pubmed_search.py --keywords "keyword1,keyword2" --output-dir ./refs --max-count 20

依赖：
    pip install biopython
"""

import os
import sys
import time
import argparse
import json
import re
from datetime import datetime

try:
    from Bio import Entrez
    from Bio import Medline
    BIOPYTHON_AVAILABLE = True
except ImportError:
    BIOPYTHON_AVAILABLE = False
    print("Warning: biopython not installed. Install with: pip install biopython")
    print("Falling back to direct HTTP requests...")


def search_pubmed(keyword, max_count=20, email="research@example.com"):
    """Search PubMed for papers matching the keyword."""
    if BIOPYTHON_AVAILABLE:
        Entrez.email = email
        try:
            handle = Entrez.esearch(db="pubmed", term=keyword, retmax=max_count, sort="relevance")
            record = Entrez.read(handle)
            handle.close()
            id_list = record["IdList"]
            
            if not id_list:
                return []
            
            # Fetch full records
            handle = Entrez.efetch(db="pubmed", id=",".join(id_list), rettype="medline", retmode="text")
            records = list(Medline.parse(handle))
            handle.close()
            
            papers = []
            for rec in records:
                paper = {
                    "pmid": rec.get("PMID", ""),
                    "title": rec.get("TI", ""),
                    "abstract": rec.get("AB", ""),
                    "authors": rec.get("AU", []),
                    "journal": rec.get("JT", rec.get("TA", "")),
                    "pub_date": rec.get("DP", ""),
                    "mesh_terms": rec.get("MH", []),
                    "keywords": rec.get("OT", [])
                }
                papers.append(paper)
            
            return papers
        except Exception as e:
            print(f"Error searching PubMed for '{keyword}': {e}")
            return []
    else:
        # Fallback: direct HTTP
        import urllib.request
        import urllib.parse
        
        base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"
        params = urllib.parse.urlencode({
            "db": "pubmed",
            "term": keyword,
            "retmax": max_count,
            "retmode": "json",
            "sort": "relevance"
        })
        
        try:
            url = base_url + "esearch.fcgi?" + params
            with urllib.request.urlopen(url, timeout=30) as response:
                data = json.loads(response.read().decode())
                id_list = data.get("esearchresult", {}).get("idlist", [])
            
            if not id_list:
                return []
            
            # Fetch summaries
            params = urllib.parse.urlencode({"db": "pubmed", "id": ",".join(id_list), "retmode": "json"})
            url = base_url + "esummary.fcgi?" + params
            with urllib.request.urlopen(url, timeout=30) as response:
                data = json.loads(response.read().decode())
            
            papers = []
            for pmid in id_list:
                rec = data.get("result", {}).get(pmid, {})
                paper = {
                    "pmid": pmid,
                    "title": rec.get("title", ""),
                    "abstract": "",  # esummary doesn't include abstract
                    "authors": [a.get("name", "") for a in rec.get("authors", [])],
                    "journal": rec.get("fulljournalname", rec.get("source", "")),
                    "pub_date": rec.get("pubdate", ""),
                    "mesh_terms": [],
                    "keywords": []
                }
                papers.append(paper)
            
            return papers
        except Exception as e:
            print(f"Error in fallback search for '{keyword}': {e}")
            return []


def fetch_pmc_fulltext(pmid, email="research@example.com"):
    """Try to fetch PMC full text if available."""
    if not BIOPYTHON_AVAILABLE:
        return None
    
    try:
        Entrez.email = email
        # Convert PMID to PMC ID
        handle = Entrez.elink(dbfrom="pubmed", db="pmc", id=pmid)
        record = Entrez.read(handle)
        handle.close()
        
        if record and record[0].get("LinkSetDb"):
            pmc_id = record[0]["LinkSetDb"][0]["Link"][0]["Id"]
            # Fetch full text
            handle = Entrez.efetch(db="pmc", id=pmc_id, rettype="xml", retmode="xml")
            content = handle.read()
            handle.close()
            # Simple text extraction from XML
            text = re.sub(r'<[^>]+>', ' ', content.decode('utf-8', errors='ignore'))
            text = re.sub(r'\s+', ' ', text).strip()
            return text
    except Exception as e:
        print(f"Failed to fetch PMC full text for PMID {pmid}: {e}")
    
    return None


def save_paper(paper, index, output_dir):
    """Save a single paper as a txt file."""
    safe_title = re.sub(r'[^\w\s-]', '', paper.get("title", "untitled"))[:50].strip()
    safe_title = safe_title.replace(" ", "_") if safe_title else f"paper_{index}"
    filename = f"{index:03d}_{safe_title}.txt"
    filepath = os.path.join(output_dir, filename)
    
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(f"Title: {paper.get('title', '')}\n")
        f.write(f"PMID: {paper.get('pmid', '')}\n")
        f.write(f"Journal: {paper.get('journal', '')}\n")
        f.write(f"Pub Date: {paper.get('pub_date', '')}\n")
        authors = paper.get("authors", [])
        if authors:
            f.write(f"Authors: {', '.join(authors[:10])}\n")
        mesh = paper.get("mesh_terms", [])
        if mesh:
            f.write(f"MeSH Terms: {'; '.join(mesh[:20])}\n")
        keywords = paper.get("keywords", [])
        if keywords:
            f.write(f"Keywords: {'; '.join(keywords[:20])}\n")
        f.write(f"\nAbstract:\n{paper.get('abstract', 'No abstract available')}\n")
        
        # Try to fetch full text
        pmid = paper.get("pmid", "")
        if pmid:
            fulltext = fetch_pmc_fulltext(pmid)
            if fulltext:
                f.write(f"\nFull Text (PMC):\n{fulltext[:50000]}\n")
    
    return filepath


def main():
    parser = argparse.ArgumentParser(description="Search PubMed for papers and save as txt files")
    parser.add_argument("--keywords", required=True, help="Comma-separated keywords")
    parser.add_argument("--output-dir", required=True, help="Output directory for txt files")
    parser.add_argument("--max-count", type=int, default=20, help="Maximum papers per keyword")
    parser.add_argument("--email", default="research@example.com", help="Email for NCBI")
    args = parser.parse_args()
    
    os.makedirs(args.output_dir, exist_ok=True)
    
    keywords = [k.strip() for k in args.keywords.split(",") if k.strip()]
    per_keyword = max(1, args.max_count // max(1, len(keywords)))
    
    all_papers = []
    for kw in keywords:
        print(f"Searching PubMed for: {kw}")
        papers = search_pubmed(kw, per_keyword, args.email)
        all_papers.extend(papers)
        time.sleep(1)  # respect NCBI rate limit
    
    print(f"Total papers found: {len(all_papers)}")
    for i, paper in enumerate(all_papers, 1):
        try:
            save_paper(paper, i, args.output_dir)
        except Exception as e:
            print(f"Failed to save paper {i}: {e}")
    
    print("Done")


if __name__ == "__main__":
    main()
