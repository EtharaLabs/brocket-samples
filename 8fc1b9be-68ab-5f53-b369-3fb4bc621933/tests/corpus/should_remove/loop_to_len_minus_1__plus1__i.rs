// GENERATED. axis combination: loop_to_len_minus_1__plus1__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    if s.len() < 2 {
        return 0;
    }
    let mut total = 0;
    for base in 0..s.len() - 1 {
        let idx = base + 1;
        total += s[idx];
    }
    total
}
