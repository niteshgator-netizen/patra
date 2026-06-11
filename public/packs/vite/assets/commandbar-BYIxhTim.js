import{c as O,r as Ce,a4 as _n,H as An,o as On,e as gn}from"./_plugin-vue_export-helper-D5v2PVWY.js";import{P as mn,u as se,e as P,b as Z,c as Zt}from"./useBranding-DpwJ9cBs.js";import{a as ft}from"./index-D2kJ1YPz.js";import{I as Nn,J as Vt,K as Ut,L as Cn,F as x,M as Sn,N as Mn,O as En,P as wn,Q as Tn,R as zt,S as Gt,T as yn,U as In,V as bn,W as Rn,X as $n,Y as xn,Z as _t,$ as Ln,a0 as jn}from"./dashboard-BJwGAB8K.js";import{L as kn,u as Kt,w as U,a as Dn}from"./Validators-fiweTme6.js";import{L as Bn,m as Hn,x as Pn,bp as Zn,bq as Vn}from"./DashboardIcon-Ieu1yjiE.js";import"./utils.esm-BLlFaPuM.js";import"./_commonjsHelpers-BosuxZz1.js";import"./index-CPXUNC6Q.js";import"./index-DN3rM4CW.js";import"./index-DXm6zKby.js";import"./IntegrationHelper-CnIdd4wO.js";import"./vue-dompurify-html-D_Dpv_Ot.js";import"./useKeyboardNavigableList-BUhPsGQp.js";import"./helper-BVTgYTlr.js";import"./Icon-3zV6666-.js";import"./module-DVy-r8Kw.js";import"./BarChart-C91FJdLg.js";import"./constants-lVAyZKq6.js";import"./IframeLoader-B6KNEcU_.js";import"./js.cookie-DhuBleE4.js";/**
 * @license
 * Copyright 2019 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const Me=window,ct=Me.ShadowRoot&&(Me.ShadyCSS===void 0||Me.ShadyCSS.nativeShadow)&&"adoptedStyleSheets"in Document.prototype&&"replace"in CSSStyleSheet.prototype,ht=Symbol(),At=new WeakMap;let Ft=class{constructor(e,n,i){if(this._$cssResult$=!0,i!==ht)throw Error("CSSResult is not constructable. Use `unsafeCSS` or `css` instead.");this.cssText=e,this.t=n}get styleSheet(){let e=this.o;const n=this.t;if(ct&&e===void 0){const i=n!==void 0&&n.length===1;i&&(e=At.get(n)),e===void 0&&((this.o=e=new CSSStyleSheet).replaceSync(this.cssText),i&&At.set(n,e))}return e}toString(){return this.cssText}};const Un=t=>new Ft(typeof t=="string"?t:t+"",void 0,ht),ye=(t,...e)=>{const n=t.length===1?t[0]:e.reduce((i,o,s)=>i+(a=>{if(a._$cssResult$===!0)return a.cssText;if(typeof a=="number")return a;throw Error("Value passed to 'css' function must be a 'css' function result: "+a+". Use 'unsafeCSS' to pass non-literal values, but take care to ensure page security.")})(o)+t[s+1],t[0]);return new Ft(n,t,ht)},zn=(t,e)=>{ct?t.adoptedStyleSheets=e.map(n=>n instanceof CSSStyleSheet?n:n.styleSheet):e.forEach(n=>{const i=document.createElement("style"),o=Me.litNonce;o!==void 0&&i.setAttribute("nonce",o),i.textContent=n.cssText,t.appendChild(i)})},Ot=ct?t=>t:t=>t instanceof CSSStyleSheet?(e=>{let n="";for(const i of e.cssRules)n+=i.cssText;return Un(n)})(t):t;/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */var Ve;const Ee=window,gt=Ee.trustedTypes,Gn=gt?gt.emptyScript:"",mt=Ee.reactiveElementPolyfillSupport,it={toAttribute(t,e){switch(e){case Boolean:t=t?Gn:null;break;case Object:case Array:t=t==null?t:JSON.stringify(t)}return t},fromAttribute(t,e){let n=t;switch(e){case Boolean:n=t!==null;break;case Number:n=t===null?null:Number(t);break;case Object:case Array:try{n=JSON.parse(t)}catch{n=null}}return n}},Yt=(t,e)=>e!==t&&(e==e||t==t),Ue={attribute:!0,type:String,converter:it,reflect:!1,hasChanged:Yt},ot="finalized";let te=class extends HTMLElement{constructor(){super(),this._$Ei=new Map,this.isUpdatePending=!1,this.hasUpdated=!1,this._$El=null,this._$Eu()}static addInitializer(e){var n;this.finalize(),((n=this.h)!==null&&n!==void 0?n:this.h=[]).push(e)}static get observedAttributes(){this.finalize();const e=[];return this.elementProperties.forEach((n,i)=>{const o=this._$Ep(i,n);o!==void 0&&(this._$Ev.set(o,i),e.push(o))}),e}static createProperty(e,n=Ue){if(n.state&&(n.attribute=!1),this.finalize(),this.elementProperties.set(e,n),!n.noAccessor&&!this.prototype.hasOwnProperty(e)){const i=typeof e=="symbol"?Symbol():"__"+e,o=this.getPropertyDescriptor(e,i,n);o!==void 0&&Object.defineProperty(this.prototype,e,o)}}static getPropertyDescriptor(e,n,i){return{get(){return this[n]},set(o){const s=this[e];this[n]=o,this.requestUpdate(e,s,i)},configurable:!0,enumerable:!0}}static getPropertyOptions(e){return this.elementProperties.get(e)||Ue}static finalize(){if(this.hasOwnProperty(ot))return!1;this[ot]=!0;const e=Object.getPrototypeOf(this);if(e.finalize(),e.h!==void 0&&(this.h=[...e.h]),this.elementProperties=new Map(e.elementProperties),this._$Ev=new Map,this.hasOwnProperty("properties")){const n=this.properties,i=[...Object.getOwnPropertyNames(n),...Object.getOwnPropertySymbols(n)];for(const o of i)this.createProperty(o,n[o])}return this.elementStyles=this.finalizeStyles(this.styles),!0}static finalizeStyles(e){const n=[];if(Array.isArray(e)){const i=new Set(e.flat(1/0).reverse());for(const o of i)n.unshift(Ot(o))}else e!==void 0&&n.push(Ot(e));return n}static _$Ep(e,n){const i=n.attribute;return i===!1?void 0:typeof i=="string"?i:typeof e=="string"?e.toLowerCase():void 0}_$Eu(){var e;this._$E_=new Promise(n=>this.enableUpdating=n),this._$AL=new Map,this._$Eg(),this.requestUpdate(),(e=this.constructor.h)===null||e===void 0||e.forEach(n=>n(this))}addController(e){var n,i;((n=this._$ES)!==null&&n!==void 0?n:this._$ES=[]).push(e),this.renderRoot!==void 0&&this.isConnected&&((i=e.hostConnected)===null||i===void 0||i.call(e))}removeController(e){var n;(n=this._$ES)===null||n===void 0||n.splice(this._$ES.indexOf(e)>>>0,1)}_$Eg(){this.constructor.elementProperties.forEach((e,n)=>{this.hasOwnProperty(n)&&(this._$Ei.set(n,this[n]),delete this[n])})}createRenderRoot(){var e;const n=(e=this.shadowRoot)!==null&&e!==void 0?e:this.attachShadow(this.constructor.shadowRootOptions);return zn(n,this.constructor.elementStyles),n}connectedCallback(){var e;this.renderRoot===void 0&&(this.renderRoot=this.createRenderRoot()),this.enableUpdating(!0),(e=this._$ES)===null||e===void 0||e.forEach(n=>{var i;return(i=n.hostConnected)===null||i===void 0?void 0:i.call(n)})}enableUpdating(e){}disconnectedCallback(){var e;(e=this._$ES)===null||e===void 0||e.forEach(n=>{var i;return(i=n.hostDisconnected)===null||i===void 0?void 0:i.call(n)})}attributeChangedCallback(e,n,i){this._$AK(e,i)}_$EO(e,n,i=Ue){var o;const s=this.constructor._$Ep(e,i);if(s!==void 0&&i.reflect===!0){const a=(((o=i.converter)===null||o===void 0?void 0:o.toAttribute)!==void 0?i.converter:it).toAttribute(n,i.type);this._$El=e,a==null?this.removeAttribute(s):this.setAttribute(s,a),this._$El=null}}_$AK(e,n){var i;const o=this.constructor,s=o._$Ev.get(e);if(s!==void 0&&this._$El!==s){const a=o.getPropertyOptions(s),l=typeof a.converter=="function"?{fromAttribute:a.converter}:((i=a.converter)===null||i===void 0?void 0:i.fromAttribute)!==void 0?a.converter:it;this._$El=s,this[s]=l.fromAttribute(n,a.type),this._$El=null}}requestUpdate(e,n,i){let o=!0;e!==void 0&&(((i=i||this.constructor.getPropertyOptions(e)).hasChanged||Yt)(this[e],n)?(this._$AL.has(e)||this._$AL.set(e,n),i.reflect===!0&&this._$El!==e&&(this._$EC===void 0&&(this._$EC=new Map),this._$EC.set(e,i))):o=!1),!this.isUpdatePending&&o&&(this._$E_=this._$Ej())}async _$Ej(){this.isUpdatePending=!0;try{await this._$E_}catch(n){Promise.reject(n)}const e=this.scheduleUpdate();return e!=null&&await e,!this.isUpdatePending}scheduleUpdate(){return this.performUpdate()}performUpdate(){var e;if(!this.isUpdatePending)return;this.hasUpdated,this._$Ei&&(this._$Ei.forEach((o,s)=>this[s]=o),this._$Ei=void 0);let n=!1;const i=this._$AL;try{n=this.shouldUpdate(i),n?(this.willUpdate(i),(e=this._$ES)===null||e===void 0||e.forEach(o=>{var s;return(s=o.hostUpdate)===null||s===void 0?void 0:s.call(o)}),this.update(i)):this._$Ek()}catch(o){throw n=!1,this._$Ek(),o}n&&this._$AE(i)}willUpdate(e){}_$AE(e){var n;(n=this._$ES)===null||n===void 0||n.forEach(i=>{var o;return(o=i.hostUpdated)===null||o===void 0?void 0:o.call(i)}),this.hasUpdated||(this.hasUpdated=!0,this.firstUpdated(e)),this.updated(e)}_$Ek(){this._$AL=new Map,this.isUpdatePending=!1}get updateComplete(){return this.getUpdateComplete()}getUpdateComplete(){return this._$E_}shouldUpdate(e){return!0}update(e){this._$EC!==void 0&&(this._$EC.forEach((n,i)=>this._$EO(i,this[i],n)),this._$EC=void 0),this._$Ek()}updated(e){}firstUpdated(e){}};te[ot]=!0,te.elementProperties=new Map,te.elementStyles=[],te.shadowRootOptions={mode:"open"},mt==null||mt({ReactiveElement:te}),((Ve=Ee.reactiveElementVersions)!==null&&Ve!==void 0?Ve:Ee.reactiveElementVersions=[]).push("1.6.3");/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */var ze;const we=window,ne=we.trustedTypes,Nt=ne?ne.createPolicy("lit-html",{createHTML:t=>t}):void 0,st="$lit$",V=`lit$${(Math.random()+"").slice(9)}$`,Wt="?"+V,Kn=`<${Wt}>`,J=document,ue=()=>J.createComment(""),pe=t=>t===null||typeof t!="object"&&typeof t!="function",Xt=Array.isArray,Fn=t=>Xt(t)||typeof(t==null?void 0:t[Symbol.iterator])=="function",Ge=`[ 	
\f\r]`,le=/<(?:(!--|\/[^a-zA-Z])|(\/?[a-zA-Z][^>\s]*)|(\/?$))/g,Ct=/-->/g,St=/>/g,Y=RegExp(`>|${Ge}(?:([^\\s"'>=/]+)(${Ge}*=${Ge}*(?:[^ 	
\f\r"'\`<>=]|("|')|))|$)`,"g"),Mt=/'/g,Et=/"/g,Jt=/^(?:script|style|textarea|title)$/i,Yn=t=>(e,...n)=>({_$litType$:t,strings:e,values:n}),y=Yn(1),L=Symbol.for("lit-noChange"),N=Symbol.for("lit-nothing"),wt=new WeakMap,X=J.createTreeWalker(J,129,null,!1);function qt(t,e){if(!Array.isArray(t)||!t.hasOwnProperty("raw"))throw Error("invalid template strings array");return Nt!==void 0?Nt.createHTML(e):e}const Wn=(t,e)=>{const n=t.length-1,i=[];let o,s=e===2?"<svg>":"",a=le;for(let l=0;l<n;l++){const r=t[l];let c,d,p=-1,h=0;for(;h<r.length&&(a.lastIndex=h,d=a.exec(r),d!==null);)h=a.lastIndex,a===le?d[1]==="!--"?a=Ct:d[1]!==void 0?a=St:d[2]!==void 0?(Jt.test(d[2])&&(o=RegExp("</"+d[2],"g")),a=Y):d[3]!==void 0&&(a=Y):a===Y?d[0]===">"?(a=o??le,p=-1):d[1]===void 0?p=-2:(p=a.lastIndex-d[2].length,c=d[1],a=d[3]===void 0?Y:d[3]==='"'?Et:Mt):a===Et||a===Mt?a=Y:a===Ct||a===St?a=le:(a=Y,o=void 0);const v=a===Y&&t[l+1].startsWith("/>")?" ":"";s+=a===le?r+Kn:p>=0?(i.push(c),r.slice(0,p)+st+r.slice(p)+V+v):r+V+(p===-2?(i.push(void 0),l):v)}return[qt(t,s+(t[n]||"<?>")+(e===2?"</svg>":"")),i]};class ve{constructor({strings:e,_$litType$:n},i){let o;this.parts=[];let s=0,a=0;const l=e.length-1,r=this.parts,[c,d]=Wn(e,n);if(this.el=ve.createElement(c,i),X.currentNode=this.el.content,n===2){const p=this.el.content,h=p.firstChild;h.remove(),p.append(...h.childNodes)}for(;(o=X.nextNode())!==null&&r.length<l;){if(o.nodeType===1){if(o.hasAttributes()){const p=[];for(const h of o.getAttributeNames())if(h.endsWith(st)||h.startsWith(V)){const v=d[a++];if(p.push(h),v!==void 0){const u=o.getAttribute(v.toLowerCase()+st).split(V),_=/([.?@])?(.*)/.exec(v);r.push({type:1,index:s,name:_[2],strings:u,ctor:_[1]==="."?Jn:_[1]==="?"?Qn:_[1]==="@"?ei:Ie})}else r.push({type:6,index:s})}for(const h of p)o.removeAttribute(h)}if(Jt.test(o.tagName)){const p=o.textContent.split(V),h=p.length-1;if(h>0){o.textContent=ne?ne.emptyScript:"";for(let v=0;v<h;v++)o.append(p[v],ue()),X.nextNode(),r.push({type:2,index:++s});o.append(p[h],ue())}}}else if(o.nodeType===8)if(o.data===Wt)r.push({type:2,index:s});else{let p=-1;for(;(p=o.data.indexOf(V,p+1))!==-1;)r.push({type:7,index:s}),p+=V.length-1}s++}}static createElement(e,n){const i=J.createElement("template");return i.innerHTML=e,i}}function ie(t,e,n=t,i){var o,s,a,l;if(e===L)return e;let r=i!==void 0?(o=n._$Co)===null||o===void 0?void 0:o[i]:n._$Cl;const c=pe(e)?void 0:e._$litDirective$;return(r==null?void 0:r.constructor)!==c&&((s=r==null?void 0:r._$AO)===null||s===void 0||s.call(r,!1),c===void 0?r=void 0:(r=new c(t),r._$AT(t,n,i)),i!==void 0?((a=(l=n)._$Co)!==null&&a!==void 0?a:l._$Co=[])[i]=r:n._$Cl=r),r!==void 0&&(e=ie(t,r._$AS(t,e.values),r,i)),e}class Xn{constructor(e,n){this._$AV=[],this._$AN=void 0,this._$AD=e,this._$AM=n}get parentNode(){return this._$AM.parentNode}get _$AU(){return this._$AM._$AU}u(e){var n;const{el:{content:i},parts:o}=this._$AD,s=((n=e==null?void 0:e.creationScope)!==null&&n!==void 0?n:J).importNode(i,!0);X.currentNode=s;let a=X.nextNode(),l=0,r=0,c=o[0];for(;c!==void 0;){if(l===c.index){let d;c.type===2?d=new ae(a,a.nextSibling,this,e):c.type===1?d=new c.ctor(a,c.name,c.strings,this,e):c.type===6&&(d=new ti(a,this,e)),this._$AV.push(d),c=o[++r]}l!==(c==null?void 0:c.index)&&(a=X.nextNode(),l++)}return X.currentNode=J,s}v(e){let n=0;for(const i of this._$AV)i!==void 0&&(i.strings!==void 0?(i._$AI(e,i,n),n+=i.strings.length-2):i._$AI(e[n])),n++}}class ae{constructor(e,n,i,o){var s;this.type=2,this._$AH=N,this._$AN=void 0,this._$AA=e,this._$AB=n,this._$AM=i,this.options=o,this._$Cp=(s=o==null?void 0:o.isConnected)===null||s===void 0||s}get _$AU(){var e,n;return(n=(e=this._$AM)===null||e===void 0?void 0:e._$AU)!==null&&n!==void 0?n:this._$Cp}get parentNode(){let e=this._$AA.parentNode;const n=this._$AM;return n!==void 0&&(e==null?void 0:e.nodeType)===11&&(e=n.parentNode),e}get startNode(){return this._$AA}get endNode(){return this._$AB}_$AI(e,n=this){e=ie(this,e,n),pe(e)?e===N||e==null||e===""?(this._$AH!==N&&this._$AR(),this._$AH=N):e!==this._$AH&&e!==L&&this._(e):e._$litType$!==void 0?this.g(e):e.nodeType!==void 0?this.$(e):Fn(e)?this.T(e):this._(e)}k(e){return this._$AA.parentNode.insertBefore(e,this._$AB)}$(e){this._$AH!==e&&(this._$AR(),this._$AH=this.k(e))}_(e){this._$AH!==N&&pe(this._$AH)?this._$AA.nextSibling.data=e:this.$(J.createTextNode(e)),this._$AH=e}g(e){var n;const{values:i,_$litType$:o}=e,s=typeof o=="number"?this._$AC(e):(o.el===void 0&&(o.el=ve.createElement(qt(o.h,o.h[0]),this.options)),o);if(((n=this._$AH)===null||n===void 0?void 0:n._$AD)===s)this._$AH.v(i);else{const a=new Xn(s,this),l=a.u(this.options);a.v(i),this.$(l),this._$AH=a}}_$AC(e){let n=wt.get(e.strings);return n===void 0&&wt.set(e.strings,n=new ve(e)),n}T(e){Xt(this._$AH)||(this._$AH=[],this._$AR());const n=this._$AH;let i,o=0;for(const s of e)o===n.length?n.push(i=new ae(this.k(ue()),this.k(ue()),this,this.options)):i=n[o],i._$AI(s),o++;o<n.length&&(this._$AR(i&&i._$AB.nextSibling,o),n.length=o)}_$AR(e=this._$AA.nextSibling,n){var i;for((i=this._$AP)===null||i===void 0||i.call(this,!1,!0,n);e&&e!==this._$AB;){const o=e.nextSibling;e.remove(),e=o}}setConnected(e){var n;this._$AM===void 0&&(this._$Cp=e,(n=this._$AP)===null||n===void 0||n.call(this,e))}}let Ie=class{constructor(e,n,i,o,s){this.type=1,this._$AH=N,this._$AN=void 0,this.element=e,this.name=n,this._$AM=o,this.options=s,i.length>2||i[0]!==""||i[1]!==""?(this._$AH=Array(i.length-1).fill(new String),this.strings=i):this._$AH=N}get tagName(){return this.element.tagName}get _$AU(){return this._$AM._$AU}_$AI(e,n=this,i,o){const s=this.strings;let a=!1;if(s===void 0)e=ie(this,e,n,0),a=!pe(e)||e!==this._$AH&&e!==L,a&&(this._$AH=e);else{const l=e;let r,c;for(e=s[0],r=0;r<s.length-1;r++)c=ie(this,l[i+r],n,r),c===L&&(c=this._$AH[r]),a||(a=!pe(c)||c!==this._$AH[r]),c===N?e=N:e!==N&&(e+=(c??"")+s[r+1]),this._$AH[r]=c}a&&!o&&this.j(e)}j(e){e===N?this.element.removeAttribute(this.name):this.element.setAttribute(this.name,e??"")}};class Jn extends Ie{constructor(){super(...arguments),this.type=3}j(e){this.element[this.name]=e===N?void 0:e}}const qn=ne?ne.emptyScript:"";class Qn extends Ie{constructor(){super(...arguments),this.type=4}j(e){e&&e!==N?this.element.setAttribute(this.name,qn):this.element.removeAttribute(this.name)}}class ei extends Ie{constructor(e,n,i,o,s){super(e,n,i,o,s),this.type=5}_$AI(e,n=this){var i;if((e=(i=ie(this,e,n,0))!==null&&i!==void 0?i:N)===L)return;const o=this._$AH,s=e===N&&o!==N||e.capture!==o.capture||e.once!==o.once||e.passive!==o.passive,a=e!==N&&(o===N||s);s&&this.element.removeEventListener(this.name,this,o),a&&this.element.addEventListener(this.name,this,e),this._$AH=e}handleEvent(e){var n,i;typeof this._$AH=="function"?this._$AH.call((i=(n=this.options)===null||n===void 0?void 0:n.host)!==null&&i!==void 0?i:this.element,e):this._$AH.handleEvent(e)}}class ti{constructor(e,n,i){this.element=e,this.type=6,this._$AN=void 0,this._$AM=n,this.options=i}get _$AU(){return this._$AM._$AU}_$AI(e){ie(this,e)}}const ni={I:ae},Tt=we.litHtmlPolyfillSupport;Tt==null||Tt(ve,ae),((ze=we.litHtmlVersions)!==null&&ze!==void 0?ze:we.litHtmlVersions=[]).push("2.8.0");const ii=(t,e,n)=>{var i,o;const s=(i=n==null?void 0:n.renderBefore)!==null&&i!==void 0?i:e;let a=s._$litPart$;if(a===void 0){const l=(o=n==null?void 0:n.renderBefore)!==null&&o!==void 0?o:null;s._$litPart$=a=new ae(e.insertBefore(ue(),l),l,void 0,n??{})}return a._$AI(t),a};/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */var Ke,Fe;let z=class extends te{constructor(){super(...arguments),this.renderOptions={host:this},this._$Do=void 0}createRenderRoot(){var e,n;const i=super.createRenderRoot();return(e=(n=this.renderOptions).renderBefore)!==null&&e!==void 0||(n.renderBefore=i.firstChild),i}update(e){const n=this.render();this.hasUpdated||(this.renderOptions.isConnected=this.isConnected),super.update(e),this._$Do=ii(n,this.renderRoot,this.renderOptions)}connectedCallback(){var e;super.connectedCallback(),(e=this._$Do)===null||e===void 0||e.setConnected(!0)}disconnectedCallback(){var e;super.disconnectedCallback(),(e=this._$Do)===null||e===void 0||e.setConnected(!1)}render(){return L}};z.finalized=!0,z._$litElement$=!0,(Ke=globalThis.litElementHydrateSupport)===null||Ke===void 0||Ke.call(globalThis,{LitElement:z});const yt=globalThis.litElementPolyfillSupport;yt==null||yt({LitElement:z});((Fe=globalThis.litElementVersions)!==null&&Fe!==void 0?Fe:globalThis.litElementVersions=[]).push("3.3.3");/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const be=t=>e=>typeof e=="function"?((n,i)=>(customElements.define(n,i),i))(t,e):((n,i)=>{const{kind:o,elements:s}=i;return{kind:o,elements:s,finisher(a){customElements.define(n,a)}}})(t,e);/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const oi=(t,e)=>e.kind==="method"&&e.descriptor&&!("value"in e.descriptor)?{...e,finisher(n){n.createProperty(e.key,t)}}:{kind:"field",key:Symbol(),placement:"own",descriptor:{},originalKey:e.key,initializer(){typeof e.initializer=="function"&&(this[e.key]=e.initializer.call(this))},finisher(n){n.createProperty(e.key,t)}},si=(t,e,n)=>{e.constructor.createProperty(n,t)};function E(t){return(e,n)=>n!==void 0?si(t,e,n):oi(t,e)}/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */function G(t){return E({...t,state:!0})}/**
 * @license
 * Copyright 2021 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */var Ye;((Ye=window.HTMLSlotElement)===null||Ye===void 0?void 0:Ye.prototype.assignedElements)!=null;/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const H={ATTRIBUTE:1,CHILD:2,PROPERTY:3,BOOLEAN_ATTRIBUTE:4},_e=t=>(...e)=>({_$litDirective$:t,values:e});class Ae{constructor(e){}get _$AU(){return this._$AM._$AU}_$AT(e,n,i){this._$Ct=e,this._$AM=n,this._$Ci=i}_$AS(e,n){return this.update(e,n)}update(e,n){return this.render(...n)}}/**
 * @license
 * Copyright 2020 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const{I:ai}=ni,Qt=t=>t.strings===void 0,It=()=>document.createComment(""),re=(t,e,n)=>{var i;const o=t._$AA.parentNode,s=e===void 0?t._$AB:e._$AA;if(n===void 0){const a=o.insertBefore(It(),s),l=o.insertBefore(It(),s);n=new ai(a,l,t,t.options)}else{const a=n._$AB.nextSibling,l=n._$AM,r=l!==t;if(r){let c;(i=n._$AQ)===null||i===void 0||i.call(n,t),n._$AM=t,n._$AP!==void 0&&(c=t._$AU)!==l._$AU&&n._$AP(c)}if(a!==s||r){let c=n._$AA;for(;c!==a;){const d=c.nextSibling;o.insertBefore(c,s),c=d}}}return n},W=(t,e,n=t)=>(t._$AI(e,n),t),li={},en=(t,e=li)=>t._$AH=e,ri=t=>t._$AH,We=t=>{var e;(e=t._$AP)===null||e===void 0||e.call(t,!1,!0);let n=t._$AA;const i=t._$AB.nextSibling;for(;n!==i;){const o=n.nextSibling;n.remove(),n=o}};/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const bt=(t,e,n)=>{const i=new Map;for(let o=e;o<=n;o++)i.set(t[o],o);return i},ci=_e(class extends Ae{constructor(t){if(super(t),t.type!==H.CHILD)throw Error("repeat() can only be used in text expressions")}ct(t,e,n){let i;n===void 0?n=e:e!==void 0&&(i=e);const o=[],s=[];let a=0;for(const l of t)o[a]=i?i(l,a):a,s[a]=n(l,a),a++;return{values:s,keys:o}}render(t,e,n){return this.ct(t,e,n).values}update(t,[e,n,i]){var o;const s=ri(t),{values:a,keys:l}=this.ct(e,n,i);if(!Array.isArray(s))return this.ut=l,a;const r=(o=this.ut)!==null&&o!==void 0?o:this.ut=[],c=[];let d,p,h=0,v=s.length-1,u=0,_=a.length-1;for(;h<=v&&u<=_;)if(s[h]===null)h++;else if(s[v]===null)v--;else if(r[h]===l[u])c[u]=W(s[h],a[u]),h++,u++;else if(r[v]===l[_])c[_]=W(s[v],a[_]),v--,_--;else if(r[h]===l[_])c[_]=W(s[h],a[_]),re(t,c[_+1],s[h]),h++,_--;else if(r[v]===l[u])c[u]=W(s[v],a[u]),re(t,s[h],s[v]),v--,u++;else if(d===void 0&&(d=bt(l,u,_),p=bt(r,h,v)),d.has(r[h]))if(d.has(r[v])){const R=p.get(l[u]),K=R!==void 0?s[R]:null;if(K===null){const F=re(t,s[h]);W(F,a[u]),c[u]=F}else c[u]=W(K,a[u]),re(t,s[h],K),s[R]=null;u++}else We(s[v]),v--;else We(s[h]),h++;for(;u<=_;){const R=re(t,c[_+1]);W(R,a[u]),c[u++]=R}for(;h<=v;){const R=s[h++];R!==null&&We(R)}return this.ut=l,en(t,c),L}});/**
 * @license
 * Copyright 2020 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const hi=_e(class extends Ae{constructor(t){if(super(t),t.type!==H.PROPERTY&&t.type!==H.ATTRIBUTE&&t.type!==H.BOOLEAN_ATTRIBUTE)throw Error("The `live` directive is not allowed on child or event bindings");if(!Qt(t))throw Error("`live` bindings can only contain a single expression")}render(t){return t}update(t,[e]){if(e===L||e===N)return e;const n=t.element,i=t.name;if(t.type===H.PROPERTY){if(e===n[i])return L}else if(t.type===H.BOOLEAN_ATTRIBUTE){if(!!e===n.hasAttribute(i))return L}else if(t.type===H.ATTRIBUTE&&n.getAttribute(i)===e+"")return L;return en(t),e}});/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const he=(t,e)=>{var n,i;const o=t._$AN;if(o===void 0)return!1;for(const s of o)(i=(n=s)._$AO)===null||i===void 0||i.call(n,e,!1),he(s,e);return!0},Te=t=>{let e,n;do{if((e=t._$AM)===void 0)break;n=e._$AN,n.delete(t),t=e}while((n==null?void 0:n.size)===0)},tn=t=>{for(let e;e=t._$AM;t=e){let n=e._$AN;if(n===void 0)e._$AN=n=new Set;else if(n.has(t))break;n.add(t),pi(e)}};function di(t){this._$AN!==void 0?(Te(this),this._$AM=t,tn(this)):this._$AM=t}function ui(t,e=!1,n=0){const i=this._$AH,o=this._$AN;if(o!==void 0&&o.size!==0)if(e)if(Array.isArray(i))for(let s=n;s<i.length;s++)he(i[s],!1),Te(i[s]);else i!=null&&(he(i,!1),Te(i));else he(this,t)}const pi=t=>{var e,n,i,o;t.type==H.CHILD&&((e=(i=t)._$AP)!==null&&e!==void 0||(i._$AP=ui),(n=(o=t)._$AQ)!==null&&n!==void 0||(o._$AQ=di))};class vi extends Ae{constructor(){super(...arguments),this._$AN=void 0}_$AT(e,n,i){super._$AT(e,n,i),tn(this),this.isConnected=e._$AU}_$AO(e,n=!0){var i,o;e!==this.isConnected&&(this.isConnected=e,e?(i=this.reconnected)===null||i===void 0||i.call(this):(o=this.disconnected)===null||o===void 0||o.call(this)),n&&(he(this,e),Te(this))}setValue(e){if(Qt(this._$Ct))this._$Ct._$AI(e,this);else{const n=[...this._$Ct._$AH];n[this._$Ci]=e,this._$Ct._$AI(n,this,0)}}disconnected(){}reconnected(){}}/**
 * @license
 * Copyright 2020 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const nn=()=>new fi;let fi=class{};const Xe=new WeakMap,on=_e(class extends vi{render(t){return N}update(t,[e]){var n;const i=e!==this.G;return i&&this.G!==void 0&&this.ot(void 0),(i||this.rt!==this.lt)&&(this.G=e,this.dt=(n=t.options)===null||n===void 0?void 0:n.host,this.ot(this.lt=t.element)),N}ot(t){var e;if(typeof this.G=="function"){const n=(e=this.dt)!==null&&e!==void 0?e:globalThis;let i=Xe.get(n);i===void 0&&(i=new WeakMap,Xe.set(n,i)),i.get(this.G)!==void 0&&this.G.call(this.dt,void 0),i.set(this.G,t),t!==void 0&&this.G.call(this.dt,t)}else this.G.value=t}get rt(){var t,e,n;return typeof this.G=="function"?(e=Xe.get((t=this.dt)!==null&&t!==void 0?t:globalThis))===null||e===void 0?void 0:e.get(this.G):(n=this.G)===null||n===void 0?void 0:n.value}disconnected(){this.rt===this.lt&&this.ot(void 0)}reconnected(){this.ot(this.lt)}});/**
 * @license
 * Copyright 2018 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */const at=_e(class extends Ae{constructor(t){var e;if(super(t),t.type!==H.ATTRIBUTE||t.name!=="class"||((e=t.strings)===null||e===void 0?void 0:e.length)>2)throw Error("`classMap()` can only be used in the `class` attribute and must be the only part in the attribute.")}render(t){return" "+Object.keys(t).filter(e=>t[e]).join(" ")+" "}update(t,[e]){var n,i;if(this.it===void 0){this.it=new Set,t.strings!==void 0&&(this.nt=new Set(t.strings.join(" ").split(/\s/).filter(s=>s!=="")));for(const s in e)e[s]&&!(!((n=this.nt)===null||n===void 0)&&n.has(s))&&this.it.add(s);return this.render(e)}const o=t.element.classList;this.it.forEach(s=>{s in e||(o.remove(s),this.it.delete(s))});for(const s in e){const a=!!e[s];a===this.it.has(s)||!((i=this.nt)===null||i===void 0)&&i.has(s)||(a?(o.add(s),this.it.add(s)):(o.remove(s),this.it.delete(s)))}return L}});/*!
 * hotkeys-js v3.8.7
 * A simple micro-library for defining and dispatching keyboard shortcuts. It has no dependencies.
 * 
 * Copyright (c) 2021 kenny wong <wowohoo@qq.com>
 * http://jaywcjlove.github.io/hotkeys
 * 
 * Licensed under the MIT license.
 */var Je=typeof navigator<"u"?navigator.userAgent.toLowerCase().indexOf("firefox")>0:!1;function qe(t,e,n){t.addEventListener?t.addEventListener(e,n,!1):t.attachEvent&&t.attachEvent("on".concat(e),function(){n(window.event)})}function sn(t,e){for(var n=e.slice(0,e.length-1),i=0;i<n.length;i++)n[i]=t[n[i].toLowerCase()];return n}function an(t){typeof t!="string"&&(t=""),t=t.replace(/\s/g,"");for(var e=t.split(","),n=e.lastIndexOf("");n>=0;)e[n-1]+=",",e.splice(n,1),n=e.lastIndexOf("");return e}function _i(t,e){for(var n=t.length>=e.length?t:e,i=t.length>=e.length?e:t,o=!0,s=0;s<n.length;s++)i.indexOf(n[s])===-1&&(o=!1);return o}var ln={backspace:8,tab:9,clear:12,enter:13,return:13,esc:27,escape:27,space:32,left:37,up:38,right:39,down:40,del:46,delete:46,ins:45,insert:45,home:36,end:35,pageup:33,pagedown:34,capslock:20,num_0:96,num_1:97,num_2:98,num_3:99,num_4:100,num_5:101,num_6:102,num_7:103,num_8:104,num_9:105,num_multiply:106,num_add:107,num_enter:108,num_subtract:109,num_decimal:110,num_divide:111,"⇪":20,",":188,".":190,"/":191,"`":192,"-":Je?173:189,"=":Je?61:187,";":Je?59:186,"'":222,"[":219,"]":221,"\\":220},q={"⇧":16,shift:16,"⌥":18,alt:18,option:18,"⌃":17,ctrl:17,control:17,"⌘":91,cmd:91,command:91},Rt={16:"shiftKey",18:"altKey",17:"ctrlKey",91:"metaKey",shiftKey:16,ctrlKey:17,altKey:18,metaKey:91},T={16:!1,18:!1,17:!1,91:!1},w={};for(var Se=1;Se<20;Se++)ln["f".concat(Se)]=111+Se;var m=[],rn="all",cn=[],Re=function(e){return ln[e.toLowerCase()]||q[e.toLowerCase()]||e.toUpperCase().charCodeAt(0)};function hn(t){rn=t||"all"}function fe(){return rn||"all"}function Ai(){return m.slice(0)}function Oi(t){var e=t.target||t.srcElement,n=e.tagName,i=!0;return(e.isContentEditable||(n==="INPUT"||n==="TEXTAREA"||n==="SELECT")&&!e.readOnly)&&(i=!1),i}function gi(t){return typeof t=="string"&&(t=Re(t)),m.indexOf(t)!==-1}function mi(t,e){var n,i;t||(t=fe());for(var o in w)if(Object.prototype.hasOwnProperty.call(w,o))for(n=w[o],i=0;i<n.length;)n[i].scope===t?n.splice(i,1):i++;fe()===t&&hn(e||"all")}function Ni(t){var e=t.keyCode||t.which||t.charCode,n=m.indexOf(e);if(n>=0&&m.splice(n,1),t.key&&t.key.toLowerCase()==="meta"&&m.splice(0,m.length),(e===93||e===224)&&(e=91),e in T){T[e]=!1;for(var i in q)q[i]===e&&(S[i]=!1)}}function Ci(t){if(!t)Object.keys(w).forEach(function(a){return delete w[a]});else if(Array.isArray(t))t.forEach(function(a){a.key&&Qe(a)});else if(typeof t=="object")t.key&&Qe(t);else if(typeof t=="string"){for(var e=arguments.length,n=new Array(e>1?e-1:0),i=1;i<e;i++)n[i-1]=arguments[i];var o=n[0],s=n[1];typeof o=="function"&&(s=o,o=""),Qe({key:t,scope:o,method:s,splitKey:"+"})}}var Qe=function(e){var n=e.key,i=e.scope,o=e.method,s=e.splitKey,a=s===void 0?"+":s,l=an(n);l.forEach(function(r){var c=r.split(a),d=c.length,p=c[d-1],h=p==="*"?"*":Re(p);if(w[h]){i||(i=fe());var v=d>1?sn(q,c):[];w[h]=w[h].map(function(u){var _=o?u.method===o:!0;return _&&u.scope===i&&_i(u.mods,v)?{}:u})}})};function $t(t,e,n){var i;if(e.scope===n||e.scope==="all"){i=e.mods.length>0;for(var o in T)Object.prototype.hasOwnProperty.call(T,o)&&(!T[o]&&e.mods.indexOf(+o)>-1||T[o]&&e.mods.indexOf(+o)===-1)&&(i=!1);(e.mods.length===0&&!T[16]&&!T[18]&&!T[17]&&!T[91]||i||e.shortcut==="*")&&e.method(t,e)===!1&&(t.preventDefault?t.preventDefault():t.returnValue=!1,t.stopPropagation&&t.stopPropagation(),t.cancelBubble&&(t.cancelBubble=!0))}}function xt(t){var e=w["*"],n=t.keyCode||t.which||t.charCode;if(S.filter.call(this,t)){if((n===93||n===224)&&(n=91),m.indexOf(n)===-1&&n!==229&&m.push(n),["ctrlKey","altKey","shiftKey","metaKey"].forEach(function(v){var u=Rt[v];t[v]&&m.indexOf(u)===-1?m.push(u):!t[v]&&m.indexOf(u)>-1?m.splice(m.indexOf(u),1):v==="metaKey"&&t[v]&&m.length===3&&(t.ctrlKey||t.shiftKey||t.altKey||(m=m.slice(m.indexOf(u))))}),n in T){T[n]=!0;for(var i in q)q[i]===n&&(S[i]=!0);if(!e)return}for(var o in T)Object.prototype.hasOwnProperty.call(T,o)&&(T[o]=t[Rt[o]]);t.getModifierState&&!(t.altKey&&!t.ctrlKey)&&t.getModifierState("AltGraph")&&(m.indexOf(17)===-1&&m.push(17),m.indexOf(18)===-1&&m.push(18),T[17]=!0,T[18]=!0);var s=fe();if(e)for(var a=0;a<e.length;a++)e[a].scope===s&&(t.type==="keydown"&&e[a].keydown||t.type==="keyup"&&e[a].keyup)&&$t(t,e[a],s);if(n in w){for(var l=0;l<w[n].length;l++)if((t.type==="keydown"&&w[n][l].keydown||t.type==="keyup"&&w[n][l].keyup)&&w[n][l].key){for(var r=w[n][l],c=r.splitKey,d=r.key.split(c),p=[],h=0;h<d.length;h++)p.push(Re(d[h]));p.sort().join("")===m.sort().join("")&&$t(t,r,s)}}}}function Si(t){return cn.indexOf(t)>-1}function S(t,e,n){m=[];var i=an(t),o=[],s="all",a=document,l=0,r=!1,c=!0,d="+";for(n===void 0&&typeof e=="function"&&(n=e),Object.prototype.toString.call(e)==="[object Object]"&&(e.scope&&(s=e.scope),e.element&&(a=e.element),e.keyup&&(r=e.keyup),e.keydown!==void 0&&(c=e.keydown),typeof e.splitKey=="string"&&(d=e.splitKey)),typeof e=="string"&&(s=e);l<i.length;l++)t=i[l].split(d),o=[],t.length>1&&(o=sn(q,t)),t=t[t.length-1],t=t==="*"?"*":Re(t),t in w||(w[t]=[]),w[t].push({keyup:r,keydown:c,scope:s,mods:o,shortcut:i[l],method:n,key:i[l],splitKey:d});typeof a<"u"&&!Si(a)&&window&&(cn.push(a),qe(a,"keydown",function(p){xt(p)}),qe(window,"focus",function(){m=[]}),qe(a,"keyup",function(p){xt(p),Ni(p)}))}var et={setScope:hn,getScope:fe,deleteScope:mi,getPressedKeyCodes:Ai,isPressed:gi,filter:Oi,unbind:Ci};for(var tt in et)Object.prototype.hasOwnProperty.call(et,tt)&&(S[tt]=et[tt]);if(typeof window<"u"){var Mi=window.hotkeys;S.noConflict=function(t){return t&&window.hotkeys===S&&(window.hotkeys=Mi),S},window.hotkeys=S}var Oe=function(t,e,n,i){var o=arguments.length,s=o<3?e:i===null?i=Object.getOwnPropertyDescriptor(e,n):i,a;if(typeof Reflect=="object"&&typeof Reflect.decorate=="function")s=Reflect.decorate(t,e,n,i);else for(var l=t.length-1;l>=0;l--)(a=t[l])&&(s=(o<3?a(s):o>3?a(e,n,s):a(e,n))||s);return o>3&&s&&Object.defineProperty(e,n,s),s};let Q=class extends z{constructor(){super(...arguments),this.placeholder="",this.hideBreadcrumbs=!1,this.breadcrumbHome="Home",this.breadcrumbs=[],this._inputRef=nn()}render(){let e="";if(!this.hideBreadcrumbs){const n=[];for(const i of this.breadcrumbs)n.push(y`<button
            tabindex="-1"
            @click=${()=>this.selectParent(i)}
            class="breadcrumb"
          >
            ${i}
          </button>`);e=y`<div class="breadcrumb-list">
        <button
          tabindex="-1"
          @click=${()=>this.selectParent()}
          class="breadcrumb"
        >
          ${this.breadcrumbHome}
        </button>
        ${n}
      </div>`}return y`
      ${e}
      <div part="ninja-input-wrapper" class="search-wrapper">
        <input
          part="ninja-input"
          type="text"
          id="search"
          spellcheck="false"
          autocomplete="off"
          @input="${this._handleInput}"
          ${on(this._inputRef)}
          placeholder="${this.placeholder}"
          class="search"
        />
      </div>
    `}setSearch(e){this._inputRef.value&&(this._inputRef.value.value=e)}focusSearch(){requestAnimationFrame(()=>this._inputRef.value.focus())}_handleInput(e){const n=e.target;this.dispatchEvent(new CustomEvent("change",{detail:{search:n.value},bubbles:!1,composed:!1}))}selectParent(e){this.dispatchEvent(new CustomEvent("setParent",{detail:{parent:e},bubbles:!0,composed:!0}))}firstUpdated(){this.focusSearch()}_close(){this.dispatchEvent(new CustomEvent("close",{bubbles:!0,composed:!0}))}};Q.styles=ye`
    :host {
      flex: 1;
      position: relative;
    }
    .search {
      padding: 1.25em;
      flex-grow: 1;
      flex-shrink: 0;
      margin: 0px;
      border: none;
      appearance: none;
      font-size: 1.125em;
      background: transparent;
      caret-color: var(--ninja-accent-color);
      color: var(--ninja-text-color);
      outline: none;
      font-family: var(--ninja-font-family);
    }
    .search::placeholder {
      color: var(--ninja-placeholder-color);
    }
    .breadcrumb-list {
      padding: 1em 4em 0 1em;
      display: flex;
      flex-direction: row;
      align-items: stretch;
      justify-content: flex-start;
      flex: initial;
    }

    .breadcrumb {
      background: var(--ninja-secondary-background-color);
      text-align: center;
      line-height: 1.2em;
      border-radius: var(--ninja-key-border-radius);
      border: 0;
      cursor: pointer;
      padding: 0.1em 0.5em;
      color: var(--ninja-secondary-text-color);
      margin-right: 0.5em;
      outline: none;
      font-family: var(--ninja-font-family);
    }

    .search-wrapper {
      display: flex;
      border-bottom: var(--ninja-separate-border);
    }
  `;Oe([E()],Q.prototype,"placeholder",void 0);Oe([E({type:Boolean})],Q.prototype,"hideBreadcrumbs",void 0);Oe([E()],Q.prototype,"breadcrumbHome",void 0);Oe([E({type:Array})],Q.prototype,"breadcrumbs",void 0);Q=Oe([be("ninja-header")],Q);/**
 * @license
 * Copyright 2017 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */class lt extends Ae{constructor(e){if(super(e),this.et=N,e.type!==H.CHILD)throw Error(this.constructor.directiveName+"() can only be used in child bindings")}render(e){if(e===N||e==null)return this.ft=void 0,this.et=e;if(e===L)return e;if(typeof e!="string")throw Error(this.constructor.directiveName+"() called with a non-string value");if(e===this.et)return this.ft;this.et=e;const n=[e];return n.raw=n,this.ft={_$litType$:this.constructor.resultType,strings:n,values:[]}}}lt.directiveName="unsafeHTML",lt.resultType=1;const Ei=_e(lt);/**
 * @license
 * Copyright 2021 Google LLC
 * SPDX-License-Identifier: BSD-3-Clause
 */function*wi(t,e){if(t!==void 0){let n=-1;for(const i of t)n>-1&&(yield e),n++,yield i}}/**
 * @license
 * Copyright 2021 Google LLC
 * SPDX-LIcense-Identifier: Apache-2.0
 */const Ti=ye`:host{font-family:var(--mdc-icon-font, "Material Icons");font-weight:normal;font-style:normal;font-size:var(--mdc-icon-size, 24px);line-height:1;letter-spacing:normal;text-transform:none;display:inline-block;white-space:nowrap;word-wrap:normal;direction:ltr;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility;-moz-osx-font-smoothing:grayscale;font-feature-settings:"liga"}`;/**
 * @license
 * Copyright 2018 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */let rt=class extends z{render(){return y`<span><slot></slot></span>`}};rt.styles=[Ti];rt=mn([be("mwc-icon")],rt);var $e=function(t,e,n,i){var o=arguments.length,s=o<3?e:i===null?i=Object.getOwnPropertyDescriptor(e,n):i,a;if(typeof Reflect=="object"&&typeof Reflect.decorate=="function")s=Reflect.decorate(t,e,n,i);else for(var l=t.length-1;l>=0;l--)(a=t[l])&&(s=(o<3?a(s):o>3?a(e,n,s):a(e,n))||s);return o>3&&s&&Object.defineProperty(e,n,s),s};let oe=class extends z{constructor(){super(),this.selected=!1,this.hotKeysJoinedView=!0,this.addEventListener("click",this.click)}ensureInView(){requestAnimationFrame(()=>this.scrollIntoView({block:"nearest"}))}click(){this.dispatchEvent(new CustomEvent("actionsSelected",{detail:this.action,bubbles:!0,composed:!0}))}updated(e){e.has("selected")&&this.selected&&this.ensureInView()}render(){let e;this.action.mdIcon?e=y`<mwc-icon part="ninja-icon" class="ninja-icon"
        >${this.action.mdIcon}</mwc-icon
      >`:this.action.icon&&(e=Ei(this.action.icon||""));let n;this.action.hotkey&&(this.hotKeysJoinedView?n=this.action.hotkey.split(",").map(o=>{const s=o.split("+"),a=y`${wi(s.map(l=>y`<kbd>${l}</kbd>`),"+")}`;return y`<div class="ninja-hotkey ninja-hotkeys">
            ${a}
          </div>`}):n=this.action.hotkey.split(",").map(o=>{const a=o.split("+").map(l=>y`<kbd class="ninja-hotkey">${l}</kbd>`);return y`<kbd class="ninja-hotkeys">${a}</kbd>`}));const i={selected:this.selected,"ninja-action":!0};return y`
      <div
        class="ninja-action"
        part="ninja-action ${this.selected?"ninja-selected":""}"
        class=${at(i)}
      >
        ${e}
        <div class="ninja-title">${this.action.title}</div>
        ${n}
      </div>
    `}};oe.styles=ye`
    :host {
      display: flex;
      width: 100%;
    }
    .ninja-action {
      padding: 0.75em 1em;
      display: flex;
      border-left: 2px solid transparent;
      align-items: center;
      justify-content: start;
      outline: none;
      transition: color 0s ease 0s;
      width: 100%;
    }
    .ninja-action.selected {
      cursor: pointer;
      color: var(--ninja-selected-text-color);
      background-color: var(--ninja-selected-background);
      border-left: 2px solid var(--ninja-accent-color);
      outline: none;
    }
    .ninja-action.selected .ninja-icon {
      color: var(--ninja-selected-text-color);
    }
    .ninja-icon {
      font-size: var(--ninja-icon-size);
      max-width: var(--ninja-icon-size);
      max-height: var(--ninja-icon-size);
      margin-right: 1em;
      color: var(--ninja-icon-color);
      margin-right: 1em;
      position: relative;
    }

    .ninja-title {
      flex-shrink: 0.01;
      margin-right: 0.5em;
      flex-grow: 1;
      font-size: 0.8125em;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .ninja-hotkeys {
      flex-shrink: 0;
      width: min-content;
      display: flex;
    }

    .ninja-hotkeys kbd {
      font-family: inherit;
    }
    .ninja-hotkey {
      background: var(--ninja-secondary-background-color);
      padding: 0.06em 0.25em;
      border-radius: var(--ninja-key-border-radius);
      text-transform: capitalize;
      color: var(--ninja-secondary-text-color);
      font-size: 0.75em;
      font-family: inherit;
    }

    .ninja-hotkey + .ninja-hotkey {
      margin-left: 0.5em;
    }
    .ninja-hotkeys + .ninja-hotkeys {
      margin-left: 1em;
    }
  `;$e([E({type:Object})],oe.prototype,"action",void 0);$e([E({type:Boolean})],oe.prototype,"selected",void 0);$e([E({type:Boolean})],oe.prototype,"hotKeysJoinedView",void 0);oe=$e([be("ninja-action")],oe);const yi=y` <div class="modal-footer" slot="footer">
  <span class="help">
    <svg
      version="1.0"
      class="ninja-examplekey"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 1280 1280"
    >
      <path
        d="M1013 376c0 73.4-.4 113.3-1.1 120.2a159.9 159.9 0 0 1-90.2 127.3c-20 9.6-36.7 14-59.2 15.5-7.1.5-121.9.9-255 1h-242l95.5-95.5 95.5-95.5-38.3-38.2-38.2-38.3-160 160c-88 88-160 160.4-160 161 0 .6 72 73 160 161l160 160 38.2-38.3 38.3-38.2-95.5-95.5-95.5-95.5h251.1c252.9 0 259.8-.1 281.4-3.6 72.1-11.8 136.9-54.1 178.5-116.4 8.6-12.9 22.6-40.5 28-55.4 4.4-12 10.7-36.1 13.1-50.6 1.6-9.6 1.8-21 2.1-132.8l.4-122.2H1013v110z"
      />
    </svg>

    to select
  </span>
  <span class="help">
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="ninja-examplekey"
      viewBox="0 0 24 24"
    >
      <path d="M0 0h24v24H0V0z" fill="none" />
      <path
        d="M20 12l-1.41-1.41L13 16.17V4h-2v12.17l-5.58-5.59L4 12l8 8 8-8z"
      />
    </svg>
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="ninja-examplekey"
      viewBox="0 0 24 24"
    >
      <path d="M0 0h24v24H0V0z" fill="none" />
      <path d="M4 12l1.41 1.41L11 7.83V20h2V7.83l5.58 5.59L20 12l-8-8-8 8z" />
    </svg>
    to navigate
  </span>
  <span class="help">
    <span class="ninja-examplekey esc">esc</span>
    to close
  </span>
  <span class="help">
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="ninja-examplekey backspace"
      viewBox="0 0 20 20"
      fill="currentColor"
    >
      <path
        fill-rule="evenodd"
        d="M6.707 4.879A3 3 0 018.828 4H15a3 3 0 013 3v6a3 3 0 01-3 3H8.828a3 3 0 01-2.12-.879l-4.415-4.414a1 1 0 010-1.414l4.414-4.414zm4 2.414a1 1 0 00-1.414 1.414L10.586 10l-1.293 1.293a1 1 0 101.414 1.414L12 11.414l1.293 1.293a1 1 0 001.414-1.414L13.414 10l1.293-1.293a1 1 0 00-1.414-1.414L12 8.586l-1.293-1.293z"
        clip-rule="evenodd"
      />
    </svg>
    move to parent
  </span>
</div>`,Ii=ye`
  :host {
    --ninja-width: 640px;
    --ninja-backdrop-filter: none;
    --ninja-overflow-background: rgba(255, 255, 255, 0.5);
    --ninja-text-color: rgb(60, 65, 73);
    --ninja-font-size: 16px;
    --ninja-top: 20%;

    --ninja-key-border-radius: 0.25em;
    --ninja-accent-color: rgb(110, 94, 210);
    --ninja-secondary-background-color: rgb(239, 241, 244);
    --ninja-secondary-text-color: rgb(107, 111, 118);

    --ninja-selected-background: rgb(248, 249, 251);

    --ninja-icon-color: var(--ninja-secondary-text-color);
    --ninja-icon-size: 1.2em;
    --ninja-separate-border: 1px solid var(--ninja-secondary-background-color);

    --ninja-modal-background: #fff;
    --ninja-modal-shadow: rgb(0 0 0 / 50%) 0px 16px 70px;

    --ninja-actions-height: 300px;
    --ninja-group-text-color: rgb(144, 149, 157);

    --ninja-footer-background: rgba(242, 242, 242, 0.4);

    --ninja-placeholder-color: #8e8e8e;

    font-size: var(--ninja-font-size);

    --ninja-z-index: 1;
  }

  :host(.dark) {
    --ninja-backdrop-filter: none;
    --ninja-overflow-background: rgba(0, 0, 0, 0.7);
    --ninja-text-color: #7d7d7d;

    --ninja-modal-background: rgba(17, 17, 17, 0.85);
    --ninja-accent-color: rgb(110, 94, 210);
    --ninja-secondary-background-color: rgba(51, 51, 51, 0.44);
    --ninja-secondary-text-color: #888;

    --ninja-selected-text-color: #eaeaea;
    --ninja-selected-background: rgba(51, 51, 51, 0.44);

    --ninja-icon-color: var(--ninja-secondary-text-color);
    --ninja-separate-border: 1px solid var(--ninja-secondary-background-color);

    --ninja-modal-shadow: 0 16px 70px rgba(0, 0, 0, 0.2);

    --ninja-group-text-color: rgb(144, 149, 157);

    --ninja-footer-background: rgba(30, 30, 30, 85%);
  }

  .modal {
    display: none;
    position: fixed;
    z-index: var(--ninja-z-index);
    left: 0;
    top: 0;
    width: 100%;
    height: 100%;
    overflow: auto;
    background: var(--ninja-overflow-background);
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    -webkit-backdrop-filter: var(--ninja-backdrop-filter);
    backdrop-filter: var(--ninja-backdrop-filter);
    text-align: left;
    color: var(--ninja-text-color);
    font-family: var(--ninja-font-family);
  }
  .modal.visible {
    display: block;
  }

  .modal-content {
    position: relative;
    top: var(--ninja-top);
    margin: auto;
    padding: 0;
    display: flex;
    flex-direction: column;
    flex-shrink: 1;
    -webkit-box-flex: 1;
    flex-grow: 1;
    min-width: 0px;
    will-change: transform;
    background: var(--ninja-modal-background);
    border-radius: 0.5em;
    box-shadow: var(--ninja-modal-shadow);
    max-width: var(--ninja-width);
    overflow: hidden;
  }

  .bump {
    animation: zoom-in-zoom-out 0.2s ease;
  }

  @keyframes zoom-in-zoom-out {
    0% {
      transform: scale(0.99);
    }
    50% {
      transform: scale(1.01, 1.01);
    }
    100% {
      transform: scale(1, 1);
    }
  }

  .ninja-github {
    color: var(--ninja-keys-text-color);
    font-weight: normal;
    text-decoration: none;
  }

  .actions-list {
    max-height: var(--ninja-actions-height);
    overflow: auto;
    scroll-behavior: smooth;
    position: relative;
    margin: 0;
    padding: 0.5em 0;
    list-style: none;
    scroll-behavior: smooth;
  }

  .group-header {
    height: 1.375em;
    line-height: 1.375em;
    padding-left: 1.25em;
    padding-top: 0.5em;
    text-overflow: ellipsis;
    white-space: nowrap;
    overflow: hidden;
    font-size: 0.75em;
    line-height: 1em;
    color: var(--ninja-group-text-color);
    margin: 1px 0;
  }

  .modal-footer {
    background: var(--ninja-footer-background);
    padding: 0.5em 1em;
    display: flex;
    /* font-size: 0.75em; */
    border-top: var(--ninja-separate-border);
    color: var(--ninja-secondary-text-color);
  }

  .modal-footer .help {
    display: flex;
    margin-right: 1em;
    align-items: center;
    font-size: 0.75em;
  }

  .ninja-examplekey {
    background: var(--ninja-secondary-background-color);
    padding: 0.06em 0.25em;
    border-radius: var(--ninja-key-border-radius);
    color: var(--ninja-secondary-text-color);
    width: 1em;
    height: 1em;
    margin-right: 0.5em;
    font-size: 1.25em;
    fill: currentColor;
  }
  .ninja-examplekey.esc {
    width: auto;
    height: auto;
    font-size: 1.1em;
  }
  .ninja-examplekey.backspace {
    opacity: 0.7;
  }
`;var M=function(t,e,n,i){var o=arguments.length,s=o<3?e:i===null?i=Object.getOwnPropertyDescriptor(e,n):i,a;if(typeof Reflect=="object"&&typeof Reflect.decorate=="function")s=Reflect.decorate(t,e,n,i);else for(var l=t.length-1;l>=0;l--)(a=t[l])&&(s=(o<3?a(s):o>3?a(e,n,s):a(e,n))||s);return o>3&&s&&Object.defineProperty(e,n,s),s};let C=class extends z{constructor(){super(...arguments),this.placeholder="Type a command or search...",this.disableHotkeys=!1,this.hideBreadcrumbs=!1,this.openHotkey="cmd+k,ctrl+k",this.navigationUpHotkey="up,shift+tab",this.navigationDownHotkey="down,tab",this.closeHotkey="esc",this.goBackHotkey="backspace",this.selectHotkey="enter",this.hotKeysJoinedView=!1,this.noAutoLoadMdIcons=!1,this.data=[],this.visible=!1,this._bump=!0,this._actionMatches=[],this._search="",this._flatData=[],this._headerRef=nn()}open(e={}){this._bump=!0,this.visible=!0,this._headerRef.value.focusSearch(),this._actionMatches.length>0&&(this._selected=this._actionMatches[0]),this.setParent(e.parent)}close(){this._bump=!1,this.visible=!1,this.dispatchEvent(new CustomEvent("closed",{bubbles:!0,composed:!0}))}setParent(e){e?this._currentRoot=e:this._currentRoot=void 0,this._selected=void 0,this._search="",this._headerRef.value.setSearch("")}get breadcrumbs(){var e;const n=[];let i=(e=this._selected)===null||e===void 0?void 0:e.parent;if(i)for(n.push(i);i;){const o=this._flatData.find(s=>s.id===i);o!=null&&o.parent&&n.push(o.parent),i=o?o.parent:void 0}return n.reverse()}connectedCallback(){super.connectedCallback(),this.noAutoLoadMdIcons||document.fonts.load("24px Material Icons","apps").then(()=>{}),this._registerInternalHotkeys()}disconnectedCallback(){super.disconnectedCallback(),this._unregisterInternalHotkeys()}_flattern(e,n){let i=[];return e||(e=[]),e.map(o=>{const s=o.children&&o.children.some(l=>typeof l=="string"),a={...o,parent:o.parent||n};return s||(a.children&&a.children.length&&(n=o.id,i=[...i,...a.children]),a.children=a.children?a.children.map(l=>l.id):[]),a}).concat(i.length?this._flattern(i,n):i)}update(e){e.has("data")&&!this.disableHotkeys&&(this._flatData=this._flattern(this.data),this._flatData.filter(n=>!!n.hotkey).forEach(n=>{S(n.hotkey,i=>{i.preventDefault(),n.handler&&n.handler(n)})})),super.update(e)}_registerInternalHotkeys(){this.openHotkey&&S(this.openHotkey,e=>{e.preventDefault(),this.visible?this.close():this.open()}),this.selectHotkey&&S(this.selectHotkey,e=>{this.visible&&(e.preventDefault(),this._actionSelected(this._actionMatches[this._selectedIndex]))}),this.goBackHotkey&&S(this.goBackHotkey,e=>{this.visible&&(this._search||(e.preventDefault(),this._goBack()))}),this.navigationDownHotkey&&S(this.navigationDownHotkey,e=>{this.visible&&(e.preventDefault(),this._selectedIndex>=this._actionMatches.length-1?this._selected=this._actionMatches[0]:this._selected=this._actionMatches[this._selectedIndex+1])}),this.navigationUpHotkey&&S(this.navigationUpHotkey,e=>{this.visible&&(e.preventDefault(),this._selectedIndex===0?this._selected=this._actionMatches[this._actionMatches.length-1]:this._selected=this._actionMatches[this._selectedIndex-1])}),this.closeHotkey&&S(this.closeHotkey,()=>{this.visible&&this.close()})}_unregisterInternalHotkeys(){this.openHotkey&&S.unbind(this.openHotkey),this.selectHotkey&&S.unbind(this.selectHotkey),this.goBackHotkey&&S.unbind(this.goBackHotkey),this.navigationDownHotkey&&S.unbind(this.navigationDownHotkey),this.navigationUpHotkey&&S.unbind(this.navigationUpHotkey),this.closeHotkey&&S.unbind(this.closeHotkey)}_actionFocused(e,n){this._selected=e,n.target.ensureInView()}_onTransitionEnd(){this._bump=!1}_goBack(){const e=this.breadcrumbs.length>1?this.breadcrumbs[this.breadcrumbs.length-2]:void 0;this.setParent(e)}render(){const e={bump:this._bump,"modal-content":!0},n={visible:this.visible,modal:!0},o=this._flatData.filter(l=>{var r;const c=new RegExp(this._search,"gi"),d=l.title.match(c)||((r=l.keywords)===null||r===void 0?void 0:r.match(c));return(!this._currentRoot&&this._search||l.parent===this._currentRoot)&&d}).reduce((l,r)=>l.set(r.section,[...l.get(r.section)||[],r]),new Map);this._actionMatches=[...o.values()].flat(),this._actionMatches.length>0&&this._selectedIndex===-1&&(this._selected=this._actionMatches[0]),this._actionMatches.length===0&&(this._selected=void 0);const s=l=>y` ${ci(l,r=>r.id,r=>{var c;return y`<ninja-action
            exportparts="ninja-action,ninja-selected,ninja-icon"
            .selected=${hi(r.id===((c=this._selected)===null||c===void 0?void 0:c.id))}
            .hotKeysJoinedView=${this.hotKeysJoinedView}
            @mouseover=${d=>this._actionFocused(r,d)}
            @actionsSelected=${d=>this._actionSelected(d.detail)}
            .action=${r}
          ></ninja-action>`})}`,a=[];return o.forEach((l,r)=>{const c=r?y`<div class="group-header">${r}</div>`:void 0;a.push(y`${c}${s(l)}`)}),y`
      <div @click=${this._overlayClick} class=${at(n)}>
        <div class=${at(e)} @animationend=${this._onTransitionEnd}>
          <ninja-header
            exportparts="ninja-input,ninja-input-wrapper"
            ${on(this._headerRef)}
            .placeholder=${this.placeholder}
            .hideBreadcrumbs=${this.hideBreadcrumbs}
            .breadcrumbs=${this.breadcrumbs}
            @change=${this._handleInput}
            @setParent=${l=>this.setParent(l.detail.parent)}
            @close=${this.close}
          >
          </ninja-header>
          <div class="modal-body">
            <div class="actions-list" part="actions-list">${a}</div>
          </div>
          <slot name="footer"> ${yi} </slot>
        </div>
      </div>
    `}get _selectedIndex(){return this._selected?this._actionMatches.indexOf(this._selected):-1}_actionSelected(e){var n;if(this.dispatchEvent(new CustomEvent("selected",{detail:{search:this._search,action:e},bubbles:!0,composed:!0})),!!e){if(e.children&&((n=e.children)===null||n===void 0?void 0:n.length)>0&&(this._currentRoot=e.id,this._search=""),this._headerRef.value.setSearch(""),this._headerRef.value.focusSearch(),e.handler){const i=e.handler(e);i!=null&&i.keepOpen||this.close()}this._bump=!0}}async _handleInput(e){this._search=e.detail.search,await this.updateComplete,this.dispatchEvent(new CustomEvent("change",{detail:{search:this._search,actions:this._actionMatches},bubbles:!0,composed:!0}))}_overlayClick(e){var n;!((n=e.target)===null||n===void 0)&&n.classList.contains("modal")&&this.close()}};C.styles=[Ii];M([E({type:String})],C.prototype,"placeholder",void 0);M([E({type:Boolean})],C.prototype,"disableHotkeys",void 0);M([E({type:Boolean})],C.prototype,"hideBreadcrumbs",void 0);M([E()],C.prototype,"openHotkey",void 0);M([E()],C.prototype,"navigationUpHotkey",void 0);M([E()],C.prototype,"navigationDownHotkey",void 0);M([E()],C.prototype,"closeHotkey",void 0);M([E()],C.prototype,"goBackHotkey",void 0);M([E()],C.prototype,"selectHotkey",void 0);M([E({type:Boolean})],C.prototype,"hotKeysJoinedView",void 0);M([E({type:Boolean})],C.prototype,"noAutoLoadMdIcons",void 0);M([E({type:Array,hasChanged(){return!0}})],C.prototype,"data",void 0);M([G()],C.prototype,"visible",void 0);M([G()],C.prototype,"_bump",void 0);M([G()],C.prototype,"_actionMatches",void 0);M([G()],C.prototype,"_search",void 0);M([G()],C.prototype,"_currentRoot",void 0);M([G()],C.prototype,"_flatData",void 0);M([G()],C.prototype,"breadcrumbs",null);M([G()],C.prototype,"_selected",void 0);C=M([be("ninja-keys")],C);const Lt='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M19.75 2A2.25 2.25 0 0 1 22 4.25v5.462a3.25 3.25 0 0 1-.952 2.298l-8.5 8.503a3.255 3.255 0 0 1-4.597.001L3.489 16.06a3.25 3.25 0 0 1-.003-4.596l8.5-8.51A3.25 3.25 0 0 1 14.284 2h5.465Zm0 1.5h-5.465c-.465 0-.91.185-1.239.513l-8.512 8.523a1.75 1.75 0 0 0 .015 2.462l4.461 4.454a1.755 1.755 0 0 0 2.477 0l8.5-8.503a1.75 1.75 0 0 0 .513-1.237V4.25a.75.75 0 0 0-.75-.75ZM17 5.502a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Z" fill="currentColor"/></svg>',jt='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M17.5 12a5.5 5.5 0 1 1 0 11 5.5 5.5 0 0 1 0-11Zm-5.478 2a6.474 6.474 0 0 0-.708 1.5h-7.06a.75.75 0 0 0-.75.75v.907c0 .656.286 1.279.783 1.706C5.545 19.945 7.44 20.501 10 20.501c.599 0 1.162-.03 1.688-.091.25.5.563.964.93 1.38-.803.141-1.676.21-2.618.21-2.89 0-5.128-.656-6.691-2a3.75 3.75 0 0 1-1.305-2.843v-.907A2.25 2.25 0 0 1 4.254 14h7.768Zm4.697.588-.069.058-2.515 2.517-.041.05-.035.058-.032.078-.012.043-.01.086.003.088.019.085.032.078.025.042.05.066 2.516 2.516a.5.5 0 0 0 .765-.638l-.058-.069L15.711 18h4.79a.5.5 0 0 0 .491-.41L21 17.5a.5.5 0 0 0-.41-.492L20.5 17h-4.789l1.646-1.647a.5.5 0 0 0 .058-.637l-.058-.07a.5.5 0 0 0-.638-.058ZM10 2.004a5 5 0 1 1 0 10 5 5 0 0 1 0-10Zm0 1.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7Z" fill="currentColor"/></svg>',bi='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12.92 3.316c.806-.717 2.08-.145 2.08.934v15.496c0 1.078-1.274 1.65-2.08.934l-4.492-3.994a.75.75 0 0 0-.498-.19H4.25A2.25 2.25 0 0 1 2 14.247V9.75a2.25 2.25 0 0 1 2.25-2.25h3.68a.75.75 0 0 0 .498-.19l4.491-3.993Zm.58 1.49L9.425 8.43A2.25 2.25 0 0 1 7.93 9H4.25a.75.75 0 0 0-.75.75v4.497c0 .415.336.75.75.75h3.68a2.25 2.25 0 0 1 1.495.57l4.075 3.623V4.807ZM16.22 9.22a.75.75 0 0 1 1.06 0L19 10.94l1.72-1.72a.75.75 0 1 1 1.06 1.06L20.06 12l1.72 1.72a.75.75 0 1 1-1.06 1.06L19 13.06l-1.72 1.72a.75.75 0 1 1-1.06-1.06L17.94 12l-1.72-1.72a.75.75 0 0 1 0-1.06Z" fill="currentColor"/></svg>',Ri='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M15 4.25c0-1.079-1.274-1.65-2.08-.934L8.427 7.309a.75.75 0 0 1-.498.19H4.25A2.25 2.25 0 0 0 2 9.749v4.497a2.25 2.25 0 0 0 2.25 2.25h3.68a.75.75 0 0 1 .498.19l4.491 3.994c.806.716 2.081.144 2.081-.934V4.25ZM9.425 8.43 13.5 4.807v14.382l-4.075-3.624a2.25 2.25 0 0 0-1.495-.569H4.25a.75.75 0 0 1-.75-.75V9.75a.75.75 0 0 1 .75-.75h3.68a2.25 2.25 0 0 0 1.495-.569ZM18.992 5.897a.75.75 0 0 1 1.049.157A9.959 9.959 0 0 1 22 12a9.96 9.96 0 0 1-1.96 5.946.75.75 0 0 1-1.205-.892A8.459 8.459 0 0 0 20.5 12a8.459 8.459 0 0 0-1.665-5.054.75.75 0 0 1 .157-1.049Z" fill="#212121"/><path d="M17.143 8.37a.75.75 0 0 1 1.017.302c.536.99.84 2.125.84 3.328a6.973 6.973 0 0 1-.84 3.328.75.75 0 0 1-1.32-.714c.42-.777.66-1.666.66-2.614s-.24-1.837-.66-2.614a.75.75 0 0 1 .303-1.017Z" fill="currentColor"/></svg>',kt='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M19.75 2A2.25 2.25 0 0 1 22 4.25v5.462a3.25 3.25 0 0 1-.952 2.298l-.026.026a6.473 6.473 0 0 0-1.43-.692l.395-.395a1.75 1.75 0 0 0 .513-1.237V4.25a.75.75 0 0 0-.75-.75h-5.466c-.464 0-.91.185-1.238.513l-8.512 8.523a1.75 1.75 0 0 0 .015 2.462l4.461 4.454a1.755 1.755 0 0 0 2.33.13c.165.487.386.947.654 1.374a3.256 3.256 0 0 1-4.043-.442L3.489 16.06a3.25 3.25 0 0 1-.004-4.596l8.5-8.51a3.25 3.25 0 0 1 2.3-.953h5.465ZM17 5.502a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM17.5 23a5.5 5.5 0 1 0 0-11 5.5 5.5 0 0 0 0 11Zm-2.354-7.854a.5.5 0 0 1 .708 0l1.646 1.647 1.646-1.647a.5.5 0 0 1 .708.708L18.207 17.5l1.647 1.646a.5.5 0 0 1-.708.708L17.5 18.207l-1.646 1.647a.5.5 0 0 1-.708-.708l1.647-1.646-1.647-1.646a.5.5 0 0 1 0-.708Z" fill="currentColor"/></svg>',dn='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M19.25 2a.75.75 0 0 0-.743.648l-.007.102v5.69l-4.574-4.56a6.41 6.41 0 0 0-8.878-.179l-.186.18a6.41 6.41 0 0 0 0 9.063l8.845 8.84a.75.75 0 0 0 1.06-1.062l-8.845-8.838a4.91 4.91 0 0 1 6.766-7.112l.178.17L17.438 9.5H11.75a.75.75 0 0 0-.743.648L11 10.25c0 .38.282.694.648.743l.102.007h7.5a.75.75 0 0 0 .743-.648L20 10.25v-7.5a.75.75 0 0 0-.75-.75Z" fill="currentColor"/></svg>',un='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12 2c5.523 0 10 4.477 10 10s-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2Zm0 1.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17Zm-1.25 9.94 4.47-4.47a.75.75 0 0 1 1.133.976l-.073.084-5 5a.75.75 0 0 1-.976.073l-.084-.073-2.5-2.5a.75.75 0 0 1 .976-1.133l.084.073 1.97 1.97 4.47-4.47-4.47 4.47Z" fill="currentColor"/></svg>',$i='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M19.75 11.5a.75.75 0 0 1 .743.648l.007.102v5a4.75 4.75 0 0 1-4.533 4.745L15.75 22h-7.5c-.98 0-1.813-.626-2.122-1.5h9.622l.184-.005a3.25 3.25 0 0 0 3.06-3.06L19 17.25v-5a.75.75 0 0 1 .75-.75Zm-2.5-2a.75.75 0 0 1 .743.648l.007.102v7a2.25 2.25 0 0 1-2.096 2.245l-.154.005h-10a2.25 2.25 0 0 1-2.245-2.096L3.5 17.25v-7a.75.75 0 0 1 1.493-.102L5 10.25v7c0 .38.282.694.648.743L5.75 18h10a.75.75 0 0 0 .743-.648l.007-.102v-7a.75.75 0 0 1 .75-.75ZM6.218 6.216l3.998-3.996a.75.75 0 0 1 .976-.073l.084.072 4.004 3.997a.75.75 0 0 1-.976 1.134l-.084-.073-2.72-2.714v9.692a.75.75 0 0 1-.648.743l-.102.007a.75.75 0 0 1-.743-.648L10 14.255V4.556L7.279 7.277a.75.75 0 0 1-.977.072l-.084-.072a.75.75 0 0 1-.072-.977l.072-.084 3.998-3.996-3.998 3.996Z" fill="currentColor"/></svg>',xe='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12 2c5.523 0 10 4.478 10 10s-4.477 10-10 10S2 17.522 2 12S6.477 2 12 2Zm0 1.667c-4.595 0-8.333 3.738-8.333 8.333c0 4.595 3.738 8.333 8.333 8.333c4.595 0 8.333-3.738 8.333-8.333c0-4.595-3.738-8.333-8.333-8.333ZM11.25 6a.75.75 0 0 1 .743.648L12 6.75V12h3.25a.75.75 0 0 1 .102 1.493l-.102.007h-4a.75.75 0 0 1-.743-.648l-.007-.102v-6a.75.75 0 0 1 .75-.75Z" fill="currentColor"/></svg>',xi='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" aria-hidden="true" role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" preserveAspectRatio="xMidYMid meet" viewBox="0 0 24 24"><g fill="none"><path d="M10.55 2.532a2.25 2.25 0 0 1 2.9 0l6.75 5.692c.507.428.8 1.057.8 1.72v9.803a1.75 1.75 0 0 1-1.75 1.75h-3.5a1.75 1.75 0 0 1-1.75-1.75v-5.5a.25.25 0 0 0-.25-.25h-3.5a.25.25 0 0 0-.25.25v5.5a1.75 1.75 0 0 1-1.75 1.75h-3.5A1.75 1.75 0 0 1 3 19.747V9.944c0-.663.293-1.292.8-1.72l6.75-5.692zm1.933 1.147a.75.75 0 0 0-.966 0L4.767 9.37a.75.75 0 0 0-.267.573v9.803c0 .138.112.25.25.25h3.5a.25.25 0 0 0 .25-.25v-5.5c0-.967.784-1.75 1.75-1.75h3.5c.966 0 1.75.783 1.75 1.75v5.5c0 .138.112.25.25.25h3.5a.25.25 0 0 0 .25-.25V9.944a.75.75 0 0 0-.267-.573l-6.75-5.692z" fill="currentColor"></path></g></svg>',Li='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" aria-hidden="true" role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" preserveAspectRatio="xMidYMid meet" viewBox="0 0 24 24"><g fill="none"><path d="M17.754 14a2.249 2.249 0 0 1 2.25 2.249v.575c0 .894-.32 1.76-.902 2.438c-1.57 1.834-3.957 2.739-7.102 2.739c-3.146 0-5.532-.905-7.098-2.74a3.75 3.75 0 0 1-.898-2.435v-.577a2.249 2.249 0 0 1 2.249-2.25h11.501zm0 1.5H6.253a.749.749 0 0 0-.75.749v.577c0 .536.192 1.054.54 1.461c1.253 1.468 3.219 2.214 5.957 2.214s4.706-.746 5.962-2.214a2.25 2.25 0 0 0 .541-1.463v-.575a.749.749 0 0 0-.749-.75zM12 2.004a5 5 0 1 1 0 10a5 5 0 0 1 0-10zm0 1.5a3.5 3.5 0 1 0 0 7a3.5 3.5 0 0 0 0-7z" fill="currentColor"></path></g></svg>',ji='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" aria-hidden="true" role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" preserveAspectRatio="xMidYMid meet" viewBox="0 0 24 24"><g fill="none"><path d="M16.749 2h4.554l.1.014l.099.028l.06.026c.08.034.153.085.219.15l.04.044l.044.057l.054.09l.039.09l.019.064l.014.064l.009.095v4.532a.75.75 0 0 1-1.493.102l-.007-.102V4.559l-6.44 6.44a.75.75 0 0 1-.976.073L13 11L9.97 8.09l-5.69 5.689a.75.75 0 0 1-1.133-.977l.073-.084l6.22-6.22a.75.75 0 0 1 .976-.072l.084.072l3.03 2.91L19.438 3.5h-2.69a.75.75 0 0 1-.742-.648l-.007-.102a.75.75 0 0 1 .648-.743L16.75 2zM3.75 17a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5a.75.75 0 0 1 .75-.75zm5.75-3.25a.75.75 0 0 0-1.5 0v7.5a.75.75 0 0 0 1.5 0v-7.5zM13.75 15a.75.75 0 0 1 .75.75v5.5a.75.75 0 0 1-1.5 0v-5.5a.75.75 0 0 1 .75-.75zm5.75-4.25a.75.75 0 0 0-1.5 0v10.5a.75.75 0 0 0 1.5 0v-10.5z" fill="currentColor"></path></g></svg>',ki='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" aria-hidden="true" role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" preserveAspectRatio="xMidYMid meet" viewBox="0 0 24 24"><g fill="none"><path d="M12 2c5.523 0 10 4.477 10 10s-4.477 10-10 10a9.96 9.96 0 0 1-4.587-1.112l-3.826 1.067a1.25 1.25 0 0 1-1.54-1.54l1.068-3.823A9.96 9.96 0 0 1 2 12C2 6.477 6.477 2 12 2Zm0 1.5A8.5 8.5 0 0 0 3.5 12c0 1.47.373 2.883 1.073 4.137l.15.27-1.112 3.984 3.987-1.112.27.15A8.5 8.5 0 1 0 12 3.5ZM8.75 13h4.498a.75.75 0 0 1 .102 1.493l-.102.007H8.75a.75.75 0 0 1-.102-1.493L8.75 13h4.498H8.75Zm0-3.5h6.505a.75.75 0 0 1 .101 1.493l-.101.007H8.75a.75.75 0 0 1-.102-1.493L8.75 9.5h6.505H8.75Z" fill="currentColor"/></svg>',Dt='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" aria-hidden="true" role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" preserveAspectRatio="xMidYMid meet" viewBox="0 0 24 24"><g fill="none"><path d="M4 13.999L13 14a2 2 0 0 1 1.995 1.85L15 16v1.5C14.999 21 11.284 22 8.5 22c-2.722 0-6.335-.956-6.495-4.27L2 17.5v-1.501c0-1.054.816-1.918 1.85-1.995L4 14zM15.22 14H20c1.054 0 1.918.816 1.994 1.85L22 16v1c-.001 3.062-2.858 4-5 4a7.16 7.16 0 0 1-2.14-.322c.336-.386.607-.827.802-1.327A6.19 6.19 0 0 0 17 19.5l.267-.006c.985-.043 3.086-.363 3.226-2.289L20.5 17v-1a.501.501 0 0 0-.41-.492L20 15.5h-4.051a2.957 2.957 0 0 0-.595-1.34L15.22 14H20h-4.78zM4 15.499l-.1.01a.51.51 0 0 0-.254.136a.506.506 0 0 0-.136.253l-.01.101V17.5c0 1.009.45 1.722 1.417 2.242c.826.445 2.003.714 3.266.753l.317.005l.317-.005c1.263-.039 2.439-.308 3.266-.753c.906-.488 1.359-1.145 1.412-2.057l.005-.186V16a.501.501 0 0 0-.41-.492L13 15.5l-9-.001zM8.5 3a4.5 4.5 0 1 1 0 9a4.5 4.5 0 0 1 0-9zm9 2a3.5 3.5 0 1 1 0 7a3.5 3.5 0 0 1 0-7zm-9-.5c-1.654 0-3 1.346-3 3s1.346 3 3 3s3-1.346 3-3s-1.346-3-3-3zm9 2c-1.103 0-2 .897-2 2s.897 2 2 2s2-.897 2-2s-.897-2-2-2z" fill="currentColor"></path></g></svg>',Di='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" aria-hidden="true" role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" preserveAspectRatio="xMidYMid meet" viewBox="0 0 24 24"><g fill="none"><path d="M19.75 2A2.25 2.25 0 0 1 22 4.25v5.462a3.25 3.25 0 0 1-.952 2.298l-8.5 8.503a3.255 3.255 0 0 1-4.597.001L3.489 16.06a3.25 3.25 0 0 1-.003-4.596l8.5-8.51A3.25 3.25 0 0 1 14.284 2h5.465zm0 1.5h-5.465c-.465 0-.91.185-1.239.513l-8.512 8.523a1.75 1.75 0 0 0 .015 2.462l4.461 4.454a1.755 1.755 0 0 0 2.477 0l8.5-8.503a1.75 1.75 0 0 0 .513-1.237V4.25a.75.75 0 0 0-.75-.75zM17 5.502a1.5 1.5 0 1 1 0 3a1.5 1.5 0 0 1 0-3z" fill="currentColor"></path></g></svg>',Bi='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" aria-hidden="true" role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" preserveAspectRatio="xMidYMid meet" viewBox="0 0 24 24"><g fill="none"><path d="M6.25 3h11.5a3.25 3.25 0 0 1 3.245 3.066L21 6.25v11.5a3.25 3.25 0 0 1-3.066 3.245L17.75 21H6.25a3.25 3.25 0 0 1-3.245-3.066L3 17.75V6.25a3.25 3.25 0 0 1 3.066-3.245L6.25 3h11.5h-11.5zM4.5 14.5v3.25a1.75 1.75 0 0 0 1.606 1.744l.144.006h11.5a1.75 1.75 0 0 0 1.744-1.607l.006-.143V14.5h-3.825a3.752 3.752 0 0 1-3.475 2.995l-.2.005a3.752 3.752 0 0 1-3.632-2.812l-.043-.188H4.5v3.25v-3.25zm13.25-10H6.25a1.75 1.75 0 0 0-1.744 1.606L4.5 6.25V13H9a.75.75 0 0 1 .743.648l.007.102a2.25 2.25 0 0 0 4.495.154l.005-.154a.75.75 0 0 1 .648-.743L15 13h4.5V6.25a1.75 1.75 0 0 0-1.607-1.744L17.75 4.5z" fill="currentColor"></path></g></svg>',Bt='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" aria-hidden="true" role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" preserveAspectRatio="xMidYMid meet" viewBox="0 0 24 24"><g fill="none"><path d="M14.75 15c.966 0 1.75.784 1.75 1.75l-.001.962c.117 2.19-1.511 3.297-4.432 3.297c-2.91 0-4.567-1.09-4.567-3.259v-1c0-.966.784-1.75 1.75-1.75h5.5zm0 1.5h-5.5a.25.25 0 0 0-.25.25v1c0 1.176.887 1.759 3.067 1.759c2.168 0 2.995-.564 2.933-1.757V16.75a.25.25 0 0 0-.25-.25zm-11-6.5h4.376a4.007 4.007 0 0 0-.095 1.5H3.75a.25.25 0 0 0-.25.25v1c0 1.176.887 1.759 3.067 1.759c.462 0 .863-.026 1.207-.077a2.743 2.743 0 0 0-1.173 1.576l-.034.001C3.657 16.009 2 14.919 2 12.75v-1c0-.966.784-1.75 1.75-1.75zm16.5 0c.966 0 1.75.784 1.75 1.75l-.001.962c.117 2.19-1.511 3.297-4.432 3.297l-.169-.002a2.755 2.755 0 0 0-1.218-1.606c.387.072.847.108 1.387.108c2.168 0 2.995-.564 2.933-1.757V11.75a.25.25 0 0 0-.25-.25h-4.28a4.05 4.05 0 0 0-.096-1.5h4.376zM12 8a3 3 0 1 1 0 6a3 3 0 0 1 0-6zm0 1.5a1.5 1.5 0 1 0 0 3a1.5 1.5 0 0 0 0-3zM6.5 3a3 3 0 1 1 0 6a3 3 0 0 1 0-6zm11 0a3 3 0 1 1 0 6a3 3 0 0 1 0-6zm-11 1.5a1.5 1.5 0 1 0 0 3a1.5 1.5 0 0 0 0-3zm11 0a1.5 1.5 0 1 0 0 3a1.5 1.5 0 0 0 0-3z" fill="currentColor"></path></g></svg>',Ht='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M17.5 12a5.5 5.5 0 1 1 0 11 5.5 5.5 0 0 1 0-11Zm0 2-.09.007a.5.5 0 0 0-.402.402L17 14.5V17L14.498 17l-.09.008a.5.5 0 0 0-.402.402l-.008.09.008.09a.5.5 0 0 0 .402.402l.09.008H17v2.503l.008.09a.5.5 0 0 0 .402.402l.09.008.09-.008a.5.5 0 0 0 .402-.402l.008-.09V18l2.504.001.09-.008a.5.5 0 0 0 .402-.402l.008-.09-.008-.09a.5.5 0 0 0-.403-.402l-.09-.008H18v-2.5l-.008-.09a.5.5 0 0 0-.402-.403L17.5 14Zm-3.246-4c.835 0 1.563.454 1.951 1.13a6.44 6.44 0 0 0-1.518.509.736.736 0 0 0-.433-.139H9.752a.75.75 0 0 0-.75.75v4.249c0 1.41.974 2.594 2.286 2.915a6.42 6.42 0 0 0 .735 1.587l-.02-.001a4.501 4.501 0 0 1-4.501-4.501V12.25A2.25 2.25 0 0 1 9.752 10h4.502Zm-6.848 0a3.243 3.243 0 0 0-.817 1.5H4.25a.75.75 0 0 0-.75.75v2.749a2.501 2.501 0 0 0 3.082 2.433c.085.504.24.985.453 1.432A4.001 4.001 0 0 1 2 14.999V12.25a2.25 2.25 0 0 1 2.096-2.245L4.25 10h3.156Zm12.344 0A2.25 2.25 0 0 1 22 12.25v.56A6.478 6.478 0 0 0 17.5 11l-.245.005A3.21 3.21 0 0 0 16.6 10h3.15ZM18.5 4a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5ZM12 3a3 3 0 1 1 0 6 3 3 0 0 1 0-6ZM5.5 4a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5Zm13 1.5a1 1 0 1 0 0 2 1 1 0 0 0 0-2Zm-6.5-1a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3Zm-6.5 1a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z" fill="currentColor"/></svg>',Hi='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12 1.996a7.49 7.49 0 0 1 7.496 7.25l.004.25v4.097l1.38 3.156a1.25 1.25 0 0 1-1.145 1.75L15 18.502a3 3 0 0 1-5.995.177L9 18.499H4.275a1.251 1.251 0 0 1-1.147-1.747L4.5 13.594V9.496c0-4.155 3.352-7.5 7.5-7.5ZM13.5 18.5l-3 .002a1.5 1.5 0 0 0 2.993.145l.006-.147ZM12 3.496c-3.32 0-6 2.674-6 6v4.41L4.656 17h14.697L18 13.907V9.509l-.004-.225A5.988 5.988 0 0 0 12 3.496Z" fill="currentColor"/></svg>',Pi='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M10.125 13.995a2.737 2.737 0 0 0-.617 1.5h-5.26a.749.749 0 0 0-.748.75v.577c0 .536.191 1.054.539 1.461 1.177 1.379 2.984 2.12 5.469 2.205.049.57.273 1.09.617 1.508h-.129c-3.145 0-5.531-.905-7.098-2.739A3.75 3.75 0 0 1 2 16.822v-.578c0-1.19.925-2.164 2.095-2.243l.154-.006h5.876Zm4.621-2.5h3c.648 0 1.18.492 1.244 1.123l.007.127-.001 1.25h1.25c.967 0 1.75.784 1.75 1.75v4.5a1.75 1.75 0 0 1-1.75 1.75h-8a1.75 1.75 0 0 1-1.75-1.75v-4.5c0-.966.784-1.75 1.75-1.75h1.25v-1.25c0-.647.492-1.18 1.123-1.243l.127-.007h3-3Zm5.5 4h-8a.25.25 0 0 0-.25.25v4.5c0 .138.112.25.25.25h8a.25.25 0 0 0 .25-.25v-4.5a.25.25 0 0 0-.25-.25Zm-2.75-2.5h-2.5v1h2.5v-1ZM9.997 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10Zm0 1.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7Z" fill="currentColor"/></svg>',Zi='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M21 7.511a3.247 3.247 0 0 1 1.5 2.739v6c0 2.9-2.35 5.25-5.25 5.25h-9A3.247 3.247 0 0 1 5.511 20H17.25A3.75 3.75 0 0 0 21 16.25V7.511ZM5.25 4h11.5a3.25 3.25 0 0 1 3.245 3.066L20 7.25v8.5a3.25 3.25 0 0 1-3.066 3.245L16.75 19H5.25a3.25 3.25 0 0 1-3.245-3.066L2 15.75v-8.5a3.25 3.25 0 0 1 3.066-3.245L5.25 4ZM18.5 8.899l-7.15 3.765a.75.75 0 0 1-.603.042l-.096-.042L3.5 8.9v6.85a1.75 1.75 0 0 0 1.606 1.744l.144.006h11.5a1.75 1.75 0 0 0 1.744-1.607l.006-.143V8.899ZM16.75 5.5H5.25a1.75 1.75 0 0 0-1.744 1.606l-.004.1L11 11.152l7.5-3.947A1.75 1.75 0 0 0 16.75 5.5Z" fill="currentColor"/></svg>',Vi='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M19.75 2A2.25 2.25 0 0 1 22 4.25v5.462a3.25 3.25 0 0 1-.952 2.298l-8.5 8.503a3.255 3.255 0 0 1-4.597.001L3.489 16.06a3.25 3.25 0 0 1-.003-4.596l8.5-8.51A3.25 3.25 0 0 1 14.284 2h5.465Zm0 1.5h-5.465c-.465 0-.91.185-1.239.513l-8.512 8.523a1.75 1.75 0 0 0 .015 2.462l4.461 4.454a1.755 1.755 0 0 0 2.477 0l8.5-8.503a1.75 1.75 0 0 0 .513-1.237V4.25a.75.75 0 0 0-.75-.75ZM17 5.502a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Z" fill="currentColor"/></svg>',Ui='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M8.75 3h6.5a.75.75 0 0 1 .743.648L16 3.75V7h1.75A3.25 3.25 0 0 1 21 10.25v6.5A3.25 3.25 0 0 1 17.75 20H6.25A3.25 3.25 0 0 1 3 16.75v-6.5A3.25 3.25 0 0 1 6.25 7H8V3.75a.75.75 0 0 1 .648-.743L8.75 3h6.5-6.5Zm9 5.5H6.25a1.75 1.75 0 0 0-1.75 1.75v6.5c0 .966.784 1.75 1.75 1.75h11.5a1.75 1.75 0 0 0 1.75-1.75v-6.5a1.75 1.75 0 0 0-1.75-1.75Zm-3.25-4h-5V7h5V4.5Z" fill="currentColor"/></svg>',zi='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M6.25 3h11.5a3.25 3.25 0 0 1 3.245 3.066L21 6.25v11.5a3.25 3.25 0 0 1-3.066 3.245L17.75 21H6.25a3.25 3.25 0 0 1-3.245-3.066L3 17.75V6.25a3.25 3.25 0 0 1 3.066-3.245L6.25 3h11.5-11.5ZM4.5 14.5v3.25a1.75 1.75 0 0 0 1.606 1.744l.144.006h11.5a1.75 1.75 0 0 0 1.744-1.607l.006-.143V14.5h-3.825a3.752 3.752 0 0 1-3.475 2.995l-.2.005a3.752 3.752 0 0 1-3.632-2.812l-.043-.188H4.5v3.25-3.25Zm13.25-10H6.25a1.75 1.75 0 0 0-1.744 1.606L4.5 6.25V13H9a.75.75 0 0 1 .743.648l.007.102a2.25 2.25 0 0 0 4.495.154l.005-.154a.75.75 0 0 1 .648-.743L15 13h4.5V6.25a1.75 1.75 0 0 0-1.607-1.744L17.75 4.5Z" fill="currentColor"/></svg>',Gi='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="m18.492 2.33 3.179 3.179a2.25 2.25 0 0 1 0 3.182l-2.584 2.584A2.25 2.25 0 0 1 21 13.5v5.25A2.25 2.25 0 0 1 18.75 21H5.25A2.25 2.25 0 0 1 3 18.75V5.25A2.25 2.25 0 0 1 5.25 3h5.25a2.25 2.25 0 0 1 2.225 1.915L15.31 2.33a2.25 2.25 0 0 1 3.182 0ZM4.5 18.75c0 .414.336.75.75.75l5.999-.001.001-6.75H4.5v6Zm8.249.749h6.001a.75.75 0 0 0 .75-.75V13.5a.75.75 0 0 0-.75-.75h-6.001v6.75Zm-2.249-15H5.25a.75.75 0 0 0-.75.75v6h6.75v-6a.75.75 0 0 0-.75-.75Zm2.25 4.81v1.94h1.94l-1.94-1.94Zm3.62-5.918-3.178 3.178a.75.75 0 0 0 0 1.061l3.179 3.179a.75.75 0 0 0 1.06 0l3.18-3.179a.75.75 0 0 0 0-1.06l-3.18-3.18a.75.75 0 0 0-1.06 0Z" fill="currentColor"/></svg>',Ki='<svg role="img" class="ninja-icon ninja-icon--fluent" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 20 20"><path fill="currentColor" d="M9.562 3.262a.5.5 0 0 1 .879 0l6.5 12a.5.5 0 0 1-.44.739H3.5a.5.5 0 0 1-.44-.739l6.503-12Zm1.758-.477c-.567-1.047-2.07-1.047-2.638 0L2.18 14.786a1.5 1.5 0 0 0 1.32 2.215h13.002a1.5 1.5 0 0 0 1.319-2.215l-6.5-12ZM10.5 7.5a.5.5 0 1 0-1 0v4a.5.5 0 0 0 1 0v-4Zm.25 6.25a.75.75 0 1 1-1.5 0a.75.75 0 0 1 1.5 0Z"/></svg>',Fi=`<svg role="img" class="ninja-icon ninja-icon--fluent" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect width="24" height="24" fill="#FFEBEE"/>
<path d="M8 8.5C8 7.94772 8.44772 7.5 9 7.5C9.55228 7.5 10 7.94772 10 8.5V13C10 13.5523 9.55228 14 9 14C8.44772 14 8 13.5523 8 13V8.5Z" fill="#FF382D"/>
<path d="M8 15.5C8 14.9477 8.44772 14.5 9 14.5C9.55228 14.5 10 14.9477 10 15.5C10 16.0523 9.55228 16.5 9 16.5C8.44772 16.5 8 16.0523 8 15.5Z" fill="#FF382D"/>
<path d="M11 8.5C11 7.94772 11.4477 7.5 12 7.5C12.5523 7.5 13 7.94772 13 8.5V13C13 13.5523 12.5523 14 12 14C11.4477 14 11 13.5523 11 13V8.5Z" fill="#FF382D"/>
<path d="M11 15.5C11 14.9477 11.4477 14.5 12 14.5C12.5523 14.5 13 14.9477 13 15.5C13 16.0523 12.5523 16.5 12 16.5C11.4477 16.5 11 16.0523 11 15.5Z" fill="#FF382D"/>
<path d="M14 8.5C14 7.94772 14.4477 7.5 15 7.5C15.5523 7.5 16 7.94772 16 8.5V13C16 13.5523 15.5523 14 15 14C14.4477 14 14 13.5523 14 13V8.5Z" fill="#FF382D"/>
<path d="M14 15.5C14 14.9477 14.4477 14.5 15 14.5C15.5523 14.5 16 14.9477 16 15.5C16 16.0523 15.5523 16.5 15 16.5C14.4477 16.5 14 16.0523 14 15.5Z" fill="#FF382D"/>
</svg>
`,Yi=`<svg role="img" class="ninja-icon ninja-icon--fluent" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect width="24" height="24" fill="#F1F5F8"/>
<path d="M9.7642 8L9.62358 14.1619H8.25142L8.11506 8H9.7642ZM8.9375 16.821C8.67898 16.821 8.45739 16.7301 8.27273 16.5483C8.09091 16.3665 8 16.1449 8 15.8835C8 15.6278 8.09091 15.4091 8.27273 15.2273C8.45739 15.0455 8.67898 14.9545 8.9375 14.9545C9.19034 14.9545 9.40909 15.0455 9.59375 15.2273C9.78125 15.4091 9.875 15.6278 9.875 15.8835C9.875 16.0568 9.83097 16.2145 9.7429 16.3565C9.65767 16.4986 9.54403 16.6122 9.40199 16.6974C9.26278 16.7798 9.10795 16.821 8.9375 16.821Z" fill="#446888"/>
<path d="M13.1073 8L12.9667 14.1619H11.5945L11.4582 8H13.1073ZM12.2806 16.821C12.0221 16.821 11.8005 16.7301 11.6159 16.5483C11.434 16.3665 11.3431 16.1449 11.3431 15.8835C11.3431 15.6278 11.434 15.4091 11.6159 15.2273C11.8005 15.0455 12.0221 14.9545 12.2806 14.9545C12.5335 14.9545 12.7522 15.0455 12.9369 15.2273C13.1244 15.4091 13.2181 15.6278 13.2181 15.8835C13.2181 16.0568 13.1741 16.2145 13.086 16.3565C13.0008 16.4986 12.8872 16.6122 12.7451 16.6974C12.6059 16.7798 12.4511 16.821 12.2806 16.821Z" fill="#446888"/>
<path d="M16.4505 8L16.3098 14.1619H14.9377L14.8013 8H16.4505ZM15.6237 16.821C15.3652 16.821 15.1436 16.7301 14.959 16.5483C14.7772 16.3665 14.6862 16.1449 14.6862 15.8835C14.6862 15.6278 14.7772 15.4091 14.959 15.2273C15.1436 15.0455 15.3652 14.9545 15.6237 14.9545C15.8766 14.9545 16.0953 15.0455 16.28 15.2273C16.4675 15.4091 16.5612 15.6278 16.5612 15.8835C16.5612 16.0568 16.5172 16.2145 16.4291 16.3565C16.3439 16.4986 16.2303 16.6122 16.0882 16.6974C15.949 16.7798 15.7942 16.821 15.6237 16.821Z" fill="#446888"/>
</svg>`,Wi=`<svg role="img" class="ninja-icon ninja-icon--fluent" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect width="24" height="24" fill="#F1F5F8"/>
<path d="M10.7642 8L10.6236 14.1619H9.25142L9.11506 8H10.7642ZM9.9375 16.821C9.67898 16.821 9.45739 16.7301 9.27273 16.5483C9.09091 16.3665 9 16.1449 9 15.8835C9 15.6278 9.09091 15.4091 9.27273 15.2273C9.45739 15.0455 9.67898 14.9545 9.9375 14.9545C10.1903 14.9545 10.4091 15.0455 10.5938 15.2273C10.7812 15.4091 10.875 15.6278 10.875 15.8835C10.875 16.0568 10.831 16.2145 10.7429 16.3565C10.6577 16.4986 10.544 16.6122 10.402 16.6974C10.2628 16.7798 10.108 16.821 9.9375 16.821Z" fill="#446888"/>
<path d="M14.1073 8L13.9667 14.1619H12.5945L12.4582 8H14.1073ZM13.2806 16.821C13.0221 16.821 12.8005 16.7301 12.6159 16.5483C12.434 16.3665 12.3431 16.1449 12.3431 15.8835C12.3431 15.6278 12.434 15.4091 12.6159 15.2273C12.8005 15.0455 13.0221 14.9545 13.2806 14.9545C13.5335 14.9545 13.7522 15.0455 13.9369 15.2273C14.1244 15.4091 14.2181 15.6278 14.2181 15.8835C14.2181 16.0568 14.1741 16.2145 14.086 16.3565C14.0008 16.4986 13.8872 16.6122 13.7451 16.6974C13.6059 16.7798 13.4511 16.821 13.2806 16.821Z" fill="#446888"/>
</svg>`,Xi=`<svg role="img" class="ninja-icon ninja-icon--fluent" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect width="24" height="24" fill="#F1F5F8"/>
<path d="M12.7642 8L12.6236 14.1619H11.2514L11.1151 8H12.7642ZM11.9375 16.821C11.679 16.821 11.4574 16.7301 11.2727 16.5483C11.0909 16.3665 11 16.1449 11 15.8835C11 15.6278 11.0909 15.4091 11.2727 15.2273C11.4574 15.0455 11.679 14.9545 11.9375 14.9545C12.1903 14.9545 12.4091 15.0455 12.5938 15.2273C12.7812 15.4091 12.875 15.6278 12.875 15.8835C12.875 16.0568 12.831 16.2145 12.7429 16.3565C12.6577 16.4986 12.544 16.6122 12.402 16.6974C12.2628 16.7798 12.108 16.821 11.9375 16.821Z" fill="#446888"/>
</svg>`,Ji=`<svg role="img" class="ninja-icon ninja-icon--fluent" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect width="24" height="24" fill="#F1F5F8"/>
<path d="M13.5686 8L11.1579 16.9562H10L12.4107 8H13.5686Z" fill="#446888"/>
</svg>`,de='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="m13.314 7.565l-.136.126l-10.48 10.488a2.27 2.27 0 0 0 3.211 3.208L16.388 10.9a2.251 2.251 0 0 0-.001-3.182l-.157-.146a2.25 2.25 0 0 0-2.916-.007Zm-.848 2.961l1.088 1.088l-8.706 8.713a.77.77 0 1 1-1.089-1.088l8.707-8.713Zm4.386 4.48L16.75 15a.75.75 0 0 0-.743.648L16 15.75v.75h-.75a.75.75 0 0 0-.743.648l-.007.102c0 .38.282.694.648.743l.102.007H16v.75c0 .38.282.694.648.743l.102.007a.75.75 0 0 0 .743-.648l.007-.102V18h.75a.75.75 0 0 0 .743-.648L19 17.25a.75.75 0 0 0-.648-.743l-.102-.007h-.75v-.75a.75.75 0 0 0-.648-.743L16.75 15l.102.007Zm-1.553-6.254l.027.027a.751.751 0 0 1 0 1.061l-.711.713l-1.089-1.089l.73-.73a.75.75 0 0 1 1.043.018ZM6.852 5.007L6.75 5a.75.75 0 0 0-.743.648L6 5.75v.75h-.75a.75.75 0 0 0-.743.648L4.5 7.25c0 .38.282.693.648.743L5.25 8H6v.75c0 .38.282.693.648.743l.102.007a.75.75 0 0 0 .743-.648L7.5 8.75V8h.75a.75.75 0 0 0 .743-.648L9 7.25a.75.75 0 0 0-.648-.743L8.25 6.5H7.5v-.75a.75.75 0 0 0-.648-.743L6.75 5l.102.007Zm12-2L18.75 3a.75.75 0 0 0-.743.648L18 3.75v.75h-.75a.75.75 0 0 0-.743.648l-.007.102c0 .38.282.693.648.743L17.25 6H18v.75c0 .38.282.693.648.743l.102.007a.75.75 0 0 0 .743-.648l.007-.102V6h.75a.75.75 0 0 0 .743-.648L21 5.25a.75.75 0 0 0-.648-.743L20.25 4.5h-.75v-.75a.75.75 0 0 0-.648-.743L18.75 3l.102.007Z" fill="currentColor"/></svg>',qi='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M4 4.5A2.5 2.5 0 0 1 6.5 2H18a2.5 2.5 0 0 1 2.5 2.5v14.25a.75.75 0 0 1-.75.75H5.5a1 1 0 0 0 1 1h13.25a.75.75 0 0 1 0 1.5H6.5A2.5 2.5 0 0 1 4 19.5v-15ZM5.5 18H19V4.5a1 1 0 0 0-1-1H6.5a1 1 0 0 0-1 1V18Z" fill="currentColor"/></svg>',Qi='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M6.75 19.5h14.5a.75.75 0 0 0 .102-1.493L21.25 18H6.75a.75.75 0 0 0-.102 1.493l.102.007Zm0-15h14.5a.75.75 0 0 0 .102-1.493L21.25 3H6.75a.75.75 0 0 0-.102 1.493l.102.007Zm7 3.5a.75.75 0 0 0 0 1.5h7.5a.75.75 0 0 0 0-1.5h-7.5ZM13 13.75a.75.75 0 0 1 .75-.75h7.5a.75.75 0 0 1 0 1.5h-7.5a.75.75 0 0 1-.75-.75Zm-2-2.25a4.5 4.5 0 1 1-9 0a4.5 4.5 0 0 1 9 0Zm-4-2a.5.5 0 0 0-1 0V11H4.5a.5.5 0 0 0 0 1H6v1.5a.5.5 0 0 0 1 0V12h1.5a.5.5 0 0 0 0-1H7V9.5Z" fill="currentColor"/></svg>',e1='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M6.75 4.5h14.5a.75.75 0 0 0 .102-1.493L21.25 3H6.75a.75.75 0 0 0-.102 1.493l.102.007Zm0 15h14.5a.75.75 0 0 0 .102-1.493L21.25 18H6.75a.75.75 0 0 0-.102 1.493l.102.007Zm7-11.5a.75.75 0 0 0 0 1.5h7.5a.75.75 0 0 0 0-1.5h-7.5ZM13 13.75a.75.75 0 0 1 .75-.75h7.5a.75.75 0 0 1 0 1.5h-7.5a.75.75 0 0 1-.75-.75Zm-2-2.25a4.5 4.5 0 1 1-9 0a4.5 4.5 0 0 1 9 0Zm-2 0a.5.5 0 0 0-.5-.5h-4a.5.5 0 0 0 0 1h4a.5.5 0 0 0 .5-.5Z" fill="currentColor"/></svg>',t1='<svg role="img" class="ninja-icon ninja-icon--fluent" width="18" height="18" fill="none" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M3 17h7.522l-2 2H3a1 1 0 0 1-.117-1.993L3 17Zm0-2h7.848a1.75 1.75 0 0 1-.775-2H3l-.117.007A1 1 0 0 0 3 15Zm0-8h18l.117-.007A1 1 0 0 0 21 5H3l-.117.007A1 1 0 0 0 3 7Zm9.72 9.216a.75.75 0 1 1 1.06 1.06l-4.5 4.5a.75.75 0 1 1-1.06-1.06l4.5-4.5ZM3 9h10a1 1 0 0 1 .117 1.993L13 11H3a1 1 0 0 1-.117-1.993L3 9Zm13.5-1a.75.75 0 0 1 .744.658l.14 1.13a3.25 3.25 0 0 0 2.828 2.829l1.13.139a.75.75 0 0 1 0 1.488l-1.13.14a3.25 3.25 0 0 0-2.829 2.828l-.139 1.13a.75.75 0 0 1-1.488 0l-.14-1.13a3.25 3.25 0 0 0-2.828-2.829l-1.13-.139a.75.75 0 0 1 0-1.488l1.13-.14a3.25 3.25 0 0 0 2.829-2.828l.139-1.13A.75.75 0 0 1 16.5 8Z" fill="currentColor"/></svg>',n1='<svg role="img" class="ninja-icon ninja-icon--fluent" xmlns="http://www.w3.org/2000/svg" width="18" height="18"viewBox="0 0 24 24"><path fill="currentColor" d="M3.839 5.858c2.94-3.916 9.03-5.055 13.364-2.36c4.28 2.66 5.854 7.777 4.1 12.577c-1.655 4.533-6.016 6.328-9.159 4.048c-1.177-.854-1.634-1.925-1.854-3.664l-.106-.987l-.045-.398c-.123-.934-.311-1.352-.705-1.572c-.535-.298-.892-.305-1.595-.033l-.351.146l-.179.078c-1.014.44-1.688.595-2.541.416l-.2-.047l-.164-.047c-2.789-.864-3.202-4.647-.565-8.157Zm.984 6.716l.123.037l.134.03c.439.087.814.015 1.437-.242l.602-.257c1.202-.493 1.985-.54 3.046.05c.917.512 1.275 1.298 1.457 2.66l.053.459l.055.532l.047.422c.172 1.361.485 2.09 1.248 2.644c2.275 1.65 5.534.309 6.87-3.349c1.516-4.152.174-8.514-3.484-10.789c-3.675-2.284-8.899-1.306-11.373 1.987c-2.075 2.763-1.82 5.28-.215 5.816Zm11.225-1.994a1.25 1.25 0 1 1 2.414-.647a1.25 1.25 0 0 1-2.414.647Zm.494 3.488a1.25 1.25 0 1 1 2.415-.647a1.25 1.25 0 0 1-2.415.647ZM14.07 7.577a1.25 1.25 0 1 1 2.415-.647a1.25 1.25 0 0 1-2.415.647Zm-.028 8.998a1.25 1.25 0 1 1 2.414-.647a1.25 1.25 0 0 1-2.414.647Zm-3.497-9.97a1.25 1.25 0 1 1 2.415-.646a1.25 1.25 0 0 1-2.415.646Z"/></svg>',i1='<svg role="img" class="ninja-icon ninja-icon--fluent" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="currentColor" d="M12 2a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 12 2Zm5 10a5 5 0 1 1-10 0a5 5 0 0 1 10 0Zm4.25.75a.75.75 0 0 0 0-1.5h-1.5a.75.75 0 0 0 0 1.5h1.5ZM12 19a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 12 19Zm-7.75-6.25a.75.75 0 0 0 0-1.5h-1.5a.75.75 0 0 0 0 1.5h1.5Zm-.03-8.53a.75.75 0 0 1 1.06 0l1.5 1.5a.75.75 0 0 1-1.06 1.06l-1.5-1.5a.75.75 0 0 1 0-1.06Zm1.06 15.56a.75.75 0 1 1-1.06-1.06l1.5-1.5a.75.75 0 1 1 1.06 1.06l-1.5 1.5Zm14.5-15.56a.75.75 0 0 0-1.06 0l-1.5 1.5a.75.75 0 0 0 1.06 1.06l1.5-1.5a.75.75 0 0 0 0-1.06Zm-1.06 15.56a.75.75 0 1 0 1.06-1.06l-1.5-1.5a.75.75 0 1 0-1.06 1.06l1.5 1.5Z"/></svg>',o1='<svg role="img" class="ninja-icon ninja-icon--fluent" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="currentColor" d="M20.026 17.001c-2.762 4.784-8.879 6.423-13.663 3.661A9.965 9.965 0 0 1 3.13 17.68a.75.75 0 0 1 .365-1.132c3.767-1.348 5.785-2.91 6.956-5.146c1.232-2.353 1.551-4.93.689-8.463a.75.75 0 0 1 .769-.927a9.961 9.961 0 0 1 4.457 1.327c4.784 2.762 6.423 8.879 3.66 13.662Zm-8.248-4.903c-1.25 2.389-3.31 4.1-6.817 5.499a8.49 8.49 0 0 0 2.152 1.766a8.502 8.502 0 0 0 8.502-14.725a8.484 8.484 0 0 0-2.792-1.015c.647 3.384.23 6.043-1.045 8.475Z"/></svg>',s1='<svg role="img" class="ninja-icon ninja-icon--fluent" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="currentColor" d="M4.25 3A2.25 2.25 0 0 0 2 5.25v10.5A2.25 2.25 0 0 0 4.25 18H9.5v1.25c0 .69-.56 1.25-1.25 1.25h-.5a.75.75 0 0 0 0 1.5h8.5a.75.75 0 0 0 0-1.5h-.5c-.69 0-1.25-.56-1.25-1.25V18h5.25A2.25 2.25 0 0 0 22 15.75V5.25A2.25 2.25 0 0 0 19.75 3H4.25ZM13 18v1.25c0 .45.108.875.3 1.25h-2.6c.192-.375.3-.8.3-1.25V18h2ZM3.5 5.25a.75.75 0 0 1 .75-.75h15.5a.75.75 0 0 1 .75.75V13h-17V5.25Zm0 9.25h17v1.25a.75.75 0 0 1-.75.75H4.25a.75.75 0 0 1-.75-.75V14.5Z"/></svg>',ee='<svg role="img" class="ninja-icon ninja-icon--fluent" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="currentColor" d="M12 3.5c-3.104 0-6 2.432-6 6.25v4.153L4.682 17h14.67l-1.354-3.093V11.75a.75.75 0 0 1 1.5 0v1.843l1.381 3.156a1.25 1.25 0 0 1-1.145 1.751H15a3.002 3.002 0 0 1-6.003 0H4.305a1.25 1.25 0 0 1-1.15-1.739l1.344-3.164V9.75C4.5 5.068 8.103 2 12 2c.86 0 1.705.15 2.5.432a.75.75 0 0 1-.502 1.413A5.964 5.964 0 0 0 12 3.5ZM12 20c.828 0 1.5-.671 1.501-1.5h-3.003c0 .829.673 1.5 1.502 1.5Zm3.25-13h-2.5l-.101.007A.75.75 0 0 0 12.75 8.5h1.043l-1.653 2.314l-.055.09A.75.75 0 0 0 12.75 12h2.5l.102-.007a.75.75 0 0 0-.102-1.493h-1.042l1.653-2.314l.055-.09A.75.75 0 0 0 15.25 7Zm6-5h-3.5l-.101.007A.75.75 0 0 0 17.75 3.5h2.134l-2.766 4.347l-.05.09A.75.75 0 0 0 17.75 9h3.5l.102-.007A.75.75 0 0 0 21.25 7.5h-2.133l2.766-4.347l.05-.09A.75.75 0 0 0 21.25 2Z"/></svg>',a1=t=>[{key:"light",label:t("COMMAND_BAR.COMMANDS.LIGHT_MODE"),icon:i1},{key:"dark",label:t("COMMAND_BAR.COMMANDS.DARK_MODE"),icon:o1},{key:"auto",label:t("COMMAND_BAR.COMMANDS.SYSTEM_MODE"),icon:s1}],l1=t=>{kn.set(Bn.COLOR_SCHEME,t);const e=window.matchMedia("(prefers-color-scheme: dark)").matches;Nn(e),document.documentElement.setAttribute("data-theme",document.body.classList.contains("dark")?"dark":"light")};function r1(){const{t}=se(),e=O(()=>a1(t));return{goToAppearanceHotKeys:O(()=>{const i=e.value.map(o=>({id:o.key,title:o.label,parent:"appearance_settings",section:t("COMMAND_BAR.SECTIONS.APPEARANCE"),icon:o.icon,handler:()=>{l1(o.key)}}));return[{id:"appearance_settings",title:t("COMMAND_BAR.COMMANDS.CHANGE_APPEARANCE"),section:t("COMMAND_BAR.SECTIONS.APPEARANCE"),icon:n1,children:i.map(o=>o.id)},...i]})}}const B=U.SNOOZE_OPTIONS,ce=t=>()=>P.emit(Ut,t),c1=[{id:"snooze_notification",title:"COMMAND_BAR.COMMANDS.SNOOZE_NOTIFICATION",icon:ee,children:Object.values(B)},{id:B.AN_HOUR_FROM_NOW,title:"COMMAND_BAR.COMMANDS.AN_HOUR_FROM_NOW",parent:"snooze_notification",section:"COMMAND_BAR.SECTIONS.SNOOZE_NOTIFICATION",icon:ee,handler:ce(B.AN_HOUR_FROM_NOW)},{id:B.UNTIL_TOMORROW,title:"COMMAND_BAR.COMMANDS.UNTIL_TOMORROW",section:"COMMAND_BAR.SECTIONS.SNOOZE_NOTIFICATION",parent:"snooze_notification",icon:ee,handler:ce(B.UNTIL_TOMORROW)},{id:B.UNTIL_NEXT_WEEK,title:"COMMAND_BAR.COMMANDS.UNTIL_NEXT_WEEK",section:"COMMAND_BAR.SECTIONS.SNOOZE_NOTIFICATION",parent:"snooze_notification",icon:ee,handler:ce(B.UNTIL_NEXT_WEEK)},{id:B.UNTIL_NEXT_MONTH,title:"COMMAND_BAR.COMMANDS.UNTIL_NEXT_MONTH",section:"COMMAND_BAR.SECTIONS.SNOOZE_NOTIFICATION",parent:"snooze_notification",icon:ee,handler:ce(B.UNTIL_NEXT_MONTH)},{id:B.UNTIL_CUSTOM_TIME,title:"COMMAND_BAR.COMMANDS.UNTIL_CUSTOM_TIME",section:"COMMAND_BAR.SECTIONS.SNOOZE_NOTIFICATION",parent:"snooze_notification",icon:ee,handler:ce(B.UNTIL_CUSTOM_TIME)}];function h1(){const{t}=se(),e=Kt(),n=o=>o.map(s=>({...s,title:t(s.title),section:s.section?t(s.section):void 0}));return{inboxHotKeys:O(()=>Vt(e.name)?n(c1):[])}}const d1=[{id:"goto_conversation_dashboard",title:"COMMAND_BAR.COMMANDS.GO_TO_CONVERSATION_DASHBOARD",section:"COMMAND_BAR.SECTIONS.GENERAL",icon:xi,path:t=>`accounts/${t}/dashboard`,role:["administrator","agent"]},{id:"goto_contacts_dashboard",title:"COMMAND_BAR.COMMANDS.GO_TO_CONTACTS_DASHBOARD",section:"COMMAND_BAR.SECTIONS.GENERAL",featureFlag:x.CRM,icon:Li,path:t=>`accounts/${t}/contacts`,role:["administrator","agent"]},{id:"open_reports_overview",section:"COMMAND_BAR.SECTIONS.REPORTS",title:"COMMAND_BAR.COMMANDS.GO_TO_REPORTS_OVERVIEW",featureFlag:x.REPORTS,icon:ji,path:t=>`accounts/${t}/reports/overview`,role:["administrator"]},{id:"open_conversation_reports",section:"COMMAND_BAR.SECTIONS.REPORTS",title:"COMMAND_BAR.COMMANDS.GO_TO_CONVERSATION_REPORTS",featureFlag:x.REPORTS,icon:ki,path:t=>`accounts/${t}/reports/conversation`,role:["administrator"]},{id:"open_agent_reports",section:"COMMAND_BAR.SECTIONS.REPORTS",title:"COMMAND_BAR.COMMANDS.GO_TO_AGENT_REPORTS",featureFlag:x.REPORTS,icon:Dt,path:t=>`accounts/${t}/reports/agent`,role:["administrator"]},{id:"open_label_reports",section:"COMMAND_BAR.SECTIONS.REPORTS",title:"COMMAND_BAR.COMMANDS.GO_TO_LABEL_REPORTS",featureFlag:x.REPORTS,icon:Di,path:t=>`accounts/${t}/reports/label`,role:["administrator"]},{id:"open_inbox_reports",section:"COMMAND_BAR.SECTIONS.REPORTS",title:"COMMAND_BAR.COMMANDS.GO_TO_INBOX_REPORTS",featureFlag:x.REPORTS,icon:Bi,path:t=>`accounts/${t}/reports/inboxes`,role:["administrator"]},{id:"open_team_reports",section:"COMMAND_BAR.SECTIONS.REPORTS",title:"COMMAND_BAR.COMMANDS.GO_TO_TEAM_REPORTS",featureFlag:x.REPORTS,icon:Bt,path:t=>`accounts/${t}/reports/teams`,role:["administrator"]},{id:"open_agent_settings",section:"COMMAND_BAR.SECTIONS.SETTINGS",title:"COMMAND_BAR.COMMANDS.GO_TO_SETTINGS_AGENTS",featureFlag:x.AGENT_MANAGEMENT,icon:Dt,path:t=>`accounts/${t}/settings/agents/list`,role:["administrator"]},{id:"open_team_settings",title:"COMMAND_BAR.COMMANDS.GO_TO_SETTINGS_TEAMS",featureFlag:x.TEAM_MANAGEMENT,section:"COMMAND_BAR.SECTIONS.SETTINGS",icon:Bt,path:t=>`accounts/${t}/settings/teams/list`,role:["administrator"]},{id:"open_inbox_settings",title:"COMMAND_BAR.COMMANDS.GO_TO_SETTINGS_INBOXES",featureFlag:x.INBOX_MANAGEMENT,section:"COMMAND_BAR.SECTIONS.SETTINGS",icon:zi,path:t=>`accounts/${t}/settings/inboxes/list`,role:["administrator"]},{id:"open_label_settings",title:"COMMAND_BAR.COMMANDS.GO_TO_SETTINGS_LABELS",featureFlag:x.LABELS,section:"COMMAND_BAR.SECTIONS.SETTINGS",icon:Vi,path:t=>`accounts/${t}/settings/labels/list`,role:["administrator"]},{id:"open_canned_response_settings",title:"COMMAND_BAR.COMMANDS.GO_TO_SETTINGS_CANNED_RESPONSES",featureFlag:x.CANNED_RESPONSES,section:"COMMAND_BAR.SECTIONS.SETTINGS",icon:Zi,path:t=>`accounts/${t}/settings/canned-response/list`,role:["administrator","agent"]},{id:"open_applications_settings",title:"COMMAND_BAR.COMMANDS.GO_TO_SETTINGS_APPLICATIONS",featureFlag:x.INTEGRATIONS,section:"COMMAND_BAR.SECTIONS.SETTINGS",icon:Gi,path:t=>`accounts/${t}/settings/applications`,role:["administrator"]},{id:"open_account_settings",title:"COMMAND_BAR.COMMANDS.GO_TO_SETTINGS_ACCOUNT",section:"COMMAND_BAR.SECTIONS.SETTINGS",icon:Ui,path:t=>`accounts/${t}/settings/general`,role:["administrator"]},{id:"open_profile_settings",title:"COMMAND_BAR.COMMANDS.GO_TO_SETTINGS_PROFILE",section:"COMMAND_BAR.SECTIONS.SETTINGS",icon:Pi,path:t=>`accounts/${t}/profile/settings`,role:["administrator","agent"]},{id:"open_notifications",title:"COMMAND_BAR.COMMANDS.GO_TO_NOTIFICATIONS",section:"COMMAND_BAR.SECTIONS.SETTINGS",icon:Hi,path:t=>`accounts/${t}/notifications`,role:["administrator","agent"]}];function u1(){const{t}=se(),e=Dn(),{isAdmin:n}=Cn(),i=Z("getCurrentAccountId"),o=Z("accounts/isFeatureEnabledonAccount"),s=l=>{e.push(Hn(l))};return{goToCommandHotKeys:O(()=>{let l=d1.filter(r=>r.featureFlag?o.value(i.value,r.featureFlag):!0);return n.value||(l=l.filter(r=>r.role.includes("agent"))),l.map(r=>({id:r.id,section:t(r.section),title:t(r.title),icon:r.icon,handler:()=>s(r.path(i.value))}))})}}const pn=U.SNOOZE_OPTIONS,p1=[{id:"resolve_conversation",title:"COMMAND_BAR.COMMANDS.RESOLVE_CONVERSATION",section:"COMMAND_BAR.SECTIONS.CONVERSATION",icon:un,handler:()=>P.emit(wn)}],vn=(t,e,n)=>Object.values(pn).map(i=>({id:i,title:`COMMAND_BAR.COMMANDS.${i.toUpperCase()}`,parent:e,section:n,icon:xe,handler:()=>P.emit(t,i)})),Pt=[{id:"snooze_conversation",title:"COMMAND_BAR.COMMANDS.SNOOZE_CONVERSATION",section:"COMMAND_BAR.SECTIONS.CONVERSATION",icon:xe,children:Object.values(pn)},...vn(zt,"snooze_conversation","COMMAND_BAR.SECTIONS.SNOOZE_CONVERSATION")],v1=[{id:"reopen_conversation",title:"COMMAND_BAR.COMMANDS.REOPEN_CONVERSATION",section:"COMMAND_BAR.SECTIONS.CONVERSATION",icon:dn,handler:()=>P.emit(Tn)}],f1={id:"send_transcript",title:"COMMAND_BAR.COMMANDS.SEND_TRANSCRIPT",section:"COMMAND_BAR.SECTIONS.CONVERSATION",icon:$i,handler:()=>P.emit(En)},_1={id:"unmute_conversation",title:"COMMAND_BAR.COMMANDS.UNMUTE_CONVERSATION",section:"COMMAND_BAR.SECTIONS.CONVERSATION",icon:Ri,handler:()=>P.emit(Sn)},A1={id:"mute_conversation",title:"COMMAND_BAR.COMMANDS.MUTE_CONVERSATION",section:"COMMAND_BAR.SECTIONS.CONVERSATION",icon:bi,handler:()=>P.emit(Mn)},O1=U.SNOOZE_OPTIONS,fn=t=>()=>P.emit(t),g1=[{id:"bulk_action_snooze_conversation",title:"COMMAND_BAR.COMMANDS.SNOOZE_CONVERSATION",section:"COMMAND_BAR.SECTIONS.BULK_ACTIONS",icon:xe,children:Object.values(O1)},...vn(Gt,"bulk_action_snooze_conversation","COMMAND_BAR.SECTIONS.BULK_ACTIONS")],m1=[{id:"bulk_action_reopen_conversation",title:"COMMAND_BAR.COMMANDS.REOPEN_CONVERSATION",section:"COMMAND_BAR.SECTIONS.BULK_ACTIONS",icon:dn,handler:fn(yn)}],N1=[{id:"bulk_action_resolve_conversation",title:"COMMAND_BAR.COMMANDS.RESOLVE_CONVERSATION",section:"COMMAND_BAR.SECTIONS.BULK_ACTIONS",icon:un,handler:fn(In)}];function C1(){const{t}=se(),e=Z("bulkActions/getSelectedConversationIds"),n=o=>o.map(s=>({...s,title:t(s.title),section:t(s.section)}));return{bulkActionsHotKeys:O(()=>{let o=[];return e.value.length>0&&(o=[...g1,...m1,...N1]),n(o)})}}const nt=(t,e)=>t.map(n=>({...n,title:e(n.title),section:e(n.section)})),S1=(t,e)=>[{label:t("CONVERSATION.PRIORITY.OPTIONS.NONE"),key:null,icon:Ji},{label:t("CONVERSATION.PRIORITY.OPTIONS.URGENT"),key:"urgent",icon:Fi},{label:t("CONVERSATION.PRIORITY.OPTIONS.HIGH"),key:"high",icon:Yi},{label:t("CONVERSATION.PRIORITY.OPTIONS.MEDIUM"),key:"medium",icon:Wi},{label:t("CONVERSATION.PRIORITY.OPTIONS.LOW"),key:"low",icon:Xi}].filter(n=>n.key!==e),M1=(t,e)=>e===Pn.REPLY?[{label:t("INTEGRATION_SETTINGS.OPEN_AI.OPTIONS.REPLY_SUGGESTION"),key:"reply_suggestion",icon:de}]:[{label:t("INTEGRATION_SETTINGS.OPEN_AI.OPTIONS.SUMMARIZE"),key:"summarize",icon:qi}],E1=t=>[{label:t("INTEGRATION_SETTINGS.OPEN_AI.OPTIONS.CONFIDENT"),key:"confident",icon:de},{label:t("INTEGRATION_SETTINGS.OPEN_AI.OPTIONS.FIX_SPELLING_GRAMMAR"),key:"fix_spelling_grammar",icon:t1},{label:t("INTEGRATION_SETTINGS.OPEN_AI.OPTIONS.PROFESSIONAL"),key:"professional",icon:Qi},{label:t("INTEGRATION_SETTINGS.OPEN_AI.OPTIONS.CASUAL"),key:"casual",icon:e1},{label:t("INTEGRATION_SETTINGS.OPEN_AI.OPTIONS.MAKE_FRIENDLY"),key:"friendly",icon:de},{label:t("INTEGRATION_SETTINGS.OPEN_AI.OPTIONS.STRAIGHTFORWARD"),key:"straightforward",icon:de}];function w1(){const{t}=se(),e=Zt(),n=Kt(),{activeLabels:i,inactiveLabels:o,addLabelToConversation:s,removeLabelFromConversation:a}=bn(),{captainTasksEnabled:l}=Rn(),{agentsList:r}=$n(),c=Z("getSelectedChat"),d=Z("draftMessages/getReplyEditorMode"),p=Z("getContextMenuChatId"),h=Z("teams/getTeams"),v=Z("draftMessages/get"),u=O(()=>{var A;return(A=c.value)==null?void 0:A.id}),_=O(()=>`draft-${u.value}-${d.value}`),R=O(()=>v.value(_.value)),K=O(()=>{var A,f;return!!((f=(A=c.value)==null?void 0:A.meta)!=null&&f.team)}),F=O(()=>K.value?[{id:0,name:t("TEAMS_SETTINGS.LIST.NONE")},...h.value]:h.value),ge=A=>{e.dispatch("assignAgent",{conversationId:c.value.id,agentId:A.agentInfo.id})},Le=A=>{e.dispatch("assignPriority",{conversationId:c.value.id,priority:A.priority.key})},je=A=>{e.dispatch("assignTeam",{conversationId:c.value.id,teamId:A.teamInfo.id})},ke=O(()=>{var ut,pt,vt;const A=((ut=c.value)==null?void 0:ut.status)===U.STATUS_TYPE.OPEN,f=((pt=c.value)==null?void 0:pt.status)===U.STATUS_TYPE.SNOOZED,$=((vt=c.value)==null?void 0:vt.status)===U.STATUS_TYPE.RESOLVED;let Ze=[];return A?Ze=[...p1,...Pt]:($||f)&&(Ze=v1),nt(Ze,t)}),De=O(()=>{var A;return S1(t,(A=c.value)==null?void 0:A.priority)}),me=O(()=>{const A=r.value.map(f=>({id:`agent-${f.id}`,title:f.name,parent:"assign_an_agent",section:t("COMMAND_BAR.SECTIONS.CHANGE_ASSIGNEE"),agentInfo:f,icon:jt,handler:ge}));return[{id:"assign_an_agent",title:t("COMMAND_BAR.COMMANDS.ASSIGN_AN_AGENT"),section:t("COMMAND_BAR.SECTIONS.CONVERSATION"),icon:jt,children:A.map(f=>f.id)},...A]}),Be=O(()=>{const A=De.value.map(f=>({id:`priority-${f.key}`,title:f.label,parent:"assign_priority",section:t("COMMAND_BAR.SECTIONS.CHANGE_PRIORITY"),priority:f,icon:f.icon,handler:Le}));return[{id:"assign_priority",title:t("COMMAND_BAR.COMMANDS.ASSIGN_PRIORITY"),section:t("COMMAND_BAR.SECTIONS.CONVERSATION"),icon:Ki,children:A.map(f=>f.id)},...A]}),He=O(()=>{const A=F.value.map(f=>({id:`team-${f.id}`,title:f.name,parent:"assign_a_team",section:t("COMMAND_BAR.SECTIONS.CHANGE_TEAM"),teamInfo:f,icon:Ht,handler:je}));return[{id:"assign_a_team",title:t("COMMAND_BAR.COMMANDS.ASSIGN_A_TEAM"),section:t("COMMAND_BAR.SECTIONS.CONVERSATION"),icon:Ht,children:A.map(f=>f.id)},...A]}),Ne=O(()=>[...o.value.map(f=>({id:f.title,title:`#${f.title}`,parent:"add_a_label_to_the_conversation",section:t("COMMAND_BAR.SECTIONS.ADD_LABEL"),icon:Lt,handler:$=>s({title:$.id})})),{id:"add_a_label_to_the_conversation",title:t("COMMAND_BAR.COMMANDS.ADD_LABELS_TO_CONVERSATION"),section:t("COMMAND_BAR.SECTIONS.CONVERSATION"),icon:Lt,children:o.value.map(f=>f.title)}]),Pe=O(()=>[...i.value.map(f=>({id:f.title,title:`#${f.title}`,parent:"remove_a_label_to_the_conversation",section:t("COMMAND_BAR.SECTIONS.REMOVE_LABEL"),icon:kt,handler:$=>a($.id)})),{id:"remove_a_label_to_the_conversation",title:t("COMMAND_BAR.COMMANDS.REMOVE_LABEL_FROM_CONVERSATION"),section:t("COMMAND_BAR.SECTIONS.CONVERSATION"),icon:kt,children:i.value.map(f=>f.title)}]),g=O(()=>i.value.length?[...Ne.value,...Pe.value]:Ne.value),I=O(()=>nt([c.value.muted?_1:A1,f1],t)),j=O(()=>{const f=(R.value?E1(t):M1(t,d.value)).map($=>({id:`ai-assist-${$.key}`,title:$.label,parent:"ai_assist",section:t("COMMAND_BAR.SECTIONS.AI_ASSIST"),priority:$,icon:$.icon,handler:()=>P.emit(xn,$.key)}));return[{id:"ai_assist",title:t("COMMAND_BAR.COMMANDS.AI_ASSIST"),section:t("COMMAND_BAR.SECTIONS.AI_ASSIST"),icon:de,children:f.map($=>$.id)},...f]}),b=O(()=>_t(n.name)||Vt(n.name)),k=O(()=>_t(n.name,!0,!1)&&p.value),D=O(()=>{const A=[...ke.value,...I.value,...me.value,...He.value,...g.value,...Be.value];return l.value?[...A,...j.value]:A});return{conversationHotKeys:O(()=>k.value?nt(Pt,t):b.value?D.value:[])}}const T1=["placeholder"],y1="dynamic_snooze_",so={__name:"commandbar",setup(t){const e=Zt(),{t:n,tm:i}=se(),{resolvedLocale:o}=Ln(),s=Ce(null),a=Ce(null),{goToAppearanceHotKeys:l}=r1(),{inboxHotKeys:r}=h1(),{goToCommandHotKeys:c}=u1(),{bulkActionsHotKeys:d}=C1(),{conversationHotKeys:p}=w1(),h=["snooze_conversation","snooze_notification","bulk_action_snooze_conversation"],v=U.SNOOZE_OPTIONS.UNTIL_CUSTOM_TIME,u=Ce([]),_=Ce(null),R=O(()=>h.includes(_.value)?n("COMMAND_BAR.SNOOZE_PLACEHOLDER"):n("COMMAND_BAR.SEARCH_PLACEHOLDER")),K=new Set(Object.values(U.SNOOZE_OPTIONS)),F=O(()=>{const g=[...u.value,...r.value,...c.value,...l.value,...d.value,...p.value];return u.value.length?g.filter(I=>!K.has(I.id)||!h.includes(I.parent)):g}),ge=()=>{s.value.data=F.value},Le={snooze_conversation:zt,snooze_notification:Ut,bulk_action_snooze_conversation:Gt},je={snooze_conversation:"COMMAND_BAR.SECTIONS.SNOOZE_CONVERSATION",snooze_notification:"COMMAND_BAR.SECTIONS.SNOOZE_NOTIFICATION",bulk_action_snooze_conversation:"COMMAND_BAR.SECTIONS.BULK_ACTIONS"},ke=O(()=>{const g=i("SNOOZE_PARSER");return!g||typeof g!="object"?{}:JSON.parse(JSON.stringify(g))}),De=(g,I)=>{const j=jn(g,new Date,{translations:ke.value,locale:o.value});if(!j.length)return[];const b=Le[I],k=n(je[I]);return j.map((D,dt)=>({id:`${y1}${dt}`,title:D.label!==D.formattedDate?`${D.label} - ${D.formattedDate}`:D.formattedDate,parent:I,section:k,icon:xe,keywords:g,handler:()=>{P.emit(b,D.resolve()),ft(Vn.NLP_SNOOZE_APPLIED,{label:D.label})}}))},me=()=>{_.value=null,u.value=[]},Be=g=>{if(!g||typeof g.open!="function"||typeof g.close!="function")return;const I=g.open.bind(g),j=g.close.bind(g);g.open=(...b)=>{const[k={}]=b;return _.value=k.parent||null,u.value=[],I(...b)},g.close=(...b)=>(me(),j(...b))},He=g=>{const{detail:{action:{title:I=null,section:j=null,id:b=null,children:k=null}={}}={}}=g;a.value=b===v?b:null,Array.isArray(k)&&k.length&&(_.value=b),ft(Zn.COMMAND_BAR,{section:j,action:I}),ge()},Ne=g=>{const{detail:{search:I="",actions:j=[]}={}}=g,b=I.trim();if(j.length>0){const k=[...new Set(j.map(D=>D.parent).filter(Boolean))];k.length===1?_.value=k[0]:_.value=null}if(!b||!h.includes(_.value||"")){u.value=[];return}u.value=De(b,_.value)},Pe=()=>{a.value!==v&&e.dispatch("setContextMenuChatId",null),me()};return _n(()=>{s.value&&(s.value.data=F.value)}),An(()=>{ge(),Be(s.value)}),(g,I)=>(On(),gn("ninja-keys",{ref_key:"ninjakeys",ref:s,noAutoLoadMdIcons:"",hideBreadcrumbs:"",placeholder:R.value,onChange:Ne,onSelected:He,onClosed:Pe},null,40,T1))}};export{so as default};
//# sourceMappingURL=commandbar-BYIxhTim.js.map
