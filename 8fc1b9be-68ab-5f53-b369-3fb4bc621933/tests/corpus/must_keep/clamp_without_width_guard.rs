// MUST KEEP. With len 1, `len - 2` wraps, clamp(1, huge) returns at least 1, and s[1] panics.
pub fn f(s: &[u32], i: usize) -> u32 {
    let j = i.clamp(1, s.len() - 2);
    s[j]
}
