// GENERATED. axis combination: len_ge_4__min_len1__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    if s.len() < 4 {
        return 0;
    }
    let base = i;
    let idx = base.min(s.len() - 1);
    s[idx]
}
