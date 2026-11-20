// GENERATED. axis combination: nonempty__max_len1__j
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    if s.is_empty() {
        return 0;
    }
    let base = j;
    let idx = base.max(s.len() - 1);
    s[idx]
}
