pub fn f(s: &[u32], a: usize) -> u32 {
    if a <= s.len() { return s[a.max(s.len() - 1)] }
    0
}
