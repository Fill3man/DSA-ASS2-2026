import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerinax/mongodb;

type RestaurantCreated record {|
    *http:Created;
    Restaurant body;
|};

type MenuItemCreated record {|
    *http:Created;
    MenuItem body;
|};

@http:ServiceConfig {cors: {allowOrigins: ["*"]}}
service /api/v1 on new http:Listener(port) {

    resource function get health() returns map<string> {
        return {status: "UP", 'service: SERVICE_NAME};
    }

    resource function post restaurants(NewRestaurant req) returns RestaurantCreated|http:InternalServerError {
        Restaurant r = {
            restaurantId: "rest-" + shortId(),
            name: req.name,
            cuisine: req?.cuisine,
            address: req.address,
            location: req.location,
            openingHours: req.openingHours
        };
        error? saved = insertRestaurant(r);
        if saved is error {
            return internalError(saved);
        }
        return <RestaurantCreated>{headers: {"Location": "/api/v1/restaurants/" + r.restaurantId}, body: r};
    }

    resource function get restaurants(string? cuisine = (), boolean openNow = false)
            returns RestaurantView[]|http:InternalServerError {
        Restaurant[]|error all = listRestaurants(cuisine);
        if all is error {
            return internalError(all);
        }
        RestaurantView[] views = from Restaurant r in all select view(r);
        return openNow ? views.filter(v => v.openNow) : views;
    }

    resource function get restaurants/[string restaurantId]() returns RestaurantView|http:NotFound|http:InternalServerError {
        Restaurant|error r = findRestaurant(restaurantId);
        return r is error ? errorResponse(r) : view(r);
    }

    resource function put restaurants/[string restaurantId]/opening\-hours(OpeningHours[] hours)
            returns RestaurantView|http:NotFound|http:InternalServerError {
        do {
            if !check setOpeningHours(restaurantId, hours) {
                return <http:NotFound>{body: <ErrorBody>{message: string `restaurant ${restaurantId} not found`}};
            }
            return view(check findRestaurant(restaurantId));
        } on fail error e {
            return errorResponse(e);
        }
    }

    resource function get restaurants/[string restaurantId]/menu(boolean availableOnly = false)
            returns MenuItem[]|http:InternalServerError {
        MenuItem[]|error menu = listMenu(restaurantId, availableOnly);
        return menu is error ? internalError(menu) : menu;
    }

    resource function post restaurants/[string restaurantId]/menu(NewMenuItem req)
            returns MenuItemCreated|http:NotFound|http:InternalServerError {
        do {
            _ = check findRestaurant(restaurantId);
            MenuItem m = {
                itemId: "item-" + shortId(),
                restaurantId,
                name: req.name,
                description: req?.description,
                category: req?.category,
                price: req.price,
                available: req.available,
                stock: req.stock
            };
            check insertMenuItem(m);
            return <MenuItemCreated>{headers: {"Location": string `/api/v1/restaurants/${restaurantId}/menu/${m.itemId}`}, body: m};
        } on fail error e {
            return errorResponse(e);
        }
    }

    resource function patch restaurants/[string restaurantId]/menu/[string itemId](MenuItemUpdate req)
            returns MenuItem|http:NotFound|http:InternalServerError {
        map<json> fields = {};
        foreach [string, anydata] [k, v] in req.entries() {
            fields[k] = v.toJson();
        }
        return applyMenuUpdate(restaurantId, itemId, {set: fields});
    }

    resource function patch restaurants/[string restaurantId]/menu/[string itemId]/stock(StockChange req)
            returns MenuItem|http:BadRequest|http:NotFound|http:InternalServerError {
        if req?.set is int {
            return applyMenuUpdate(restaurantId, itemId, {set: {stock: req?.set}});
        }
        int? delta = req?.delta;
        if delta is int {
            // Never let a manual adjustment push stock below zero.
            MenuItem|error current = findMenuItem(restaurantId, itemId);
            if current is error {
                return errorResponse(current);
            }
            if current.stock + delta < 0 {
                return <http:BadRequest>{body: <ErrorBody>{message: string `only ${current.stock} in stock`}};
            }
            return applyMenuUpdate(restaurantId, itemId, {inc: {stock: delta}});
        }
        return <http:BadRequest>{body: <ErrorBody>{message: "send either {\"delta\": n} or {\"set\": n}"}};
    }
}

isolated function applyMenuUpdate(string restaurantId, string itemId, mongodb:Update update)
        returns MenuItem|http:NotFound|http:InternalServerError {
    do {
        if !check updateMenuItem(restaurantId, itemId, update) {
            return <http:NotFound>{body: <ErrorBody>{message: string `menu item ${itemId} not found`}};
        }
        return check findMenuItem(restaurantId, itemId);
    } on fail error e {
        return errorResponse(e);
    }
}

isolated function view(Restaurant r) returns RestaurantView => {...r, openNow: isOpenNow(r.openingHours)};

isolated function shortId() returns string => uuid:createType4AsString().substring(0, 8);

isolated function errorResponse(error e) returns http:NotFound|http:InternalServerError {
    if e is NotFoundError {
        return <http:NotFound>{body: <ErrorBody>{message: e.message()}};
    }
    return internalError(e);
}

isolated function internalError(error e) returns http:InternalServerError {
    log:printError("request failed", e);
    return {body: <ErrorBody>{message: "internal error"}};
}
