combined <- read.csv('G:/OmicsWorks/test/metabolism/demo/results/tables/combined_diff_results.csv', stringsAsFactors=FALSE)
# Print all names containing 'bile', 'cholic', 'cholate', 'tauro', 'glyco', 'L-Proline', 'proline'
idx <- grep('bile|cholic|cholate|tauro|glyco|proline|succinate|arachidon|linoleat|butyrate|taurin', combined$name, ignore.case=TRUE)
cat('Found', length(idx), 'names:\n')
for (i in idx) {
 cat(sprintf('%s: FE_vs_CD logFC=%.3f adj.P=%.2e | CD_vs_NC logFC=%.3f adj.P=%.2e | Trend=%s | VIP=%.3f\n', 
 combined$name[i], combined$logFC_FE_vs_CD[i], combined$adj.P.Val_FE_vs_CD[i], 
 combined$logFC_CD_vs_NC[i], combined$adj.P.Val_CD_vs_NC[i], 
 combined$trend_pattern[i], combined$VIP_score[i]))
}
