import os, re, sys
try:
    from Bio import Entrez
except ImportError:
    print('Biopython not installed; skipping PMC full text fetch.')
    sys.exit(0)

Entrez.email = 'omics-agent@example.com'
KNOWLEDGE_DIR = r'{KNOWLEDGE_DIR}'

def get_pmc_id(pmid):
    try:
        handle = Entrez.elink(dbfrom='pubmed', db='pmc', id=pmid)
        rec = Entrez.read(handle)
        handle.close()
        for linkset in rec:
            for linksetdb in linkset.get('LinkSetDb', []):
                if linksetdb.get('DbTo', '').lower() == 'pmc':
                    for item in linksetdb.get('IdList', []):
                        return 'PMC' + str(item)
    except Exception as e:
        print('elink failed for %s: %s' % (pmid, e))
    return None

def fetch_pmc_fulltext(pmc_id):
    try:
        handle = Entrez.efetch(db='pmc', id=pmc_id, rettype='text', retmode='text')
        text = handle.read()
        handle.close()
        return text
    except Exception as e:
        print('efetch failed for %s: %s' % (pmc_id, e))
        return None

def main():
    for fn in os.listdir(KNOWLEDGE_DIR):
        if not fn.startswith('ref_') or not fn.endswith('.txt'):
            continue
        path = os.path.join(KNOWLEDGE_DIR, fn)
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        m = re.search(r'PMID:\s*(\d+)', content)
        if not m:
            continue
        pmid = m.group(1)
        pmc_id = get_pmc_id(pmid)
        if not pmc_id:
            print('No PMC full text for PMID %s' % pmid)
            continue
        fulltext = fetch_pmc_fulltext(pmc_id)
        if not fulltext:
            continue
        if 'PMC Full Text' in content:
            print('PMC already appended for PMID %s' % pmid)
            continue
        with open(path, 'a', encoding='utf-8') as f:
            f.write('\n\n=== PMC Full Text (PMCID: %s) ===\n' % pmc_id)
            f.write(fulltext[:50000])
        print('Appended PMC full text for PMID %s (%s)' % (pmid, pmc_id))

if __name__ == '__main__':
    main()
