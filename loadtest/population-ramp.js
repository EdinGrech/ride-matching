import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';
import exec from 'k6/execution';

const baseUrl = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
const tokenIssuer = (__ENV.TOKEN_ISSUER || 'http://mock-idp:8080/ride').replace(/\/$/, '');
const tokenIssuerHost = __ENV.TOKEN_ISSUER_HOST || 'localhost:8090';
const runId = __ENV.RUN_ID;
const timeScale = Number(__ENV.TIME_SCALE || 60);
const pollSeconds = Number(__ENV.POLL_SECONDS || 5);
const riderCancelRate = Number(__ENV.RIDER_CANCEL_RATE || 0);
const driverDeclineRate = Number(__ENV.DRIVER_DECLINE_RATE || 0);
const tripMinMinutes = Number(__ENV.TRIP_MIN_MINUTES || 5);
const tripMaxMinutes = Number(__ENV.TRIP_MAX_MINUTES || 30);
const benchmarkProfile = __ENV.BENCHMARK_PROFILE || 'full';
const defaultStages = {
  quick: [
    { duration: '5s', target: 1 },
    { duration: '15s', target: 1 },
    { duration: '5s', target: 2 },
    { duration: '20s', target: 2 },
    { duration: '5s', target: 0 },
  ],
  full: [
    { duration: '1m', target: 1 },
    { duration: '2m', target: 1 },
    { duration: '1m', target: 5 },
    { duration: '3m', target: 5 },
    { duration: '1m', target: 10 },
    { duration: '3m', target: 10 },
    { duration: '1m', target: 25 },
    { duration: '4m', target: 25 },
    { duration: '1m', target: 50 },
    { duration: '5m', target: 50 },
    { duration: '2m', target: 0 },
  ],
};
const cohortStages = JSON.parse(__ENV.COHORT_STAGES || JSON.stringify(defaultStages[benchmarkProfile] || []));
const maxCohorts = Math.max(...cohortStages.map((stage) => stage.target));
const riderTokens = JSON.parse(__ENV.RIDER_TOKENS || '[]');
const driverTokens = JSON.parse(__ENV.DRIVER_TOKENS || '[]');
const completedLifecycles = new Counter('ride_lifecycles_completed');
const abortedLifecycles = new Counter('ride_lifecycles_aborted');
const cancelledLifecycles = new Counter('ride_lifecycles_cancelled');
let quarantined = false;
let nextLocationAt = 0;

function scaledStages(multiplier) {
  return cohortStages.map((stage) => ({ duration: stage.duration, target: stage.target * multiplier }));
}

export const options = {
  scenarios: {
    riders: {
      executor: 'ramping-vus',
      exec: 'rider',
      startVUs: 0,
      stages: scaledStages(2),
      gracefulRampDown: '30s',
      gracefulStop: '30s',
    },
    drivers: {
      executor: 'ramping-vus',
      exec: 'driver',
      startVUs: 0,
      stages: scaledStages(5),
      gracefulRampDown: '30s',
      gracefulStop: '30s',
    },
  },
  thresholds: {
    checks: ['rate>0.99'],
    'http_req_failed{flow:population-ramp}': ['rate<0.01'],
    'http_req_duration{flow:population-ramp}': ['p(95)<1000'],
    dropped_iterations: ['count==0'],
    ride_lifecycles_aborted: ['count==0'],
  },
};

function body(response) {
  try {
    return response.json();
  } catch (_) {
    return null;
  }
}

function endpointName(method, path) {
  return `${method} ${path.replace(/\/rides\/[^/]+/, '/rides/:id')}`;
}

function request(method, path, token, name, expected, value, role) {
  const endpoint = endpointName(method, path);
  const response = http.request(method, `${baseUrl}${path}`, value && JSON.stringify(value), {
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    responseCallback: http.expectedStatuses(...expected),
    tags: { name: endpoint, flow: 'population-ramp', role, time_scale: String(timeScale) },
  });
  check(response, { [endpoint]: (result) => expected.includes(result.status) });
  return response;
}

