 srn <- length(asf) <=100
 fsize <- ifelse(srn,7,1)

 hcol <- colorRampPalette(c("#4DBBD5", "white", "#E64B35"))(100)
 hh <- max(6, min(24, nrow(hmz) *0.25 +3))
