import ballerina/time;

// Opening-hours logic. Namibia is UTC+2 all year (no daylight saving since
// 2017), so local time is computed with a fixed offset.

configurable int utcOffsetHours = 2;

# Turn this off to accept orders around the clock (handy for late-night testing).
configurable boolean enforceOpeningHours = true;

// Index 0 = Sunday, to match the epoch arithmetic below.
final readonly & Day[] daysFromSunday = [SUN, MON, TUE, WED, THU, FRI, SAT];

isolated function isOpenNow(OpeningHours[] hours) returns boolean {
    int localSeconds = time:utcNow()[0] + utcOffsetHours * 3600;
    int days = localSeconds / 86400;
    // 1970-01-01 was a Thursday (index 4).
    Day today = daysFromSunday[(days + 4) % 7];
    int minuteOfDay = (localSeconds % 86400) / 60;

    foreach OpeningHours h in hours {
        if h.day == today && minuteOfDay >= toMinutes(h.open) && minuteOfDay < toMinutes(h.close) {
            return true;
        }
    }
    return false;
}

isolated function acceptsOrders(Restaurant r) returns boolean => !enforceOpeningHours || isOpenNow(r.openingHours);

isolated function toMinutes(string hhmm) returns int {
    int|error h = int:fromString(hhmm.substring(0, 2));
    int|error m = int:fromString(hhmm.substring(3, 5));
    return (h is int ? h : 0) * 60 + (m is int ? m : 0);
}