function issueToken(subject) {
  const response = http.post(`${tokenIssuer}/token`, `grant_type=client_credentials&subject=${encodeURIComponent(subject)}`, {
    headers: {
      Authorization: 'Basic cmlkZS13ZWI6bG9jYWw=',
      'Content-Type': 'application/x-www-form-urlencoded',
      Host: tokenIssuerHost,
    },
    tags: { name: 'POST /ride/token', flow: 'actor-setup' },
  });
  const token = body(response)?.access_token;
  if (response.status !== 200 || !token) throw new Error(`could not issue a token for ${subject}: HTTP ${response.status}`);
  return token;
}

function waitForApi() {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    const response = http.get(`${baseUrl}/drivers/me/state`, { tags: { name: 'GET /drivers/me/state', flow: 'actor-setup' } });
    if (response.status !== 0) return;
    sleep(1);
  }
  throw new Error(`API did not become reachable at ${baseUrl}`);
}

export function setup() {
  if (!runId) throw new Error('set RUN_ID to identify this load-test run');
  if (!defaultStages[benchmarkProfile] || !Array.isArray(cohortStages) || !cohortStages.length || cohortStages.some((stage) => !stage.duration || !Number.isInteger(stage.target) || stage.target < 0)) {
    throw new Error('BENCHMARK_PROFILE must be quick or full and COHORT_STAGES must contain non-negative integer targets');
  }
  if (!Number.isFinite(timeScale) || timeScale <= 0 || !Number.isFinite(pollSeconds) || pollSeconds <= 0
      || tripMinMinutes < 0 || tripMaxMinutes < tripMinMinutes || riderCancelRate < 0 || riderCancelRate > 1
      || driverDeclineRate < 0 || driverDeclineRate > 1) {
    throw new Error('timing and cancellation settings must be valid');
  }
  waitForApi();
  // k6 VU IDs are shared by both scenarios, so each role needs slots for every possible ID.
  const actorSlots = maxCohorts * 7;
  const generatedRiderTokens = riderTokens.length ? riderTokens : Array.from(
    { length: actorSlots },
    (_, index) => issueToken(`rider-load-test-${runId}-${index + 1}`),
  );
  const generatedDriverTokens = driverTokens.length ? driverTokens : Array.from(
    { length: actorSlots },
    (_, index) => issueToken(`driver-load-test-${runId}-${index + 1}`),
  );
  if (generatedRiderTokens.length < actorSlots || generatedDriverTokens.length < actorSlots) {
    throw new Error(`RIDER_TOKENS and DRIVER_TOKENS each need ${actorSlots} distinct tokens`);
  }
  return { riderTokens: generatedRiderTokens, driverTokens: generatedDriverTokens };
}

function tokenForVu(data, role) {
  const token = (role === 'rider' ? data.riderTokens : data.driverTokens)[exec.vu.idInInstance - 1];
  if (!token) throw new Error('missing token for virtual user');
  return token;
}

function locationForVu() {
  const offset = exec.vu.idInInstance / 10_000;
  return { latitude: 51.5074 + offset, longitude: -0.1278 };
}

function tripSeconds() {
  const minutes = tripMinMinutes + Math.random() * (tripMaxMinutes - tripMinMinutes);
  return minutes * 60 / timeScale;
}

function abort(role, reason) {
  abortedLifecycles.add(1, { flow: 'population-ramp', role, reason, time_scale: String(timeScale) });
  quarantined = true;
}

function updateLocation(token, location) {
  if (Date.now() < nextLocationAt) return true;
  const updated = request('PUT', '/drivers/me/location', token, 'periodic_location_update', [200], { location }, 'driver');
  nextLocationAt = Date.now() + (10_000 / timeScale);
  return updated.status === 200;
}

function simulateDriverPhase(token, ride, seconds) {
  let elapsed = 0;
  while (elapsed < seconds) {
    const wait = Math.min(pollSeconds / timeScale, seconds - elapsed);
    sleep(wait);
    elapsed += wait;
    const state = request('GET', '/drivers/me/state', token, 'poll_driver_state', [200], undefined, 'driver');
    if (body(state)?.ride?.id !== ride.id || !updateLocation(token, ride.pickup)) return false;
  }
  return true;
}

