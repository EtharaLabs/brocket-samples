// GENERATED. axis combination: equal_lengths__plus2__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    assert_eq!(s.len(), t.len());
    let mut total = 0;
    for base in 0..s.len() {
        let idx = base + 2;
        total += t[idx];
    }
    total
}
