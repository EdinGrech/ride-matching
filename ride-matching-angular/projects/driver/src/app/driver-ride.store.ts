import { DestroyRef, inject } from '@angular/core';
import { patchState, signalStore, withHooks, withMethods, withState } from '@ngrx/signals';
import { firstValueFrom } from 'rxjs';
import { DriverRideView, DriverStatus, DriverView, Location, RideApi } from 'shared-api';
import { AuthFacade } from 'shared-auth';

interface DriverRideState {
  driver: DriverView | null;
  ride: DriverRideView | null;
  loading: boolean;
  error: string | null;
}

const initialState: DriverRideState = {
  driver: null,
  ride: null,
  loading: false,
  error: null,
};

export const DriverRideStore = signalStore(
  { providedIn: 'root' },
  withState(initialState),
  withMethods((store, api = inject(RideApi), auth = inject(AuthFacade)) => {
    let inFlight = false;
    const reload = () => firstValueFrom(api.currentDriverState());
    const run = async <T>(request: () => Promise<T>, update: (value: T) => void): Promise<void> => {
      if (inFlight) {
        return;
      }
      inFlight = true;
      patchState(store, { loading: true, error: null });
      try {
        update(await request());
      } catch (error: unknown) {
        patchState(store, { error: messageOf(error) });
      } finally {
        patchState(store, { loading: false });
        inFlight = false;
      }
    };
    return {
      async setAvailability(available: boolean, location: Location): Promise<void> {
        await run(
          async () => {
            await firstValueFrom(api.setAvailability(available, location));
            return reload();
          },
          ({ driver, ride }) => patchState(store, { driver, ride }),
        );
      },
      async updateLocation(location: Location): Promise<void> {
        await run(
          () => firstValueFrom(api.updateLocation(location)),
          (driver) => patchState(store, { driver }),
        );
      },
      async refresh(): Promise<void> {
        if (auth.hasRole('DRIVER')) {
          await run(reload, ({ driver, ride }) => patchState(store, { driver, ride }));
        }
      },
      async accept(): Promise<void> {
        await transition((rideId) => api.accept(rideId));
      },
      async decline(): Promise<void> {
        await transition((rideId) => api.decline(rideId));
      },
      async arrive(): Promise<void> {
        await transition((rideId) => api.arrive(rideId));
      },
      async pickup(): Promise<void> {
        await transition((rideId) => api.pickup(rideId));
      },
      async complete(): Promise<void> {
        await transition((rideId) => api.complete(rideId));
      },
      async cancel(): Promise<void> {
        await transition((rideId) => api.cancel(rideId));
      },
      clear(): void {
        patchState(store, initialState);
      },
    };

    async function transition(action: (rideId: string) => ReturnType<RideApi['accept']>): Promise<void> {
      const ride = store.ride();
      if (ride) {
        await run(
          async () => {
            await firstValueFrom(action(ride.id));
            return reload();
          },
          ({ driver, ride: refreshedRide }) => patchState(store, { driver, ride: refreshedRide }),
        );
      }
    }
  }),
  withHooks((store, auth = inject(AuthFacade), destroyRef = inject(DestroyRef)) => ({
    onInit() {
      const poller = window.setInterval(() => {
        if (auth.hasRole('DRIVER') && shouldPoll(store.driver()?.status)) {
          void store.refresh();
        }
      }, 5_000);
      destroyRef.onDestroy(() => window.clearInterval(poller));
    },
  })),
);

export function shouldPoll(status: DriverStatus | undefined): boolean {
  return status === 'AVAILABLE' || status === 'OFFERED' || status === 'DRIVING_TO_PICKUP' || status === 'WAITING_AT_PICKUP' || status === 'DRIVING_TO_DESTINATION';
}

export function shouldUpdateLocation(status: DriverStatus | undefined): boolean {
  return status === 'AVAILABLE' || status === 'DRIVING_TO_PICKUP' || status === 'WAITING_AT_PICKUP' || status === 'DRIVING_TO_DESTINATION';
}

function messageOf(error: unknown): string {
  const response = error as { error?: { message?: string }; message?: string };
  return response.error?.message ?? response.message ?? 'The request failed.';
}
