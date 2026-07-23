# Check feature IDs and match with annotation
raw <- read.csv("G:/OmicsWorks/test/metabolism/expression.csv", check.names = FALSE)
cat("First column name:", colnames(raw)[1], "\n")
cat("First few feature IDs:\n")
print(head(as.character(raw[,1])))
cat("\nLast few feature IDs:\n")
print(tail(as.character(raw[,1])))
cat("\nTotal features:", nrow(raw), "\n")

# Check metabolites annotation file
meta_anno <- read.csv("G:/OmicsWorks/test/metabolism/metabolites.csv", check.names = FALSE)
cat("\nMetabolites annotation columns:", colnames(meta_anno), "\n")
cat("First few IDs:\n")
print(head(as.character(meta_anno[,1])))
cat("\nTotal annotations:", nrow(meta_anno), "\n")

# Check if feature IDs from expression match any IDs in annotation
expr_ids <- as.character(raw[,1])
anno_ids <- as.character(meta_anno[,1])
cat("\nOverlap between expression features and annotation IDs:", sum(expr_ids %in% anno_ids), "\n")
cat("Overlap between annotation name and expression features:", sum(meta_anno$name %in% expr_ids), "\n")
