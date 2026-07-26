lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Find the for loop at line612
cat("Line612:", lines[612], "\n")
cat("Line613:", lines[613], "\n") 
cat("Line614:", lines[614], "\n")
cat("Line615:", lines[615], "\n")
cat("Line616:", lines[616], "\n")

# Rebuild the file: keep lines1:611, insert new for loop, keep lines615:end
new_section <- c(
'for (pw_nm in pairwise_names) {',
' pv <- opls_perm_all$P_Value[opls_perm_all$Comparison == pw_nm]',
' q2v <- opls_params_all$Q2[opls_params_all$Comparison == pw_nm]',
' if (pv <0.05) {',
' cat(sprintf(" => OPLSDA(%s) separation significant (p=%.4f, Q2=%.3f)\\n", pw_nm, pv, q2v))',
' } else {',
' cat(sprintf(" => OPLSDA(%s) separation NOT significant (p=%.4f, Q2=%.3f)\\n", pw_nm, pv, q2v))',
' }',
' if (q2v >=0.4) cat(sprintf(" => OPLSDA(%s) good predictive ability\\n", pw_nm))',
' else if (q2v >=0) cat(sprintf(" => OPLSDA(%s) moderate predictive ability\\n", pw_nm))',
' else cat(sprintf(" => OPLSDA(%s) may be overfitted\\n", pw_nm))',
'}'
)

# Build new content
new_lines <- c(
 lines[1:611],
 new_section,
 lines[615:length(lines)]
)

writeLines(new_lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Rebuilt file successfully!\n")
cat("Old length:", length(lines), "New length:", length(new_lines), "\n")
