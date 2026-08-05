# -*- coding: utf-8 -*-
import os
root = r"G:/OmicsWorks/test/multiple_omics/demo"
for rel in ["tmp/explore_test.txt", "tmp/1_expression_matrix_preprocessing/scripts/tmp_fix.txt"]:
 p = os.path.join(root, rel)
 if os.path.exists(p): os.remove(p)
 print("removed:", rel)
print("cleanup done")
