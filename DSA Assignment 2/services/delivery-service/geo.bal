import ballerina/lang.'float as floats;

// Distance and ETA estimates.

const float EARTH_RADIUS_KM = 6371.0;

// Great-circle distance between two points (haversine formula).
isolated function distanceKm(GeoPoint a, GeoPoint b) returns float {
    float dLat = toRadians(b.latitude - a.latitude);
    float dLon = toRadians(b.longitude - a.longitude);
    float h = floats:sin(dLat / 2) * floats:sin(dLat / 2)
        + floats:cos(toRadians(a.latitude)) * floats:cos(toRadians(b.latitude))
        * floats:sin(dLon / 2) * floats:sin(dLon / 2);
    return 2 * EARTH_RADIUS_KM * floats:atan2(floats:sqrt(h), floats:sqrt(1 - h));
}

isolated function toRadians(float degrees) returns float => degrees * floats:PI / 180;

// Typical city speeds in km/h.
isolated function speedKmh(string? vehicle) returns float {
    match vehicle {
        "Car" => {
            return 25;
        }
        "Bicycle" => {
            return 12;
        }
        _ => {
            return 30;
        }
    }
}

// Driver -> restaurant -> customer. Roads aren't straight, so the straight
// line distance is scaled by 1.3. Never less than 5 minutes.
isolated function etaMinutes(Driver driver, GeoPoint pickup, GeoPoint? dropoff) returns int {
    float km = distanceKm(driver.location, pickup);
    if dropoff is GeoPoint {
        km += distanceKm(pickup, dropoff);
    }
    float minutes = km * 1.3 / speedKmh(driver?.vehicle) * 60;
    int rounded = <int>floats:ceiling(minutes);
    return rounded < 5 ? 5 : rounded;
}
