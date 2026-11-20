// GENERATED. axis combination: unguarded__clamp_len2__j
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = j;
    let idx = base.clamp(1, s.len() - 2);
    s[idx]
}
