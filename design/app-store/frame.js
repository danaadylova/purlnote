// Frames phone screenshots for the App Store at 1320 x 2868 (6.9-inch
// iPhone): a caption on top, the screenshot below in a rounded phone shape.
// Usage: node frame.js <folder with 1.png, 2.png, ...> <output folder>
const {chromium}=require('playwright');const fs=require('fs');const path=require('path');
const [inDir,outDir]=process.argv.slice(2);
const font=(f)=>'file://'+path.join(__dirname,'node_modules/@fontsource',f);
const shots=[
  {n:1,bg:'#3B1C34',fg:'#FFF8EE',accent:'#E7A33E',title:'Every project,<br>one swipe away',sub:'Pick up right where you left off'},
  {n:2,bg:'#E3ECD8',fg:'#3B1C34',accent:'#3F5C37',title:'Never lose<br>your row',sub:'A row ruler that stays on your line'},
  {n:3,bg:'#F4CDBE',fg:'#3B1C34',accent:'#8A5A2B',title:'One step<br>at a time',sub:'Only your size\'s numbers'},
  {n:4,bg:'#F1E6D8',fg:'#3B1C34',accent:'#3F5C37',title:'Notes, photos<br>and counters',sub:'Everything for each project in one place'},
  {n:5,bg:'#3B1C34',fg:'#FFF8EE',accent:'#E7A33E',title:'Made by a knitter,<br>for knitters',sub:'Works offline, with or without Ravelry'},
];
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1320,height:2868}});
for(const s of shots){const img=path.resolve(inDir,s.n+'.png');if(!fs.existsSync(img))continue;
const html=`<style>
@font-face{font-family:B;src:url(${font('bricolage-grotesque/files/bricolage-grotesque-latin-800-normal.woff2')})}
@font-face{font-family:F;src:url(${font('figtree/files/figtree-latin-500-normal.woff2')})}
body{margin:0;width:1320px;height:2868px;overflow:hidden;background:${s.bg};color:${s.fg};text-align:center}
h1{font-family:B;font-size:118px;line-height:1.02;margin:190px 60px 0;letter-spacing:-2px}
p{font-family:F;font-size:52px;margin:34px 60px 0;opacity:.85}
.bar{width:120px;height:12px;border-radius:6px;background:${s.accent};margin:0 auto 46px}
.phone{position:absolute;left:150px;top:820px;width:1020px;border-radius:118px;overflow:hidden;
  border:22px solid #1d0f1a;box-shadow:0 40px 120px rgba(0,0,0,.28)}
.phone img{display:block;width:100%}
</style><div style="padding-top:1px"></div><h1 style="margin-top:170px"><div class="bar"></div>${s.title}</h1><p>${s.sub}</p>
<div class="phone"><img src="file://${img}"></div>`;
const tmp=path.join(outDir,"_frame.html");fs.writeFileSync(tmp,html);await p.goto("file://"+path.resolve(tmp));await p.evaluate(()=>document.fonts.ready);
await p.waitForTimeout(400);await p.screenshot({path:path.join(outDir,'appstore-'+s.n+'.png')});}
fs.rmSync(path.join(outDir,'_frame.html'),{force:true});fs.rmSync(path.join(outDir,'_frame.html'),{force:true});await b.close();})();
