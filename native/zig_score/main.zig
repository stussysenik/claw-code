const std = @import("std");

const Match = struct {
    score: usize,
    kind: []const u8,
    name: []const u8,
    source_hint: []const u8,
    responsibility: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("usage: zig-score <query> <limit>\n", .{});
        std.process.exit(1);
    }

    const query = args[1];
    const limit = try std.fmt.parseInt(usize, args[2], 10);
    const input = try std.fs.File.stdin().readToEndAlloc(allocator, 8 * 1024 * 1024);
    defer allocator.free(input);

    var tokens = try collectTokens(allocator, query);
    defer {
        for (tokens.items) |token| allocator.free(token);
        tokens.deinit();
    }

    var matches = std.ArrayList(Match).init(allocator);
    defer matches.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (line.len == 0) continue;

        var fields = std.mem.splitScalar(u8, line, '\t');
        const kind = fields.next() orelse continue;
        const name = fields.next() orelse continue;
        const source_hint = fields.next() orelse continue;
        const responsibility = fields.next() orelse continue;

        const score = try scoreLine(allocator, line, tokens.items);
        if (score == 0) continue;

        try matches.append(.{
            .score = score,
            .kind = kind,
            .name = name,
            .source_hint = source_hint,
            .responsibility = responsibility,
        });
    }

    selectionSort(matches.items);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    const capped = @min(limit, matches.items.len);

    var index: usize = 0;
    while (index < capped) : (index += 1) {
        const item = matches.items[index];
        try stdout.print(
            "{d}\t{s}\t{s}\t{s}\t{s}\n",
            .{ item.score, item.kind, item.name, item.source_hint, item.responsibility },
        );
    }

    try stdout.flush();
}

fn collectTokens(allocator: std.mem.Allocator, query: []const u8) !std.ArrayList([]u8) {
    var tokens = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (tokens.items) |token| allocator.free(token);
        tokens.deinit();
    }

    var parts = std.mem.tokenizeAny(u8, query, " /_-\t\r\n");
    while (parts.next()) |part| {
        const lowered = try lowerAlloc(allocator, part);
        try tokens.append(lowered);
    }

    return tokens;
}

fn scoreLine(allocator: std.mem.Allocator, line: []const u8, tokens: []const []u8) !usize {
    const lowered = try lowerAlloc(allocator, line);
    defer allocator.free(lowered);

    var score: usize = 0;
    for (tokens) |token| {
        if (token.len == 0) continue;
        if (std.mem.indexOf(u8, lowered, token) != null) {
            score += 1;
        }
    }

    return score;
}

fn lowerAlloc(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const buffer = try allocator.alloc(u8, value.len);

    for (value, 0..) |char, index| {
        buffer[index] = std.ascii.toLower(char);
    }

    return buffer;
}

fn selectionSort(items: []Match) void {
    var index: usize = 0;
    while (index < items.len) : (index += 1) {
        var best = index;
        var cursor = index + 1;

        while (cursor < items.len) : (cursor += 1) {
            if (lessThan(items[cursor], items[best])) {
                best = cursor;
            }
        }

        if (best != index) {
            const tmp = items[index];
            items[index] = items[best];
            items[best] = tmp;
        }
    }
}

fn lessThan(left: Match, right: Match) bool {
    if (left.score != right.score) return left.score > right.score;
    return std.mem.order(u8, left.name, right.name) == .lt;
}
