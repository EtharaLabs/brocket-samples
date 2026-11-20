// GENERATED. axis combination: if_lt_len__sat_sub3__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = i;
    if base < s.len() {
        let idx = s.len().saturating_sub(3);
        return s[idx];
    }
    0
}
