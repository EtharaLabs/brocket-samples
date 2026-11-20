const std=@import("std");
const a=std.heap.page_allocator;
pub const Token=union(enum) { pattern: usize, conjunction, disjunction, negation, open, close };
const Pair=struct { left: usize, right: usize };
const Node=union(enum) { pattern: usize, conjunction: Pair, disjunction: Pair, negation: usize };
pub const Expression=struct {
    tokens: []const Token, pos: usize=0, nodes: std.ArrayList(Node)=.empty, root: usize=0,
    pub fn parse(tokens: []const Token) ?Expression {
        var self=Expression{.tokens=tokens};
        self.root=self.disjunction() orelse return null;
        if (self.pos!=tokens.len) return null;
        return self;
    }
    fn add(self: *Expression,node: Node) usize { self.nodes.append(a,node) catch unreachable; return self.nodes.items.len-1; }
    fn unary(self: *Expression) ?usize {
        if (self.pos==self.tokens.len) return null;
        const token=self.tokens[self.pos]; self.pos+=1;
        return switch (token) {
            .pattern=>|p| self.add(.{.pattern=p}),
            .negation=>self.add(.{.negation=self.unary() orelse return null}),
            .open=>blk: {
                const inner=self.disjunction() orelse return null;
                if (self.pos==self.tokens.len or self.tokens[self.pos]!=.close) return null;
                self.pos+=1; break :blk inner;
            },
            else=>null,
        };
    }
    fn conjunction(self: *Expression) ?usize {
        var left=self.unary() orelse return null;
        while (self.pos<self.tokens.len and self.tokens[self.pos]==.conjunction) {
            self.pos+=1;
            left=self.add(.{.conjunction=.{.left=left,.right=self.unary() orelse return null}});
        }
        return left;
    }
    fn disjunction(self: *Expression) ?usize {
        var left=self.conjunction() orelse return null;
        while (self.pos<self.tokens.len and self.tokens[self.pos]!=.close) {
            if (self.tokens[self.pos]==.disjunction) self.pos+=1;
            left=self.add(.{.disjunction=.{.left=left,.right=self.conjunction() orelse return null}});
        }
        return left;
    }
    pub fn evaluate(self: Expression,node: usize,values: []const bool) bool {
        return switch (self.nodes.items[node]) {
            .pattern=>|p| values[p],
            .negation=>|n| !self.evaluate(n,values),
            .conjunction=>|p| self.evaluate(p.left,values) and self.evaluate(p.right,values),
            .disjunction=>|p| self.evaluate(p.left,values) or self.evaluate(p.right,values),
        };
    }
    pub fn allMatch(self: Expression,node: usize,rows: []const []bool) bool {
        switch (self.nodes.items[node]) {
            .disjunction=>|p| return self.allMatch(p.left,rows) and self.allMatch(p.right,rows),
            else=> { for (rows) |row| { if (self.evaluate(node,row)) return true; } return false; },
        }
    }
};

test "and binds tighter than implicit or, with negation and grouping" {
    const expr=Expression.parse(&.{.{.pattern=0},.{.pattern=1},.conjunction,.negation,.open,.{.pattern=2},.disjunction,.{.pattern=3},.close}).?;
    try std.testing.expect(expr.evaluate(expr.root,&.{true,false,true,true}));
    try std.testing.expect(expr.evaluate(expr.root,&.{false,true,false,false}));
    try std.testing.expect(!expr.evaluate(expr.root,&.{false,true,true,false}));
}
test "invalid expressions fail instead of becoming a permissive match" {
    try std.testing.expect(Expression.parse(&.{.conjunction,.{.pattern=0}})==null);
    try std.testing.expect(Expression.parse(&.{.open,.{.pattern=0}})==null);
    try std.testing.expect(Expression.parse(&.{.{.pattern=0},.disjunction})==null);
}
