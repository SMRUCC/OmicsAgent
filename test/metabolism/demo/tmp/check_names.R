combined <- read.csv('G:/OmicsWorks/test/metabolism/demo/results/tables/combined_diff_results.csv', stringsAsFactors=FALSE)
cat('Column names:\n')
cat(paste(names(combined), collapse='\n'), '\n\n')
cat('First20 names:\n')
cat(paste(head(combined$name,20), collapse='\n'), '\n\n')
cat('Any name containing L-Proline:\n')
idx <- grep('L-Proline', combined$molecule_id, ignore.case=TRUE)
cat('Found', length(idx), '\n')
if (length(idx) >0) {
 for (i in idx) {
 cat(sprintf('%s (%s): FE_vs_CD logFC=%.3f adj.P=%.2e\n', combined$name[i], combined$molecule_id[i], combined$logFC_FE_vs_CD[i], combined$adj.P.Val_FE_vs_CD[i]))
 }
}
cat('\nAny name containing TUDCA or tauroursodeoxycholic:\n')
idx <- grep('tauroursodeoxycholic|TUDCA', combined$name, ignore.case=TRUE)
cat('Found', length(idx), '\n')
