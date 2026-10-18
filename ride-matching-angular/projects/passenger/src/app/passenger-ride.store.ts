import { DestroyRef, inject } from '@angular/core';
import { patchState, signalStore, withHooks, withMethods, withState } from '@ngrx/signals';
import { firstValueFrom } from 'rxjs';
import { Location, PassengerRideView, RideApi } from 'shared-api';
import { AuthFacade } from 'shared-auth';

interface PassengerRideState {
  ride: PassengerRideView | null;
  loading: boolean;
  error: string | null;
}

const initialState: PassengerRideState = {
  ride: null,
  loading: false,
  error: null,
};

export const PassengerRideStore = signalStore(
  { providedIn: 'root' },
  withState(initialState),
  withMethods((store, api = inject(RideApi), auth = inject(AuthFacade)) => {
    let inFlight = false;
    const run = async (request: () => Promise<PassengerRideView | null>): Promise<void> => {
      if (inFlight) {
        return;
      }
      inFlight = true;
      patchState(store, { loading: true, error: null });
      try {
        patchState(store, { ride: await request() });
      } catch (error: unknown) {
        const response = error as { error?: { message?: string }; message?: string };
        patchState(store, { error: response.error?.message ?? response.message ?? 'The request failed.' });
      } finally {
        patchState(store, { loading: false });
        inFlight = false;
      }
    };
    return {
      async requestRide(pickup: Location, destination: Location): Promise<void> {
        await run(() => firstValueFrom(api.requestRide(pickup, destination)));
      },
      async cancelRide(): Promise<void> {
        await run(() => firstValueFrom(api.cancelCurrentRiderRide()));
      },
      async refresh(): Promise<void> {
        if (auth.hasRole('RIDER')) {
          const previousRide = store.ride();
          await run(async () => {
            const ride = await firstValueFrom(api.currentRiderRide());
            return ride ?? (previousRide?.status === 'IN_PROGRESS' ? { ...previousRide, status: 'COMPLETED' } : null);
          });
        }
      },
      clear(): void {
        patchState(store, initialState);
      },
    };
  }),
  withHooks((store, auth = inject(AuthFacade), destroyRef = inject(DestroyRef)) => ({
    onInit() {
      const poller = window.setInterval(() => {
        if (auth.hasRole('RIDER') && isActiveRide(store.ride())) {
          void store.refresh();
        }
      }, 5_000);
      destroyRef.onDestroy(() => window.clearInterval(poller));
    },
  })),
);

export function isActiveRide(ride: PassengerRideView | null): boolean {
  return ride !== null && ride.status !== 'COMPLETED' && ride.status !== 'CANCELLED';
}
