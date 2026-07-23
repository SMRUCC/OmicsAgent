file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Fix the ropls::opls call - remove plotL, printL, crossval parameters
# These might not exist in all versions of ropls

# Find the opls call
opls_line <- grep("oplsda_model <- opls\\(", lines)
cat("Found opls() call at line:", opls_line, "\n")

if (length(opls_line) >0) {
 # Find the end of the opls call (matching closing parenthesis)
 start_idx <- opls_line[1]
 # The call spans multiple lines, find the closing parenthesis
 end_idx <- start_idx
 open_paren <-0
 for (i in start_idx:min(start_idx+20, length(lines))) {
 open_paren <- open_paren + 
 nchar(gsub("[^(]", "", lines[i])) - 
 nchar(gsub("[^)]", "", lines[i]))
 if (open_paren >=0 && i > start_idx) {
 end_idx <- i
 break
 }
 }
 
 cat("OPLS call from line", start_idx, "to", end_idx, "\n")
 for (i in start_idx:end_idx) {
 cat(" Line", i, ":", lines[i], "\n")
 }
 
 # Replace the opls call
 new_opls_call <- c(
 '# Use ropls::opls for OPLSDA',
 '# Remove problematic parameters (plotL, printL, crossval) not in all ropls versions',
 'oplsda_model <- tryCatch({',
 ' opls(',
 ' x = X_mat,',
 ' y = Y_fac,',
 ' predI =1,',
 ' orthoI =2',
 ' )',
 '}, error = function(e) {',
 ' cat(" Warning: standard OPLSDA failed:", e$message, "\\n")',
 ' cat(" Trying with predI=1, orthoI=1...\\n")',
 ' tryCatch({',
 ' opls(',
 ' x = X_mat,',
 ' y = Y_fac,',
 ' predI =1,',
 ' orthoI =1',
 ' )',
 ' }, error = function(e2) {',
 ' cat(" OPLSDA also failed:", e2$message, "\\n")',
 ' NULL',
 ' })',
 '})'
 )
 
 lines <- c(lines[1:(start_idx-1)], new_opls_call, lines[(end_idx+1):length(lines)])
 cat("OPLS call replaced.\n")
}

writeLines(lines, file_path)
cat("Done.\n")
