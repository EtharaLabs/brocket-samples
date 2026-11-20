// GENERATED. axis combination: len_ge_4__clamp_len2__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    if s.len() < 4 {
        return 0;
    }
    let base = i;
    let idx = base.clamp(1, s.len() - 2);
    s[idx]
}
