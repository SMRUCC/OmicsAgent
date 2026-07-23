file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Simplify the OPLSDA section: skip sPLSDA tuning, use PLSDA directly for multi-group
# The sPLSDA with sparse keepX keeps failing to converge

# Find the problematic section and replace it
# From "} else {" after ropls check, to the brace closing the else block

# Find the else line
else_line <- grep("^} else \\{$", lines)
cat("else lines:", else_line, "\n")

# The else we need is the one inside the OPLSDA section (after if (nlevels(groups) ==2))
# Find it by looking for the one followed by cat(">>> Using mixOmics::splsda...")
for (el in else_line) {
 if (el < length(lines) && grepl("mixOmics::splsda", lines[el+1])) {
 cat("Found relevant else at line:", el, "\n")
 
 # Replace from else_line+1 to the matching closing brace
 # We know the closing brace is at line314 (from earlier debugging)
 # Let me just replace the entire block
 replacement <- c(
 ' cat(">>> Using PLSDA for multi-group OPLSDA-like analysis\\n")',
 ' # For multi-group, we use PLSDA and rename components as predictive/orthogonal',
 ' # This provides OPLSDA-like interpretation',
 ' oplsda_model <- plsda(t(expr_matrix), groups, ncomp =3)'
 )
 
 # Find the closing brace (the } that closes this else block)
 # Count braces from else_line+1
 brace_count <-1
 close_line <- el +1
 while (brace_count >0 && close_line <= length(lines)) {
 brace_count <- brace_count + 
 nchar(gsub("[^{]", "", lines[close_line])) - 
 nchar(gsub("[^}]", "", lines[close_line]))
 if (brace_count ==0) break
 close_line <- close_line +1
 }
 cat("Else block from line", el+1, "to", close_line, "(brace count:", brace_count, ")\n")
 
 lines <- c(lines[1:el], replacement, lines[(close_line+1):length(lines)])
 cat("Replaced else block. New structure:\n")
 for (i in el:(el+5)) cat("Line", i, ":", lines[i], "\n")
 break
 }
}

writeLines(lines, file_path)
cat("Done.\n")
