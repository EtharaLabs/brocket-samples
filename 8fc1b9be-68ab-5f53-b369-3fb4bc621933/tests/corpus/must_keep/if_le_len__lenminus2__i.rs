// GENERATED. axis combination: if_le_len__lenminus2__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = i;
    if base <= s.len() {
        let idx = s.len() - 2;
        return s[idx];
    }
    0
}
