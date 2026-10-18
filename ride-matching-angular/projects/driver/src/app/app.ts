import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { MapLocation, MapMarker, RideMapComponent } from 'shared-map';
import { AuthFacade } from 'shared-auth';
import { DriverRideStore, shouldUpdateLocation } from './driver-ride.store';

const PICKUP_RADIUS_METRES = 50;

@Component({
  imports: [RideMapComponent],
  selector: 'app-root',
  styleUrl: './app.scss',
  templateUrl: './app.html',
})
export class App implements OnInit, OnDestroy {
  protected readonly auth = inject(AuthFacade);
  protected readonly rideStore = inject(DriverRideStore);
  protected location: MapLocation = { latitude: 51.5074, longitude: -0.1278 };
  private locationPoller?: number;

  ngOnInit(): void {
    void this.initialize();
  }

  ngOnDestroy(): void {
    window.clearInterval(this.locationPoller);
  }

  private async initialize(): Promise<void> {
    await this.auth.initialize();
    await this.rideStore.refresh();
    const driverLocation = this.rideStore.driver()?.location;
    if (driverLocation) {
      this.location = driverLocation;
    }
    this.locationPoller = window.setInterval(() => {
      if (shouldUpdateLocation(this.rideStore.driver()?.status)) {
        void this.rideStore.updateLocation(this.location);
      }
    }, 10_000);
  }

  protected selectedLocation(): MapLocation {
    return this.location;
  }

  protected selectLocation(location: MapLocation): void {
    this.location = location;
    if (shouldUpdateLocation(this.rideStore.driver()?.status)) {
      void this.rideStore.updateLocation(location);
    }
  }

  protected setAvailability(available: boolean): void {
    void this.rideStore.setAvailability(available, this.selectedLocation());
  }

  protected withinPickupRadius(): boolean {
    const pickup = this.rideStore.ride()?.pickup;
    return pickup !== undefined && distanceMetres(this.location, pickup) <= PICKUP_RADIUS_METRES;
  }

  protected logout(): void {
    this.rideStore.clear();
    this.auth.logout();
  }

  protected markers(): MapMarker[] {
    const location = this.selectedLocation();
    const ride = this.rideStore.ride();
    const markers: MapMarker[] = [{ location, label: 'Current driver location', color: '#276749' }];
    if (ride) {
      markers.push({ location: ride.pickup, label: 'Passenger pickup', color: '#b85d4b' });
      if (ride.destination) {
        markers.push({ location: ride.destination, label: 'Passenger destination', color: '#6d5eb5' });
      }
    }
    return markers;
  }
}

function distanceMetres(a: MapLocation, b: MapLocation): number {
  const radians = Math.PI / 180;
  const latitude = (b.latitude - a.latitude) * radians;
  const longitude = (b.longitude - a.longitude) * radians;
  const arc = Math.sin(latitude / 2) ** 2 + Math.cos(a.latitude * radians) * Math.cos(b.latitude * radians) * Math.sin(longitude / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(arc), Math.sqrt(1 - arc));
}
