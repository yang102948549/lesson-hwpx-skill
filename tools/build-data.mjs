#!/usr/bin/env node
/*
 * 성취기준 데이터 만들기
 *   원문: sources/curriculum-data.js (2022 개정 교육과정 고시 원문, 초1~고3 4,451개)
 *   보강: DECK6/korean-secondary-learning-map (중·고 세부 학습 주제, 평가 질문, 오개념, 선수학습 관계, 쪽번호)
 * 두 자료를 성취기준 코드로 잇고 data/curriculum.json 하나로 씁니다.
 *
 *   node tools/build-data.mjs            고정된 커밋으로 만들기 (내려받은 파일은 .cache에 보관)
 *   node tools/build-data.mjs --ref main 최신 main으로 만들기 (커밋 SHA를 기록)
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const REPO = 'DECK6/korean-secondary-learning-map';
const PINNED = 'b57e5bb51bf58ccb3dc0bca132d4cd01552182ba'; // 2026-09-07
const refArg = process.argv.indexOf('--ref');
const REF = refArg > 0 ? process.argv[refArg + 1] : PINNED;

const FILES = [
  'middle/courses.json', 'middle/domains.json', 'middle/standards.json', 'middle/topics.json', 'middle/learning-relations.json',
  'high/courses.json', 'high/domains.json', 'high/standards.json', 'high/topics.json', 'high/learning-relations.json',
  'bridges/transition-alignments.json', 'bridges/elementary-transitions.json', 'bridges/elementary-topic-inventory.json'
];

async function resolveSha(ref) {
  if (/^[0-9a-f]{40}$/.test(ref)) return ref;
  const r = await fetch(`https://api.github.com/repos/${REPO}/commits/${ref}`, { headers: { 'User-Agent': 'lesson-design-build' } });
  if (!r.ok) throw new Error(`커밋을 찾지 못했어요: ${ref} (${r.status})`);
  return (await r.json()).sha;
}

async function load(sha, path) {
  const file = join(ROOT, '.cache', 'learning-map', sha, path);
  if (!existsSync(file)) {
    const url = `https://raw.githubusercontent.com/${REPO}/${sha}/data/kr/${path}`;
    const r = await fetch(url);
    if (!r.ok) throw new Error(`내려받기 실패: ${url} (${r.status})`);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, Buffer.from(await r.arrayBuffer()));
    console.log('  받음', path);
  }
  return JSON.parse(readFileSync(file, 'utf8'));
}

const bare = c => c.replace(/[\[\]\s]/g, '');
/* 로마 숫자 표기 차이(Ⅰ / I)를 없앤 비교용 키 */
const norm = c => bare(c).replace(/Ⅲ/g, 'III').replace(/Ⅱ/g, 'II').replace(/Ⅰ/g, 'I');
const schoolOf = band => ({ 초: '초등학교', 중: '중학교', 고: '고등학교' })[band[0]];

/* 1. 원문 */
const sandbox = {};
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(readFileSync(join(ROOT, 'sources', 'curriculum-data.js'), 'utf8'), sandbox);
const { units: UNITS, source: OFFICIAL_SOURCE } = sandbox.CurriculumData;

/* 같은 코드가 두 과목에 공식으로 겹치는 경우가 있어(예: 12스문01-01 스포츠 문화 / 스페인어권 문화) 배열로 둡니다 */
const standards = [];
const byKey = new Map(); // norm(code) → [entry]
for (const [band, subject, course, domain, list] of UNITS) {
  for (const [code, text] of list) {
    const e = { code, text, school: schoolOf(band), band, subject, course, domain };
    standards.push(e);
    const k = norm(code);
    if (!byKey.has(k)) byKey.set(k, []);
    byKey.get(k).push(e);
  }
}
/* 코드가 겹치면 과목명으로 고르기 */
const pick = (key, courseLabel) => {
  const list = byKey.get(key) || [];
  if (list.length < 2 || !courseLabel) return list;
  const same = list.filter(e => e.course.replace(/\s/g, '') === courseLabel.replace(/\s/g, ''));
  return same.length ? same : list;
};

/* 2. 학습지도 */
const sha = await resolveSha(REF);
console.log(`학습지도 ${REPO}@${sha.slice(0, 7)}`);
const D = {};
for (const f of FILES) D[f] = await load(sha, f);
const recs = f => D[f].records;

const courseLabel = new Map();
for (const lvl of ['middle', 'high']) for (const c of recs(`${lvl}/courses.json`)) courseLabel.set(c.id, c.labelKorean);

