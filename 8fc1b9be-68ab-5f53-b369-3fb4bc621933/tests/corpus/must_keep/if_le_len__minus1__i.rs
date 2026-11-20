// GENERATED. axis combination: if_le_len__minus1__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = i;
    if base <= s.len() {
        let idx = base - 1;
        return s[idx];
    }
    0
}
