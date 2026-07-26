const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const scriptDir = __dirname;
const htmlPath = 'G:/OmicsWorks/test/metabolism/demo/analysis/report.html';
const pdfPath = 'G:/OmicsWorks/test/metabolism/demo/analysis/report.pdf';

console.log('工作目录:', scriptDir);
console.log('HTML路径:', htmlPath);
console.log('PDF路径:', pdfPath);

//尝试安装puppeteer
console.log('\n尝试安装puppeteer...');
try {
 execSync('npm init -y', { cwd: scriptDir, stdio: 'pipe' });
 console.log('npm init完成');
} catch (e) {
 console.log('npm init跳过');
}

try {
 execSync('npm install puppeteer --no-save', { cwd: scriptDir, stdio: 'inherit', timeout:300000 });
 console.log('puppeteer安装成功');
} catch (e) {
 console.error('puppeteer安装失败:', e.message);
 process.exit(1);
}

//使用puppeteer转换
const puppeteer = require('puppeteer');
(async () => {
 const browser = await puppeteer.launch({ headless: true });
 const page = await browser.newPage();
 await page.goto('file:///' + htmlPath.replace(/\\/g, '/'), { 
 waitUntil: 'networkidle0',
 timeout:30000 
 });
 await page.pdf({
 path: pdfPath,
 format: 'A3',
 margin: { top: '15mm', bottom: '15mm', left: '15mm', right: '15mm' },
 printBackground: true,
 displayHeaderFooter: false
 });
 await browser.close();
 
 if (fs.existsSync(pdfPath)) {
 console.log('\nPDF成功生成:', pdfPath);
 console.log('PDF文件大小:', fs.statSync(pdfPath).size, '字节');
 } else {
 console.log('\nPDF生成失败');
 }
})().catch(err => {
 console.error('错误:', err.message);
 process.exit(1);
});
