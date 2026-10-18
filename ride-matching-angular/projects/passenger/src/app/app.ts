import { Component, OnInit, inject } from '@angular/core';
import { MapLocation, MapMarker, RideMapComponent } from 'shared-map';
import { AuthFacade } from 'shared-auth';
import { isActiveRide, PassengerRideStore } from './passenger-ride.store';

@Component({
  imports: [RideMapComponent],
  selector: 'app-root',
  styleUrl: './app.scss',
  templateUrl: './app.html',
})
export class App implements OnInit {
  protected readonly auth = inject(AuthFacade);
  protected readonly rideStore = inject(PassengerRideStore);
  protected readonly isActiveRide = isActiveRide;
  protected pickup: MapLocation | null = null;
  protected destination: MapLocation | null = null;
  protected selectingPickup = true;

  ngOnInit(): void {
    void this.auth.initialize().then(() => {
      void this.rideStore.refresh();
      navigator.geolocation?.getCurrentPosition(
        ({ coords }) => {
          this.pickup = { latitude: coords.latitude, longitude: coords.longitude };
          this.selectingPickup = false;
        },
        () => undefined,
        { enableHighAccuracy: true, timeout: 10_000 },
      );
    });
  }

  protected selectLocation(location: MapLocation): void {
    if (!isActiveRide(this.rideStore.ride())) {
      if (this.selectingPickup || !this.pickup) {
        this.pickup = location;
        this.selectingPickup = false;
      } else {
        this.destination = location;
      }
    }
  }

  protected selectPickupOnMap(): void {
    this.selectingPickup = true;
  }

  protected mapCenter(): MapLocation {
    return this.pickup ?? { latitude: 51.5074, longitude: -0.1278 };
  }

  protected canRequestRide(): boolean {
    return this.pickup !== null && this.destination !== null && !isActiveRide(this.rideStore.ride());
  }

  protected requestRide(): void {
    if (this.pickup && this.destination) {
      void this.rideStore.requestRide(this.pickup, this.destination);
    }
  }

  protected logout(): void {
    this.rideStore.clear();
    this.auth.logout();
  }

  protected markers(): MapMarker[] {
    const ride = this.rideStore.ride();
    const markers: MapMarker[] = [];
    if (this.pickup) {
      markers.push({ location: this.pickup, label: 'Your pickup', color: '#d28a42' });
    }
    if (this.destination) {
      markers.push({ location: this.destination, label: 'Selected destination', color: '#6d5eb5' });
    }
    if (ride) {
      markers.push(
        { location: ride.pickup, label: `Pickup · ${ride.status}`, color: '#b85d4b' },
      );
      if (ride.driver) {
        markers.push({ location: ride.driver.location, label: `Driver · ${ride.driver.status}`, color: '#2563a6' });
      }
    }
    return markers;
  }
}
