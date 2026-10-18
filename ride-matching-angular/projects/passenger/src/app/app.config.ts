import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideOAuthClient } from 'angular-oauth2-oidc';
import { API_BASE_URL } from 'shared-api';
import { RIDE_AUTH_CONFIG, authInterceptor } from 'shared-auth';
import { environment } from '../environments/environment';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideHttpClient(withInterceptors([authInterceptor])),
    provideOAuthClient(),
    { provide: API_BASE_URL, useValue: environment.apiBaseUrl },
    { provide: RIDE_AUTH_CONFIG, useValue: environment.auth },
  ],
};
