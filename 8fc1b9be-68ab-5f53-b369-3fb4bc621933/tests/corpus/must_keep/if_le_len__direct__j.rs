// GENERATED. axis combination: if_le_len__direct__j
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = j;
    if base <= s.len() {
        let idx = base;
        return s[idx];
    }
    0
}
