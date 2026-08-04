// 临时用于 playwright-cli run-code 的浏览器端脚本
["expression", "annotation", "sampleinfo"].forEach((k, i) => {
  const el = document.querySelector(`[data-fld='${k}']`);
  if (el) {
    el.value = ["./rna/counts.csv", "./rna/gene_anno.csv", "./meta/sample_rna.csv"][i];
    el.dispatchEvent(new Event("input"));
  }
});
const b = document.querySelector("#baseDirInput");
if (b) { b.value = "G:\\OmicsWorks\\test"; b.dispatchEvent(new Event("input")); }

// 切换到内联编辑，添加行并填写示例数据
const kindBtn = document.querySelector("[data-kind='inline']");
if (kindBtn) kindBtn.click();
setTimeout(() => {
  const add = document.querySelector("#addRowBtn");
  if (add) add.click();
  const inp = document.querySelector("#alignTable input[data-col='subject_id']");
  if (inp) { inp.value = "P001"; inp.dispatchEvent(new Event("input")); }
}, 80);
