// The guard is on another path, so it does not dominate the index.
pub fn f(s: &[u32], i: usize, flag: bool) -> u32 {
    if flag && i < s.len() {
        return s[i];
    }
    s[i]
}
