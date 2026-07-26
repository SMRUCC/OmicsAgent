const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const htmlPath = 'G:/OmicsWorks/test/metabolism/demo/analysis/report.html';
const pdfPath = 'G:/OmicsWorks/test/metabolism/demo/analysis/report.pdf';

console.log('HTML文件大小:', fs.statSync(htmlPath).size, '字节');

//检查是否已有可用的模块
try {
 //尝试使用puppeteer（如果已安装）
 const puppeteer = require('puppeteer');
 (async () => {
 const browser = await puppeteer.launch();
 const page = await browser.newPage();
 await page.goto('file://' + htmlPath, { waitUntil: 'networkidle0' });
 await page.pdf({
 path: pdfPath,
 format: 'A3',
 margin: { top: '15mm', bottom: '15mm', left: '15mm', right: '15mm' },
 printBackground: true
 });
 await browser.close();
 console.log('PDF成功生成:', pdfPath);
 console.log('PDF文件大小:', fs.statSync(pdfPath).size, '字节');
 })().catch(err => {
 console.error('Puppeteer错误:', err.message);
 process.exit(1);
 });
} catch (e) {
 console.log('Puppeteer未安装，尝试安装...');
 try {
 execSync('npm install puppeteer', { cwd: __dirname, stdio: 'inherit' });
 console.log('安装完成，重新运行脚本');
 } catch (installErr) {
 console.error('安装失败:', installErr.message);
 process.exit(1);
 }
}
