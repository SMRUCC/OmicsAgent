path = "G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R"
with open(path, 'r') as f:
 lines = f.readlines()

fix_count =0
for i in range(len(lines)):
 if "for (i in1:nrow(combined)) {" in lines[i]:
 # Replace with properly spaced version
 lines[i] = lines[i].replace("in1:nrow", "in" + " " + "1:nrow")
 fix_count +=1
 print(f"Fixed line {i+1}: {repr(lines[i])}")

if fix_count >0:
 with open(path, 'w') as f:
 f.writelines(lines)
 print(f"Fixed {fix_count} occurrences")
else:
 print("No occurrences found to fix")
