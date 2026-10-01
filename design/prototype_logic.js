
var R = function (id, name, sub, mins, meals, diet, jain, spice, tags, cuisine, color, ing, steps) {
  return { id: id, name: name, sub: sub, mins: mins, meals: meals, diet: diet, jain: jain, spice: spice, tags: tags, cuisine: cuisine, color: color, ing: ing, steps: steps };
};
var RECIPES = [
  R('poha','Kanda Poha','Halka, 20 minute ka Maharashtrian nashta',20,'b','veg',false,1,['lowOil','kid','light'],'Maharashtrian','#F2C94C',['Mota poha 2 cup','Pyaaz 1','Moongphali','Kadi patta','Hari mirch','Nimbu','Haldi'],['Poha dho ke 5 min chhaan lo.','Rai, kadi patta, moongphali aur pyaaz ka tadka lagao.','Haldi, namak aur poha daal ke 2 min dhak ke pakao.','Nimbu aur dhaniya se finish karo.']),
  R('cheela','Moong Dal Cheela','Protein wala nashta, paneer stuffing ke saath',25,'bd','veg',true,2,['protein','lowOil','lowSugar','kid'],'North Indian','#D9B54A',['Peeli moong dal 1 cup (bhigi)','Adrak','Hari mirch','Hing','Paneer (stuffing)','Dhaniya'],['Dal 3 ghante bhigo ke adrak-mirch ke saath pees lo.','Hing aur namak milao.','Garam tawe pe patla phailao, thoda tel.','Paneer bhar ke fold karo.']),
  R('upma','Vegetable Upma','Sooji aur sabziyon ka garam nashta',20,'b','veg',false,1,['lowOil','light','kid'],'South Indian','#EAD9A0',['Sooji 1 cup','Gajar, matar','Pyaaz','Rai, urad dal','Kadi patta','Ghee 1 tsp'],['Sooji ko sukha bhoon lo.','Rai, urad dal, kadi patta, pyaaz aur sabzi ka tadka.','2.5 cup garam paani daal ke sooji milao.','Dhak ke 3 min, upar se ghee.']),
  R('omelette','Masala Omelette','10 minute, full protein',10,'bd','egg',false,2,['protein','kid'],'North Indian','#F4D03F',['Ande 3','Pyaaz, tamatar','Hari mirch','Dhaniya','Makhan'],['Ande phento, namak-mirch daalo.','Pyaaz, tamatar, dhaniya milao.','Makhan mein dheemi aanch pe pakao, palto.']),
  R('idli','Idli Sambar','Bhaap mein bana, bilkul kam tel',30,'b','veg',false,2,['lowOil','light','kid','lowSugar'],'South Indian','#F3EFE6',['Idli batter','Toor dal','Sambar masala','Drumstick, lauki','Imli','Nariyal chutney'],['Batter ko saanchon mein bhar ke 12 min steam karo.','Toor dal ubaal lo.','Sabzi, imli, sambar masala ke saath dal pakao.','Rai-kadi patta ka tadka.']),
  R('thepla','Methi Thepla','Gujarati tiffin favourite',30,'bl','veg',true,1,['lowSugar','kid','noMaidaOk'],'Gujarati','#B8A15A',['Gehun ka aata 2 cup','Taaza methi','Dahi','Haldi, ajwain','Til'],['Aate mein methi, dahi, masale milao.','Naram aata goondho.','Patle bel ke tawe pe halka tel lagake seko.']),
  R('paratha','Aloo Paratha','Makhan aur dahi ke saath',35,'bl','veg',false,2,['kid','rainy'],'North Indian','#D9A441',['Aata','Aloo 4 (uble)','Hari mirch','Amchur','Makhan','Dahi'],['Aloo mein masale milao.','Aate ki loi mein bhar ke belo.','Tawe pe ghee/makhan se seko.']),
  R('rajma','Rajma Chawal','Sunday wala comfort food',45,'l','veg',false,2,['protein','kid'],'North Indian','#8E3B2E',['Rajma 1 cup (raat bhar bhiga)','Pyaaz-tamatar masala','Adrak-lahsun','Garam masala','Basmati chawal'],['Rajma 5-6 seeti tak pakao.','Pyaaz-tamatar ka gaadha masala bhoono.','Rajma milao, 15 min dheemi aanch.','Jeera rice ke saath serve.']),
  R('daltadka','Dal Tadka & Jeera Rice','Roz ka, sabko pasand',30,'ld','veg',false,2,['protein','lowOil','light','kid'],'North Indian','#E8B73A',['Toor + masoor dal','Tamatar','Jeera','Lahsun','Laal mirch','Chawal'],['Dal haldi-namak ke saath 3 seeti.','Ghee mein jeera, lahsun, mirch ka tadka.','Dal pe tadka daalo, dhaniya.','Jeera rice alag se.']),
  R('lauki','Lauki Chana Dal','Halka, kam tel, sugar-friendly',35,'ld','veg',true,1,['lowOil','lowSugar','light','protein'],'North Indian','#C7B25A',['Chana dal 1/2 cup','Lauki 300g','Tamatar','Hing','Jeera','Adrak'],['Chana dal 30 min bhigo lo.','Hing-jeera-adrak ka tadka.','Lauki, dal, tamatar daal ke 3 seeti.','Dhaniya se garnish.']),
  R('gatte','Gatte ki Sabzi','Rajasthani, bina pyaaz-lahsun',40,'l','veg',true,3,['protein','special'],'Rajasthani','#D98C2B',['Besan 1 cup','Dahi 1 cup','Ajwain','Laal mirch','Hing','Kasuri methi'],['Besan ke gatte bana ke 10 min ubaalo.','Dahi mein masale phento.','Hing-jeera tadka, phir dahi masala dheere pakao.','Gatte daal ke 5 min simmer.']),
  R('bhindi','Bhindi Masala','Sookhi sabzi, roti ke saath',25,'ld','veg',false,2,['lowSugar'],'North Indian','#5E8C3A',['Bhindi 400g','Pyaaz','Amchur','Dhaniya powder','Laal mirch'],['Bhindi sukha ke kaat lo.','Tez aanch pe bhoono jab tak chipchipa na rahe.','Pyaaz aur masale daal ke 5 min.']),
  R('pbm','Paneer Butter Masala','Mehmaan aayein toh yahi',35,'ld','veg',false,2,['protein','kid','special'],'North Indian','#E0662C',['Paneer 250g','Tamatar 4','Kaju','Makhan','Malai','Kasuri methi'],['Tamatar-kaju ubaal ke pees lo.','Makhan mein gravy pakao.','Paneer, malai, kasuri methi daal ke 5 min.']),
  R('palak','Palak Paneer','Hara, protein aur iron',35,'ld','veg',false,2,['protein','lowSugar'],'North Indian','#3F7D3A',['Palak 2 gaddi','Paneer 200g','Pyaaz','Lahsun','Hari mirch','Malai'],['Palak blanch karke pees lo.','Pyaaz-lahsun bhoono, palak daalo.','Paneer daal ke 5 min, upar malai.']),
  R('khichdi','Moong Dal Khichdi','Pet ke liye sabse halka',25,'ld','veg',true,1,['light','lowOil','kid','protein','lowSugar'],'Gujarati','#E9C75A',['Chawal 1/2 cup','Peeli moong dal 1/2 cup','Ghee','Jeera','Hing','Haldi'],['Chawal-dal dho ke 20 min bhigo.','Ghee mein jeera-hing.','Haldi, namak, 4 cup paani, 3 seeti.','Dahi/papad ke saath.']),
  R('curdrice','Curd Rice','Thanda, 15 minute',15,'ld','veg',true,1,['light','kid','lowOil'],'South Indian','#F5F2E8',['Pake chawal 2 cup','Dahi 1 cup','Rai','Kadi patta','Adrak','Anaar'],['Chawal halka mash karo.','Dahi, namak milao.','Rai-kadi patta-adrak ka tadka upar.']),
  R('kadhi','Kadhi Pakora','Baarish ka pakka favourite',40,'l','veg',false,2,['rainy','special'],'North Indian','#F0C23B',['Besan','Khatta dahi','Pyaaz (pakode)','Methi dana','Laal mirch'],['Pyaaz ke pakode tal lo.','Dahi-besan phent ke 20 min pakao.','Pakode daal ke 5 min, upar tadka.']),
  R('pakode','Pyaaz Pakode','Chai ke saath, baarish mein',20,'bd','veg',false,2,['rainy','kid'],'North Indian','#C98A2E',['Besan 1 cup','Pyaaz 3','Hari mirch','Ajwain','Tel (talne ke liye)'],['Pyaaz patla kaat ke namak lagao.','Besan, mirch, ajwain milao, thoda paani.','Garam tel mein kurkure tal lo.']),
  R('eggcurry','Anda Curry','Masaledaar, rice ke saath',30,'d','egg',false,3,['protein'],'North Indian','#C8612C',['Ande 6 (uble)','Pyaaz-tamatar','Adrak-lahsun','Garam masala','Kasuri methi'],['Ande halka tal lo.','Pyaaz-tamatar masala bhoono.','Paani, ande daal ke 10 min.']),
  R('chicken','Chicken Curry','Ghar wali, tez masala',50,'ld','nonveg',false,3,['protein','special'],'North Indian','#9C3B1F',['Chicken 750g','Dahi','Pyaaz 3','Adrak-lahsun','Garam masala'],['Chicken dahi-masale mein 30 min rakho.','Pyaaz gehra bhoono.','Chicken daal ke dhak ke 25 min.']),
  R('macher','Macher Jhol','Bengali, halki fish curry',40,'ld','nonveg',false,2,['protein','lowOil','light'],'Bengali','#D4822E',['Rohu 500g','Aloo','Panch phoron','Haldi','Sarson tel'],['Machli haldi-namak laga ke halka tal lo.','Panch phoron, aloo, masale.','Paani daal ke machli, 10 min simmer.']),
  R('noodles','Veg Hakka Noodles','Bachchon ki farmaish',20,'d','veg',false,2,['kid','maida'],'Indo-Chinese','#D7A65A',['Hakka noodles','Patta gobhi, shimla mirch, gajar','Lahsun','Soya sauce','Sirka'],['Noodles ubaal ke thande paani se dho lo.','Tez aanch pe lahsun aur sabzi.','Noodles, sauce, sirka daal ke toss.'])
];
var IMG = {"bhindi": "/_blob/7e1f7cf529ef7fb700f8ee4a0571881a", "cheela": "/_blob/30e265b55a3049cab666de3257822e59", "chicken": "/_blob/39e057f41741a5ff6637d3e14ff69656", "curdrice": "/_blob/5f6f8910b676dd35caa5d2aece312f93", "daltadka": "/_blob/c8c7d8bc17aee33eac502f4cbe76d4fe", "eggcurry": "/_blob/ca81e0079963bb10020a0547f19c85f0", "gatte": "/_blob/75fd1b70ceb766eeab01c94389e9e47d", "idli": "/_blob/1501d8599bc3687f6ba334d71072c275", "kadhi": "/_blob/238ebebfbec634df32f84e6f5820fbe3", "khichdi": "/_blob/295c7e199dce08840052b46d8202109a", "lauki": "/_blob/6107c79758aa1e7fa6f0036da2c86226", "macher": "/_blob/eaecbe7f8ac70a1522938a16e653f4d1", "noodles": "/_blob/65e7911991a940259b832639453cabbe", "omelette": "/_blob/04f8cdd2f76c190571ec7140482ddac5", "pakode": "/_blob/a3150607fec39b630b69bcac82306d18", "palak": "/_blob/b0d2750c2fde5c7ad7f1d72da7f53ff2", "paratha": "/_blob/d6c414fcf550f0b748cb9b0dffc97f67", "pbm": "/_blob/14964ca0ee1ce9c5b9beddd20907ad62", "poha": "/_blob/f0365243312ff4b10d3020917918c783", "rajma": "/_blob/52a9b1adebb4c52e2092df55134da756", "thepla": "/_blob/49dbedab0f4e7963a0083a40735d041c", "upma": "/_blob/47e03ba1c4991b227d0f0a72f5d3308e"};
var DIETS = [{v:'Veg',hint:'Shakahari',mark:'vm'},{v:'Jain',hint:'Bina pyaaz-lahsun',mark:'vm'},{v:'Egg',hint:'Veg + ande',mark:'vm eg'},{v:'Non-veg',hint:'Sab kuch',mark:'vm nv'}];
var SPICES = ['Kam','Medium','Teekha'];
var NEEDS = ['Low oil','Low sugar','High protein','No maida','Kid-friendly'];
var CUISINES = ['North Indian','South Indian','Gujarati','Rajasthani','Bengali','Maharashtrian','Indo-Chinese'];
var POOL = [{name:'Chachu',color:'#1F6F8B'},{name:'Bua',color:'#9A4A1E'},{name:'Nani',color:'#5B5BD6'},{name:'Ramesh bhaiya',color:'#4A6A1E'}];
var SLOTS = [{k:'b',label:'Nashta',eyebrow:'SUBAH KA NASHTA'},{k:'l',label:'Lunch',eyebrow:'DOPAHAR KA KHAANA'},{k:'d',label:'Dinner',eyebrow:'RAAT KA KHAANA'}];
var DIETLABEL = {veg:'Veg',egg:'Egg',nonveg:'Non-veg'};
var MARK = {veg:'vm',egg:'vm eg',nonveg:'vm nv'};

