// GENERATED. axis combination: nonempty__mod_len__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    if s.is_empty() {
        return 0;
    }
    let base = i;
    let idx = base % s.len();
    s[idx]
}
