// GENERATED. axis combination: if_lt_len__mod_len__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = i;
    if base < s.len() {
        let idx = base % s.len();
        return s[idx];
    }
    0
}
