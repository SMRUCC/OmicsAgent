combined <- read.csv('G:/OmicsWorks/test/metabolism/demo/results/tables/combined_diff_results.csv', stringsAsFactors=FALSE)

# Search in molecule_id for key metabolites
key_terms <- c('L-Proline', 'Taurocholate', 'Cholic acid', 'Taurine', 'Succinate', 
 'Linoleate', 'Arachidonate', 'Glycodeoxycholate', 'Murideoxycholate',
 'Lithocholate', 'Cholate', 'Deoxycholate', 'Glycolithocholic',
 'Taurolithocholate', '7-Oxodeoxycholate', '3b,7a,12a-Trihydroxy',
 'Glycolithocholic', 'Sulfolithocholylglycine')

for (term in key_terms) {
 idx <- grep(term, combined$molecule_id, ignore.case=TRUE, fixed=TRUE)
 if (length(idx) >0) {
 for (i in idx) {
 cat(sprintf('%s: FE_vs_CD logFC=%.3f adj.P=%.2e | CD_vs_NC logFC=%.3f adj.P=%.2e | FE_vs_NC logFC=%.3f adj.P=%.2e | Trend=%s | VIP=%.3f\n', 
 combined$molecule_id[i], 
 combined$logFC_FE_vs_CD[i], combined$adj.P.Val_FE_vs_CD[i], 
 combined$logFC_CD_vs_NC[i], combined$adj.P.Val_CD_vs_NC[i],
 combined$logFC_FE_vs_NC[i], combined$adj.P.Val_FE_vs_NC[i],
 combined$trend_pattern[i], combined$VIP_score[i]))
 }
 }
}
