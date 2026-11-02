const EARTH_RADIUS_METERS = 6_371_000;
const MAX_PLAUSIBLE_SPEED_METERS_PER_SECOND = 300;

function distanceMeters(first, second) {
    const toRadians = degrees => degrees * Math.PI / 180;
    const latitudeDelta = toRadians(second.latitude - first.latitude);
    const longitudeDelta = toRadians(second.longitude - first.longitude);
    const firstLatitude = toRadians(first.latitude);
    const secondLatitude = toRadians(second.latitude);

    const haversine = Math.min(1,
        Math.sin(latitudeDelta / 2) ** 2 +
        Math.cos(firstLatitude) *
            Math.cos(secondLatitude) *
            Math.sin(longitudeDelta / 2) ** 2);

    return 2 * EARTH_RADIUS_METERS *
        Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
}

function getLocationAnomalies(previous, current, receivedAt, isMocked) {
    const anomalies = [];

    if (isMocked) {
        anomalies.push('Perangkat menandai lokasi sebagai mock');
    }

    if (previous?.lastUpdated && previous.latitude != null && previous.longitude != null) {
        const elapsedSeconds =
            (receivedAt.getTime() - new Date(previous.lastUpdated).getTime()) / 1000;

        if (elapsedSeconds > 0) {
            const speed = distanceMeters(previous, current) / elapsedSeconds;

            if (speed > MAX_PLAUSIBLE_SPEED_METERS_PER_SECOND) {
                anomalies.push(
                    `Perpindahan tidak wajar (${Math.round(speed * 3.6)} km/jam)`
                );
            }
        }
    }

    return anomalies;
}

module.exports = { getLocationAnomalies };