export function rider(data) {
  if (quarantined) {
    sleep(1);
    return;
  }
  const token = tokenForVu(data, 'rider');
  const current = request('GET', '/riders/me/ride', token, 'poll_rider_ride', [200, 204], undefined, 'rider');
  const ride = body(current);
  if (current.status === 204) {
    const pickup = locationForVu();
    const requested = request('POST', '/rides', token, 'request_ride', [201], {
      pickup,
      destination: { latitude: pickup.latitude + 0.01, longitude: pickup.longitude + 0.01 },
    }, 'rider');
    if (!body(requested)?.id) abort('rider', 'ride_request_failed');
    return;
  }
  if (current.status !== 200 || !ride?.id) {
    abort('rider', 'rider_state_failed');
    return;
  }
  if (ride.status === 'OFFERED' && Math.random() < riderCancelRate) {
    const cancelled = request('DELETE', '/riders/me/ride', token, 'cancel_rider_ride', [200], undefined, 'rider');
    if (cancelled.status === 200) cancelledLifecycles.add(1, { flow: 'population-ramp', time_scale: String(timeScale) });
    else abort('rider', 'rider_cancellation_failed');
    return;
  }
  sleep(pollSeconds / timeScale);
}

export function driver(data) {
  if (quarantined) {
    sleep(1);
    return;
  }
  const token = tokenForVu(data, 'driver');
  const home = locationForVu();
  const state = request('GET', '/drivers/me/state', token, 'poll_driver_state', [200], undefined, 'driver');
  const ride = body(state)?.ride;
  if (state.status !== 200) {
    abort('driver', 'driver_state_failed');
    return;
  }
  if (!ride) {
    const available = request('PUT', '/drivers/me/availability', token, 'make_driver_available', [200, 409], { available: true, location: home }, 'driver');
    if (available.status === 409) {
      sleep(pollSeconds / timeScale);
      return;
    }
    if (available.status !== 200) {
      abort('driver', 'availability_failed');
      return;
    }
    nextLocationAt = Date.now() + (10_000 / timeScale);
    sleep(pollSeconds / timeScale);
    return;
  }
  if (ride.status === 'OFFERED') {
    const action = Math.random() < driverDeclineRate
      ? request('POST', `/rides/${ride.id}/decline`, token, 'decline_offer', [200], undefined, 'driver')
      : request('POST', `/rides/${ride.id}/accept`, token, 'accept_offer', [200], undefined, 'driver');
    if (action.status !== 200) abort('driver', 'offer_action_failed');
    return;
  }
  if (ride.status === 'DRIVER_EN_ROUTE') {
    if (!simulateDriverPhase(token, ride, tripSeconds() * 0.3)
        || request('POST', `/rides/${ride.id}/arrive`, token, 'mark_waiting_at_pickup', [200], undefined, 'driver').status !== 200
        || request('POST', `/rides/${ride.id}/pickup`, token, 'pick_up_passenger', [200], undefined, 'driver').status !== 200) {
      abort('driver', 'en_route_transition_failed');
    }
    return;
  }
  if (ride.status === 'WAITING_AT_PICKUP') {
    if (request('POST', `/rides/${ride.id}/pickup`, token, 'pick_up_passenger', [200], undefined, 'driver').status !== 200) abort('driver', 'pickup_failed');
    return;
  }
  if (ride.status === 'IN_PROGRESS') {
    if (!simulateDriverPhase(token, ride, tripSeconds() * 0.7)
        || request('POST', `/rides/${ride.id}/complete`, token, 'complete_ride', [200], undefined, 'driver').status !== 200) {
      abort('driver', 'completion_failed');
      return;
    }
    completedLifecycles.add(1, { flow: 'population-ramp', time_scale: String(timeScale) });
    return;
  }
  abort('driver', 'unexpected_ride_status');
}
