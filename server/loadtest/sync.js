// Load test at 10x the planned peak (docs/backend/01-plan.md section 1):
// 14 pushes/s of one set each and 3 pulls/s, for 5 minutes, from 200 accounts.
// Run: k6 run -e BASE=http://localhost:8080 loadtest/sync.js   (server started with AUTH_DEV=1)
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE || 'http://localhost:8080';
const USERS = 200;
const DURATION = __ENV.DURATION || '5m';

export const options = {
  scenarios: {
    push: { executor: 'constant-arrival-rate', exec: 'push', rate: 14, timeUnit: '1s', duration: DURATION, preAllocatedVUs: 50 },
    pull: { executor: 'constant-arrival-rate', exec: 'pull', rate: 3, timeUnit: '1s', duration: DURATION, preAllocatedVUs: 20 },
  },
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.001'],
  },
};

export function setup() {
  const run = Date.now();
  const tokens = [];
  for (let i = 0; i < USERS; i++) {
    const res = http.post(`${BASE}/v1/auth/dev`, JSON.stringify({ subject: `load-${run}-${i}` }),
      { headers: { 'Content-Type': 'application/json' } });
    tokens.push(res.json('accessToken'));
  }
  return { tokens };
}

function auth(data) {
  const token = data.tokens[Math.floor(Math.random() * data.tokens.length)];
  return { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` } };
}

export function push(data) {
  const now = Date.now();
  const id = `${__VU}-${__ITER}-${now}`;
  const body = { changes: [{ table: 'workoutSet', id, op: 'upsert', updatedAt: now, row: {
    id, workoutExerciseId: 'we-load', position: __ITER % 20, loadHundredths: 10000, unit: 'kg', reps: 8,
    type: 'working', completedAt: now, annotations: [] } }] };
  const res = http.post(`${BASE}/v1/sync/push`, JSON.stringify(body), auth(data));
  check(res, { 'push 200': (r) => r.status === 200 });
}

export function pull(data) {
  const res = http.get(`${BASE}/v1/sync/pull?since=0`, auth(data));
  check(res, { 'pull 200': (r) => r.status === 200 });
}
