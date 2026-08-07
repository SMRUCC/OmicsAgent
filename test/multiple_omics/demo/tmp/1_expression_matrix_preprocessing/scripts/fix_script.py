# -*- coding: utf-8 -*-
import io
p = r"G:/OmicsWorks/test/multiple_omics/demo/tmp/1_expression_matrix_preprocessing/scripts/1_expression_matrix_preprocessing.R"
with io.open(p, "r", encoding="utf-8") as f:
 txt = f.read()
old = "else1e-6" # no space (broken)
new = "else" + " " + "1e-6" # with space (correct R syntax)
count = txt.count(old)
assert count >0, "pattern not found"
fixed = txt.replace(old, new)
with io.open(p, "w", encoding="utf-8") as f:
 f.write(fixed)
print("fixed OK, occurrences replaced:", count)
print("new fragment:", new)
