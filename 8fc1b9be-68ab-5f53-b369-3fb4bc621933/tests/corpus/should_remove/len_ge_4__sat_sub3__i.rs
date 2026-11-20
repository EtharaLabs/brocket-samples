// GENERATED. axis combination: len_ge_4__sat_sub3__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    if s.len() < 4 {
        return 0;
    }
    let base = i;
    let idx = s.len().saturating_sub(3);
    s[idx]
}
