const resolve_dataframe = function(data) {
    if (!is.data.frame(data)) {
        read.csv(data, row.names = 1, check.names = FALSE);
    } else {
        data;
    }
}