// GENERATED. axis combination: nonempty__sat_sub1__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    if s.is_empty() {
        return 0;
    }
    let base = i;
    let idx = s.len().saturating_sub(1);
    s[idx]
}
