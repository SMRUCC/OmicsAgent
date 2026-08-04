// 临时 Playwright 驱动脚本（验证 dataset.html 关键交互后删除）
const { chromium } = require("playwright");

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1500, height: 950 } });
  await page.goto("http://127.0.0.1:8791/dataset.html");
  await page.waitForSelector("#basicBody");

  // 填写第一条数据集的路径
  await page.evaluate(() => {
    const set = (sel, val) => {
      const el = document.querySelector(sel);
      if (el) { el.value = val; el.dispatchEvent(new Event("input")); }
    };
    set("[data-fld='id']", "rna");
    set("[data-fld='type']", "transcriptome");
    set("[data-fld='label']", "肝脏转录组");
    set("[data-fld='expression']", "./rna/counts.csv");
    set("[data-fld='annotation']", "./rna/gene_anno.csv");
    set("[data-fld='sampleinfo']", "./meta/sample_rna.csv");
    set("[data-fld='unit']", "TPM");
    set("#baseDirInput", "G:\\OmicsWorks\\test");
  });

  await page.waitForTimeout(120);

  // 切换到内联编辑，添加一行并输入 subject_id
  await page.click("[data-kind='inline']");
  await page.waitForTimeout(120);
  await page.click("#addRowBtn");
  await page.waitForTimeout(80);
  await page.fill("#alignTable input[data-col='subject_id']", "P001");
  await page.waitForTimeout(80);

  // 打开预览
  await page.click("#previewBtn");
  await page.waitForTimeout(200);

  // 截图
  await page.screenshot({ path: "ds-state.png", fullPage: false });

  // 取 JSON 文本做断言
  const json = await page.evaluate(() => window.getManifestJson());
  console.log("JSON BEGIN");
  console.log(json);
  console.log("JSON END");

  await browser.close();
})();
