import ballerina/http;
import ballerina/log;

@http:ServiceConfig {cors: {allowOrigins: ["*"]}}
service /api/v1 on new http:Listener(port) {

    resource function get health() returns map<string> {
        return {status: "UP", 'service: SERVICE_NAME};
    }

    // Newest first. Without filters this is the platform-wide feed.
    // ?channel=IN_APP&unreadOnly=true gives a user's unread in-app inbox.
    resource function get notifications(RecipientType? recipientType = (), string? recipientId = (),
            Channel? channel = (), boolean unreadOnly = false, int 'limit = 50)
            returns Notification[]|http:InternalServerError {
        map<json> filter = recipientFilter(recipientType, recipientId);
        if channel is Channel {
            filter["channel"] = channel;
        }
        if unreadOnly {
            filter["read"] = {"$ne": true};
        }
        return query(filter, 'limit);
    }

    resource function get notifications/'order/[string orderId]() returns Notification[]|http:InternalServerError {
        return query({orderId}, 100);
    }

    // Badge number for the bell icon.
    resource function get notifications/unread\-count(RecipientType recipientType, string recipientId)
            returns record {|int count;|}|http:InternalServerError {
        do {
            int count = check notifications->countDocuments(
                {recipientType, recipientId, channel: IN_APP, read: {"$ne": true}});
            return {count};
        } on fail error e {
            return internalError(e);
        }
    }

    // Mark all of a user's in-app notifications as read.
    resource function post notifications/mark\-read(Recipient req) returns record {|int updated;|}|http:InternalServerError {
        do {
            var result = check notifications->updateMany(
                {recipientType: req.recipientType, recipientId: req.recipientId, channel: IN_APP, read: {"$ne": true}},
                {set: {read: true}});
            return {updated: result.modifiedCount};
        } on fail error e {
            return internalError(e);
        }
    }
}

isolated function recipientFilter(RecipientType? recipientType, string? recipientId) returns map<json> {
    map<json> filter = {};
    if recipientType is RecipientType {
        filter["recipientType"] = recipientType;
    }
    if recipientId is string {
        filter["recipientId"] = recipientId;
    }
    return filter;
}

isolated function query(map<json> filter, int 'limit) returns Notification[]|http:InternalServerError {
    do {
        stream<Notification, error?> result = check notifications->find(filter,
                {sort: {createdAt: -1}, 'limit: 'limit}, (), Notification);
        return check from Notification n in result select n;
    } on fail error e {
        return internalError(e);
    }
}

isolated function internalError(error e) returns http:InternalServerError {
    log:printError("request failed", e);
    return {body: {message: "internal error"}};
}