const stdIdToEntries = new Map(); // 학습지도 성취기준 id → 원문 항목들
const unmatched = [];
let matched = 0;
for (const lvl of ['middle', 'high']) {
  for (const s of recs(`${lvl}/standards.json`)) {
    const entries = pick(norm(s.code), courseLabel.get(s.courseId));
    if (!entries.length) { unmatched.push(bare(s.code)); continue; }
    matched++;
    stdIdToEntries.set(s.id, entries);
    const L = s.sourceLocator || {};
    for (const e of entries) e.map = { summary: s.summary, sourceId: L.sourceId, section: L.section, printedPage: L.printedPage ?? null, pdfPage: L.pdfPage ?? null, topics: [] };
  }
}

/* 주제 → 원문 항목 */
const topicToEntry = new Map();
for (const lvl of ['middle', 'high']) {
  for (const t of recs(`${lvl}/topics.json`)) {
    if (t.collapseInto) continue; // 다른 주제로 합쳐진 중복 후보
    const entries = (t.standardAlignments || []).flatMap(a => stdIdToEntries.get(a.standardId) || []);
    if (!entries.length) continue;
    topicToEntry.set(t.id, entries[0]);
    const item = {
      role: t.topicRole,
      facet: t.facetKeyDetail || t.facetKey,
      kind: t.contentKind,
      evidence: t.evidence || [],
      prompts: t.assessmentPrompts || [],
      misconceptions: t.misconceptions || []
    };
    if (t.topicRole !== 'anchor') item.focus = (t.labelKorean || '').split(' — ').pop();
    for (const e of entries) e.map.topics.push(item);
  }
}
/* 초등 주제 → 성취기준 코드 (초등→중 연결용) */
for (const s of D['bridges/elementary-topic-inventory.json'].standards) {
  const [e] = pick(norm(s.code), s.subjectKorean);
  if (e) for (const id of s.topicIds) topicToEntry.set(id, e);
}

/* 3. 선수·후속 관계 (주제 관계를 성취기준 코드 관계로 접음) */
const links = new Map();
const addLink = (from, to, reason, basis, kind) => {
  if (!from || !to || from === to) return;
  const key = `${from.code}/${from.course}>${to.code}/${to.course}`;
  if (!links.has(key)) links.set(key, { from, to, reason, basis, kind });
};
for (const f of ['middle/learning-relations.json', 'high/learning-relations.json', 'bridges/elementary-transitions.json']) {
  for (const r of recs(f)) addLink(topicToEntry.get(r.prerequisiteTopicId), topicToEntry.get(r.dependentTopicId), r.reason, r.basis, r.relationKind);
}
for (const r of recs('bridges/transition-alignments.json')) {
  for (const a of r.fromTopicIds) for (const b of r.toTopicIds) addLink(topicToEntry.get(a), topicToEntry.get(b), r.reason, r.basis, r.transitionKind);
}

/* 4. 합치기 */
for (const l of links.values()) {
  const rel = (e, other) => ({ code: other.code, course: other.course, reason: l.reason, basis: l.basis, kind: l.kind });
  (l.to.prereq ||= []).push(rel(l.to, l.from));
  (l.from.next ||= []).push(rel(l.from, l.to));
}

const out = {
  built: new Date().toISOString().slice(0, 10),
  sources: {
    text: { name: OFFICIAL_SOURCE, file: 'sources/curriculum-data.js' },
    learningMap: { repo: `https://github.com/${REPO}`, commit: sha, license: 'MIT' }
  },
  units: UNITS.map(([band, subject, course, domain, list]) => [band, subject, course, domain, list.map(s => s[0])]),
  standards
};
mkdirSync(join(ROOT, 'data'), { recursive: true });
writeFileSync(join(ROOT, 'data', 'curriculum.json'), JSON.stringify(out));

const secondary = standards.filter(s => s.school !== '초등학교');
console.log(`성취기준 ${standards.length}개 (중·고 ${secondary.length}개 중 학습지도 연결 ${secondary.filter(s => s.map).length}개), 선후 관계 ${links.size}개`);
console.log(`학습지도 성취기준 ${matched + unmatched.length}개 중 원문과 연결 ${matched}개`);
if (unmatched.length) console.log(`원문 없는 학습지도 코드 ${unmatched.length}개: ${unmatched.slice(0, 15).join(', ')}${unmatched.length > 15 ? ' …' : ''}`);