class Component extends DCLogic {
  constructor(props) {
    super(props);
    var start = props && props.start ? props.start : 'splash';
    this.state = {
      screen: start, editId: 'm1', slot: 'l', plan: [], draft: '', thinking: false, detailId: null, backTo: 'home', toast: '', addIdx: 0,
      members: [
        {id:'m1',name:'Papa',color:'#2F5FC4',diet:'Veg',spice:'Medium',needs:['Low sugar','Low oil'],cuisines:['North Indian','Rajasthani']},
        {id:'m2',name:'Mummy',color:'#B8386A',diet:'Veg',spice:'Medium',needs:['High protein'],cuisines:['Gujarati','North Indian']},
        {id:'m3',name:'Dadi',color:'#7549BF',diet:'Jain',spice:'Kam',needs:['Low oil'],cuisines:['Rajasthani','Gujarati']},
        {id:'m4',name:'Daughter',color:'#B85A0C',diet:'Egg',spice:'Kam',needs:['Kid-friendly'],cuisines:['Indo-Chinese','South Indian']},
        {id:'m5',name:'Wife',color:'#0E7C3A',diet:'Non-veg',spice:'Teekha',needs:['High protein'],cuisines:['Bengali','South Indian']}
      ],
      messages: [{from:'bot',text:'Namaste! Main Maharaj hoon. Ghar ke 5 logon ki pasand mujhe yaad hai.\nBas pucho — aaj kya banaun?',chips:['Aaj lunch mein kya?','Kuch halka dinner','15 min mein nashta','Mehmaan aa rahe hain']}]
    };
    if (start === 'chat') this.state.screen = 'chat';
  }
  componentWillUnmount() { clearTimeout(this.t1); clearTimeout(this.t2); clearTimeout(this.t3); }

