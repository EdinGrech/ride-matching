import { RideAuthConfig } from 'shared-auth';

export interface Environment {
  production: boolean;
  apiBaseUrl: string;
  auth: RideAuthConfig;
}

export const environment: Environment = {
  production: false,
  apiBaseUrl: 'http://localhost:8080',
  auth: {
    issuer: 'http://localhost:8090/ride',
    apiOrigin: 'http://localhost:8080',
    clientId: 'ride-passenger-web',
  },
};
