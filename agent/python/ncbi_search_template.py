import os
import sys
import time
import urllib.request
import urllib.parse
import json
import xml.etree.ElementTree as ET

# NCBI PubMed search script
# Searches PubMed for the given keywords and saves results as txt files

KEYWORDS = [{KEYWORDS}]
MAX_RESULTS = {MAX_RESULTS}
OUTPUT_DIR = r"{OUTPUT_DIR}"

def search_pubmed(keyword, max_results):
    base_url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
    # Step 1: ESearch to get PMIDs
    search_params = urllib.parse.urlencode({
        'db': 'pubmed',
        'term': keyword,
        'retmax': max_results,
        'retmode': 'json',
        'sort': 'date'
    })
    search_url = f"{base_url}/esearch.fcgi?{search_params}"
    try:
        with urllib.request.urlopen(search_url, timeout=30) as resp:
            data = json.loads(resp.read().decode('utf-8'))
        pmids = data.get('esearchresult', {}).get('idlist', [])
    except Exception as e:
        print(f"ESearch failed for keyword '{keyword}': {e}")
        return []

    # Step 2: EFetch to get full records
    if not pmids:
        return []

    fetch_params = urllib.parse.urlencode({
        'db': 'pubmed',
        'id': ','.join(pmids),
        'retmode': 'xml'
    })
    fetch_url = f"{base_url}/efetch.fcgi?{fetch_params}"
    try:
        with urllib.request.urlopen(fetch_url, timeout=60) as resp:
            xml_data = resp.read().decode('utf-8')
    except Exception as e:
        print(f"EFetch failed: {e}")
        return []

    # Parse XML
    papers = []
    try:
        root = ET.fromstring(xml_data)
        for article in root.findall('.//PubmedArticle'):
            paper = {}
            pmid_elem = article.find('.//PMID')
            paper['pmid'] = pmid_elem.text if pmid_elem is not None else ''
            title_elem = article.find('.//ArticleTitle')
            paper['title'] = title_elem.text if title_elem is not None else ''
            journal_elem = article.find('.//Journal/Title')
            paper['journal'] = journal_elem.text if journal_elem is not None else ''
            year_elem = article.find('.//PubDate/Year')
            paper['year'] = year_elem.text if year_elem is not None else ''
            doi_elem = article.find('.//ArticleId[@IdType="doi"]')
            paper['doi'] = doi_elem.text if doi_elem is not None else ''

            # Authors
            authors = []
            for author in article.findall('.//Author'):
                last = author.find('LastName')
                init = author.find('Initials')
                if last is not None:
                    name = last.text
                    if init is not None:
                        name += ' ' + init.text
                    authors.append(name)
            paper['authors'] = '; '.join(authors)

            # Abstract
            abstract_parts = []
            for abs in article.findall('.//Abstract/AbstractText'):
                if abs.text:
                    abstract_parts.append(abs.text)
            paper['abstract'] = ' '.join(abstract_parts)

            # MeSH terms
            mesh_terms = []
            for mesh in article.findall('.//MeshHeading/DescriptorName'):
                if mesh.text:
                    mesh_terms.append(mesh.text)
            paper['mesh_terms'] = '; '.join(mesh_terms)

            papers.append(paper)
    except Exception as e:
        print(f"XML parse failed: {e}")

    return papers

def save_paper(paper, idx, output_dir):
    safe_title = ''.join(c if c.isalnum() or c in ' -_' else '_' for c in paper.get('title', '')[:50])
    filename = f"ref_{idx}_{safe_title}.txt"
    filepath = os.path.join(output_dir, filename)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(f"PMID: {paper.get('pmid', '')}\n")
        f.write(f"Title: {paper.get('title', '')}\n")
        f.write(f"Authors: {paper.get('authors', '')}\n")
        f.write(f"Journal: {paper.get('journal', '')}\n")
        f.write(f"Year: {paper.get('year', '')}\n")
        f.write(f"DOI: {paper.get('doi', '')}\n")
        f.write(f"MeSH Terms: {paper.get('mesh_terms', '')}\n")
        f.write('\nAbstract:\n')
        f.write(paper.get('abstract', ''))
    return filepath

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    all_papers = []
    per_keyword = max(1, MAX_RESULTS // len(KEYWORDS)) if KEYWORDS else 0
    for kw in KEYWORDS:
        print(f"Searching PubMed for: {kw}")
        papers = search_pubmed(kw, per_keyword)
        all_papers.extend(papers)
        time.sleep(1)  # respect NCBI rate limit

    print(f"Total papers found: {len(all_papers)}")
    for i, paper in enumerate(all_papers, 1):
        try:
            save_paper(paper, i, OUTPUT_DIR)
        except Exception as e:
            print(f"Failed to save paper {i}: {e}")

    print("Done")

if __name__ == '__main__':
    main()
