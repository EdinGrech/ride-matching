import { AfterViewInit, Component, ElementRef, OnDestroy, ViewChild, effect, input, output } from '@angular/core';
import * as L from 'leaflet';

export interface MapLocation {
  latitude: number;
  longitude: number;
}

export interface MapMarker {
  location: MapLocation;
  label: string;
  color: string;
}

@Component({
  selector: 'rm-ride-map',
  template: '<div #map class="map" aria-label="Ride location map"></div>',
  styleUrl: './ride-map.scss',
})
export class RideMapComponent implements AfterViewInit, OnDestroy {
  @ViewChild('map') private mapElement?: ElementRef<HTMLDivElement>;

  readonly center = input.required<MapLocation>();
  readonly markers = input<MapMarker[]>([]);
  readonly locationSelected = output<MapLocation>();

  private map?: L.Map;
  private markerLayer?: L.LayerGroup;
  private renderedCenter?: MapLocation;

  constructor() {
    effect(() => {
      const center = this.center();
      this.markers();
      if (this.map && !sameLocation(center, this.renderedCenter)) {
        this.map.setView([center.latitude, center.longitude], this.map.getZoom());
        this.renderedCenter = center;
      }
      this.drawMarkers();
    });
  }

  ngAfterViewInit(): void {
    const element = this.mapElement?.nativeElement;
    if (!element) {
      return;
    }
    const center = this.center();
    this.map = L.map(element, { zoomControl: false }).setView([center.latitude, center.longitude], 13);
    this.renderedCenter = center;
    L.control.zoom({ position: 'bottomright' }).addTo(this.map);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
      maxZoom: 19,
    }).addTo(this.map);
    this.markerLayer = L.layerGroup().addTo(this.map);
    this.map.on('click', ({ latlng }) => {
      this.locationSelected.emit({
        latitude: Number(latlng.lat.toFixed(6)),
        longitude: Number(latlng.lng.toFixed(6)),
      });
    });
    this.drawMarkers();
  }

  ngOnDestroy(): void {
    this.map?.remove();
  }

  private drawMarkers(): void {
    if (!this.markerLayer) {
      return;
    }
    this.markerLayer.clearLayers();
    for (const marker of this.markers()) {
      L.circleMarker([marker.location.latitude, marker.location.longitude], {
        radius: 9,
        color: '#ffffff',
        weight: 2,
        fillColor: marker.color,
        fillOpacity: 1,
      }).bindTooltip(marker.label, { direction: 'top' }).addTo(this.markerLayer);
    }
  }
}

function sameLocation(a: MapLocation, b: MapLocation | undefined): boolean {
  return a.latitude === b?.latitude && a.longitude === b?.longitude;
}
