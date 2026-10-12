/* Offline presentation: all names, posts and counts below are fictional. */
'use strict';
const paths={home:'M3 10 12 3l9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z',search:'M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0',user:'M20 21v-2a7 7 0 0 0-14 0v2M17 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0',plus:'M12 5v14M5 12h14',heart:'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z',comment:'M21 11a9 9 0 0 1-9 9 10 10 0 0 1-4-.8L3 21l1.7-5a9 9 0 1 1 16.3-5Z',repost:'m7 3-4 4 4 4M3 7h13a4 4 0 0 1 4 4m-3 10 4-4-4-4m4 4H8a4 4 0 0 1-4-4',share:'M12 16V3m-5 5 5-5 5 5M5 12v8a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-8',compass:'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM16 8l-3 5-5 3 3-5Z',back:'m15 5-7 7 7 7',more:'M5 12h.01M12 12h.01M19 12h.01',signal:'M4 18v-3m5 3V11m5 7V7m5 11V3',wifi:'M3 8a15 15 0 0 1 18 0M6 12a10 10 0 0 1 12 0m-9 4a5 5 0 0 1 6 0m-3 4h.01',smile:'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM8 14a4 4 0 0 0 8 0M8 9h.01M16 9h.01',play:'m9 5 11 7-11 7Z'};
const icon=name=>`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name]||paths.more}"/></svg>`;
const status=()=>`<div class="status"><span>09:41</span><div class="status-icons">${icon('signal')}${icon('wifi')}<span class="battery"></span></div></div>`;
const author=(name,letter,time,tone='')=>`<div class="author"><div class="avatar ${tone}">${letter}</div><div><strong>${name}</strong><small>${time}</small></div><span class="more">${icon('more')}</span></div>`;
const actions=(reposts='12',comments='36',likes='128')=>`<div class="actions"><span>${icon('repost')}${reposts}</span><span>${icon('comment')}${comments}</span><span>${icon('heart')}${likes}</span><span>${icon('share')}</span></div>`;
// Original vector scenery, deliberately illustrative rather than simulated photographs.
function landscape(kind=0){
 const palettes=[['#e9eddf','#c9d5b5','#829e79','#4d755f','#f4e5ad'],['#e4ece7','#bed2c6','#839e92','#416e65','#f6f0d3'],['#efe5cd','#d8cbae','#aaa685','#5c7964','#faf2db']];
 const p=palettes[kind%3];
 return `<svg class="landscape" viewBox="0 0 240 240" preserveAspectRatio="xMidYMid slice" role="img" aria-label="山野风景插画"><rect width="240" height="240" fill="${p[0]}"/><circle cx="177" cy="53" r="23" fill="${p[4]}"/><path d="M0 143 65 61 120 127 162 87 240 164v76H0Z" fill="${p[1]}"/><path d="m0 190 57-76 74 53 46-35 63 34v74H0Z" fill="${p[2]}"/><path d="M0 226q74-108 156-51t84 1v64H0Z" fill="${p[3]}"/><path d="M93 240q62-60 62-79" fill="none" stroke="${p[0]}" stroke-width="5" opacity=".55"/></svg>`;
}
const media=()=>`<div class="media-grid">${[0,1,2].map(landscape).join('')}</div>`;
const dock=()=>`<div class="dock-backdrop"></div><div class="dock" aria-label="底部导航示意">${[['home','首页'],['compass','发现'],['comment','消息'],['user','我的']].map(([i,t],n)=>`<span class="dock-item ${n===0?'selected':''}">${icon(i)}${t}</span>`).join('')}</div><div class="home-indicator"></div>`;
document.querySelector('#home-screen').innerHTML=`${status()}<div class="home-title">${icon('user')}<div class="segmented"><span class="selected">关注</span><span>推荐</span></div>${icon('plus')}</div><div class="feed-content"><article class="card">${author('山野来信','山','12 分钟前 · 来自 HarmonyOS')}<p class="body-text">周末去山里走了走。雨停以后，整条小路都是青草的味道。<br><span class="topic">#周末出走计划#</span></p>${media()}<div class="comment-peek"><strong>小禾：</strong>这条路看着就很适合慢慢走。</div>${actions()}</article><article class="card">${author('小禾的日常','禾','28 分钟前','ochre')}<p class="body-text">最近在读一本关于植物的书。原来每天路过的那棵树，已经在这里长了四十年。</p><div class="comment-peek"><strong>山野来信：</strong>下次路过，会忍不住多看两眼。</div>${actions('4','18','67')}</article></div>${dock()}`;
const searchTabs=['综合','实时','用户','视频','图片'];
document.querySelector('#search-screen').innerHTML=`${status()}<div class="search-title">${icon('back')}<div class="search-field">${icon('search')}<span>山野</span><span class="close">×</span></div></div><div class="tabs" aria-label="搜索分类">${searchTabs.map((t,i)=>`<button class="tab" type="button" data-search="${i}" aria-pressed="${i===0}">${t}</button>`).join('')}</div><div class="search-results" id="search-results" aria-live="polite"></div><div class="home-indicator"></div>`;
const userCard=(name='山野来信',letter='山',description='记录山间的路，也记录路上的小事。')=>`<div class="card user-result"><div class="author"><div class="avatar">${letter}</div><div><strong>${name}</strong><small>摄影 · 户外记录</small></div><span class="follow">+ 关注</span></div><p class="user-note">${description}</p></div>`;
function showSearch(index){
 document.querySelectorAll('[data-search]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.search)===index)));
 const post=`<article class="card">${author('山野来信','山',index===1?'刚刚':'今天 08:26')}<p class="body-text">进山不一定要走很远。有时候，一条安静的小路就够了。<br><span class="topic">#山野之间#</span></p><div class="photo-wide">${landscape(1)}</div>${actions('8','24','96')}</article>`;
 let content='';
 if(index===0)content=userCard()+post+`<div class="result-note">找到相关用户、微博与话题</div>`;
 if(index===1)content=`<div class="result-heading">按发布时间倒序排列</div>`+post+`<article class="card">${author('走走停停','走','2 分钟前','lake')}<p class="body-text">今天的山野，是刚下过雨的绿色。</p>${actions('2','7','19')}</article>`;
 if(index===2)content=userCard()+userCard('山野观察笔记','记','观察树木、云和季节的变化。')+userCard('住在山边的人','林','偶尔爬山，经常散步。')+`<div class="result-note">演示用户均为虚构账号</div>`;
 if(index===3)content=`<article class="card">${author('山野来信','山','今天 08:26')}<p class="body-text">留一段山里的声音。</p><div class="video-placeholder" aria-label="视频封面示意，不播放">${icon('play')}</div>${actions('6','12','48')}</article><div class="result-note">视频分类示意 · 本页不包含实际视频</div>`;
 if(index===4)content=`<div class="gallery-results">${[0,1,2,0].map((p,i)=>`<div class="gallery-tile">${landscape(p)}<p>${['雨后的山路','山野之间','出门走走','周末的绿色'][i]}<br><span class="topic">#山野#</span></p></div>`).join('')}</div>`;
 document.querySelector('#search-results').innerHTML=content;
}
document.querySelectorAll('[data-search]').forEach(b=>b.addEventListener('click',()=>showSearch(Number(b.dataset.search))));showSearch(0);
const comment=(name,letter,text,reply='',tone='')=>`<div class="comment"><div class="avatar ${tone}">${letter}</div><div class="comment-body"><div class="comment-name"><span>${name}</span><span>${icon('heart')} 12</span></div><p>${text}</p><div class="comment-time">12 分钟前</div>${reply?`<div class="reply"><strong>山野来信：</strong>${reply}</div>`:''}</div></div>`;
document.querySelector('#detail-screen').innerHTML=`${status()}<div class="detail-title">${icon('back')}<span>微博详情</span>${icon('share')}</div><div class="detail-scroll">${author('山野来信','山','今天 08:26 · 来自 HarmonyOS')}<article class="article"><p>有时候，出门散步并不需要一个目的地。</p><p>沿着河边走了很久，看见有人钓鱼，有人带着狗慢慢走。树影落在水面上，风一吹，就散开了。</p><p>回来的路上买了一束花。今天没做什么特别的事，但觉得这一天过得不错。</p><p class="topic">#生活里的小事#</p></article><hr class="detail-rule"><div class="tabs detail-tabs" aria-label="讨论分类">${['转发 12','评论 36','赞 128'].map((t,i)=>`<button class="tab" type="button" data-detail="${i}" aria-pressed="${i===1}">${t}</button>`).join('')}</div><div id="discussion" aria-live="polite"></div></div><div class="dock-backdrop"></div><div class="dock compose-dock" aria-label="评论入口示意"><span class="placeholder">写评论…</span>${icon('smile')}${icon('heart')}${icon('repost')}</div><div class="home-indicator"></div>`;
function showDetail(index){
 document.querySelectorAll('[data-detail]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.detail)===index)));
 const panel=document.querySelector('#discussion');
 if(index===1)panel.innerHTML=comment('小禾的日常','禾','不赶时间的散步，真的会让人心情好一点。','是的，连路边的树都能看很久。','ochre')+comment('走走停停','走','这样的日子就很好。','','lake');
 if(index===0)panel.innerHTML=comment('走走停停','走','转发微博：今天下班也去河边走走。','','lake')+comment('小禾的日常','禾','把周末留给散步。','','ochre');
 if(index===2)panel.innerHTML=[['小禾的日常','禾','ochre'],['走走停停','走','lake'],['山边的树','树','']].map(([n,l,t])=>`<div class="like-user">${author(n,l,'喜欢这条微博',t)}</div>`).join('');
}
document.querySelectorAll('[data-detail]').forEach(b=>b.addEventListener('click',()=>showDetail(Number(b.dataset.detail))));showDetail(1);
const params=new URLSearchParams(location.search);
function setTheme(theme){
 const dark=theme==='dark';document.documentElement.dataset.theme=dark?'dark':'light';
 const button=document.querySelector('#theme-toggle');button.textContent=dark?'切换浅色':'切换深色';button.setAttribute('aria-pressed',String(dark));
}
setTheme(params.get('theme'));
document.querySelector('#theme-toggle').addEventListener('click',()=>setTheme(document.documentElement.dataset.theme==='dark'?'light':'dark'));
if(params.get('export')==='1'){
 const requested=params.get('scene');
 document.body.classList.add('export');
 if(requested==='overview'){
  document.body.classList.add('overview');
  document.querySelectorAll('.device-caption').forEach((caption,i)=>{caption.textContent=['01 · 首页','02 · 搜索','03 · 正文与讨论'][i];});
 }else{
  const scene=['home','search','detail'].includes(requested)?requested:'home';
  document.getElementById(scene).classList.add('export-selected');
 }
}
window.__showcaseReady=true;
