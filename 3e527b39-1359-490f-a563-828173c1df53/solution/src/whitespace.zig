const std = @import("std");
pub const Rules = struct {
    trailing: bool=true, eof: bool=true, space_tab: bool=true, indent: bool=false,
    tab: bool=false, cr: bool=false, incomplete: bool=false, width: usize=8,
    pub fn parse(text: []const u8) Rules {
        var rules=Rules{}; var words=std.mem.tokenizeAny(u8,text,", ");
        while (words.next()) |word| {
            if (std.mem.startsWith(u8,word,"tabwidth=")) { rules.width=@max(1,std.fmt.parseInt(usize,word[9..],10) catch 8); continue; }
            const enabled=word[0]!='-'; const key=if (enabled) word else word[1..];
            if (std.mem.eql(u8,key,"trailing-space")) { rules.trailing=enabled; rules.eof=enabled; }
            else if (std.mem.eql(u8,key,"blank-at-eol")) rules.trailing=enabled
            else if (std.mem.eql(u8,key,"blank-at-eof")) rules.eof=enabled
            else if (std.mem.eql(u8,key,"space-before-tab")) rules.space_tab=enabled
            else if (std.mem.eql(u8,key,"indent-with-non-tab")) rules.indent=enabled
            else if (std.mem.eql(u8,key,"tab-in-indent")) rules.tab=enabled
            else if (std.mem.eql(u8,key,"cr-at-eol")) rules.cr=enabled
            else if (std.mem.eql(u8,key,"incomplete")) rules.incomplete=enabled;
        }
        return rules;
    }
    pub fn errorMessage(self: Rules, raw: []const u8) ?[]const u8 {
        var text=std.mem.trimEnd(u8,raw,"\n"); if (self.cr and text.len>0 and text[text.len-1]=='\r') text=text[0..text.len-1];
        var indent: usize=0; var spaces: usize=0; var space_tab=false; var tab=false; var long_spaces=false;
        while (indent<text.len and (text[indent]==' ' or text[indent]=='\t')) : (indent+=1) {
            if (text[indent]==' ') { spaces+=1; if (spaces>=self.width) long_spaces=true; }
            else { if (spaces>0) space_tab=true; spaces=0; tab=true; }
        }
        var messages: std.ArrayList(u8)=.empty; const a=std.heap.page_allocator;
        const trailing=self.trailing and text.len>0 and std.ascii.isWhitespace(text[text.len-1]);
        if (trailing) messages.appendSlice(a,"trailing whitespace") catch unreachable;
        const extra: ?[]const u8=if (self.space_tab and space_tab) "space before tab in indent" else if (self.indent and long_spaces) "indent with spaces" else if (self.tab and tab) "tab in indent" else null;
        if (extra) |msg| { if (messages.items.len>0) messages.appendSlice(a,", ") catch unreachable; messages.appendSlice(a,msg) catch unreachable; }
        if (messages.items.len==0) return null;
        messages.append(a,'.') catch unreachable; return messages.items;
    }
};
test "space before tab applies only to indentation" {
    const rules=Rules{};
    try std.testing.expect(rules.errorMessage("a \tb\n")==null);
    try std.testing.expectEqualStrings("space before tab in indent.",rules.errorMessage(" \tb\n").?);
}
test "tab width controls non-tab indentation checks" {
    const rules=Rules.parse("indent-with-non-tab,tabwidth=9");
    try std.testing.expect(rules.errorMessage("        a\n")==null);
}
