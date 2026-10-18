import { HttpInterceptorFn } from '@angular/common/http';
import { Injectable, InjectionToken, inject, signal } from '@angular/core';
import { AuthConfig, OAuthService } from 'angular-oauth2-oidc';

export type Role = 'DRIVER' | 'RIDER' | 'ADMIN';

export interface Session {
  subject: string;
  roles: Role[];
}

export interface RideAuthConfig {
  clientId: string;
  issuer: string;
  apiOrigin: string;
}

export const RIDE_AUTH_CONFIG = new InjectionToken<RideAuthConfig>('RIDE_AUTH_CONFIG');

@Injectable({ providedIn: 'root' })
export class AuthFacade {
  private readonly oauth = inject(OAuthService);
  private readonly config = inject(RIDE_AUTH_CONFIG);
  private readonly currentSession = signal<Session | null>(null);
  private readonly currentAccessToken = signal<string | null>(null);

  readonly session = this.currentSession.asReadonly();
  readonly accessToken = this.currentAccessToken.asReadonly();

  async initialize(): Promise<void> {
    const config: AuthConfig = {
      issuer: this.config.issuer,
      redirectUri: window.location.origin,
      clientId: this.config.clientId,
      responseType: 'code',
      scope: 'openid profile',
      requireHttps: false,
      strictDiscoveryDocumentValidation: false,
    };
    this.oauth.configure(config);
    await this.oauth.loadDiscoveryDocumentAndTryLogin();
    this.readSession();
  }

  login(): void {
    this.oauth.initCodeFlow();
  }

  logout(): void {
    this.oauth.logOut();
    this.currentSession.set(null);
    this.currentAccessToken.set(null);
  }

  hasRole(role: Role): boolean {
    return this.currentSession()?.roles.includes(role) ?? false;
  }

  private readSession(): void {
    const token = this.oauth.getAccessToken();
    if (!token) {
      this.currentAccessToken.set(null);
      return;
    }
    const payload = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const claims = JSON.parse(atob(payload.padEnd(payload.length + (4 - payload.length % 4) % 4, '='))) as {
      sub?: string;
      roles?: Role[];
    };
    this.currentSession.set({ subject: claims.sub ?? 'unknown user', roles: claims.roles ?? [] });
    this.currentAccessToken.set(token);
  }
}

export const authInterceptor: HttpInterceptorFn = (request, next) => {
  const auth = inject(AuthFacade);
  const config = inject(RIDE_AUTH_CONFIG);
  const token = auth.accessToken();
  return token && request.url.startsWith(config.apiOrigin)
    ? next(request.clone({ setHeaders: { Authorization: `Bearer ${token}` } }))
    : next(request);
};