  fitFor(m, r) {
    if (m.diet === 'Jain' && !r.jain) return {s:'no', note:'Pyaaz-lahsun hai'};
    if (m.diet === 'Veg' && r.diet !== 'veg') return {s:'no', note: r.diet === 'egg' ? 'Isme anda hai' : 'Non-veg hai'};
    if (m.diet === 'Egg' && r.diet === 'nonveg') return {s:'no', note:'Non-veg hai'};
    if (m.needs.indexOf('No maida') > -1 && r.tags.indexOf('maida') > -1) return {s:'no', note:'Maida hai'};
    var tw = [];
    if (m.spice === 'Kam' && r.spice === 3) tw.push('unki katori mein kam mirch');
    if (m.spice === 'Teekha' && r.spice === 1) tw.push('upar se laal mirch / achaar');
    if (m.needs.indexOf('Low sugar') > -1 && r.tags.indexOf('lowSugar') < 0) tw.push('portion chhota, salad zyada');
    if (m.needs.indexOf('Low oil') > -1 && r.tags.indexOf('lowOil') < 0) tw.push('kam tel mein banao');
    if (m.needs.indexOf('High protein') > -1 && r.tags.indexOf('protein') < 0) tw.push('saath mein dahi/paneer');
    if (m.needs.indexOf('Kid-friendly') > -1 && r.tags.indexOf('kid') < 0 && r.spice > 1) tw.push('bachche ke liye alag, halka');
    if (tw.length) return {s:'tweak', note: tw[0].charAt(0).toUpperCase() + tw[0].slice(1)};
    return {s:'fit', note: m.cuisines.indexOf(r.cuisine) > -1 ? 'Favourite cuisine bhi' : 'Bilkul sahi'};
  }
  summarize(r) {
    if (this._sc && this._sc[r.id]) return this._sc[r.id];
    var out = this._summarize(r);
    if (this._sc) this._sc[r.id] = out;
    return out;
  }
  _summarize(r) {
    var ms = this.state.members, self = this, can = 0, perfect = 0, like = 0, tweaks = [], nos = [];
    ms.forEach(function (m) {
      var f = self.fitFor(m, r);
      if (f.s !== 'no') can++; else nos.push(m.name);
      if (f.s === 'fit') perfect++;
      if (f.s === 'tweak') tweaks.push(m.name + ': ' + f.note.toLowerCase());
      if (m.cuisines.indexOf(r.cuisine) > -1) like++;
    });
    var n = ms.length, label, short, cls;
    if (can === n && perfect === n) { label = 'Sabke liye perfect'; short = 'Sabke liye'; cls = 'badge b-fit'; }
    else if (can === n) { label = 'Sabke liye · ' + tweaks.length + ' tweak'; short = 'Sab · ' + tweaks.length + ' tweak'; cls = 'badge b-tw'; }
    else { label = can + '/' + n + ' ke liye'; short = can + '/' + n + ' ke liye'; cls = 'badge b-no'; }
    var note = nos.length ? (nos.join(', ') + ' ke liye nahi') : (tweaks.length ? tweaks[0] : 'Sab khush, koi badlaav nahi');
    return { can: can, perfect: perfect, label: label, short: short, cls: cls, note: note, score: can * 10 + perfect * 3 + like * 2 - (nos.length ? 15 : 0) };
  }
  ranked(list) {
    var self = this;
    return list.map(function (r) { return { r: r, s: self.summarize(r) }; }).sort(function (a, b) { return b.s.score - a.s.score || a.r.mins - b.r.mins; });
  }
  constraintLine() {
    var ms = this.state.members, bits = [];
    ms.forEach(function (m) {
      if (m.diet === 'Jain') bits.push(m.name + ' (Jain)');
      if (m.needs.indexOf('Low sugar') > -1) bits.push(m.name + ' (low sugar)');
      if (m.spice === 'Kam' && m.needs.indexOf('Kid-friendly') > -1) bits.push(m.name + ' (kam mirch)');
    });
    return bits.length ? 'Dhyaan rakha: ' + bits.slice(0, 3).join(' · ') : 'Sabki pasand dhyaan mein hai';
  }
  showToast(t) { var self = this; clearTimeout(this.t3); this.setState({ toast: t }); this.t3 = setTimeout(function () { self.setState({ toast: '' }); }, 2200); }
  togglePlan(id) {
    var p = this.state.plan.slice(), i = p.indexOf(id);
    if (i > -1) p.splice(i, 1); else p.push(id);
    this.setState({ plan: p });
  }
  open(id) { this.setState({ detailId: id, backTo: this.state.screen === 'detail' ? this.state.backTo : this.state.screen, screen: 'detail' }); }
  reply(q) {
    var s = q.toLowerCase(), slot = this.state.slot, explicitSlot = false, fs = [], why = [], ms = this.state.members;
    if (/nashta|breakfast|subah/.test(s)) { slot = 'b'; explicitSlot = true; }
    else if (/lunch|dopahar/.test(s)) { slot = 'l'; explicitSlot = true; }
    else if (/dinner|raat/.test(s)) { slot = 'd'; explicitSlot = true; }
    var tag = function (t, w) { fs.push(function (r) { return r.tags.indexOf(t) > -1; }); why.push(w); };
    if (/halka|light|bimaar|simple|hal?ka/.test(s)) tag('light', 'halka');
    if (/protein|gym/.test(s)) tag('protein', 'high protein');
    if (/guest|mehmaan|mehman|party|special/.test(s)) tag('special', 'mehmaan-worthy');
    if (/baarish|barish|rain/.test(s)) tag('rainy', 'baarish wala');
    if (/tiffin|bachch|kid|beti|daughter/.test(s)) tag('kid', 'bachchon ko pasand');
    if (/jaldi|quick|fast|15|10 min|20 min/.test(s)) { fs.push(function (r) { return r.mins <= 20; }); why.push('20 min ke andar'); }
    if (/paneer/.test(s)) { fs.push(function (r) { return /Paneer/.test(r.name) || r.id === 'cheela'; }); why.push('paneer wala'); }
    var cmap = {south:'South Indian',gujarat:'Gujarati',punjab:'North Indian',rajasthan:'Rajasthani',bengal:'Bengali',chinese:'Indo-Chinese',maharash:'Maharashtrian'};
    Object.keys(cmap).forEach(function (k) { if (s.indexOf(k) > -1) { fs.push(function (r) { return r.cuisine === cmap[k]; }); why.push(cmap[k]); } });
    var who = null;
    ms.forEach(function (m) { if (s.indexOf(m.name.toLowerCase()) > -1) who = m; });
    var self = this;
    if (who) { fs.push(function (r) { return self.fitFor(who, r).s !== 'no'; }); why.push(who.name + ' ke hisaab se'); }
    var list = RECIPES.filter(function (r) { return fs.every(function (f) { return f(r); }); });
    var inSlot = list.filter(function (r) { return r.meals.indexOf(slot) > -1; });
    if (explicitSlot || inSlot.length >= 2) list = inSlot;
    var slotObj = SLOTS.filter(function (x) { return x.k === slot; })[0];
    var top = this.ranked(list).slice(0, 4);
    var text;
    if (!top.length) {
      top = this.ranked(RECIPES.filter(function (r) { return r.meals.indexOf(slot) > -1; })).slice(0, 4);
      text = 'Is combo mein exact match nahi mila. ' + slotObj.label + ' ke liye ye sabse kareeb hain:';
    } else {
      var allOk = top.filter(function (t) { return t.s.can === ms.length; }).length;
      text = slotObj.label + ' ke liye ' + top.length + ' options' + (why.length ? ' — ' + why.join(', ') : '') + '.\n' + allOk + ' mein poora parivaar kha sakta hai. ' + this.constraintLine() + '.';
    }
    var follow = slot === 'b' ? ['Protein wala nashta', 'Daughter ka tiffin', 'Kuch South Indian'] : ['Kuch halka', 'Baarish special', 'Paneer wala kuch', 'Dadi ke liye kya?'];
    return { from: 'bot', text: text, recipes: top.map(function (t) { return t.r.id; }), chips: follow, slot: slot };
  }
  send(q) {
    var t = (q || '').trim(); if (!t || this.state.thinking) return;
    var self = this;
    var msgs = this.state.messages.concat([{ from: 'me', text: t }]);
    this.setState({ messages: msgs, draft: '', thinking: true, screen: 'chat' });
    clearTimeout(this.t1);
    this.t1 = setTimeout(function () {
      var r = self.reply(t);
      self.setState({ messages: self.state.messages.concat([r]), thinking: false, slot: r.slot });
    }, 1300);
  }

