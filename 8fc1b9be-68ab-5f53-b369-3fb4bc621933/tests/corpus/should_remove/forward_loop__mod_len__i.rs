// GENERATED. axis combination: forward_loop__mod_len__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let mut total = 0;
    for base in 0..s.len() {
        let idx = base % s.len();
        total += s[idx];
    }
    total
}
