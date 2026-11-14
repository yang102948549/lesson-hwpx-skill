#!/usr/bin/env node
/*
 * 성취기준 찾기 (lessonapp-prd-mcp의 검색 로직을 명령줄로 옮김)
 *
 *   node scripts/standards.mjs browse  [--school 중학교] [--grades 1,2] [--subject 과학] [--course 과학] [--domain …]
 *   node scripts/standards.mjs search  <낱말> [필터…] [--limit 20]
 *   node scripts/standards.mjs get     <코드> [<코드> …]          원문과 소속
 *   node scripts/standards.mjs context <코드> [<코드> …]          원문 + 세부 주제·평가 증거·평가 질문·오개념·선수/후속 학습 (수업·평가 설계용)
 *   --json 을 붙이면 JSON으로 출력
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DATA = JSON.parse(readFileSync(join(ROOT, 'data', 'curriculum.json'), 'utf8'));
const ALL = DATA.standards;

/* ---------- 인자 ---------- */
const [cmd, ...rest] = process.argv.slice(2);
const opts = {}, pos = [];
for (let i = 0; i < rest.length; i++) {
  const a = rest[i];
  if (a === '--json') opts.json = true;
  else if (a.startsWith('--')) opts[a.slice(2)] = rest[++i];
  else pos.push(a);
}
const grades = opts.grades ? opts.grades.split(',').map(Number) : null;
const school = opts.school ? ({ 초: '초등학교', 중: '중학교', 고: '고등학교' })[opts.school[0]] : null;

/* ---------- 학교급·학년 → 학년군 (사이트 curriculum.js와 같은 규칙) ---------- */
function bandsFor() {
  const all = [...new Set(ALL.map(s => s.band))];
  const head = school ? school[0] : '';
  const pool = head ? all.filter(b => b.startsWith(head)) : all;
  if (!grades?.length || !head) return pool;
  const fit = pool.filter(b => {
    const m = b.match(/(\d)(?:~(\d))?$/), lo = Number(m[1]), hi = Number(m[2] || m[1]);
    return grades.some(n => n >= lo && n <= hi);
  });
  return fit.length ? fit : pool;
}
const scope = () => {
  const bands = bandsFor();
  return ALL.filter(s => bands.includes(s.band)
    && (!opts.subject || s.subject === opts.subject)
    && (!opts.course || s.course === opts.course)
    && (!opts.domain || s.domain === opts.domain));
};
const norm = c => c.replace(/[\[\]\s]/g, '').replace(/Ⅲ/g, 'III').replace(/Ⅱ/g, 'II').replace(/Ⅰ/g, 'I');
const find = code => ALL.filter(s => norm(s.code) === norm(code));
const where = s => `${s.band} · ${s.subject}${s.course !== s.subject ? ' · ' + s.course : ''}${s.domain ? ' · ' + s.domain : ''}`;
const line = s => `- [${s.code}] ${s.text}  (${where(s)})`;

const out = (data, text) => { console.log(opts.json ? JSON.stringify(data, null, 1) : text); };
const fail = msg => { console.error(msg); process.exit(1); };

/* ---------- 명령 ---------- */
if (cmd === 'browse') {
  const rows = scope();
  if (!rows.length) fail('조건에 맞는 교육과정이 없어요. 필터를 줄여 보세요.');
  const depth = opts.course ? 4 : opts.subject ? 3 : 2; // 학년군/교과 → 과목 → 영역
  const tree = new Map();
  for (const s of rows) {
    const key = [s.band, s.subject, s.course, s.domain || '(영역 없음)'].slice(0, depth).join(' / ');
    tree.set(key, (tree.get(key) || 0) + 1);
  }
  out(Object.fromEntries(tree), [...tree].map(([k, n]) => `${k} (성취기준 ${n}개)`).join('\n'));
} else if (cmd === 'search') {
  const q = pos.join(' ');
  const limit = Number(opts.limit || 20);
  const hits = scope().filter(s => !q || s.text.includes(q) || s.code.includes(q) || (s.domain || '').includes(q));
  if (!hits.length) fail('검색 결과가 없어요. 낱말을 줄이거나 필터를 풀어 보세요.');
  out(hits.slice(0, limit), `${hits.length}개 중 ${Math.min(limit, hits.length)}개\n${hits.slice(0, limit).map(line).join('\n')}`);
} else if (cmd === 'get' || cmd === 'context') {
  if (!pos.length) fail('성취기준 코드를 하나 이상 주세요. 예: 9과01-01');
  const found = [], missing = [];
  for (const c of pos) { const f = find(c); f.length ? found.push(...f) : missing.push(c); }
  if (!found.length) fail(`코드를 찾을 수 없어요: ${missing.join(', ')}`);
  if (cmd === 'get') {
    out(found.map(({ map, prereq, next, ...s }) => s), found.map(line).join('\n') + (missing.length ? `\n\n찾지 못한 코드: ${missing.join(', ')}` : ''));
  } else {
    out(found, found.map(contextText).join('\n\n---\n\n') + (missing.length ? `\n\n찾지 못한 코드: ${missing.join(', ')}` : ''));
  }
} else {
  console.log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(2, 11).map(l => l.replace(/^ \* ?/, '')).join('\n'));
  process.exit(cmd ? 1 : 0);
}

function contextText(s) {
  const L = [`## [${s.code}] ${s.text}`, `소속: ${s.school} ${where(s)}`];
  const m = s.map;
  if (!m) {
    L.push('', '(초등 성취기준은 아직 세부 주제·평가 자료가 없습니다. 원문을 바탕으로 분석하세요.)');
  } else {
    if (m.printedPage) L.push(`출처: ${m.sourceId} · ${m.section} · 별책 ${m.printedPage}쪽`);
    if (m.summary) L.push(`요약(학습지도 작성): ${m.summary}`);
    /* 고등학교 주제는 성취기준 문장을 틀에 끼운 기계 생성 문장이라 글로는 보여 주지 않음(--json에는 있음) */
    const topics = m.topics.filter(t => t.kind !== 'mechanical-derivative');
    if (!topics.length) L.push('', '(세부 주제·평가 자료가 없습니다. 원문을 바탕으로 분석하세요.)');
    topics.forEach((t, i) => {
      L.push('', `### 세부 주제 ${i + 1}${t.focus ? ` · ${t.focus}` : ''} (${t.facet})`);
      if (t.evidence.length) L.push('평가 증거:', ...t.evidence.map(x => `- ${x}`));
      if (t.prompts.length) L.push('평가 질문:', ...t.prompts.map(x => `- ${x}`));
      if (t.misconceptions.length) L.push('흔한 오개념:', ...t.misconceptions.map(x => `- ${x}`));
    });
  }
  const rel = (title, list) => {
    if (!list?.length) return;
    L.push('', `### ${title}`);
    for (const r of list) {
      const [o] = find(r.code).filter(x => x.course === r.course);
      L.push(`- [${r.code}] ${o ? o.text : ''}${o ? `  (${o.band} · ${o.course})` : ''}`, `  근거: ${r.reason} — ${r.basis}`);
    }
  };
  rel('선수 학습', s.prereq);
  rel('후속 학습', s.next);
  return L.join('\n');
}
