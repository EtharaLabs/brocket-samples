// GENERATED. axis combination: if_lt_len__lenminus1__j
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = j;
    if base < s.len() {
        let idx = s.len() - 1;
        return s[idx];
    }
    0
}
