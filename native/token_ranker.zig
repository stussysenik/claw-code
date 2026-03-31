const std = @import("std");

const Row = struct {
    kind: []const u8,
    name: []const u8,
    source_hint: []const u8,
    score: usize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) return;

    const input = try std.fs.cwd().readFileAlloc(allocator, args[1], 16 * 1024 * 1024);
    defer allocator.free(input);

    var lines = std.mem.splitScalar(u8, input, '\n');
    const prompt_line = lines.next() orelse return;

    if (!std.mem.startsWith(u8, prompt_line, "prompt\t")) return;

    const prompt = prompt_line["prompt\t".len..];
    var prompt_tokens = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer {
        for (prompt_tokens.items) |token| allocator.free(token);
        prompt_tokens.deinit(allocator);
    }
    try collectTokensLower(allocator, prompt, &prompt_tokens);

    var rows = try std.ArrayList(Row).initCapacity(allocator, 0);
    defer rows.deinit(allocator);

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (!std.mem.startsWith(u8, line, "entry\t")) continue;

        var fields = std.mem.splitScalar(u8, line, '\t');
        _ = fields.next();
        const kind = fields.next() orelse continue;
        const name = fields.next() orelse continue;
        const source_hint = fields.next() orelse continue;
        const responsibility = fields.next() orelse "";

        const haystack = try std.mem.concat(allocator, u8, &[_][]const u8{ name, " ", source_hint, " ", responsibility });
        defer allocator.free(haystack);

        const lower_haystack = try asciiLower(allocator, haystack);
        defer allocator.free(lower_haystack);
        const lower_name = try asciiLower(allocator, name);
        defer allocator.free(lower_name);

        var score: usize = 0;
        for (prompt_tokens.items) |token| {
            if (token.len == 0) continue;
            if (std.mem.eql(u8, token, lower_name)) {
                score += 3;
                continue;
            }
            if (std.mem.indexOf(u8, lower_haystack, token) != null) {
                score += 1;
            }
        }

        try rows.append(allocator, .{
            .kind = kind,
            .name = name,
            .source_hint = source_hint,
            .score = score,
        });
    }

    sortRows(rows.items);

    const stdout = std.fs.File.stdout().deprecatedWriter();
    for (rows.items) |row| {
        try stdout.print("{s}\t{s}\t{s}\t{}\n", .{ row.kind, row.name, row.source_hint, row.score });
    }
}

fn sortRows(rows: []Row) void {
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        var best = i;
        var j = i + 1;
        while (j < rows.len) : (j += 1) {
            if (rows[j].score > rows[best].score) {
                best = j;
            } else if (rows[j].score == rows[best].score and std.mem.order(u8, rows[j].name, rows[best].name) == .lt) {
                best = j;
            }
        }
        if (best != i) {
            const tmp = rows[i];
            rows[i] = rows[best];
            rows[best] = tmp;
        }
    }
}

fn collectTokensLower(allocator: std.mem.Allocator, input: []const u8, output: *std.ArrayList([]const u8)) !void {
    const lower = try asciiLower(allocator, input);
    defer allocator.free(lower);
    var token_start: ?usize = null;

    var index: usize = 0;
    while (index < lower.len) : (index += 1) {
        const ch = lower[index];
        const is_word = std.ascii.isAlphanumeric(ch) or ch == '_';

        if (is_word and token_start == null) {
            token_start = index;
        } else if (!is_word and token_start != null) {
            const start = token_start.?;
            if (index > start) {
                try output.append(allocator, try allocator.dupe(u8, lower[start..index]));
            }
            token_start = null;
        }
    }

    if (token_start) |start| {
        if (lower.len > start) {
            try output.append(allocator, try allocator.dupe(u8, lower[start..lower.len]));
        }
    }
}

fn asciiLower(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const buffer = try allocator.alloc(u8, input.len);
    for (input, 0..) |ch, idx| {
        buffer[idx] = std.ascii.toLower(ch);
    }
    return buffer;
}
