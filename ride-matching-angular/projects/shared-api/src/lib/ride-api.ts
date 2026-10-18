import { HttpClient } from '@angular/common/http';
import { Injectable, InjectionToken, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

export const API_BASE_URL = new InjectionToken<string>('API_BASE_URL');

export interface Location {
  latitude: number;
  longitude: number;
}

export interface DriverView {
  id: string;
  location: Location;
  status: DriverStatus;
}

export interface PassengerRideView {
  id: string;
  pickup: Location;
  destination: Location;
  status: RideStatus;
  driver?: DriverView;
}

export interface DriverRideView {
  id: string;
  pickup: Location;
  destination?: Location;
  status: RideStatus;
}

export interface DriverStateView {
  driver: DriverView | null;
  ride: DriverRideView | null;
}

export type DriverStatus = 'AVAILABLE' | 'OFFLINE' | 'OFFERED' | 'DRIVING_TO_PICKUP' | 'WAITING_AT_PICKUP' | 'DRIVING_TO_DESTINATION' | 'PENALIZED';
export type RideStatus = 'MATCHING' | 'OFFERED' | 'DRIVER_EN_ROUTE' | 'WAITING_AT_PICKUP' | 'IN_PROGRESS' | 'COMPLETED' | 'CANCELLED';

@Injectable({ providedIn: 'root' })
export class RideApi {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = inject(API_BASE_URL);

  currentDriver(): Observable<DriverView> {
    return this.http.get<DriverView>(`${this.baseUrl}/drivers/me`);
  }

  currentDriverState(): Observable<DriverStateView> {
    return this.http.get<DriverStateView>(`${this.baseUrl}/drivers/me/state`);
  }

  setAvailability(available: boolean, location: Location): Observable<DriverView> {
    return this.http.put<DriverView>(`${this.baseUrl}/drivers/me/availability`, { available, location });
  }

  updateLocation(location: Location): Observable<DriverView> {
    return this.http.put<DriverView>(`${this.baseUrl}/drivers/me/location`, { location });
  }

  requestRide(pickup: Location, destination: Location): Observable<PassengerRideView> {
    return this.http.post<PassengerRideView>(`${this.baseUrl}/rides`, { pickup, destination });
  }

  currentRiderRide(): Observable<PassengerRideView | null> {
    return this.http.get<PassengerRideView>(`${this.baseUrl}/riders/me/ride`, { observe: 'response' }).pipe(
      map((response) => response.body ?? null),
    );
  }

  cancelCurrentRiderRide(): Observable<PassengerRideView> {
    return this.http.delete<PassengerRideView>(`${this.baseUrl}/riders/me/ride`);
  }

  currentDriverRide(): Observable<DriverRideView | null> {
    return this.http.get<DriverRideView>(`${this.baseUrl}/drivers/me/ride`, { observe: 'response' }).pipe(
      map((response) => response.body ?? null),
    );
  }

  accept(rideId: string): Observable<void> {
    return this.http.post<void>(`${this.baseUrl}/rides/${rideId}/accept`, {});
  }

  decline(rideId: string): Observable<void> {
    return this.http.post<void>(`${this.baseUrl}/rides/${rideId}/decline`, {});
  }

  arrive(rideId: string): Observable<void> {
    return this.http.post<void>(`${this.baseUrl}/rides/${rideId}/arrive`, {});
  }

  pickup(rideId: string): Observable<void> {
    return this.http.post<void>(`${this.baseUrl}/rides/${rideId}/pickup`, {});
  }

  complete(rideId: string): Observable<void> {
    return this.http.post<void>(`${this.baseUrl}/rides/${rideId}/complete`, {});
  }

  cancel(rideId: string): Observable<void> {
    return this.http.post<void>(`${this.baseUrl}/rides/${rideId}/cancel`, {});
  }
}
