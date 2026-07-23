path = "G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R"
data = open(path, "r").read()
data = data.replace("in1:", "in" + " " + "1:")
open(path, "w").write(data)
print("Done")
