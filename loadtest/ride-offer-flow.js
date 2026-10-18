import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const baseUrl = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
const tokenIssuer = (__ENV.TOKEN_ISSUER || 'http://mock-idp:8080/ride').replace(/\/$/, '');
const tokenIssuerHost = __ENV.TOKEN_ISSUER_HOST || 'localhost:8090';
const generateLocalTokens = (__ENV.GENERATE_LOCAL_TOKENS || 'true') === 'true';
const runId = __ENV.RUN_ID;
const vus = Number(__ENV.VUS || 1);
const duration = __ENV.DURATION || '1m';
const minIterationDuration = __ENV.MIN_ITERATION_DURATION || '1s';
const pollSeconds = Number(__ENV.POLL_SECONDS || 5);
const maxPolls = Number(__ENV.MAX_POLLS || 12);
const declineRate = Number(__ENV.DECLINE_RATE || 0);
const completedLifecycles = new Counter('ride_lifecycles_completed');
const abortedLifecycles = new Counter('ride_lifecycles_aborted');

function tokens(name) {
  const value = JSON.parse(__ENV[name] || '[]');
  if (!Array.isArray(value) || value.some((token) => typeof token !== 'string' || !token)) {
    throw new Error(`${name} must be a JSON array of access tokens`);
  }
  return value;
}

const riderTokens = tokens('RIDER_TOKENS');
const driverTokens = tokens('DRIVER_TOKENS');
const fallbackDriverTokens = tokens('FALLBACK_DRIVER_TOKENS');

export const options = {
  minIterationDuration,
  scenarios: {
    ride_lifecycle: {
      executor: 'constant-vus',
      vus,
      duration,
      gracefulStop: '30s',
    },
  },
  thresholds: {
    checks: ['rate>0.99'],
    http_req_failed: ['rate<0.01'],
    'http_req_duration{flow:ride-lifecycle}': ['p(95)<1000'],
  },
};

function request(method, path, token, name, expected, body) {
  const response = http.request(method, `${baseUrl}${path}`, body && JSON.stringify(body), {
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    tags: { name, flow: 'ride-lifecycle' },
  });
  check(response, { [name]: (result) => expected.includes(result.status) });
  return response;
}

function body(response) {
  try {
    return response.json();
  } catch (_) {
    return null;
  }
}

function issueToken(subject) {
  const response = http.post(`${tokenIssuer}/token`, `grant_type=client_credentials&subject=${encodeURIComponent(subject)}`, {
    headers: {
      Authorization: 'Basic cmlkZS13ZWI6bG9jYWw=',
      'Content-Type': 'application/x-www-form-urlencoded',
      Host: tokenIssuerHost,
    },
    tags: { name: 'issue_load_test_token', flow: 'token-setup' },
  });
  const token = body(response)?.access_token;
  if (response.status !== 200 || !token) {
    throw new Error(`could not issue a token for ${subject}: HTTP ${response.status}`);
  }
  return token;
}

export function setup() {
  if (!runId) {
    throw new Error('set RUN_ID to identify this load-test run');
  }
  if (riderTokens.length || driverTokens.length || fallbackDriverTokens.length) {
    if (riderTokens.length < vus || driverTokens.length < vus) {
      throw new Error('RIDER_TOKENS and DRIVER_TOKENS need one distinct token per VU');
    }
    if (declineRate > 0 && fallbackDriverTokens.length < vus) {
      throw new Error('FALLBACK_DRIVER_TOKENS needs one distinct token per VU when DECLINE_RATE is greater than zero');
    }
    return { riderTokens, driverTokens, fallbackDriverTokens };
  }
  if (!generateLocalTokens) {
    throw new Error('provide token arrays when GENERATE_LOCAL_TOKENS=false');
  }
  return {
    riderTokens: Array.from({ length: vus }, (_, index) => issueToken(`rider-k6-${runId}-${index + 1}`)),
    driverTokens: Array.from({ length: vus }, (_, index) => issueToken(`driver-k6-${runId}-${index + 1}`)),
    fallbackDriverTokens: declineRate > 0
      ? Array.from({ length: vus }, (_, index) => issueToken(`driver-k6-fallback-${runId}-${index + 1}`))
      : [],
  };
}

function abort(reason) {
  abortedLifecycles.add(1, { reason });
}