  renderVals() {
    this._sc = {};
    var self = this, st = this.state, ms = st.members;
    var byId = function (id) { return RECIPES.filter(function (r) { return r.id === id; })[0]; };
    var slotObj = SLOTS.filter(function (x) { return x.k === st.slot; })[0];
    var card = function (r, i) {
      var s = self.summarize(r), on = st.plan.indexOf(r.id) > -1;
      return { name: r.name, img: IMG[r.id], mins: r.mins, color: r.color, cuisine: r.cuisine, mark: MARK[r.diet], fitShort: s.short, badgeCls: s.cls, note: s.note,
        delay: (i * 0.07) + 's', addCls: on ? 'add on' : 'add', addLabel: on ? 'ADDED' : 'ADD',
        open: function () { self.open(r.id); }, toggle: function () { self.togglePlan(r.id); } };
    };
    var edit = ms.filter(function (m) { return m.id === st.editId; })[0] || ms[0];
    var updateEdit = function (fn) {
      self.setState({ members: st.members.map(function (m) { if (m.id !== edit.id) return m; var c = JSON.parse(JSON.stringify(m)); fn(c); return c; }) });
    };
    var toggleIn = function (arr, v) { var i = arr.indexOf(v); if (i > -1) arr.splice(i, 1); else arr.push(v); };

    var slotRecipes = this.ranked(RECIPES.filter(function (r) { return r.meals.indexOf(st.slot) > -1; }));
    var heroR = slotRecipes[0].r, heroS = slotRecipes[0].s;

    var d = null;
    if (st.detailId) {
      var r = byId(st.detailId), s = this.summarize(r), on = st.plan.indexOf(r.id) > -1;
      d = { name: r.name, img: IMG[r.id], sub: r.sub, mins: r.mins, cuisine: r.cuisine, color: r.color, mark: MARK[r.diet], dietLabel: r.jain ? 'Jain-friendly' : DIETLABEL[r.diet],
        fitLabel: s.label, badgeCls: s.cls, ing: r.ing,
        steps: r.steps.map(function (t, i) { return { n: i + 1, t: t }; }),
        fits: ms.map(function (m) { var f = self.fitFor(m, r); return { name: m.name, initial: m.name.charAt(0), color: m.color, note: f.note,
          label: f.s === 'fit' ? 'Perfect' : f.s === 'tweak' ? 'Tweak' : 'Nahi', cls: f.s === 'fit' ? 'badge b-fit' : f.s === 'tweak' ? 'badge b-tw' : 'badge b-no' }; }),
        link: 'https://www.youtube.com/results?search_query=' + encodeURIComponent(r.name + ' recipe'),
        addLabel: on ? 'Menu mein hai' : 'Menu mein daalo', toggle: function () { self.togglePlan(r.id); } };
    }

    var planR = st.plan.map(byId);
    var ingSeen = {}, planIng = [];
    planR.forEach(function (r) { r.ing.forEach(function (x) { if (!ingSeen[x]) { ingSeen[x] = 1; planIng.push(x); } }); });
    var planAll = planR.length && ms.every(function (m) { return planR.some(function (r) { return self.fitFor(m, r).s !== 'no'; }); });

    return {
      haldi: this.props.haldi ?? '#FFCC33',
      isSplash: st.screen === 'splash', isFamily: st.screen === 'family', isPrefs: st.screen === 'prefs', isLoading: st.screen === 'loading',
      isHome: st.screen === 'home', isChat: st.screen === 'chat', isDetail: st.screen === 'detail' && !!d, isPlan: st.screen === 'plan',
      goFamily: function () { self.setState({ screen: 'family' }); },
      goHome: function () { self.setState({ screen: 'home' }); },
      goPlan: function () { self.setState({ screen: 'plan' }); },
      goBack: function () { self.setState({ screen: st.backTo || 'home' }); },
      skipToHome: function () { self.setState({ screen: 'home' }); },
      finishOnboarding: function () { self.setState({ screen: 'loading' }); clearTimeout(self.t2); self.t2 = setTimeout(function () { self.setState({ screen: 'home' }); }, 1900); },
      addMember: function () {
        var p = POOL[st.addIdx % POOL.length], id = 'x' + Date.now();
        self.setState({ addIdx: st.addIdx + 1, editId: id, screen: 'prefs', members: st.members.concat([{ id: id, name: p.name, color: p.color, diet: 'Veg', spice: 'Medium', needs: [], cuisines: [] }]) });
      },
      memberCount: ms.length,
      memberCards: ms.map(function (m, i) {
        return { name: m.name, initial: m.name.charAt(0), color: m.color, diet: m.diet, delay: (i * 0.06) + 's',
          summary: m.spice + ' mirch' + (m.needs.length ? ' · ' + m.needs.join(', ') : '') + (m.cuisines.length ? ' · ' + m.cuisines.join(', ') : ''),
          edit: function () { self.setState({ editId: m.id, screen: 'prefs' }); } };
      }),
      memberTabs: ms.map(function (m) { return { name: m.name, initial: m.name.charAt(0), color: m.color, cls: m.id === edit.id ? 'chip on' : 'chip', pick: function () { self.setState({ editId: m.id }); } }; }),
      edit: { name: edit.name, initial: edit.name.charAt(0), color: edit.color },
      dietOpts: DIETS.map(function (o) { return { label: o.v, hint: o.hint, mark: o.mark, cls: edit.diet === o.v ? 'chip on' : 'chip', pick: function () { updateEdit(function (c) { c.diet = o.v; }); } }; }),
      spiceOpts: SPICES.map(function (v, i) { return { label: v, dots: new Array(i + 1).fill(0), cls: edit.spice === v ? 'seg on' : 'seg', pick: function () { updateEdit(function (c) { c.spice = v; }); } }; }),
      needOpts: NEEDS.map(function (v) { return { label: v, cls: edit.needs.indexOf(v) > -1 ? 'chip on' : 'chip', pick: function () { updateEdit(function (c) { toggleIn(c.needs, v); }); } }; }),
      cuisineOpts: CUISINES.map(function (v) { return { label: v, cls: edit.cuisines.indexOf(v) > -1 ? 'chip on' : 'chip', pick: function () { updateEdit(function (c) { toggleIn(c.cuisines, v); }); } }; }),
      constraintLine: this.constraintLine(),
      slotEyebrow: slotObj.eyebrow, slotName: slotObj.label,
      familyLine: ms.length + ' log · ' + this.constraintLine().replace('Dhyaan rakha: ', ''),
      avStack: ms.slice(0, 4).map(function (m) { return { initial: m.name.charAt(0), color: m.color }; }),
      slotTabs: SLOTS.map(function (x) { return { label: x.label, cls: x.k === st.slot ? 'seg on' : 'seg', pick: function () { self.setState({ slot: x.k }); } }; }),
      hero: { name: heroR.name, mins: heroR.mins, fitLabel: heroS.label, open: function () { self.open(heroR.id); } },
      quickAsks: ['15 min mein kuch', 'Kuch halka', 'Baarish special', 'Daughter ka tiffin', 'Mehmaan aa rahe hain', 'High protein'].map(function (q) { return { label: q, ask: function () { self.send(q); } }; }),
      tiles: slotRecipes.slice(0, 8).map(function (x, i) { return card(x.r, i); }),
      openChatEmpty: function () { self.setState({ screen: 'chat' }); },
      messages: st.messages.map(function (m) {
        var cards = (m.recipes || []).map(function (id, i) { return card(byId(id), i); });
        return { isMe: m.from === 'me', isBot: m.from === 'bot', text: m.text, hasCards: cards.length > 0, cards: cards,
          hasChips: !!(m.chips && m.chips.length), chips: (m.chips || []).map(function (q) { return { label: q, ask: function () { self.send(q); } }; }) };
      }),
      thinking: st.thinking,
      draft: st.draft,
      onDraft: function (e) { self.setState({ draft: e.target.value }); },
      onKey: function (e) { if (e.key === 'Enter') self.send(st.draft); },
      sendDraft: function () { self.send(st.draft); },
      voice: function () { self.showToast('Voice input — real app mein Hinglish mein bol sakte ho'); },
      d: d || { fits: [], ing: [], steps: [] },
      hasPlan: st.plan.length > 0, noPlan: st.plan.length === 0, planCount: st.plan.length,
      planNames: planR.map(function (r) { return r.name; }).join(', '),
      planCoverage: planAll ? 'har member ke liye kuch na kuch hai' : 'kuch members ke liye aur dish chahiye',
      planItems: planR.map(function (r, i) { var c = card(r, i); return c; }),
      planIng: planIng,
      sendCook: function () { self.showToast('Menu + saaman list cook ko WhatsApp par bhej di'); },
      orderMissing: function () { self.showToast('Missing saaman cart mein daal diya'); },
      hasToast: !!st.toast, toast: st.toast
    };
  }
}
