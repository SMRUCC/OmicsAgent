lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Fix line609-610: put else on same line
lines[609] <- 'if (p_val_plsda <0.05) cat(" => PLSDA group separation significant (p<0.05)\\n") else cat(" => PLSDA group separation NOT significant (p>=0.05)\\n")'
# Remove the now-unnecessary line610
lines[610] <- ""

# Also fix the else/else if inside the for loop (lines617-622)
# Line617: } else { -> should stay on same line after line616
lines[616] <- ' cat(sprintf(" => OPLSDA(%s) separation significant (p=%.4f, Q2=%.3f)\\n", pw_nm, pv, q2v)) } else {'
lines[617] <- ""
# Line618 becomes the else body
lines[618] <- ' cat(sprintf(" => OPLSDA(%s) separation NOT significant (p=%.4f, Q2=%.3f)\\n", pw_nm, pv, q2v))'
# Line619: } -> stays as is

# Line620-622: if/else if/else - combine on one line
lines[620] <- ' if (q2v >=0.4) cat(sprintf(" => OPLSDA(%s) good predictive ability\\n", pw_nm)) else if (q2v >=0) cat(sprintf(" => OPLSDA(%s) moderate predictive ability\\n", pw_nm)) else cat(sprintf(" => OPLSDA(%s) may be overfitted\\n", pw_nm))'
lines[621] <- ""
lines[622] <- ""

writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Fixed R syntax: else must be on same line as if block.\n")
