import ballerina/http;
import ballerina/log;
import ballerina/uuid;

type CustomerCreated record {|
    *http:Created;
    Customer body;
|};

@http:ServiceConfig {cors: {allowOrigins: ["*"]}}
service /api/v1 on new http:Listener(port) {

    resource function get health() returns map<string> {
        return {status: "UP", 'service: SERVICE_NAME};
    }

    resource function get customers() returns Customer[]|http:InternalServerError {
        Customer[]|error result = listCustomers();
        return result is error ? internalError(result) : result;
    }

    resource function post customers(NewCustomer req) returns CustomerCreated|http:Conflict|http:InternalServerError {
        do {
            if check emailTaken(req.email) {
                return <http:Conflict>{body: <ErrorBody>{message: "email already registered"}};
            }
            Customer c = {
                customerId: "cust-" + shortId(),
                name: req.name,
                email: req.email,
                phone: req.phone,
                addresses: from int i in 0 ..< req.addresses.length()
                    select toAddress(req.addresses[i], i == 0 && !hasDefault(req.addresses)),
                createdAt: nowIso()
            };
            check insertCustomer(c);
            log:printInfo("customer registered", customerId = c.customerId);
            return <CustomerCreated>{headers: {"Location": "/api/v1/customers/" + c.customerId}, body: c};
        } on fail error e {
            // The unique index on email catches a race between two registrations.
            if isDuplicateKey(e) {
                return <http:Conflict>{body: <ErrorBody>{message: "email already registered"}};
            }
            return internalError(e);
        }
    }

    resource function get customers/[string customerId]() returns Customer|http:NotFound|http:InternalServerError {
        Customer|error c = findCustomer(customerId);
        return c is error ? errorResponse(c) : c;
    }

    resource function put customers/[string customerId](CustomerUpdate req)
            returns Customer|http:NotFound|http:InternalServerError {
        do {
            map<json> fields = {};
            if req.name is string {
                fields["name"] = req.name;
            }
            if req.phone is string {
                fields["phone"] = req.phone;
            }
            if fields.length() > 0 && !check updateCustomer(customerId, fields) {
                return <http:NotFound>{body: <ErrorBody>{message: string `customer ${customerId} not found`}};
            }
            return check findCustomer(customerId);
        } on fail error e {
            return errorResponse(e);
        }
    }

    resource function get customers/[string customerId]/addresses()
            returns CustomerAddress[]|http:NotFound|http:InternalServerError {
        Customer|error c = findCustomer(customerId);
        return c is error ? errorResponse(c) : c.addresses;
    }

    resource function post customers/[string customerId]/addresses(NewAddress req)
            returns CustomerAddress[]|http:NotFound|http:InternalServerError {
        do {
            if !check addAddress(customerId, toAddress(req, req.isDefault)) {
                return <http:NotFound>{body: <ErrorBody>{message: string `customer ${customerId} not found`}};
            }
            return (check findCustomer(customerId)).addresses;
        } on fail error e {
            return errorResponse(e);
        }
    }

    resource function delete customers/[string customerId]/addresses/[string addressId]()
            returns http:NoContent|http:NotFound|http:InternalServerError {
        boolean|error removed = removeAddress(customerId, addressId);
        if removed is error {
            return internalError(removed);
        }
        return removed ? http:NO_CONTENT : <http:NotFound>{body: <ErrorBody>{message: "address not found"}};
    }

    resource function get customers/[string customerId]/orders(int 'limit = 20)
            returns OrderHistoryEntry[]|http:InternalServerError {
        OrderHistoryEntry[]|error result = customerOrders(customerId, 'limit);
        return result is error ? internalError(result) : result;
    }
}

isolated function toAddress(NewAddress a, boolean isDefault) returns CustomerAddress => {
    addressId: "addr-" + shortId(),
    label: a.label,
    street: a.street,
    city: a.city,
    postalCode: a.postalCode,
    latitude: a.latitude,
    longitude: a.longitude,
    isDefault
};

isolated function hasDefault(NewAddress[] addresses) returns boolean {
    foreach NewAddress a in addresses {
        if a.isDefault {
            return true;
        }
    }
    return false;
}

isolated function shortId() returns string => uuid:createType4AsString().substring(0, 8);

isolated function errorResponse(error e) returns http:NotFound|http:InternalServerError {
    if e is CustomerNotFoundError {
        return <http:NotFound>{body: <ErrorBody>{message: e.message()}};
    }
    return internalError(e);
}

isolated function internalError(error e) returns http:InternalServerError {
    log:printError("request failed", e);
    return {body: <ErrorBody>{message: "internal error"}};
}