function waitForDriverRide(token, rideId) {
  for (let attempt = 0; attempt < maxPolls; attempt += 1) {
    const response = request('GET', '/drivers/me/ride', token, 'poll_driver_ride', [200, 204]);
    const ride = body(response);
    if (ride?.id === rideId && ride.status === 'OFFERED') return ride;
    sleep(pollSeconds);
  }
  check(false, { 'driver receives an offer': () => false });
  return null;
}

function waitForRiderStatus(token, rideId, expectedStatus) {
  for (let attempt = 0; attempt < maxPolls; attempt += 1) {
    const response = request('GET', '/riders/me/ride', token, 'poll_rider_ride', [200, 204]);
    const ride = body(response);
    if (ride?.id === rideId && ride.status === expectedStatus) return true;
    sleep(pollSeconds);
  }
  check(false, { [`rider sees ${expectedStatus}`]: () => false });
  return false;
}

export default function (tokensForRun) {
  const index = __VU - 1;
  const riderToken = tokensForRun.riderTokens[index];
  const driverToken = tokensForRun.driverTokens[index];
  const fallbackToken = tokensForRun.fallbackDriverTokens[index];
  if (!riderToken || !driverToken) {
    throw new Error('RIDER_TOKENS and DRIVER_TOKENS need one distinct token per VU');
  }
  const latitude = 51.5074 + index / 10_000;
  const pickup = { latitude, longitude: -0.1278 };
  const destination = { latitude: latitude + 0.01, longitude: -0.1178 };

  const primaryAvailability = request('PUT', '/drivers/me/availability', driverToken, 'make_primary_available', [200], {
    available: true,
    location: pickup,
  });
  if (primaryAvailability.status !== 200) {
    abort('availability_failed');
    return;
  }
  if (fallbackToken) {
    const fallbackAvailability = request('PUT', '/drivers/me/availability', fallbackToken, 'make_fallback_available', [200], {
      available: true,
      location: { latitude: latitude + 0.001, longitude: -0.1278 },
    });
    if (fallbackAvailability.status !== 200) {
      abort('fallback_availability_failed');
      return;
    }
  }

  const requested = request('POST', '/rides', riderToken, 'request_ride', [201], { pickup, destination });
  const ride = body(requested);
  if (!ride?.id || ride.status !== 'OFFERED') {
    check(ride, { 'ride is offered': (value) => value?.status === 'OFFERED' });
    abort(requested.status === 201 ? 'no_driver_available' : 'ride_request_failed');
    return;
  }

  let acceptedBy = driverToken;
  if (fallbackToken && Math.random() < declineRate) {
    const primaryOffer = waitForDriverRide(driverToken, ride.id);
    if (!primaryOffer) {
      abort('primary_offer_timeout');
      return;
    }
    const declined = request('POST', `/rides/${ride.id}/decline`, driverToken, 'decline_offer', [200]);
    if (declined.status !== 200) {
      abort('decline_failed');
      return;
    }
    const fallbackOffer = waitForDriverRide(fallbackToken, ride.id);
    if (!fallbackOffer) {
      abort('fallback_offer_timeout');
      return;
    }
    acceptedBy = fallbackToken;
  }

  const offered = waitForDriverRide(acceptedBy, ride.id);
  if (!offered) {
    abort('driver_offer_timeout');
    return;
  }
  const accepted = request('POST', `/rides/${ride.id}/accept`, acceptedBy, 'accept_offer', [200]);
  if (accepted.status !== 200) {
    abort('accept_failed');
    return;
  }
  if (!waitForRiderStatus(riderToken, ride.id, 'DRIVER_EN_ROUTE')) {
    abort('rider_status_timeout');
    return;
  }
  const located = request('PUT', '/drivers/me/location', acceptedBy, 'arrive_at_pickup', [200], { location: pickup });
  if (located.status !== 200) {
    abort('location_failed');
    return;
  }
  const arrived = request('POST', `/rides/${ride.id}/arrive`, acceptedBy, 'mark_waiting_at_pickup', [200]);
  if (arrived.status !== 200) {
    abort('arrival_failed');
    return;
  }
  const pickedUp = request('POST', `/rides/${ride.id}/pickup`, acceptedBy, 'pick_up_passenger', [200]);
  if (pickedUp.status !== 200) {
    abort('pickup_failed');
    return;
  }
  const completed = request('POST', `/rides/${ride.id}/complete`, acceptedBy, 'complete_ride', [200]);
  if (completed.status !== 200) {
    abort('completion_failed');
    return;
  }
  completedLifecycles.add(1);
}
