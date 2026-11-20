// GENERATED. axis combination: if_le_len__sat_sub1__j
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = j;
    if base <= s.len() {
        let idx = s.len().saturating_sub(1);
        return s[idx];
    }
    0
}
