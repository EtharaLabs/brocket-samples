// MUST KEEP. max(i, len-1) is at least len-1 but unbounded above, so s[j] can exceed len.
// Punishes confusing the direction of a comparison summary.
pub fn f(s: &[u32], i: usize) -> u32 {
    if s.is_empty() {
        return 0;
    }
    let j = i.max(s.len() - 1);
    s[j]
}
