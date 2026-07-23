import csv
with open('G:/OmicsWorks/test/metabolism/demo/results/tables/combined_diff_results.csv', 'r', encoding='utf-8') as f:
 reader = csv.DictReader(f)
 key_terms = ['Proline', 'TUDCA', 'Taurocholate', 'Tauro', 'Cholic acid', 'Taurine', 'Deoxycholate', 
 'Butyrate', 'Linoleate', 'Arachidonate', 'Succinate', 'Lithocholate', 'Glycodeoxycholate',
 'Murideoxycholate', 'Cholate', 'Chenodeoxycholate', 'Glycolithocholic']
 for row in reader:
 name = row.get('name', '')
 if name:
 for term in key_terms:
 if term.lower() in name.lower():
 print(f"{name}: FE_vs_CD logFC={row.get('logFC_FE_vs_CD','')} adj.P={row.get('adj.P.Val_FE_vs_CD','')} | CD_vs_NC logFC={row.get('logFC_CD_vs_NC','')} adj.P={row.get('adj.P.Val_CD_vs_NC','')} | Trend={row.get('trend_pattern','')} | VIP={row.get('VIP_score','')}")
 break
