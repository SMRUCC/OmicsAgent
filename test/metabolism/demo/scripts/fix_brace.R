file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Find the missing closing brace for the else block
# The structure is:
# if (nlevels(groups) ==2) {
# ...
# } else {
# ... (lines305-326 approximately)
# } <-- THIS IS MISSING
# 
# # Extract scores...
# if (inherits(oplsda_model, "opls")) {

# Find the line with "if (inherits(oplsda_model, \"opls\"))"
opls_check <- grep('if \\(inherits\\(oplsda_model, "opls"\\)\\)', lines)
cat("Found opls check at line:", opls_check, "\n")

# This line should be preceded by a } closing the else block
# Let me check5 lines before
for (i in (opls_check-5):(opls_check-1)) {
 cat(" Line", i, ":", lines[i], "\n")
}

# The line before opls_check is likely a comment line or blank
# We need to insert a } before the comment

# Find the line that is the last of the else block
# Look for the inner if block closing brace
inner_if_close <- grep("^\\s*\\}\\s*$", lines[(opls_check-10):(opls_check-1)])
if (length(inner_if_close) >0) {
 last_close <- (opls_check-10) + max(inner_if_close) -1
 cat("Last closing brace found at line:", last_close, ":", lines[last_close], "\n")
 
 # The missing } should be inserted after this line
 # Insert a } before the comment line
 insert_pos <- opls_check -1
 while (insert_pos >0 && grepl("^\\s*#|^\\s*$", lines[insert_pos])) {
 insert_pos <- insert_pos -1
 }
 insert_pos <- insert_pos +1
 cat("Inserting } at position:", insert_pos, "\n")
 
 lines <- c(lines[1:(insert_pos-1)], "}", lines[insert_pos:length(lines)])
 cat("Inserted closing brace.\n")
}

writeLines(lines, file_path)
cat("Done.\n")
